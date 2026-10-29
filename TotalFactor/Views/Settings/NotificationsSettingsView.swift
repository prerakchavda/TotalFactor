import SwiftUI

struct NotificationsSettingsView: View {
    @State private var notifService = NotificationService.shared

    var body: some View {
        Form {
            if !notifService.isAuthorized {
                Section {
                    Button {
                        Task {
                            _ = await notifService.requestAuthorization()
                        }
                    } label: {
                        HStack {
                            Image(systemName: "bell.badge.fill")
                                .foregroundStyle(Color.accentColor)
                            Text("Enable iOS Notifications")
                                .fontWeight(.semibold)
                        }
                    }
                } footer: {
                    Text("Total Factor needs permission to deliver morning weigh-in, meal logging, and gym rest reminders.")
                }
            }

            Section("Daily Morning Weigh-In") {
                Toggle("Weigh-In Reminder", isOn: Binding(
                    get: { notifService.isWeighInReminderEnabled },
                    set: { notifService.isWeighInReminderEnabled = $0 }
                ))

                if notifService.isWeighInReminderEnabled {
                    DatePicker("Reminder Time", selection: Binding(
                        get: {
                            var c = Calendar.current.dateComponents([.year, .month, .day], from: .now)
                            c.hour = notifService.weighInReminderHour
                            c.minute = notifService.weighInReminderMinute
                            return Calendar.current.date(from: c) ?? .now
                        },
                        set: { newDate in
                            let comps = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                            notifService.weighInReminderHour = comps.hour ?? 7
                            notifService.weighInReminderMinute = comps.minute ?? 30
                        }
                    ), displayedComponents: .hourAndMinute)
                }
            }

            Section("Meal & Food Logging") {
                Toggle("Meal Logging Reminders", isOn: Binding(
                    get: { notifService.isFoodLoggingReminderEnabled },
                    set: { notifService.isFoodLoggingReminderEnabled = $0 }
                ))

                if notifService.isFoodLoggingReminderEnabled {
                    DatePicker("Lunch Reminder", selection: Binding(
                        get: {
                            var c = Calendar.current.dateComponents([.year, .month, .day], from: .now)
                            c.hour = notifService.lunchReminderHour
                            c.minute = notifService.lunchReminderMinute
                            return Calendar.current.date(from: c) ?? .now
                        },
                        set: { newDate in
                            let comps = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                            notifService.lunchReminderHour = comps.hour ?? 12
                            notifService.lunchReminderMinute = comps.minute ?? 30
                        }
                    ), displayedComponents: .hourAndMinute)

                    DatePicker("Dinner Reminder", selection: Binding(
                        get: {
                            var c = Calendar.current.dateComponents([.year, .month, .day], from: .now)
                            c.hour = notifService.dinnerReminderHour
                            c.minute = notifService.dinnerReminderMinute
                            return Calendar.current.date(from: c) ?? .now
                        },
                        set: { newDate in
                            let comps = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                            notifService.dinnerReminderHour = comps.hour ?? 19
                            notifService.dinnerReminderMinute = comps.minute ?? 30
                        }
                    ), displayedComponents: .hourAndMinute)

                    Toggle("Evening Missed Food Check (8:45 PM)", isOn: Binding(
                        get: { notifService.isMissedFoodCheckEnabled },
                        set: { notifService.isMissedFoodCheckEnabled = $0 }
                    ))
                }
            }

            Section("Workout & Energy Alerts") {
                Toggle("Pre-Workout Fuel & Energy Alert", isOn: Binding(
                    get: { notifService.isPreWorkoutFuelReminderEnabled },
                    set: { notifService.isPreWorkoutFuelReminderEnabled = $0 }
                ))
            }
        }
        .navigationTitle("Reminders & Notifications")
        .navigationBarTitleDisplayMode(.inline)
    }
}
