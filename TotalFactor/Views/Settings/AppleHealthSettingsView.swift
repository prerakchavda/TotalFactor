import SwiftUI
import SwiftData

struct AppleHealthSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(HealthKitService.self) private var healthService
    @Query private var profiles: [UserProfile]

    @State private var healthSyncSummary: HealthSyncSummary? = nil
    @State private var isHealthSyncing: Bool = false
    @State private var statusAlertMessage: String? = nil
    @State private var isRequestingAccess: Bool = false
    @State private var accessChecked: Bool = false

    private var profile: UserProfile {
        profiles.first ?? CoachingCoordinator.fetchOrCreateProfile(context: modelContext)
    }

    var body: some View {
        @Bindable var bindableProfile = profile

        Form {
            Section {
                Button {
                    isRequestingAccess = true
                    Task {
                        let granted = await healthService.requestPermissions()
                        await MainActor.run {
                            isRequestingAccess = false
                            accessChecked = true
                            if !granted {
                                statusAlertMessage = healthService.lastAuthError ?? "Apple Health didn't respond."
                            }
                        }
                    }
                } label: {
                    HStack {
                        Label("Check Apple Health Access", systemImage: "heart.text.square")
                        Spacer()
                        if isRequestingAccess {
                            ProgressView()
                                .controlSize(.small)
                        } else if accessChecked {
                            Image(systemName: healthService.lastAuthError == nil ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .foregroundStyle(healthService.lastAuthError == nil ? Color.green : Color.orange)
                        }
                    }
                }
                .disabled(isRequestingAccess)

                if let error = healthService.lastAuthError {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(error)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.orange)
                        if error.localizedCaseInsensitiveContains("entitlement") {
                            Text("This copy of Total Factor was installed without Apple Health permission. Install a build made with the updated Scripts/build_ipa.sh (or run it from Xcode) to fix it.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                Text("Access")
            } footer: {
                Text("Shows the Apple Health permission sheet if anything is missing. Once access works, Total Factor appears in Settings → Health → Data Access & Devices.")
            }

            Section {
                Button {
                    isHealthSyncing = true
                    Task {
                        let summary = await healthService.performFullTwoWaySync(context: modelContext)
                        await MainActor.run {
                            healthSyncSummary = summary
                            isHealthSyncing = false
                        }
                    }
                } label: {
                    HStack {
                        Label("Two-Way Apple Health Sync", systemImage: "arrow.triangle.2.circlepath")
                            .fontWeight(.semibold)
                        Spacer()
                        if isHealthSyncing {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                }
                .disabled(isHealthSyncing)

                if let summary = healthSyncSummary {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Sync Completed: \(summary.totalEvents) events processed")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color.accentColor)
                        Text("• Exported to Health: \(summary.foodExported) meals, \(summary.weighInsExported) weigh-ins, \(summary.workoutsExported) workouts")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("• Imported from Health: \(summary.foodImported) external meals, \(summary.weighInsImported) weigh-ins, \(summary.cardioImported) cardio workouts")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                if let lastSync = healthService.lastSyncDate {
                    HStack {
                        Text("Last Synced")
                        Spacer()
                        Text(lastSync.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Bi-Directional Apple Health Sync")
            } footer: {
                Text("Total Factor syncs seamlessly with Apple Health without duplicating entries.")
            }

            Section {
                Button {
                    Task {
                        let res = await healthService.syncAllHistoryToAppleHealth(context: modelContext)
                        await MainActor.run {
                            statusAlertMessage = "Synced to Apple Health:\n• \(res.foodSynced) meals\n• \(res.weighInsSynced) weigh-ins\n• \(res.workoutsSynced) completed workouts\n\nOther fitness apps on your iPhone can now access this data."
                        }
                    }
                } label: {
                    Label("Push All History to Apple Health", systemImage: "arrow.up.heart")
                }

                Button {
                    Task {
                        let imported = await healthService.importExternalDietaryIntake(context: modelContext)
                        await MainActor.run {
                            statusAlertMessage = imported > 0
                                ? "Imported \(imported) external meals from Apple Health into your daily nutrition log."
                                : "No new external meals found in Apple Health."
                        }
                    }
                } label: {
                    Label("Import Nutrition from Apple Health", systemImage: "arrow.down.heart")
                }
            } header: {
                Text("Bulk Health Tools")
            } footer: {
                Text("Pushing history shares your Total Factor meals, weigh-ins, and gym workouts with Apple Fitness, Strava, and other third-party apps.")
            }

            Section {
                Toggle("iCloud / CloudKit Sync (Paid Dev Account)", isOn: Binding(
                    get: { bindableProfile.enableCloudKitSync },
                    set: { newVal in
                        bindableProfile.enableCloudKitSync = newVal
                        UserDefaults.standard.set(newVal, forKey: "totalfactor.enableCloudKit")
                        try? modelContext.save()
                    }
                ))
            } header: {
                Text("CloudKit Synchronization")
            } footer: {
                Text("Syncs SwiftData across your personal devices signed into iCloud.")
            }
        }
        .navigationTitle("Apple Health & Cloud")
        .navigationBarTitleDisplayMode(.inline)
        .alert(
            "Apple Health Sync",
            isPresented: Binding(
                get: { statusAlertMessage != nil },
                set: { if !$0 { statusAlertMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { statusAlertMessage = nil }
        } message: {
            Text(statusAlertMessage ?? "")
        }
    }
}
