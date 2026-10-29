import Foundation
import SwiftUI
#if canImport(UserNotifications)
import UserNotifications
#endif

/// Centralized manager for local notifications, morning weigh-in reminders,
/// meal logging nudges, pre-workout fueling alerts, and rest timer alerts.
@MainActor
@Observable
public final class NotificationService {
    public static let shared = NotificationService()

    public static let weighInNotificationID = "totalfactor.reminder.weighin"
    public static let lunchNotificationID = "totalfactor.reminder.lunch"
    public static let dinnerNotificationID = "totalfactor.reminder.dinner"
    public static let missedFoodCheckNotificationID = "totalfactor.reminder.missedfood"
    public static let preWorkoutFuelNotificationID = "totalfactor.reminder.preworkoutfuel"

    // MARK: - Persistent User Preferences

    public var isAuthorized: Bool = false

    public var isWeighInReminderEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "tf_notif_weighin_enabled") as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: "tf_notif_weighin_enabled")
            scheduleWeighInReminder()
        }
    }

    public var weighInReminderHour: Int {
        get { UserDefaults.standard.object(forKey: "tf_notif_weighin_hour") as? Int ?? 7 }
        set {
            UserDefaults.standard.set(newValue, forKey: "tf_notif_weighin_hour")
            scheduleWeighInReminder()
        }
    }

    public var weighInReminderMinute: Int {
        get { UserDefaults.standard.object(forKey: "tf_notif_weighin_minute") as? Int ?? 30 }
        set {
            UserDefaults.standard.set(newValue, forKey: "tf_notif_weighin_minute")
            scheduleWeighInReminder()
        }
    }

    public var isFoodLoggingReminderEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "tf_notif_food_enabled") as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: "tf_notif_food_enabled")
            scheduleMealReminders()
        }
    }

    public var lunchReminderHour: Int {
        get { UserDefaults.standard.object(forKey: "tf_notif_lunch_hour") as? Int ?? 12 }
        set {
            UserDefaults.standard.set(newValue, forKey: "tf_notif_lunch_hour")
            scheduleMealReminders()
        }
    }

    public var lunchReminderMinute: Int {
        get { UserDefaults.standard.object(forKey: "tf_notif_lunch_minute") as? Int ?? 30 }
        set {
            UserDefaults.standard.set(newValue, forKey: "tf_notif_lunch_minute")
            scheduleMealReminders()
        }
    }

    public var dinnerReminderHour: Int {
        get { UserDefaults.standard.object(forKey: "tf_notif_dinner_hour") as? Int ?? 19 }
        set {
            UserDefaults.standard.set(newValue, forKey: "tf_notif_dinner_hour")
            scheduleMealReminders()
        }
    }

    public var dinnerReminderMinute: Int {
        get { UserDefaults.standard.object(forKey: "tf_notif_dinner_minute") as? Int ?? 30 }
        set {
            UserDefaults.standard.set(newValue, forKey: "tf_notif_dinner_minute")
            scheduleMealReminders()
        }
    }

    public var isMissedFoodCheckEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "tf_notif_missed_food_enabled") as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: "tf_notif_missed_food_enabled")
            scheduleMealReminders()
        }
    }

    public var isPreWorkoutFuelReminderEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "tf_notif_preworkout_enabled") as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: "tf_notif_preworkout_enabled")
            rescheduleAll()
        }
    }

    public var isRestTimerAlertEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "tf_notif_resttimer_enabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "tf_notif_resttimer_enabled") }
    }

    public init() {
        checkAuthorizationStatus()
    }

    // MARK: - Authorization

    public func checkAuthorizationStatus() {
        #if canImport(UserNotifications)
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            Task { @MainActor [weak self] in
                self?.isAuthorized = (settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional)
            }
        }
        #endif
    }

    public func requestAuthorization() async -> Bool {
        #if canImport(UserNotifications)
        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            self.isAuthorized = granted
            if granted {
                rescheduleAll()
            }
            return granted
        } catch {
            self.isAuthorized = false
            return false
        }
        #else
        return false
        #endif
    }

    // MARK: - Scheduling

    public func rescheduleAll() {
        scheduleWeighInReminder()
        scheduleMealReminders()
    }

    public func scheduleWeighInReminder() {
        #if canImport(UserNotifications)
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.weighInNotificationID])

        guard isWeighInReminderEnabled else { return }

        let content = UNMutableNotificationContent()
        content.title = "Morning Weigh-In"
        content.body = "Step on the scale before breakfast to log today's weight and keep your trend accurate."
        content.sound = .default
        content.interruptionLevel = .active

        var dateComponents = DateComponents()
        dateComponents.hour = weighInReminderHour
        dateComponents.minute = weighInReminderMinute

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(identifier: Self.weighInNotificationID, content: content, trigger: trigger)

        center.add(request) { _ in }
        #endif
    }

    public func scheduleMealReminders() {
        #if canImport(UserNotifications)
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [
            Self.lunchNotificationID,
            Self.dinnerNotificationID,
            Self.missedFoodCheckNotificationID
        ])

        guard isFoodLoggingReminderEnabled else { return }

        // 1. Lunch
        let lunchContent = UNMutableNotificationContent()
        lunchContent.title = "Lunch Logging"
        lunchContent.body = "Time to log lunch! Keep your macros on track for the day."
        lunchContent.sound = .default

        var lunchComponents = DateComponents()
        lunchComponents.hour = lunchReminderHour
        lunchComponents.minute = lunchReminderMinute
        let lunchTrigger = UNCalendarNotificationTrigger(dateMatching: lunchComponents, repeats: true)
        center.add(UNNotificationRequest(identifier: Self.lunchNotificationID, content: lunchContent, trigger: lunchTrigger))

        // 2. Dinner
        let dinnerContent = UNMutableNotificationContent()
        dinnerContent.title = "Dinner & Evening Macros"
        dinnerContent.body = "Check your remaining protein and calories to close out today's targets."
        dinnerContent.sound = .default

        var dinnerComponents = DateComponents()
        dinnerComponents.hour = dinnerReminderHour
        dinnerComponents.minute = dinnerReminderMinute
        let dinnerTrigger = UNCalendarNotificationTrigger(dateMatching: dinnerComponents, repeats: true)
        center.add(UNNotificationRequest(identifier: Self.dinnerNotificationID, content: dinnerContent, trigger: dinnerTrigger))

        // 3. Evening missed food check (8:45 PM)
        if isMissedFoodCheckEnabled {
            let missedContent = UNMutableNotificationContent()
            missedContent.title = "Daily Nutrition Check"
            missedContent.body = "Don't forget to mark today complete or log your evening meals."
            missedContent.sound = .default

            var missedComponents = DateComponents()
            missedComponents.hour = 20
            missedComponents.minute = 45
            let missedTrigger = UNCalendarNotificationTrigger(dateMatching: missedComponents, repeats: true)
            center.add(UNNotificationRequest(identifier: Self.missedFoodCheckNotificationID, content: missedContent, trigger: missedTrigger))
        }
        #endif
    }

    public func schedulePreWorkoutFuelAlert(workoutTitle: String, fireDate: Date) {
        #if canImport(UserNotifications)
        guard isPreWorkoutFuelReminderEnabled else { return }
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.preWorkoutFuelNotificationID])

        let interval = fireDate.timeIntervalSinceNow
        guard interval >= 10 else { return }

        let content = UNMutableNotificationContent()
        content.title = "⚡️ Pre-Workout Fuel Reminder"
        content.body = "Training \(workoutTitle) soon? Have 25–40g fast-digesting carbs and some protein to maximize workout performance."
        content.sound = .default
        content.interruptionLevel = .timeSensitive

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let request = UNNotificationRequest(identifier: Self.preWorkoutFuelNotificationID, content: content, trigger: trigger)
        center.add(request) { _ in }
        #endif
    }
}
