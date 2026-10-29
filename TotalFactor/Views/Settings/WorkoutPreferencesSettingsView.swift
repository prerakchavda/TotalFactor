import SwiftUI
import SwiftData

struct WorkoutPreferencesSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var gymProfiles: [GymProfile]

    @State private var notifService = NotificationService.shared
    @State private var showingGymProfiles: Bool = false

    var body: some View {
        Form {
            Section("Rest Timers & Apple Watch") {
                Toggle("Rest Timer Sound & Watch Vibration", isOn: Binding(
                    get: { notifService.isRestTimerAlertEnabled },
                    set: { notifService.isRestTimerAlertEnabled = $0 }
                ))

                Text("When your iPhone is locked or in your pocket during a gym session, rest timer completion alerts mirror to your Apple Watch with wrist haptic vibrations — no watch app launch required.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Section("Gym Equipment Profiles") {
                NavigationLink {
                    GymProfileEditorView()
                } label: {
                    HStack {
                        Label("Manage Gym Profiles", systemImage: "dumbbell.fill")
                        Spacer()
                        Text("\(gymProfiles.count) gyms")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }

                if let active = gymProfiles.first(where: \.isDefault) ?? gymProfiles.first {
                    HStack {
                        Text("Active Gym")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(active.name)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }
        }
        .navigationTitle("Workouts & Training")
        .navigationBarTitleDisplayMode(.inline)
    }
}
