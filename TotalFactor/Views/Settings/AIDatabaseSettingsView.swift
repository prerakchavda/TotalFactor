import SwiftUI
import SwiftData

struct AIDatabaseSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]

    @State private var geminiEnabled: Bool = GeminiConfigStore.isEnabled
    @State private var geminiModel: String = GeminiConfigStore.selectedModel
    @State private var geminiApiKeyDraft: String = GeminiConfigStore.loadAPIKey()
    @State private var geminiSavedFeedback: Bool = false

    private var profile: UserProfile {
        profiles.first ?? CoachingCoordinator.fetchOrCreateProfile(context: modelContext)
    }

    var body: some View {
        @Bindable var bindableProfile = profile

        Form {
            Section("USDA FoodData Central") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("API Key (Optional Branded Search)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    TextField("USDA FoodData Central API Key", text: $bindableProfile.usdaApiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Text("All ~8,150 USDA Foundation & SR Legacy whole foods work 100% offline with zero API key. `DEMO_KEY` powers optional online branded searches (upgrade free at api.data.gov).")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Section("Google Gemini AI Meal & Photo Parsing") {
                Toggle("Enable Gemini AI Logging", isOn: $geminiEnabled)
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
                    }

                    Text("Stored securely in iOS Keychain (never exported in CSVs). Voice dictation and natural-language parsing work offline even without an API key.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("AI & Databases")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            geminiEnabled = GeminiConfigStore.isEnabled
            geminiModel = GeminiConfigStore.selectedModel
            geminiApiKeyDraft = GeminiConfigStore.loadAPIKey()
        }
        .onChange(of: bindableProfile.usdaApiKey) { _, _ in
            try? modelContext.save()
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
