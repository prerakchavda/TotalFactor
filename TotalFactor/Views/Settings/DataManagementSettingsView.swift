import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct DataManagementSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]

    @State private var showingMacroFactorImporter: Bool = false
    @State private var showingStrongImporter: Bool = false
    @State private var importStatusTitle: String = "Import"
    @State private var importStatusMessage: String? = nil

    @State private var isGeneratingExport: Bool = false
    @State private var exportPackage: ExportAllArchiveService.ExportPackage? = nil
    @State private var showingExportSheet: Bool = false

    private var profile: UserProfile {
        profiles.first ?? CoachingCoordinator.fetchOrCreateProfile(context: modelContext)
    }

    var body: some View {
        Form {
            Section {
                Button {
                    showingMacroFactorImporter = true
                } label: {
                    Label("Import MacroFactor Nutrition Data (CSV)...", systemImage: "square.and.arrow.down.on.square.fill")
                        .foregroundStyle(Color.accentColor)
                }

                Button {
                    showingStrongImporter = true
                } label: {
                    Label("Import Strong / Workout CSV...", systemImage: "dumbbell.fill")
                }
            } header: {
                Text("Import Data")
            } footer: {
                Text("MacroFactor import supports granular food logs and daily summaries with deterministic fingerprinting (0 duplicate entries guaranteed).")
            }

            Section("Universal Data Export (AI-Ready)") {
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
                                if let pkg {
                                    #if canImport(UIKit)
                                    ShareSheetHelper.present(activityItems: pkg.fileURLs)
                                    #endif
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
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isGeneratingExport)
                }
                .padding(.vertical, 4)
            }

            Section("Individual CSV Exports") {
                Button {
                    if let url = try? CSVExportService.exportFoodLogCSV(context: modelContext) {
                        ShareSheetHelper.present(activityItems: [url])
                    }
                } label: {
                    Label("Export Food Log CSV", systemImage: "fork.knife")
                }

                Button {
                    if let url = try? CSVExportService.exportWeighInsCSV(context: modelContext) {
                        ShareSheetHelper.present(activityItems: [url])
                    }
                } label: {
                    Label("Export Weigh-Ins & Trend CSV", systemImage: "scalemass")
                }

                Button {
                    if let url = try? CSVExportService.exportWorkoutsCSV(context: modelContext) {
                        ShareSheetHelper.present(activityItems: [url])
                    }
                } label: {
                    Label("Export Workouts & Sets CSV", systemImage: "figure.strengthtraining.traditional")
                }
            }
        }
        .navigationTitle("Data & Backup")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(
            isPresented: $showingMacroFactorImporter,
            allowedContentTypes: [.commaSeparatedText, .plainText],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                if let content = try? String(contentsOf: url, encoding: .utf8) {
                    let summary = MacroFactorImportService.importCSV(
                        content: content,
                        context: modelContext
                    )
                    importStatusTitle = "MacroFactor Import"
                    importStatusMessage = summary.foodsImported > 0 || summary.weighInsImported > 0
                        ? "Imported \(summary.foodsImported) foods and \(summary.weighInsImported) weigh-ins across \(summary.daysTouched) days.\n(\(summary.foodsSkipped) existing entries skipped to prevent duplicates)."
                        : "All \(summary.foodsSkipped) food entries in this file are already logged (0 duplicates created)."
                }
            }
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
                        sourceUnitSystem: profile.unitSystem
                    )
                    importStatusTitle = "Strong Import"
                    importStatusMessage = summary.sessionsImported > 0
                        ? "Imported \(summary.sessionsImported) new workout sessions (\(summary.setsImported) sets)."
                        : "All workouts in this file are already imported."
                }
            }
        }
        .alert(
            importStatusTitle,
            isPresented: Binding(
                get: { importStatusMessage != nil },
                set: { if !$0 { importStatusMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { importStatusMessage = nil }
        } message: {
            Text(importStatusMessage ?? "")
        }
    }
}
