import Foundation
#if canImport(UIKit)
import UIKit
import AudioToolbox
#endif
#if canImport(ActivityKit)
import ActivityKit
#endif

@MainActor
@Observable
public final class RestTimerService {
    public static let shared = RestTimerService()

    public var isRunning: Bool = false
    public var endDate: Date? = nil
    /// Timestamp when the most recent rest period started, used to stamp `SetLog.restTakenSeconds`.
    public var lastRestStartedAt: Date? = nil
    public var totalSeconds: Int = 0
    public var remainingSeconds: Int = 0
    public var workoutName: String = ""
    public var exerciseName: String = ""
    public var setNumber: Int = 1
    public var nextSetSummary: String = ""

    private var tickerTask: Task<Void, Never>? = nil

    public init() {}

    public func start(
        seconds: Int,
        workoutName: String,
        exerciseName: String,
        setNumber: Int,
        nextSetSummary: String = ""
    ) {
        RestTimerNotificationScheduler.requestAuthorizationIfNeeded()

        let clamped = max(10, seconds)
        let now = Date.now
        let targetEnd = now.addingTimeInterval(TimeInterval(clamped))

        self.lastRestStartedAt = now
        self.workoutName = workoutName
        self.exerciseName = exerciseName
        self.setNumber = setNumber
        self.nextSetSummary = nextSetSummary
        self.totalSeconds = clamped
        self.endDate = targetEnd
        self.remainingSeconds = clamped
        self.isRunning = true

        var snap = SharedSnapshotStore.load()
        snap.activeRestEndDate = targetEnd
        snap.activeRestTotalSeconds = clamped
        snap.activeRestExercise = exerciseName
        SharedSnapshotStore.save(snap)

        RestTimerNotificationScheduler.schedule(
            endDate: targetEnd,
            exerciseName: exerciseName,
            nextSummary: nextSetSummary
        )
        startOrUpdateLiveActivity()
        startTicker()
        PhoneWatchSyncService.shared.pushCurrentState()
    }

    /// Returns elapsed rest seconds since the last logged set (capped to a sane 0...900s gym window)
    /// and clears `lastRestStartedAt` until the next set starts resting.
    public func consumeElapsedRestSeconds() -> Int {
        guard let started = lastRestStartedAt else { return 0 }
        lastRestStartedAt = nil
        let elapsed = Int(Date.now.timeIntervalSince(started).rounded())
        return min(max(0, elapsed), 900)
    }

    public func adjust(bySeconds delta: Int) {
        guard isRunning, let currentEnd = endDate else { return }
        let updatedEnd = currentEnd.addingTimeInterval(TimeInterval(delta))
        if updatedEnd <= .now {
            skip()
            return
        }
        endDate = updatedEnd
        totalSeconds = max(10, totalSeconds + delta)
        remainingSeconds = max(0, Int(ceil(updatedEnd.timeIntervalSinceNow)))

        var snap = SharedSnapshotStore.load()
        snap.activeRestEndDate = updatedEnd
        snap.activeRestTotalSeconds = totalSeconds
        SharedSnapshotStore.save(snap)

        RestTimerNotificationScheduler.schedule(
            endDate: updatedEnd,
            exerciseName: exerciseName,
            nextSummary: nextSetSummary
        )
        startOrUpdateLiveActivity()
        PhoneWatchSyncService.shared.pushCurrentState()
    }

    public func skip() {
        tickerTask?.cancel()
        tickerTask = nil
        isRunning = false
        endDate = nil
        remainingSeconds = 0

        var snap = SharedSnapshotStore.load()
        snap.activeRestEndDate = nil
        snap.activeRestTotalSeconds = 0
        SharedSnapshotStore.save(snap)

        RestTimerNotificationScheduler.cancel()
        endLiveActivities()
        PhoneWatchSyncService.shared.pushCurrentState()
    }

    /// Re-syncs in-app timer state when returning from Lock Screen / background.
    public func reconcileWithWallClock() {
        let snap = SharedSnapshotStore.load()
        if let activeEnd = snap.activeRestEndDate {
            let left = Int(ceil(activeEnd.timeIntervalSinceNow))
            if left > 0 {
                endDate = activeEnd
                totalSeconds = snap.activeRestTotalSeconds
                remainingSeconds = left
                isRunning = true
                startTicker()
            } else {
                skip()
            }
        } else if isRunning {
            skip()
        }
    }

    private func startTicker() {
        tickerTask?.cancel()
        tickerTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard let self, self.isRunning, let targetEnd = self.endDate else { break }
                let left = Int(ceil(targetEnd.timeIntervalSinceNow))
                if left <= 0 {
                    self.remainingSeconds = 0
                    self.isRunning = false
                    self.endDate = nil
                    // Play completion sound/haptic for foreground app; let the scheduled notification fire
                    // naturally so Apple Watch receives the mirrored wrist haptic vibration when phone is locked.
                    self.playCompletionFeedback()
                    self.endLiveActivities()
                    var snap = SharedSnapshotStore.load()
                    snap.activeRestEndDate = nil
                    SharedSnapshotStore.save(snap)
                    PhoneWatchSyncService.shared.pushCurrentState()
                    break
                } else {
                    self.remainingSeconds = left
                }
            }
        }
    }

    private func playCompletionFeedback() {
        #if canImport(UIKit)
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        AudioServicesPlaySystemSound(1005)
        #endif
    }

    private func startOrUpdateLiveActivity() {
        #if canImport(ActivityKit)
        guard ActivityAuthorizationInfo().areActivitiesEnabled, let targetEnd = endDate else { return }
        let state = RestTimerAttributes.ContentState(
            endDate: targetEnd,
            totalSeconds: totalSeconds,
            isPaused: false,
            remainingWhenPaused: 0,
            nextSetSummary: nextSetSummary
        )
        let content = ActivityContent(state: state, staleDate: targetEnd.addingTimeInterval(60))

        if let existing = Activity<RestTimerAttributes>.activities.first {
            Task {
                await existing.update(content)
            }
        } else {
            let attrs = RestTimerAttributes(
                workoutName: workoutName,
                exerciseName: exerciseName,
                setNumber: setNumber
            )
            _ = try? Activity.request(attributes: attrs, content: content, pushType: nil)
        }
        #endif
    }

    private func endLiveActivities() {
        #if canImport(ActivityKit)
        for activity in Activity<RestTimerAttributes>.activities {
            let finalState = RestTimerAttributes.ContentState(
                endDate: .now,
                totalSeconds: 0,
                isPaused: false,
                remainingWhenPaused: 0,
                nextSetSummary: "Rest complete — let's lift!"
            )
            Task {
                await activity.end(ActivityContent(state: finalState, staleDate: nil), dismissalPolicy: .immediate)
            }
        }
        #endif
    }
}
