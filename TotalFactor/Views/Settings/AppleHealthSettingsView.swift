import SwiftUI
import SwiftData
import UniformTypeIdentifiers

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
    @State private var showingHealthFileImporter: Bool = false
    @State private var isImportingHealthFile: Bool = false
    @State private var showingManualHealthEntry: Bool = false

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

                Button {
                    showingHealthFileImporter = true
                } label: {
                    HStack {
                        Label("Import Apple Health Export (.zip / .xml / .json / .csv)", systemImage: "doc.badge.arrow.up")
                            .fontWeight(.semibold)
                        Spacer()
                        if isImportingHealthFile {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                }
                .disabled(isImportingHealthFile)

                Button {
                    showingManualHealthEntry = true
                } label: {
                    Label("Log Today's Health Metrics Manually", systemImage: "slider.horizontal.3")
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
                Text("Free Sync Options (No Paid Apple Dev Account)")
            } footer: {
                Text("• Zero-Freeze File Import: In Apple Health → tap Profile → Export All Health Data, then share export.zip to Total Factor (or pick it above). Also supports Health Auto Export JSON & CSV files.\n• Shortcuts Bridge: If an earlier Health Sync shortcut froze on iPhone, delete it in Shortcuts and reinstall the updated grouped shortcut above.")
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
        .sheet(isPresented: $showingManualHealthEntry) {
            ManualHealthTelemetrySheet(
                initialStats: healthService.todayStats,
                onSave: { payload in
                    let summary = ShortcutsHealthBridge.apply(payload, context: modelContext, healthService: healthService)
                    statusAlertMessage = "Saved today's health telemetry:\n\(summary)"
                }
            )
        }
        .fileImporter(
            isPresented: $showingHealthFileImporter,
            allowedContentTypes: [.zip, .xml, .json, .commaSeparatedText, .plainText],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                isImportingHealthFile = true
                let defaultUnit = profile.unitSystem
                Task {
                    do {
                        let summary = try await AppleHealthExportImporter.importFile(
                            at: url,
                            context: modelContext,
                            healthService: healthService,
                            defaultUnitSystem: defaultUnit
                        )
                        await MainActor.run {
                            isImportingHealthFile = false
                            statusAlertMessage = "\(summary.formatDescription) imported:\n\(summary.telemetrySummary)"
                        }
                    } catch {
                        await MainActor.run {
                            isImportingHealthFile = false
                            statusAlertMessage = error.localizedDescription
                        }
                    }
                }
            case .failure(let error):
                statusAlertMessage = error.localizedDescription
            }
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

private struct ManualHealthTelemetrySheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var stepsText: String
    @State private var activeKcalText: String
    @State private var restingKcalText: String
    @State private var rhrText: String
    @State private var hrvText: String
    @State private var hrText: String
    @State private var sleepHoursText: String

    let onSave: (BridgedHealthPayload) -> Void

    init(initialStats: HealthDisplayDashboardStats, onSave: @escaping (BridgedHealthPayload) -> Void) {
        self.onSave = onSave
        _stepsText = State(initialValue: initialStats.stepsToday > 0 ? "\(initialStats.stepsToday)" : "")
        _activeKcalText = State(initialValue: initialStats.activeCaloriesDisplayOnly > 0 ? "\(Int(initialStats.activeCaloriesDisplayOnly.rounded()))" : "")
        _restingKcalText = State(initialValue: initialStats.basalCaloriesDisplayOnly > 0 ? "\(Int(initialStats.basalCaloriesDisplayOnly.rounded()))" : "")
        _rhrText = State(initialValue: initialStats.restingHeartRateBPM.map { "\(Int($0.rounded()))" } ?? "")
        _hrvText = State(initialValue: initialStats.hrvSDNNMilliseconds.map { "\(Int($0.rounded()))" } ?? "")
        _hrText = State(initialValue: initialStats.currentHeartRateBPM.map { "\(Int($0.rounded()))" } ?? "")
        _sleepHoursText = State(initialValue: initialStats.sleepHoursLastNight.map { String(format: "%.1f", $0) } ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Activity & Energy (Today)") {
                    HStack {
                        Text("Steps")
                        Spacer()
                        TextField("8,500", text: $stepsText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Text("Active Calories (kcal)")
                        Spacer()
                        TextField("450", text: $activeKcalText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Text("Resting Calories (kcal)")
                        Spacer()
                        TextField("1,650", text: $restingKcalText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                }

                Section("Heart & Recovery") {
                    HStack {
                        Text("Resting Heart Rate (bpm)")
                        Spacer()
                        TextField("58", text: $rhrText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Text("HRV SDNN (ms)")
                        Spacer()
                        TextField("52", text: $hrvText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Text("Current Heart Rate (bpm)")
                        Spacer()
                        TextField("72", text: $hrText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Text("Sleep Last Night (hr)")
                        Spacer()
                        TextField("7.5", text: $sleepHoursText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }
            .navigationTitle("Log Today's Health Metrics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var payload = BridgedHealthPayload()
                        if let v = parseNumber(stepsText) { payload.steps = Int(v.rounded()) }
                        if let v = parseNumber(activeKcalText) { payload.activeCalories = v.rounded() }
                        if let v = parseNumber(restingKcalText) { payload.basalCalories = v.rounded() }
                        if let v = parseNumber(rhrText) { payload.restingHeartRateBPM = v.rounded() }
                        if let v = parseNumber(hrvText) { payload.hrvSDNNMilliseconds = v.rounded() }
                        if let v = parseNumber(hrText) { payload.currentHeartRateBPM = v.rounded() }
                        if let v = parseNumber(sleepHoursText) { payload.sleepHours = (v * 10).rounded() / 10.0 }
                        onSave(payload)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private func parseNumber(_ s: String) -> Double? {
        Double(s.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ""))
    }
}

private struct ShortcutShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
