import Foundation
import WatchConnectivity
import WatchKit

/// Central `@Observable` state store for `TotalFactorWatch`.
/// Syncs bidirectionally with iPhone over `WCSession` (`updateApplicationContext`, `sendMessageData`, `transferUserInfo`),
/// runs wrist haptic rest timer countdowns (`3-2-1-Go`), and coordinates `WatchWorkoutSessionManager` live HR telemetry.
@MainActor
@Observable
final class WatchStore: NSObject {
    private static let cachedSnapshotKey = "totalfactor.watch.cachedSnapshot.v1"

    var snapshot: WatchSyncStateSnapshot
    var isPhoneReachable: Bool = false
    var restRemainingSeconds: Int = 0
    var selectedSetID: UUID? = nil
    var weighInDraftDisplay: Double = 175.0
    var didSeedWeighInDraft: Bool = false
    var statusBanner: String? = nil

    let workoutManager = WatchWorkoutSessionManager()

    private var restTickerTask: Task<Void, Never>? = nil
    private var lastCountdownBeepSecond: Int? = nil
    private var lastHeartRatePushAt: Date = .distantPast

    override init() {
        if let raw = UserDefaults.standard.data(forKey: Self.cachedSnapshotKey),
           let decoded = try? JSONDecoder().decode(WatchSyncStateSnapshot.self, from: raw) {
            self.snapshot = decoded
        } else {
            self.snapshot = WatchSyncStateSnapshot()
        }
        super.init()

        workoutManager.onTelemetryUpdate = { [weak self] bpm, activeKcal in
            guard let self else { return }
            self.forwardTelemetryIfNeeded(bpm: bpm, activeKcal: activeKcal)
        }

        configureWatchConnectivity()
        seedWeighInIfNeeded()
        reconcileRestTimerTicker()
    }

    var currentSet: WatchSetItemDTO? {
        guard let session = snapshot.activeSession, !session.sets.isEmpty else { return nil }
        if let selID = selectedSetID, let match = session.sets.first(where: { $0.id == selID }) {
            return match
        }
        return session.sets.first(where: { !$0.isCompleted }) ?? session.sets.last
    }

    func selectPreviousSet() {
        guard let session = snapshot.activeSession, !session.sets.isEmpty else { return }
        let currentID = currentSet?.id
        guard let idx = session.sets.firstIndex(where: { $0.id == currentID }), idx > 0 else { return }
        selectedSetID = session.sets[idx - 1].id
        WKInterfaceDevice.current().play(.click)
    }

    func selectNextSet() {
        guard let session = snapshot.activeSession, !session.sets.isEmpty else { return }
        let currentID = currentSet?.id
        guard let idx = session.sets.firstIndex(where: { $0.id == currentID }),
              idx + 1 < session.sets.count else { return }
        selectedSetID = session.sets[idx + 1].id
        WKInterfaceDevice.current().play(.click)
    }

    // MARK: - User Actions from Wrist

    func requestFreshSync() {
        sendCommand(WatchCommandPayload(action: .requestSync), queueIfUnreachable: false)
    }

    func startWorkout(programWorkoutID: UUID?) {
        WKInterfaceDevice.current().play(.start)
        sendCommand(
            WatchCommandPayload(action: .startWorkout, programWorkoutID: programWorkoutID),
            queueIfUnreachable: true
        )
        Task {
            await workoutManager.ensureWorkoutSessionStarted()
        }
    }

    func finishWorkout() {
        WKInterfaceDevice.current().play(.stop)
        let reachable = isPhoneReachable
        snapshot.activeSession = nil
        snapshot.restEndDate = nil
        snapshot.restTotalSeconds = 0
        persistSnapshotCache()
        reconcileRestTimerTicker()

        sendCommand(WatchCommandPayload(action: .finishWorkout), queueIfUnreachable: true)
        Task {
            await workoutManager.stopWorkoutSession(phoneHandledPersistence: reachable)
        }
    }

    func updateDraftSetValues(setID: UUID, weightKg: Double, reps: Int) {
        guard var session = snapshot.activeSession,
              let idx = session.sets.firstIndex(where: { $0.id == setID }) else { return }
        let clampedKg = max(0, weightKg)
        let clampedReps = max(1, min(60, reps))
        session.sets[idx].weightKg = clampedKg
        session.sets[idx].reps = clampedReps
        snapshot.activeSession = session
        persistSnapshotCache()

        sendCommand(
            WatchCommandPayload(
                action: .updateSetValues,
                setID: setID,
                weightKg: clampedKg,
                reps: clampedReps
            ),
            queueIfUnreachable: true
        )
    }

