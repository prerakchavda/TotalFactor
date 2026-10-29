import Foundation
import AppIntents
#if canImport(ActivityKit)
import ActivityKit
#endif
#if canImport(UserNotifications)
import UserNotifications
#endif

/// Shared helper used by both `RestTimerService` (in-app) and `LiveActivityIntent`s (Lock Screen / Dynamic Island)
/// so the `0:00` notification chime stays 100% synchronized even when adjusted or skipped while locked.
public enum RestTimerNotificationScheduler {
    public static let notificationID = "totalfactor.resttimer.done"

    public static func requestAuthorizationIfNeeded() {
        #if canImport(UserNotifications)
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            if settings.authorizationStatus == .notDetermined {
                center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
            }
        }
        #endif
    }

    public static func schedule(endDate: Date, exerciseName: String, nextSummary: String = "") {
        #if canImport(UserNotifications)
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [notificationID])
        center.removeDeliveredNotifications(withIdentifiers: [notificationID])

        let interval = endDate.timeIntervalSinceNow
        guard interval >= 1.0 else { return }

        let content = UNMutableNotificationContent()
        content.title = "Rest Complete — \(exerciseName)"
        content.body = nextSummary.isEmpty ? "Time for your next working set." : nextSummary
        content.sound = .default
        content.interruptionLevel = .timeSensitive

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let request = UNNotificationRequest(identifier: notificationID, content: content, trigger: trigger)
        center.add(request) { _ in }
        #endif
    }

    public static func cancel() {
        #if canImport(UserNotifications)
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [notificationID])
        center.removeDeliveredNotifications(withIdentifiers: [notificationID])
        #endif
    }
}

public struct AdjustRestTimerIntent: LiveActivityIntent {
    public static var title: LocalizedStringResource = "Add 30 Seconds to Rest Timer"
    public static var description = IntentDescription("Extends the active rest timer by 30 seconds.")

    @Parameter(title: "Seconds", default: 30)
    public var seconds: Int

    public init() {
        self.seconds = 30
    }

    public init(seconds: Int) {
        self.seconds = seconds
    }

    public func perform() async throws -> some IntentResult {
        SharedSnapshotStore.enqueueAction(
            PendingQuickAction(kind: .adjustRestSeconds, numericValue: Double(seconds), label: "+\(seconds)s")
        )
        var snap = SharedSnapshotStore.load()
        if let currentEnd = snap.activeRestEndDate {
            let updatedEnd = currentEnd.addingTimeInterval(TimeInterval(seconds))
            if updatedEnd <= .now {
                snap.activeRestEndDate = nil
                snap.activeRestTotalSeconds = 0
                SharedSnapshotStore.save(snap)
                RestTimerNotificationScheduler.cancel()
            } else {
                snap.activeRestEndDate = updatedEnd
                snap.activeRestTotalSeconds += seconds
                SharedSnapshotStore.save(snap)
                RestTimerNotificationScheduler.schedule(
                    endDate: updatedEnd,
                    exerciseName: snap.activeRestExercise ?? "Next Set"
                )

                #if canImport(ActivityKit)
                for activity in Activity<RestTimerAttributes>.activities {
                    var state = activity.content.state
                    state.endDate = updatedEnd
                    state.totalSeconds += seconds
                    await activity.update(ActivityContent(state: state, staleDate: updatedEnd.addingTimeInterval(60)))
                }
                #endif
            }
        }
        return .result()
    }
}

public struct SkipRestTimerIntent: LiveActivityIntent {
    public static var title: LocalizedStringResource = "Skip Rest Timer"
    public static var description = IntentDescription("Ends the active rest countdown immediately.")

    public init() {}

    public func perform() async throws -> some IntentResult {
        SharedSnapshotStore.enqueueAction(
            PendingQuickAction(kind: .skipRestTimer, numericValue: 0, label: "Skip")
        )
        var snap = SharedSnapshotStore.load()
        snap.activeRestEndDate = nil
        snap.activeRestTotalSeconds = 0
        SharedSnapshotStore.save(snap)
        RestTimerNotificationScheduler.cancel()

        #if canImport(ActivityKit)
        for activity in Activity<RestTimerAttributes>.activities {
            let finalState = RestTimerAttributes.ContentState(
                endDate: .now,
                totalSeconds: 0,
                isPaused: false,
                remainingWhenPaused: 0,
                nextSetSummary: "Ready for next set"
            )
            await activity.end(ActivityContent(state: finalState, staleDate: nil), dismissalPolicy: .immediate)
        }
        #endif
        return .result()
    }
}

public struct WidgetQuickAddCaloriesIntent: AppIntent {
    public static var title: LocalizedStringResource = "Quick Add Calories"
    public static var description = IntentDescription("Quickly logs a calorie snack from a widget.")

    @Parameter(title: "Calories", default: 200)
    public var calories: Int

    public init() {
        self.calories = 200
    }

    public init(calories: Int) {
        self.calories = calories
    }

    public func perform() async throws -> some IntentResult {
        SharedSnapshotStore.enqueueAction(
            PendingQuickAction(kind: .quickCalories, numericValue: Double(calories), label: "Widget Quick Add")
        )
        var snap = SharedSnapshotStore.load()
        snap.caloriesEaten += Double(calories)
        SharedSnapshotStore.save(snap)
        return .result()
    }
}

public struct WidgetNudgeWeighInIntent: AppIntent {
    public static var title: LocalizedStringResource = "Adjust Widget Weigh-In"
    public static var description = IntentDescription("Nudges the draft scale weight up or down directly on the Trend Weight widget.")

    @Parameter(title: "Direction", default: 1)
    public var direction: Int

    public init() {
        self.direction = 1
    }

    public init(direction: Int) {
        self.direction = direction
    }

    public func perform() async throws -> some IntentResult {
        var snap = SharedSnapshotStore.load()
        let baseKg = snap.draftWeighInKg ?? snap.latestScaleWeightKg ?? snap.trendWeightKg ?? 80.0
        let isImperial = (snap.unitSystemRaw == "imperial")
        // Nudge by ±0.2 lb in Imperial or ±0.1 kg in Metric
        let stepKg = isImperial ? (0.2 / 2.2046226218) : 0.1
        let updatedKg = max(25.0, min(350.0, baseKg + Double(direction) * stepKg))
        snap.draftWeighInKg = updatedKg
        SharedSnapshotStore.save(snap)
        return .result()
    }
}

public struct WidgetLogWeighInIntent: AppIntent {
    public static var title: LocalizedStringResource = "Log Widget Weigh-In"
    public static var description = IntentDescription("Logs the displayed scale weight from the Trend Weight widget and updates EMA trend weight.")

    public init() {}

    public func perform() async throws -> some IntentResult {
        var snap = SharedSnapshotStore.load()
        let kg = snap.draftWeighInKg ?? snap.latestScaleWeightKg ?? snap.trendWeightKg ?? 80.0
        SharedSnapshotStore.enqueueAction(
            PendingQuickAction(kind: .weighInKg, numericValue: kg, label: "Widget Weigh-In")
        )
        snap.latestScaleWeightKg = kg
        if let prevTrend = snap.trendWeightKg {
            snap.trendWeightKg = prevTrend + 0.1 * (kg - prevTrend)
        } else {
            snap.trendWeightKg = kg
        }
        snap.draftWeighInKg = nil
        SharedSnapshotStore.save(snap)
        return .result()
    }
}
