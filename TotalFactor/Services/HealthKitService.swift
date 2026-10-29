import Foundation
import SwiftData
#if canImport(HealthKit)
import HealthKit
#endif

public struct ExternalFitnessWorkout: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let title: String
    public let sfSymbol: String
    public let emoji: String
    public let durationMinutes: Int
    public let activeCalories: Double
    public let startDate: Date
    public let endDate: Date
    public let sourceAppName: String

    public init(
        id: UUID,
        title: String,
        sfSymbol: String,
        emoji: String,
        durationMinutes: Int,
        activeCalories: Double,
        startDate: Date,
        endDate: Date,
        sourceAppName: String
    ) {
        self.id = id
        self.title = title
        self.sfSymbol = sfSymbol
        self.emoji = emoji
        self.durationMinutes = durationMinutes
        self.activeCalories = activeCalories
        self.startDate = startDate
        self.endDate = endDate
        self.sourceAppName = sourceAppName
    }
}

public struct HealthDisplayDashboardStats: Equatable, Sendable {
    public var stepsToday: Int = 0
    /// Ground Rule 3: Watch active calories are strictly DISPLAY-ONLY and NEVER feed targets or expenditure!
    public var activeCaloriesDisplayOnly: Double = 0
    public var basalCaloriesDisplayOnly: Double = 0
    public var restingHeartRateBPM: Double? = nil
    public var currentHeartRateBPM: Double? = nil
    public var minHeartRateBPM: Double? = nil
    public var maxHeartRateBPM: Double? = nil
    public var hrvSDNNMilliseconds: Double? = nil
    public var sleepHoursLastNight: Double? = nil
}

@MainActor
@Observable
public final class HealthKitService {
    public static let shared = HealthKitService()

    public var isAuthorized: Bool = false
    public var todayStats = HealthDisplayDashboardStats()
    public var todayExternalWorkouts: [ExternalFitnessWorkout] = []
    public var currentLiveHeartRateBPM: Double? = nil
    public var lastSyncDate: Date? = nil

    #if canImport(HealthKit)
    private let store = HKHealthStore()
    private var observerRegistered = false
    private var liveHRObserverQuery: HKQuery? = nil
    #endif

    public init() {}

    public var isHealthDataAvailable: Bool {
        #if canImport(HealthKit)
        return HKHealthStore.isHealthDataAvailable()
        #else
        return false
        #endif
    }

    // MARK: - Authorization (§3 & §5)

    public func requestPermissions() async -> Bool {
        #if canImport(HealthKit)
        guard HKHealthStore.isHealthDataAvailable() else { return false }

        // IMPORTANT iOS HealthKit rule: never pass HKCorrelationType(.food) into requestAuthorization;
        // request authorization for its constituent HKQuantityTypes instead!
        let shareQuantityIDs: [HKQuantityTypeIdentifier] = [
            .bodyMass,
            .leanBodyMass,
            .dietaryEnergyConsumed,
            .dietaryProtein,
            .dietaryCarbohydrates,
            .dietaryFatTotal,
            .dietaryFiber,
            .dietarySugar,
            .dietarySodium,
            .dietaryPotassium,
            .dietaryCalcium,
            .dietaryIron,
            .dietaryVitaminD,
            .dietaryVitaminC,
            .dietaryMagnesium,
            .dietaryZinc,
            .dietaryCholesterol,
            .dietaryFatSaturated
        ]

        var toShare: Set<HKSampleType> = [HKObjectType.workoutType()]
        for id in shareQuantityIDs {
            if let qt = HKObjectType.quantityType(forIdentifier: id) {
                toShare.insert(qt)
            }
        }

        let readQuantityIDs: [HKQuantityTypeIdentifier] = [
            .bodyMass,
            .bodyFatPercentage,
            .leanBodyMass,
            .waistCircumference,
            .stepCount,
            .activeEnergyBurned,
            .basalEnergyBurned,
            .heartRate,
            .restingHeartRate,
            .heartRateVariabilitySDNN
        ]

        var toRead: Set<HKObjectType> = [HKObjectType.workoutType()]
        for id in readQuantityIDs {
            if let qt = HKObjectType.quantityType(forIdentifier: id) {
                toRead.insert(qt)
            }
        }
        if let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) {
            toRead.insert(sleepType)
        }