    func logOrToggleSet(_ setItem: WatchSetItemDTO, overrideWeightKg: Double? = nil, overrideReps: Int? = nil) {
        let finalKg = max(0, overrideWeightKg ?? setItem.weightKg)
        let finalReps = max(1, min(60, overrideReps ?? setItem.reps))
        let willComplete = !setItem.isCompleted

        if var session = snapshot.activeSession,
           let idx = session.sets.firstIndex(where: { $0.id == setItem.id }) {
            session.sets[idx].weightKg = finalKg
            session.sets[idx].reps = finalReps
            session.sets[idx].isCompleted = willComplete
            snapshot.activeSession = session

            if willComplete {
                WKInterfaceDevice.current().play(.success)
                let restSec = max(15, setItem.restSeconds)
                snapshot.restEndDate = Date.now.addingTimeInterval(TimeInterval(restSec))
                snapshot.restTotalSeconds = restSec
                snapshot.restExerciseName = setItem.exerciseName
                // Advance focus to the next uncompleted set automatically
                if let nextOpen = session.sets.first(where: { !$0.isCompleted }) {
                    selectedSetID = nextOpen.id
                }
            } else {
                WKInterfaceDevice.current().play(.click)
            }
            persistSnapshotCache()
            reconcileRestTimerTicker()
        }

        sendCommand(
            WatchCommandPayload(
                action: .toggleSetComplete,
                setID: setItem.id,
                weightKg: finalKg,
                reps: finalReps,
                rir: setItem.rir,
                restSeconds: setItem.restSeconds
            ),
            queueIfUnreachable: true
        )
    }

    func addSet(from referenceSet: WatchSetItemDTO) {
        WKInterfaceDevice.current().play(.click)
        sendCommand(
            WatchCommandPayload(
                action: .addSet,
                exerciseID: referenceSet.exerciseID,
                weightKg: referenceSet.weightKg,
                reps: referenceSet.reps,
                rir: referenceSet.rir
            ),
            queueIfUnreachable: true
        )
    }

    func startLocalPresetRest(seconds: Int) {
        let clamped = max(15, seconds)
        WKInterfaceDevice.current().play(.start)
        snapshot.restEndDate = Date.now.addingTimeInterval(TimeInterval(clamped))
        snapshot.restTotalSeconds = clamped
        if snapshot.restExerciseName.isEmpty {
            snapshot.restExerciseName = currentSet?.exerciseName ?? "Rest Timer"
        }
        lastCountdownBeepSecond = nil
        persistSnapshotCache()
        reconcileRestTimerTicker()
    }

    func adjustRest(deltaSeconds: Int) {
        WKInterfaceDevice.current().play(.click)
        if let end = snapshot.restEndDate {
            let newEnd = end.addingTimeInterval(TimeInterval(deltaSeconds))
            if newEnd <= .now {
                skipRest()
                return
            }
            snapshot.restEndDate = newEnd
            snapshot.restTotalSeconds = max(15, snapshot.restTotalSeconds + deltaSeconds)
            lastCountdownBeepSecond = nil
            persistSnapshotCache()
            reconcileRestTimerTicker()
        }
        sendCommand(
            WatchCommandPayload(action: .adjustRestTimer, deltaSeconds: deltaSeconds),
            queueIfUnreachable: false
        )
    }

    func skipRest() {
        WKInterfaceDevice.current().play(.directionDown)
        snapshot.restEndDate = nil
        snapshot.restTotalSeconds = 0
        restRemainingSeconds = 0
        lastCountdownBeepSecond = nil
        persistSnapshotCache()
        reconcileRestTimerTicker()

        sendCommand(WatchCommandPayload(action: .skipRestTimer), queueIfUnreachable: false)
    }

    func logWeighInFromWrist() {
        let kg = snapshot.internalKg(fromDisplay: weighInDraftDisplay)
        guard kg >= 25.0 && kg <= 350.0 else { return }

        WKInterfaceDevice.current().play(.success)
        snapshot.latestScaleWeightKg = kg
        if let prevTrend = snapshot.trendWeightKg {
            snapshot.trendWeightKg = 0.1 * kg + 0.9 * prevTrend
        } else {
            snapshot.trendWeightKg = kg
        }
        persistSnapshotCache()
        showTransientBanner("Saved \(snapshot.formatBodyWeight(kg))")

        sendCommand(
            WatchCommandPayload(action: .logWeighIn, weightKg: kg),
            queueIfUnreachable: true
        )
    }

    // MARK: - Rest Timer Wrist Haptics & Wall-Clock Reconciliation

