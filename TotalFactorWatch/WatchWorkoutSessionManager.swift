import Foundation
import HealthKit

/// Manages watchOS 10+ `HKWorkoutSession` & `HKLiveWorkoutBuilder` so Total Factor Watch stays active on wrist raise
/// throughout strength training and streams live heart rate + display-only active energy.
@MainActor
@Observable
final class WatchWorkoutSessionManager: NSObject {
    var liveHeartRateBPM: Double? = nil
    /// Ground Rule 3: Display-only active kcal — never modifies adaptive TDEE or macro targets.
    var activeCaloriesDisplayOnly: Double = 0
    var isRunningSession: Bool = false

    var onTelemetryUpdate: ((Double?, Double) -> Void)? = nil

    private let healthStore = HKHealthStore()
    private var workoutSession: HKWorkoutSession? = nil
    private var workoutBuilder: HKLiveWorkoutBuilder? = nil

    func requestAuthorizationIfNeeded() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        var readTypes: Set<HKObjectType> = [HKObjectType.workoutType()]
        var shareTypes: Set<HKSampleType> = [HKObjectType.workoutType()]

        if let hr = HKQuantityType.quantityType(forIdentifier: .heartRate) {
            readTypes.insert(hr)
        }
        if let activeEnergy = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) {
            readTypes.insert(activeEnergy)
            shareTypes.insert(activeEnergy)
        }
        if let bodyMass = HKQuantityType.quantityType(forIdentifier: .bodyMass) {
            readTypes.insert(bodyMass)
            shareTypes.insert(bodyMass)
        }

        try? await healthStore.requestAuthorization(toShare: shareTypes, read: readTypes)
    }

    func ensureWorkoutSessionStarted() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        if isRunningSession, workoutSession != nil { return }

        await requestAuthorizationIfNeeded()

        let config = HKWorkoutConfiguration()
        config.activityType = .traditionalStrengthTraining
        config.locationType = .indoor

        do {
            let session = try HKWorkoutSession(healthStore: healthStore, configuration: config)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: config)

            session.delegate = self
            builder.delegate = self

            self.workoutSession = session
            self.workoutBuilder = builder
            self.isRunningSession = true

            let startDate = Date.now
            session.startActivity(with: startDate)
            try await builder.beginCollection(at: startDate)
        } catch {
            self.isRunningSession = false
        }
    }

    func stopWorkoutSession(phoneHandledPersistence: Bool) async {
        guard let session = workoutSession, let builder = workoutBuilder else {
            isRunningSession = false
            liveHeartRateBPM = nil
            activeCaloriesDisplayOnly = 0
            return
        }

        session.end()
        try? await builder.endCollection(at: .now)
        if phoneHandledPersistence {
            // Avoid duplicate HKWorkout entries when iPhone persists the canonical strength workout
            builder.discardWorkout()
        } else {
            _ = try? await builder.finishWorkout()
        }

        self.workoutSession = nil
        self.workoutBuilder = nil
        self.isRunningSession = false
        self.liveHeartRateBPM = nil
        self.activeCaloriesDisplayOnly = 0
        onTelemetryUpdate?(nil, 0)
    }
}

extension WatchWorkoutSessionManager: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        let active = (toState == .running || toState == .paused)
        Task { @MainActor in
            self.isRunningSession = active
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor in
            self.isRunningSession = false
        }
    }
}

extension WatchWorkoutSessionManager: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    nonisolated func workoutBuilder(
        _ workoutBuilder: HKLiveWorkoutBuilder,
        didCollectDataOf collectedTypes: Set<HKSampleType>
    ) {
        var latestBPM: Double? = nil
        var latestActiveKcal: Double? = nil

        if let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate),
           collectedTypes.contains(hrType),
           let stats = workoutBuilder.statistics(for: hrType),
           let quantity = stats.mostRecentQuantity() {
            let bpmUnit = HKUnit.count().unitDivided(by: .minute())
            latestBPM = quantity.doubleValue(for: bpmUnit)
        }

        if let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned),
           collectedTypes.contains(energyType),
           let stats = workoutBuilder.statistics(for: energyType),
           let sum = stats.sumQuantity() {
            latestActiveKcal = sum.doubleValue(for: .kilocalorie())
        }

        guard latestBPM != nil || latestActiveKcal != nil else { return }

        Task { @MainActor in
            if let bpm = latestBPM {
                self.liveHeartRateBPM = bpm
            }
            if let kcal = latestActiveKcal {
                self.activeCaloriesDisplayOnly = kcal
            }
            self.onTelemetryUpdate?(self.liveHeartRateBPM, self.activeCaloriesDisplayOnly)
        }
    }
}
