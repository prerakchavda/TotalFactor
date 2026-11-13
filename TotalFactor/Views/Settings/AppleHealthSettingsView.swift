import SwiftUI
import SwiftData

struct AppleHealthSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @Environment(HealthKitService.self) private var healthService
    @Query private var profiles: [UserProfile]

    @State private var healthSyncSummary: HealthSyncSummary? = nil
    @State private var isHealthSyncing: Bool = false
    @State private var statusAlertMessage: String? = nil
    @State private var isRequestingAccess: Bool = false
    @State private var accessChecked: Bool = false
    @State private var shareShortcutItem: IdentifiableURL? = nil

    private struct IdentifiableURL: Identifiable {
        let id = UUID()
        let url: URL
    }

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
                            Text("Apple blocks direct HealthKit entitlements on Free Apple ID / SideStore installs. Use the free Apple Shortcuts Bridge below to sync Steps, Calories, Heart Rate, Weight & Workouts.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                Text("Access")
            } footer: {
                Text("Direct HealthKit requires a Paid Apple Developer account. On Free / SideStore builds, use Apple Shortcuts Bridge below.")
            }

            Section {
                Button {
                    if let url = ShortcutsHealthBridge.syncShortcutURL {
                        openURL(url)
                    }
                } label: {
                    Label("Run Health Sync Shortcut Now", systemImage: "bolt.heart.fill")
                        .fontWeight(.semibold)
                }

                Button {
                    if let url = ShortcutsHealthBridge.workoutShortcutURL {
                        openURL(url)
                    }
                } label: {
                    Label("Log / Import Workout via Shortcut", systemImage: "figure.run.circle")
                }

                Button {
                    installBundledShortcut(named: ShortcutsHealthBridge.healthSyncShortcutName)
                } label: {
                    Label("Install \"\(ShortcutsHealthBridge.healthSyncShortcutName)\" Shortcut", systemImage: "square.and.arrow.down")
                }

                Button {
                    installBundledShortcut(named: ShortcutsHealthBridge.workoutShortcutName)
                } label: {
                    Label("Install \"\(ShortcutsHealthBridge.workoutShortcutName)\" Shortcut", systemImage: "square.and.arrow.down")
                }

                if let syncDate = healthService.lastShortcutsSyncDate {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text("Last Shortcuts Sync")
                            Spacer()
                            Text(syncDate.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        if let summary = healthService.lastShortcutsSyncSummary, !summary.isEmpty {
                            Text(summary)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("Apple Shortcuts Bridge (Free / SideStore)")
            } footer: {
                Text("1. Tap Install (or open the synced shortcut in Apple Shortcuts).\n2. Tap Run to sync Steps, Active/Resting Calories, RHR, HRV, HR & Weight.\n3. Optional: In iPhone Shortcuts → Automation → +, create a Daily or \"When I end any workout\" trigger to run automatically.")
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
        .sheet(item: $shareShortcutItem) { item in
            ShortcutShareSheet(activityItems: [item.url])
        }
    }

    private func installBundledShortcut(named name: String) {
        if let url = ShortcutsHealthBridge.bundledShortcutURL(named: name) {
            shareShortcutItem = IdentifiableURL(url: url)
        } else {
            statusAlertMessage = "Shortcut file \"\(name).shortcut\" was not found in app resources."
        }
    }
}

private struct ShortcutShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