        do {
            try await store.requestAuthorization(toShare: toShare, read: toRead)
            isAuthorized = true
            return true
        } catch {
            return false
        }
        #else
        return false
        #endif
    }

    // MARK: - Background Smart-Scale Observer (§3)

    public func startObservingBodyMass(context: ModelContext) {
        #if canImport(HealthKit)
        guard HKHealthStore.isHealthDataAvailable(), !observerRegistered,
              let bodyMassType = HKObjectType.quantityType(forIdentifier: .bodyMass) else { return }

        observerRegistered = true
        let container = context.container
        let query = HKObserverQuery(sampleType: bodyMassType, predicate: nil) { [weak self] _, completionHandler, error in
            guard error == nil else {
                completionHandler()
                return
            }
            Task { @MainActor [weak self] in
                guard let self else {
                    completionHandler()
                    return
                }
                await self.importExternalBodyMetrics(context: container.mainContext)
                completionHandler()
            }
        }
        store.execute(query)
        store.enableBackgroundDelivery(for: bodyMassType, frequency: .immediate) { _, _ in }
        #endif
    }

    // MARK: - Import External Weigh-Ins & Body Metrics (§3: filter out self writes)

    public func importExternalBodyMetrics(context: ModelContext, daysBack: Int = 90) async {
        #if canImport(HealthKit)
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let startDate = Calendar.current.date(byAdding: .day, value: -daysBack, to: .now) ?? .distantPast
        let datePredicate = HKQuery.predicateForSamples(withStart: startDate, end: .now, options: .strictStartDate)
        let myBundleID = Bundle.main.bundleIdentifier ?? "com.totalfactor.app"

        // 1. Body Mass
        if let massType = HKQuantityType.quantityType(forIdentifier: .bodyMass) {
            let samples = await fetchQuantitySamples(type: massType, predicate: datePredicate)
            let existingWeighIns = (try? context.fetch(FetchDescriptor<WeighIn>())) ?? []
            let knownHKIDs = Set(existingWeighIns.compactMap(\.healthKitUUID))

            for sample in samples {
                // Rule §3: Don't re-import your own writes (including TotalFactorWatch companion writes)
                if sample.sourceRevision.source.bundleIdentifier.hasPrefix(myBundleID) { continue }
                if knownHKIDs.contains(sample.uuid) { continue }

                let kg = sample.quantity.doubleValue(for: .gramUnit(with: .kilo))
                let entry = WeighIn(
                    date: sample.startDate,
                    weightKg: kg,
                    source: .healthKit,
                    healthKitUUID: sample.uuid
                )
                context.insert(entry)
            }
        }

        // 2. Body Fat % and Waist Circumference
        let existingMetrics = (try? context.fetch(FetchDescriptor<BodyMetric>())) ?? []
        var knownMetricUUIDs = Set(existingMetrics.compactMap(\.healthKitUUID))

        if let bfType = HKQuantityType.quantityType(forIdentifier: .bodyFatPercentage) {
            let samples = await fetchQuantitySamples(type: bfType, predicate: datePredicate)
            for sample in samples where sample.sourceRevision.source.bundleIdentifier != myBundleID && !knownMetricUUIDs.contains(sample.uuid) {
                let pct = sample.quantity.doubleValue(for: .percent()) * 100.0
                context.insert(BodyMetric(date: sample.startDate, type: .bodyFat, value: pct, healthKitUUID: sample.uuid))
                knownMetricUUIDs.insert(sample.uuid)
            }
        }

        if let waistType = HKQuantityType.quantityType(forIdentifier: .waistCircumference) {
            let samples = await fetchQuantitySamples(type: waistType, predicate: datePredicate)
            for sample in samples where sample.sourceRevision.source.bundleIdentifier != myBundleID && !knownMetricUUIDs.contains(sample.uuid) {
                let cm = sample.quantity.doubleValue(for: .meterUnit(with: .centi))
                context.insert(BodyMetric(date: sample.startDate, type: .waist, value: cm, healthKitUUID: sample.uuid))
                knownMetricUUIDs.insert(sample.uuid)
            }
        }

        if let lbmType = HKQuantityType.quantityType(forIdentifier: .leanBodyMass) {
            let samples = await fetchQuantitySamples(type: lbmType, predicate: datePredicate)
            for sample in samples where sample.sourceRevision.source.bundleIdentifier != myBundleID && !knownMetricUUIDs.contains(sample.uuid) {
                let kg = sample.quantity.doubleValue(for: .gramUnit(with: .kilo))
                context.insert(BodyMetric(date: sample.startDate, type: .leanBodyMass, value: kg, healthKitUUID: sample.uuid))
                knownMetricUUIDs.insert(sample.uuid)
            }
        }

        _ = try? context.save()
        lastSyncDate = .now
        #endif
    }

    // MARK: - Refresh Display-Only Dashboard Telemetry (§3 & §13)

    public func refreshTodayDashboardTelemetry() async {
        #if canImport(HealthKit)
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: .now)
        let todayPred = HKQuery.predicateForSamples(withStart: startOfDay, end: .now, options: .strictStartDate)

        var stats = HealthDisplayDashboardStats()

        if let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount),
           let steps = await fetchCumulativeSum(type: stepType, unit: .count(), predicate: todayPred) {
            stats.stepsToday = Int(steps.rounded())
        }

        if let activeType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned),
           let activeKcal = await fetchCumulativeSum(type: activeType, unit: .kilocalorie(), predicate: todayPred) {
            stats.activeCaloriesDisplayOnly = activeKcal.rounded()
        }

        if let basalType = HKQuantityType.quantityType(forIdentifier: .basalEnergyBurned),
           let basalKcal = await fetchCumulativeSum(type: basalType, unit: .kilocalorie(), predicate: todayPred) {
            stats.basalCaloriesDisplayOnly = basalKcal.rounded()
        }

        let last48h = cal.date(byAdding: .hour, value: -48, to: .now) ?? startOfDay
        let recentPred = HKQuery.predicateForSamples(withStart: last48h, end: .now, options: .strictStartDate)

        if let rhrType = HKQuantityType.quantityType(forIdentifier: .restingHeartRate),
           let latestRHR = await fetchQuantitySamples(type: rhrType, predicate: recentPred).last {
            stats.restingHeartRateBPM = latestRHR.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
        }

        if let hrvType = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN),
           let latestHRV = await fetchQuantitySamples(type: hrvType, predicate: recentPred).last {
            stats.hrvSDNNMilliseconds = latestHRV.quantity.doubleValue(for: .secondUnit(with: .milli))
        }

        if let sleepType = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) {
            let sleepStart = cal.date(byAdding: .hour, value: -20, to: .now) ?? startOfDay
            let sleepPred = HKQuery.predicateForSamples(withStart: sleepStart, end: .now, options: [])
            let samples = await fetchCategorySamples(type: sleepType, predicate: sleepPred)
            let asleepValues: Set<Int> = [
                HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
                HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                HKCategoryValueSleepAnalysis.asleepREM.rawValue
            ]
            let totalSec = samples
                .filter { asleepValues.contains($0.value) }
                .reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
            if totalSec > 600 {
                stats.sleepHoursLastNight = (totalSec / 3600.0 * 10).rounded() / 10.0
            }
        }

        if let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate) {
            let hrSamples = await fetchQuantitySamples(type: hrType, predicate: todayPred)
            let bpmUnit = HKUnit.count().unitDivided(by: .minute())
            let bpms = hrSamples.map { $0.quantity.doubleValue(for: bpmUnit) }
            if let latest = bpms.last {
                stats.currentHeartRateBPM = latest
                if currentLiveHeartRateBPM == nil {
                    currentLiveHeartRateBPM = latest
                }
            }
            if let minVal = bpms.min() {
                stats.minHeartRateBPM = minVal
            }
            if let maxVal = bpms.max() {
                stats.maxHeartRateBPM = maxVal
            }
        }

        todayStats = stats
        await fetchTodayExternalWorkouts()
        #endif
    }

    // MARK: - Live Heart Rate Observer for Active Workouts

    public func startLiveHeartRateObserver() {
        #if canImport(HealthKit)
        guard HKHealthStore.isHealthDataAvailable(), liveHRObserverQuery == nil,
              let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return }

        let cal = Calendar.current
        let start = cal.date(byAdding: .minute, value: -10, to: .now) ?? .now
        let predicate = HKQuery.predicateForSamples(withStart: start, end: nil, options: .strictStartDate)

        let query = HKAnchoredObjectQuery(
            type: hrType,
            predicate: predicate,
            anchor: nil,
            limit: HKObjectQueryNoLimit
        ) { [weak self] _, samples, _, _, _ in
            if let latest = (samples as? [HKQuantitySample])?.last {
                let bpm = latest.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
                Task { @MainActor [weak self] in
                    self?.currentLiveHeartRateBPM = bpm
                }
            }
        }

        query.updateHandler = { [weak self] _, samples, _, _, _ in
            if let latest = (samples as? [HKQuantitySample])?.last {
                let bpm = latest.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
                Task { @MainActor [weak self] in
                    self?.currentLiveHeartRateBPM = bpm
                }
            }
        }

        liveHRObserverQuery = query
        store.execute(query)
        #endif
    }

    public func stopLiveHeartRateObserver() {
        #if canImport(HealthKit)
        if let q = liveHRObserverQuery {
            store.stop(q)
            liveHRObserverQuery = nil
        }
        #endif
    }

    // MARK: - Fetch Today's External Workouts (Apple Fitness Soccer, Running, Cycling, etc.)

    public func fetchTodayExternalWorkouts() async {
        #if canImport(HealthKit)
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: .now)
        let pred = HKQuery.predicateForSamples(withStart: startOfDay, end: .now, options: .strictStartDate)
        let myBundleID = Bundle.main.bundleIdentifier ?? "com.prerak.totalfactor"

        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        let workouts: [HKWorkout] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: HKObjectType.workoutType(), predicate: pred, limit: 50, sortDescriptors: [sort]) { _, samples, _ in
                continuation.resume(returning: (samples as? [HKWorkout]) ?? [])
            }
            self.store.execute(query)
        }

        let mapped = workouts.compactMap { wk -> ExternalFitnessWorkout? in
            // Filter out Total Factor's own strength workouts to avoid self-duplication
            let sourceID = wk.sourceRevision.source.bundleIdentifier
            if sourceID.hasPrefix(myBundleID) { return nil }

            let durationMins = max(1, Int((wk.duration / 60.0).rounded()))
            let kcal = wk.totalEnergyBurned?.doubleValue(for: .kilocalorie()) ?? 0
            let (name, symbol, emoji) = Self.displayMetadata(for: wk.workoutActivityType)
            let sourceName = wk.sourceRevision.source.name

            return ExternalFitnessWorkout(
                id: wk.uuid,
                title: name,
                sfSymbol: symbol,
                emoji: emoji,
                durationMinutes: durationMins,
                activeCalories: kcal.rounded(),
                startDate: wk.startDate,
                endDate: wk.endDate,
                sourceAppName: sourceName
            )
        }
        self.todayExternalWorkouts = mapped
        #endif
    }

    #if canImport(HealthKit)
    public static func displayMetadata(for activity: HKWorkoutActivityType) -> (name: String, sfSymbol: String, emoji: String) {
        switch activity {
        case .running:
            return ("Outdoor / Treadmill Run", "figure.run", "🏃")
        case .soccer:
            return ("Soccer", "figure.soccer", "⚽️")
        case .cycling:
            return ("Cycling", "figure.outdoor.cycle", "🚴")
        case .walking:
            return ("Outdoor Walk", "figure.walk", "🚶")
        case .swimming:
            return ("Swimming", "figure.pool.swim", "🏊")
        case .highIntensityIntervalTraining:
            return ("HIIT Session", "flame.fill", "🔥")
        case .basketball:
            return ("Basketball", "figure.basketball", "🏀")
        case .tennis:
            return ("Tennis", "figure.tennis", "🎾")
        case .rowing:
            return ("Rowing", "figure.rower", "🚣")
        case .stairClimbing:
            return ("Stair Climber", "figure.stairs", "🪜")
        case .functionalStrengthTraining:
            return ("Functional Strength", "figure.strengthtraining.functional", "🏋️")
        case .crossTraining:
            return ("Cross Training", "figure.cross.training", "⚡️")
        case .yoga:
            return ("Yoga", "figure.yoga", "🧘")
        case .pilates:
            return ("Pilates", "figure.pilates", "🤸")
        case .boxing, .kickboxing:
            return ("Boxing / Kickboxing", "figure.boxing", "🥊")
        case .hiking:
            return ("Hiking", "figure.hiking", "🥾")
        case .elliptical:
            return ("Elliptical", "figure.elliptical", "🏃")
        default:
            return ("Apple Fitness Workout", "figure.run", "🏅")
        }
    }
    #endif

    // MARK: - Write / Sync Food Correlation (§3)

    public func syncFoodEntry(_ entry: FoodLogEntry) async {
        #if canImport(HealthKit)
        guard HKHealthStore.isHealthDataAvailable() else { return }
        if !entry.healthKitSampleIDs.isEmpty {
            await deleteSamples(uuids: entry.healthKitSampleIDs)
            entry.healthKitSampleIDs = []
        }

        guard let foodCorrelationType = HKCorrelationType.correlationType(forIdentifier: .food) else { return }

        let n = entry.loggedNutrients
        let metadata: [String: Any] = [
            HKMetadataKeyFoodType: entry.foodName
        ]
        let date = entry.timestamp
        var samples: Set<HKSample> = []

        func addSample(_ id: HKQuantityTypeIdentifier, value: Double, unit: HKUnit) {
            guard value > 0, let qt = HKQuantityType.quantityType(forIdentifier: id) else { return }
            let sample = HKQuantitySample(
                type: qt,
                quantity: HKQuantity(unit: unit, doubleValue: value),
                start: date,
                end: date,
                metadata: metadata
            )
            samples.insert(sample)
        }

        addSample(.dietaryEnergyConsumed, value: n.calories, unit: .kilocalorie())
        addSample(.dietaryProtein, value: n.protein, unit: .gram())
        addSample(.dietaryCarbohydrates, value: n.carbs, unit: .gram())
        addSample(.dietaryFatTotal, value: n.fat, unit: .gram())
        addSample(.dietaryFiber, value: n.fiber, unit: .gram())
        addSample(.dietarySugar, value: n.sugar, unit: .gram())
        addSample(.dietarySodium, value: n.sodiumMg / 1000.0, unit: .gram())

        if let kMg = n.micronutrients[MicronutrientKey.potassiumMg.rawValue] {
            addSample(.dietaryPotassium, value: kMg / 1000.0, unit: .gram())
        }
        if let caMg = n.micronutrients[MicronutrientKey.calciumMg.rawValue] {
            addSample(.dietaryCalcium, value: caMg / 1000.0, unit: .gram())
        }
        if let feMg = n.micronutrients[MicronutrientKey.ironMg.rawValue] {
            addSample(.dietaryIron, value: feMg / 1000.0, unit: .gram())
        }
        if let vitDMcg = n.micronutrients[MicronutrientKey.vitaminDMcg.rawValue] {
            addSample(.dietaryVitaminD, value: vitDMcg / 1_000_000.0, unit: .gram())
        }
        if let vitCMg = n.micronutrients[MicronutrientKey.vitaminCMg.rawValue] {
            addSample(.dietaryVitaminC, value: vitCMg / 1000.0, unit: .gram())
        }
        if let mgMg = n.micronutrients[MicronutrientKey.magnesiumMg.rawValue] {
            addSample(.dietaryMagnesium, value: mgMg / 1000.0, unit: .gram())
        }
        if let znMg = n.micronutrients[MicronutrientKey.zincMg.rawValue] {
            addSample(.dietaryZinc, value: znMg / 1000.0, unit: .gram())
        }
        if let cholMg = n.micronutrients[MicronutrientKey.cholesterolMg.rawValue] {
            addSample(.dietaryCholesterol, value: cholMg / 1000.0, unit: .gram())
        }
        if let satG = n.micronutrients[MicronutrientKey.saturatedFatG.rawValue] {
            addSample(.dietaryFatSaturated, value: satG, unit: .gram())
        }

        guard !samples.isEmpty else { return }
        let correlation = HKCorrelation(
            type: foodCorrelationType,
            start: date,
            end: date,
            objects: samples,
            metadata: metadata
        )

        do {
            try await store.save(correlation)
            var savedIDs = samples.map(\.uuid)
            savedIDs.append(correlation.uuid)
            entry.healthKitSampleIDs = savedIDs
        } catch {
            // Silently ignore when user hasn't granted write permissions
        }
        #endif
    }

    public func deleteFoodEntrySamples(_ entry: FoodLogEntry) async {
        guard !entry.healthKitSampleIDs.isEmpty else { return }
        await deleteSamples(uuids: entry.healthKitSampleIDs)
    }

    // MARK: - Write Manual Weigh-In & Strength Workout (§3 & §9)

    public func saveManualWeighIn(_ weighIn: WeighIn) async {
        #if canImport(HealthKit)
        guard HKHealthStore.isHealthDataAvailable(),
              weighIn.source == .manual,
              let massType = HKQuantityType.quantityType(forIdentifier: .bodyMass) else { return }

        if let oldUUID = weighIn.healthKitUUID {
            await deleteSamples(uuids: [oldUUID])
        }

        let sample = HKQuantitySample(
            type: massType,
            quantity: HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: weighIn.weightKg),
            start: weighIn.date,
            end: weighIn.date
        )
        if (try? await store.save(sample)) != nil {
            weighIn.healthKitUUID = sample.uuid
        }
        #endif
    }

    public func deleteWeighInSample(_ weighIn: WeighIn) async {
        if let uuid = weighIn.healthKitUUID, weighIn.source == .manual {
            await deleteSamples(uuids: [uuid])
        }
    }

    public func saveManualLeanBodyMass(_ metric: BodyMetric) async {
        #if canImport(HealthKit)
        guard HKHealthStore.isHealthDataAvailable(),
              metric.type == .leanBodyMass,
              let lbmType = HKQuantityType.quantityType(forIdentifier: .leanBodyMass) else { return }

        if let oldUUID = metric.healthKitUUID {
            await deleteSamples(uuids: [oldUUID])
        }

        let sample = HKQuantitySample(
            type: lbmType,
            quantity: HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: metric.value),
            start: metric.date,
            end: metric.date
        )
        if (try? await store.save(sample)) != nil {
            metric.healthKitUUID = sample.uuid
        }
        #endif
    }

    public func saveStrengthWorkout(_ session: WorkoutSession) async {
        #if canImport(HealthKit)
        guard HKHealthStore.isHealthDataAvailable(),
              let endDate = session.end, endDate > session.start else { return }

        let config = HKWorkoutConfiguration()
        config.activityType = .traditionalStrengthTraining
        config.locationType = .indoor

        let builder = HKWorkoutBuilder(healthStore: store, configuration: config, device: .local())
        do {
            try await builder.beginCollection(at: session.start)
            try await builder.endCollection(at: endDate)
            if let workout = try await builder.finishWorkout() {
                session.healthKitWorkoutUUID = workout.uuid
            }
        } catch {
            // Permission not granted or Simulator unavailable
        }
        #endif
    }

    // MARK: - Private HealthKit Helpers

    public func deleteSamples(uuids: [UUID]) async {
        #if canImport(HealthKit)
        guard HKHealthStore.isHealthDataAvailable(), !uuids.isEmpty else { return }
        let pred = HKQuery.predicateForObjects(with: Set(uuids))

        let candidateTypes: [HKSampleType?] = [
            HKCorrelationType.correlationType(forIdentifier: .food),
            HKQuantityType.quantityType(forIdentifier: .bodyMass),
            HKQuantityType.quantityType(forIdentifier: .leanBodyMass),
            HKQuantityType.quantityType(forIdentifier: .dietaryEnergyConsumed),
            HKQuantityType.quantityType(forIdentifier: .dietaryProtein),
            HKQuantityType.quantityType(forIdentifier: .dietaryCarbohydrates),
            HKQuantityType.quantityType(forIdentifier: .dietaryFatTotal),
            HKQuantityType.quantityType(forIdentifier: .dietaryFiber),
            HKQuantityType.quantityType(forIdentifier: .dietarySugar),
            HKQuantityType.quantityType(forIdentifier: .dietarySodium),
            HKQuantityType.quantityType(forIdentifier: .dietaryPotassium),
            HKQuantityType.quantityType(forIdentifier: .dietaryCalcium),
            HKQuantityType.quantityType(forIdentifier: .dietaryIron),
            HKQuantityType.quantityType(forIdentifier: .dietaryVitaminD),
            HKQuantityType.quantityType(forIdentifier: .dietaryVitaminC),
            HKQuantityType.quantityType(forIdentifier: .dietaryMagnesium),
            HKQuantityType.quantityType(forIdentifier: .dietaryZinc),
            HKQuantityType.quantityType(forIdentifier: .dietaryCholesterol),
            HKQuantityType.quantityType(forIdentifier: .dietaryFatSaturated)
        ]

        for case let type? in candidateTypes {
            _ = try? await store.deleteObjects(of: type, predicate: pred)
        }
        #endif
    }

    #if canImport(HealthKit)
    private func fetchQuantitySamples(type: HKQuantityType, predicate: NSPredicate?) async -> [HKQuantitySample] {
        await withCheckedContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, samples, _ in
                continuation.resume(returning: (samples as? [HKQuantitySample]) ?? [])
            }
            store.execute(query)
        }
    }

    private func fetchCategorySamples(type: HKCategoryType, predicate: NSPredicate?) async -> [HKCategorySample] {
        await withCheckedContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, samples, _ in
                continuation.resume(returning: (samples as? [HKCategorySample]) ?? [])
            }
            store.execute(query)
        }
    }

    private func fetchCumulativeSum(type: HKQuantityType, unit: HKUnit, predicate: NSPredicate?) async -> Double? {
        await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, stats, _ in
                continuation.resume(returning: stats?.sumQuantity()?.doubleValue(for: unit))
            }
            store.execute(query)
        }
    }
    #endif
}