    func reconcileRestTimerTicker() {
        restTickerTask?.cancel()
        restTickerTask = nil

        guard let targetEnd = snapshot.restEndDate else {
            restRemainingSeconds = 0
            return
        }

        let initialLeft = Int(ceil(targetEnd.timeIntervalSinceNow))
        if initialLeft <= 0 {
            snapshot.restEndDate = nil
            restRemainingSeconds = 0
            return
        }
        restRemainingSeconds = initialLeft

        restTickerTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard let self, let activeEnd = self.snapshot.restEndDate else { break }
                let left = Int(ceil(activeEnd.timeIntervalSinceNow))
                if left <= 0 {
                    self.restRemainingSeconds = 0
                    self.snapshot.restEndDate = nil
                    self.lastCountdownBeepSecond = nil
                    self.persistSnapshotCache()
                    WKInterfaceDevice.current().play(.notification)
                    break
                } else {
                    if (1...3).contains(left) && self.lastCountdownBeepSecond != left {
                        self.lastCountdownBeepSecond = left
                        WKInterfaceDevice.current().play(.click)
                    }
                    self.restRemainingSeconds = left
                }
            }
        }
    }

    // MARK: - WatchConnectivity Transport

    private func configureWatchConnectivity() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    private func applyIncomingSnapshot(_ incoming: WatchSyncStateSnapshot) {
        let hadSession = (snapshot.activeSession != nil)
        snapshot = incoming
        persistSnapshotCache()

        if !didSeedWeighInDraft {
            seedWeighInIfNeeded()
        }

        if let active = incoming.activeSession {
            if selectedSetID == nil || !active.sets.contains(where: { $0.id == selectedSetID }) {
                selectedSetID = active.sets.first(where: { !$0.isCompleted })?.id ?? active.sets.last?.id
            }
            if !workoutManager.isRunningSession {
                Task { await workoutManager.ensureWorkoutSessionStarted() }
            }
        } else if hadSession && workoutManager.isRunningSession {
            Task { await workoutManager.stopWorkoutSession(phoneHandledPersistence: true) }
        }

        reconcileRestTimerTicker()
    }

    private func seedWeighInIfNeeded() {
        if let baseKg = snapshot.latestScaleWeightKg ?? snapshot.trendWeightKg {
            weighInDraftDisplay = (snapshot.displayWeight(baseKg) * 10.0).rounded() / 10.0
            didSeedWeighInDraft = true
        }
    }

    private func persistSnapshotCache() {
        if let raw = try? JSONEncoder().encode(snapshot) {
            UserDefaults.standard.set(raw, forKey: Self.cachedSnapshotKey)
        }
    }

    private func showTransientBanner(_ text: String) {
        statusBanner = text
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2.2))
            if self?.statusBanner == text {
                self?.statusBanner = nil
            }
        }
    }

    private func forwardTelemetryIfNeeded(bpm: Double?, activeKcal: Double) {
        guard Date.now.timeIntervalSince(lastHeartRatePushAt) >= 3.0 else { return }
        lastHeartRatePushAt = .now
        sendCommand(
            WatchCommandPayload(
                action: .liveHeartRate,
                heartRateBPM: bpm,
                activeCaloriesDisplayOnly: activeKcal
            ),
            queueIfUnreachable: false
        )
    }

    private func sendCommand(_ cmd: WatchCommandPayload, queueIfUnreachable: Bool) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated, let data = cmd.toData() else {
            if queueIfUnreachable, let dict = cmd.toUserInfo() {
                WCSession.default.transferUserInfo(dict)
            }
            return
        }

        if session.isReachable {
            session.sendMessageData(data) { [weak self] replyData in
                guard !replyData.isEmpty,
                      let updated = try? JSONDecoder().decode(WatchSyncStateSnapshot.self, from: replyData) else { return }
                Task { @MainActor in
                    self?.applyIncomingSnapshot(updated)
                }
            } errorHandler: { _ in
                if queueIfUnreachable, let dict = cmd.toUserInfo() {
                    session.transferUserInfo(dict)
                }
            }
        } else if queueIfUnreachable, let dict = cmd.toUserInfo() {
            session.transferUserInfo(dict)
        }
    }
}

extension WatchStore: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        let reachable = session.isReachable
        let latestCtx = session.receivedApplicationContext
        Task { @MainActor in
            self.isPhoneReachable = reachable
            if let snap = WatchSyncStateSnapshot.fromApplicationContext(latestCtx) {
                self.applyIncomingSnapshot(snap)
            }
            if reachable {
                self.requestFreshSync()
            }
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor in
            self.isPhoneReachable = reachable
            if reachable {
                self.requestFreshSync()
            }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let snap = WatchSyncStateSnapshot.fromApplicationContext(applicationContext) else { return }
        Task { @MainActor in
            self.applyIncomingSnapshot(snap)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessageData messageData: Data) {
        guard let snap = try? JSONDecoder().decode(WatchSyncStateSnapshot.self, from: messageData) else { return }
        Task { @MainActor in
            self.applyIncomingSnapshot(snap)
        }
    }
}
