import SwiftUI
import SwiftData

struct UnitsScheduleSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]

    private var profile: UserProfile {
        profiles.first ?? CoachingCoordinator.fetchOrCreateProfile(context: modelContext)
    }

    var body: some View {
        @Bindable var bindableProfile = profile

        Form {
            Section("Measurement Units") {
                Picker("Units", selection: $bindableProfile.unitSystem) {
                    ForEach(UnitSystem.allCases) { u in
                        Text(u.displayName).tag(u)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Daily Scale Weigh-In Rule (§3)") {
                Picker("Rule", selection: $bindableProfile.weighInRule) {
                    ForEach(WeighInRule.allCases) { r in
                        Text(r.displayName).tag(r)
                    }
                }

                Text(bindableProfile.weighInRule.explanation)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Section("Weekly Schedule & Calendar") {
                Picker("First Day of Week", selection: $bindableProfile.firstDayOfWeek) {
                    Text("Sunday").tag(1)
                    Text("Monday").tag(2)
                }

                Picker("Weekly Check-In Day", selection: $bindableProfile.checkInWeekday) {
                    Text("Sunday").tag(1)
                    Text("Monday").tag(2)
                    Text("Tuesday").tag(3)
                    Text("Wednesday").tag(4)
                    Text("Thursday").tag(5)
                    Text("Friday").tag(6)
                    Text("Saturday").tag(7)
                }

                Text("On your check-in day, Total Factor reviews your weekly intake and weight trend to offer recommended macro adjustments.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Units & Schedule")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: bindableProfile.unitSystemRaw) { _, _ in
            try? modelContext.save()
            _ = CoachingCoordinator.evaluate(context: modelContext)
        }
        .onChange(of: bindableProfile.weighInRuleRaw) { _, _ in
            try? modelContext.save()
            _ = CoachingCoordinator.evaluate(context: modelContext)
        }
        .onChange(of: bindableProfile.firstDayOfWeek) { _, _ in
            try? modelContext.save()
        }
        .onChange(of: bindableProfile.checkInWeekday) { _, _ in
            try? modelContext.save()
        }
    }
}
