import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(HealthKitService.self) private var healthService

    @Query private var profiles: [UserProfile]
    @Query private var goals: [Goal]
    @Query private var customNutrientTargets: [NutrientTarget]

    @State private var exportedFileURL: URL? = nil
    @State private var showingStrongImporter: Bool = false
    @State private var importStatusMessage: String? = nil
    @State private var exportPackage: ExportAllArchiveService.ExportPackage? = nil
    @State private var showingExportSheet: Bool = false
    @State private var isGeneratingExport: Bool = false
    @State private var healthSyncSummary: HealthSyncSummary? = nil
    @State private var isHealthSyncing: Bool = false

    // Optional Gemini API configuration (Keychain-backed via GeminiConfigStore)
    @State private var geminiEnabled: Bool = GeminiConfigStore.isEnabled
    @State private var geminiModel: String = GeminiConfigStore.selectedModel
    @State private var geminiApiKeyDraft: String = GeminiConfigStore.loadAPIKey()
    @State private var geminiSavedFeedback: Bool = false
    @State private var notifService = NotificationService.shared

    private var profile: UserProfile {
        profiles.first ?? CoachingCoordinator.fetchOrCreateProfile(context: modelContext)
    }

    private var goal: Goal {
        goals.first(where: \.isActive) ?? CoachingCoordinator.fetchOrCreateGoal(profile: profile, context: modelContext)
    }

    var body: some View {
        @Bindable var bindableProfile = profile
        @Bindable var bindableGoal = goal

        NavigationStack {
            Form {
                Section {
                    NavigationLink {
                        UpdateLogView()
                    } label: {
                        HStack {
                            Label("What's New & Update Log", systemImage: "sparkles.rectangle.stack")
                            Spacer()
                            Text(AppVersionInfo.displayBadge)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Goal & Adaptive Coaching") {
                    Picker("Active Goal", selection: $bindableGoal.type) {
                        ForEach(GoalType.allCases) { g in
                            Text(g.displayName).tag(g)
                        }
                    }

                    if bindableGoal.type != .maintain {
                        VStack(alignment: .leading) {
                            HStack {
                                Text("Weekly Target Rate")
                                Spacer()
                                Text(String(format: "%.2f%% BW / wk", bindableGoal.ratePercentPerWeek))
                                    .monospacedDigit()
                            }
                            Slider(value: $bindableGoal.ratePercentPerWeek, in: 0.10...1.25, step: 0.05)
                        }
                    }

                    Toggle("Training-Day Carb Cycling (§12)", isOn: $bindableProfile.enableTrainingDayCarbCycling)
                    Toggle("Allow Targets Below BMR / Safety Floor", isOn: $bindableProfile.overrideCalorieFloor)

                    NavigationLink {
                        NutrientTargetsEditorView()
                    } label: {
                        HStack {
                            Label("Custom Nutrient Floors & Ceilings", systemImage: "slider.horizontal.3")
                            Spacer()
                            if !customNutrientTargets.isEmpty {
                                Text("\(customNutrientTargets.count) custom")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                }

                Section("Intermittent Fasting") {
                    Toggle("Enable Intermittent Fasting", isOn: $bindableProfile.enableIntermittentFasting)
                    if bindableProfile.enableIntermittentFasting {
                        Picker("Fasting Protocol", selection: $bindableProfile.fastingProtocol) {
                            ForEach(FastingProtocol.allCases) { proto in
                                Text(proto.displayName).tag(proto)
                            }
                        }

                        HStack {
                            Text("Fast / Eat Window")
                            Spacer()
                            Text("\(Int(bindableProfile.fastingProtocol.fastHours))h Fast • \(Int(bindableProfile.fastingProtocol.eatingHours))h Eating")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Units & Schedule (§5)") {
                    Picker("Units", selection: $bindableProfile.unitSystem) {
                        ForEach(UnitSystem.allCases) { u in
                            Text(u.displayName).tag(u)
                        }
                    }

                    Picker("Daily Weigh-In Rule (§3)", selection: $bindableProfile.weighInRule) {
                        ForEach(WeighInRule.allCases) { r in
                            Text(r.displayName).tag(r)
                        }
                    }

                    Picker("First Day of Week", selection: $bindableProfile.firstDayOfWeek) {
                        Text("Sunday").tag(1)
                        Text("Monday").tag(2)
                    }

                    Picker("Weekly Check-In Day", selection: $bindableProfile.checkInWeekday) {
                        Text("Sunday").tag(1)
                        Text("Monday").tag(2)
                        Text("Friday").tag(6)
                        Text("Saturday").tag(7)
                    }
                }

                Section("Reminders & Notifications") {
                    if !notifService.isAuthorized {
                        Button {
                            Task {
                                _ = await notifService.requestAuthorization()
                            }
                        } label: {
                            Label("Enable iOS Notifications", systemImage: "bell.badge")
                                .foregroundStyle(Color.accentColor)
                        }
                    }

                    Toggle("Daily Morning Weigh-In Reminder", isOn: Binding(
                        get: { notifService.isWeighInReminderEnabled },
                        set: { notifService.isWeighInReminderEnabled = $0 }
                    ))

                    if notifService.isWeighInReminderEnabled {
                        DatePicker("Weigh-In Time", selection: Binding(
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

                    Toggle("Meal & Nutrition Logging Reminders", isOn: Binding(
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

                    Toggle("Pre-Workout Fuel & Energy Alert", isOn: Binding(
                        get: { notifService.isPreWorkoutFuelReminderEnabled },
                        set: { notifService.isPreWorkoutFuelReminderEnabled = $0 }
                    ))

                    Toggle("Rest Timer Sound & Watch Vibration", isOn: Binding(
                        get: { notifService.isRestTimerAlertEnabled },
                        set: { notifService.isRestTimerAlertEnabled = $0 }
                    ))

                    Text("When your iPhone is locked or in your pocket, rest timer completion alerts mirror to your Apple Watch with wrist haptic vibrations — no companion app required.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Section("Apple Health Bi-Directional Sync (v1.5.3)") {
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
                            Spacer()
                            if isHealthSyncing {
                                ProgressView()
                                    .controlSize(.small)
                            }
                        }
                    }
                    .disabled(isHealthSyncing)

                    if let summary = healthSyncSummary {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Last Sync: \(summary.totalEvents) events processed")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.accentColor)
                            Text("• Pushed to Health: \(summary.foodExported) meals, \(summary.weighInsExported) weigh-ins, \(summary.workoutsExported) workouts")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text("• Pulled from Health: \(summary.foodImported) external meals, \(summary.weighInsImported) weigh-ins")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }

                    Button {
                        Task {
                            let res = await healthService.syncAllHistoryToAppleHealth(context: modelContext)
                            await MainActor.run {
                                importStatusMessage = "Synced to Apple Health:\n• \(res.foodSynced) meals\n• \(res.weighInsSynced) weigh-ins\n• \(res.workoutsSynced) completed workouts\n\nOther fitness & health apps on your iPhone can now access this data."
                            }
                        }
                    } label: {
                        Label("Sync All History to Apple Health", systemImage: "arrow.up.heart")
                    }

                    Button {
                        Task {
                            let imported = await healthService.importExternalDietaryIntake(context: modelContext)
                            await MainActor.run {
                                importStatusMessage = imported > 0
                                    ? "Imported \(imported) external meals from Apple Health into your daily nutrition log."
                                    : "No new external meals found in Apple Health."
                            }
                        }
                    } label: {
                        Label("Import Nutrition from Apple Health", systemImage: "arrow.down.heart")
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

                    Toggle("iCloud / CloudKit Sync (Paid Dev Account)", isOn: Binding(
                        get: { bindableProfile.enableCloudKitSync },
                        set: { newVal in
                            bindableProfile.enableCloudKitSync = newVal
                            UserDefaults.standard.set(newVal, forKey: "totalfactor.enableCloudKit")
                        }
                    ))
                }

                Section("Food Databases & AI Meal Parsing (§4)") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("USDA FoodData Central API Key (Online Branded)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        TextField("USDA FoodData Central API Key", text: $bindableProfile.usdaApiKey)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    Text("All ~8,150 USDA Foundation & SR Legacy whole foods work 100% offline with zero API key. `DEMO_KEY` powers optional online branded searches (upgrade free at api.data.gov).")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Toggle("Enable Gemini AI Text & Meal-Photo Logging", isOn: $geminiEnabled)
                        .onChange(of: geminiEnabled) { _, newValue in
                            GeminiConfigStore.isEnabled = newValue
                        }

                    if geminiEnabled {
                        Picker("Gemini Model", selection: $geminiModel) {
                            ForEach(GeminiConfigStore.availableModels, id: \.self) { m in
                                Text(m).tag(m)
                            }
                        }
                        .onChange(of: geminiModel) { _, newModel in
                            GeminiConfigStore.selectedModel = newModel
                        }

                        SecureField("Optional Gemini API Key (Google AI Studio)", text: $geminiApiKeyDraft)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .onSubmit {
                                saveGeminiKey()
                            }

                        HStack {
                            Button {
                                saveGeminiKey()
                            } label: {
                                Label(geminiSavedFeedback ? "Saved to Keychain" : "Save Gemini Key", systemImage: geminiSavedFeedback ? "checkmark.circle.fill" : "key.fill")
                                    .font(.caption.weight(.semibold))
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)

                            if !geminiApiKeyDraft.isEmpty {
                                Button(role: .destructive) {
                                    geminiApiKeyDraft = ""
                                    GeminiConfigStore.saveAPIKey("")
                                } label: {
                                    Text("Clear Key")
                                        .font(.caption)
                                }
                            }
                            Spacer()
                        }

                        Text("Stored securely in iOS Keychain (never exported in CSVs). Voice dictation and natural-language parsing work offline even without a Gemini key.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Data Migration & AI Analysis (v1.5.3)") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Export All App Data")
                            .font(.headline)
                        Text("Download your complete history in universal CSVs, structured JSON, and an AI prompt-ready Markdown digest formatted for ChatGPT, Claude, and Gemini analysis or migration.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Button {
                            isGeneratingExport = true
                            Task {
                                let pkg = try? ExportAllArchiveService.generateExportPackage(context: modelContext)
                                await MainActor.run {
                                    exportPackage = pkg
                                    isGeneratingExport = false
                                    if pkg != nil {
                                        showingExportSheet = true
                                    }
                                }
                            }
                        } label: {
                            HStack {
                                Label("Export All Data (CSV + AI Prompt)", systemImage: "arrow.up.doc.fill")
                                    .font(.headline)
                                Spacer()
                                if isGeneratingExport {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Image(systemName: "square.and.arrow.up")
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isGeneratingExport)
                    }
                    .padding(.vertical, 4)

                    Button {
                        showingStrongImporter = true
                    } label: {
                        Label("Import Strong / Workout CSV...", systemImage: "square.and.arrow.down")
                    }

                    DisclosureGroup("Individual CSV Exports") {
                        Button("Generate Food Log CSV") {
                            exportedFileURL = try? CSVExportService.exportFoodLogCSV(context: modelContext)
                        }
                        Button("Generate Weigh-Ins & Trend CSV") {
                            exportedFileURL = try? CSVExportService.exportWeighInsCSV(context: modelContext)
                        }
                        Button("Generate Workouts & Sets CSV") {
                            exportedFileURL = try? CSVExportService.exportWorkoutsCSV(context: modelContext)
                        }

                        if let url = exportedFileURL {
                            ShareLink(item: url) {
                                Label("Share \(url.lastPathComponent)", systemImage: "square.and.arrow.up")
                                    .fontWeight(.semibold)
                            }
                        }
                    }
                }

                Section("Data Attribution & Ground Rules") {
                    Text("• Generic whole foods (~8,156 offline catalog): USDA FoodData Central Foundation + SR Legacy (Public Domain CC0).\n• Packaged barcode data: Open Food Facts, available under the Open Database License (ODbL).\n• Exercise demonstration photography: Free Exercise DB (Public Domain / Unlicense).\n• Watch active calories & heart rate are display-only and never alter nutrition targets.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .onAppear {
                geminiEnabled = GeminiConfigStore.isEnabled
                geminiModel = GeminiConfigStore.selectedModel
                geminiApiKeyDraft = GeminiConfigStore.loadAPIKey()
            }
            .fileImporter(
                isPresented: $showingStrongImporter,
                allowedContentTypes: [.commaSeparatedText, .plainText],
                allowsMultipleSelection: false
            ) { result in
                if case .success(let urls) = result, let url = urls.first {
                    let accessed = url.startAccessingSecurityScopedResource()
                    defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                    if let content = try? String(contentsOf: url, encoding: .utf8) {
                        let summary = StrongWorkoutImportService.importCSV(
                            content: content,
                            context: modelContext,
                            sourceUnitSystem: bindableProfile.unitSystem
                        )
                        importStatusMessage = summary.sessionsImported > 0
                            ? "Imported \(summary.sessionsImported) new sessions (\(summary.setsImported) sets)."
                            : "All workouts in this CSV are already imported."
                    }
                }
            }
            .alert(
                "CSV Import",
                isPresented: Binding(
                    get: { importStatusMessage != nil },
                    set: { if !$0 { importStatusMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) { importStatusMessage = nil }
            } message: {
                Text(importStatusMessage ?? "")
            }
            .sheet(isPresented: $showingExportSheet) {
                if let pkg = exportPackage {
                    #if canImport(UIKit)
                    ActivityView(activityItems: pkg.fileURLs)
                    #else
                    Text("Export package ready at \(pkg.folderURL.path)")
                    #endif
                }
            }
            .onChange(of: bindableGoal.ratePercentPerWeek) { _, _ in
                try? modelContext.save()
                _ = CoachingCoordinator.evaluate(context: modelContext)
            }
            .onChange(of: bindableGoal.typeRaw) { _, _ in
                try? modelContext.save()
                _ = CoachingCoordinator.evaluate(context: modelContext)
            }
            .onChange(of: bindableProfile.enableTrainingDayCarbCycling) { _, _ in
                try? modelContext.save()
                _ = CoachingCoordinator.evaluate(context: modelContext)
            }
            .onChange(of: bindableProfile.overrideCalorieFloor) { _, _ in
                try? modelContext.save()
                _ = CoachingCoordinator.evaluate(context: modelContext)
            }
            .onChange(of: bindableProfile.unitSystemRaw) { _, _ in
                try? modelContext.save()
                _ = CoachingCoordinator.evaluate(context: modelContext)
            }
            .onChange(of: bindableProfile.weighInRuleRaw) { _, _ in
                try? modelContext.save()
                _ = CoachingCoordinator.evaluate(context: modelContext)
            }
        }
    }

    private func saveGeminiKey() {
        GeminiConfigStore.saveAPIKey(geminiApiKeyDraft)
        geminiSavedFeedback = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            await MainActor.run {
                geminiSavedFeedback = false
            }
        }
    }
}

#if canImport(UIKit)
private struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]
    let applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif
