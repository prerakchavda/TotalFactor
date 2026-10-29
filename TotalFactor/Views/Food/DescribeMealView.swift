import SwiftUI
import SwiftData
import PhotosUI
#if canImport(UIKit)
import UIKit
#endif

/// Voice, Natural-Language & Meal-Photo Logging (`§4 / QuickAddFoodSheet Mode 5`):
/// - Hands-free live dictation via `SpeechDictationService` (`SFSpeechRecognizer`)
/// - Instant 100% offline multi-item quantity/unit/food parser (`NaturalLanguageMealParser` + ~8,156 offline USDA foods)
/// - Optional multimodal Gemini API meal text + photo analyzer (`GeminiMealParserService`)
/// - 1-tap `MultiItemMealConfirmationSheet` that logs all items and syncs to Apple Health
struct DescribeMealView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(HealthKitService.self) private var healthService

    let dayKey: String
    let defaultMealTag: MealTag
    let autoStartDictation: Bool
    let persistedFoods: [Food]
    let onLoggedAll: () -> Void

    @State private var dictation = SpeechDictationService()
    @State private var mealText: String = ""
    @State private var selectedMealTag: MealTag = .none
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var attachedJPEGData: Data? = nil
    #if canImport(UIKit)
    @State private var attachedPreviewImage: UIImage? = nil
    @State private var showingCameraCapture: Bool = false
    #endif

    @State private var isAnalyzingGemini: Bool = false
    @State private var isAnalyzingVision: Bool = false
    @State private var errorMessage: String? = nil
    @State private var parsedItems: [ParsedMealDraftItem] = []
    @State private var showingConfirmation: Bool = false
    @State private var showingGeminiKeySetup: Bool = false
    @State private var didAutoStartDictation: Bool = false
    @FocusState private var textEditorFocused: Bool

    private let examplePrompts: [String] = [
        "3 eggs, 2 slices sourdough toast with 1 tbsp butter, and 200g greek yogurt",
        "200g grilled chicken breast, 1.5 cups white rice, and 1 tbsp olive oil",
        "1 cup oats, 1 scoop whey protein, 1 tbsp peanut butter, and 1 medium banana"
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                headerBanner

                mealInputCard

                voiceAndPhotoToolbar

                #if canImport(UIKit)
                if let preview = attachedPreviewImage {
                    attachedPhotoCard(image: preview)
                }
                #endif

                if let dictErr = dictation.errorMessage {
                    statusBanner(text: dictErr, color: .orange, icon: "mic.slash.fill")
                }

                if let err = errorMessage {
                    statusBanner(text: err, color: .red, icon: "exclamationmark.triangle.fill")
                }

                actionButtonsSection

                if mealText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && attachedJPEGData == nil {
                    exampleChipsSection
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .scrollDismissesKeyboard(.interactively)
        .onAppear {
            selectedMealTag = defaultMealTag
            if autoStartDictation && !didAutoStartDictation {
                didAutoStartDictation = true
                let prefix = mealText
                Task {
                    await dictation.startRecording(existingPrefix: prefix) { updated in
                        mealText = updated
                    }
                }
            }
        }
        .onDisappear {
            if dictation.isRecording {
                dictation.stopRecording()
            }
        }
        .onChange(of: selectedPhotoItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self) {
                    #if canImport(UIKit)
                    if let uiImage = UIImage(data: data),
                       let downsampled = GeminiMealParserService.downsampleJPEGData(from: uiImage) {
                        await MainActor.run {
                            attachedPreviewImage = uiImage
                            attachedJPEGData = downsampled
                            errorMessage = nil
                        }
                    }
                    #else
                    await MainActor.run {
                        attachedJPEGData = data
                        errorMessage = nil
                    }
                    #endif
                }
            }
        }
        #if canImport(UIKit)
        .sheet(isPresented: $showingCameraCapture) {
            MealPhotoCameraPicker { capturedImage in
                if let downsampled = GeminiMealParserService.downsampleJPEGData(from: capturedImage) {
                    attachedPreviewImage = capturedImage
                    attachedJPEGData = downsampled
                    errorMessage = nil
                }
            }
            .ignoresSafeArea()
        }
        #endif
        .sheet(isPresented: $showingGeminiKeySetup) {
            GeminiQuickKeySetupSheet {
                runGeminiAnalysis()
            }
            .presentationDetents([.height(340)])
        }
        .sheet(isPresented: $showingConfirmation) {
            MultiItemMealConfirmationSheet(
                initialItems: parsedItems,
                dayKey: dayKey,
                initialMealTag: selectedMealTag,
                persistedFoods: persistedFoods,
                onConfirmed: {
                    onLoggedAll()
                }
            )
        }
    }

    // MARK: - Subviews

    private var headerBanner: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "waveform.and.mic")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 36, height: 36)
                .background(Color.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 2) {
                Text("Describe, Dictate, or Snap Your Meal")
                    .font(.subheadline.weight(.bold))
                Text("Offline parser matches ~8,156 USDA foods + your history in milliseconds, or use optional Gemini AI for photos & restaurant dishes.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var mealInputCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Meal Description")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Menu {
                    ForEach(MealTag.allCases) { tag in
                        Button {
                            selectedMealTag = tag
                        } label: {
                            if selectedMealTag == tag {
                                Label(tag.displayName, systemImage: "checkmark")
                            } else {
                                Text(tag.displayName)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "fork.knife")
                        Text(selectedMealTag == .none ? "Meal Tag" : selectedMealTag.displayName)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 8, weight: .bold))
                    }
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.14), in: Capsule())
                }

                if !mealText.isEmpty {
                    Button("Clear") {
                        mealText = ""
                        errorMessage = nil
                    }
                    .font(.caption2.weight(.semibold))
                }
            }

            ZStack(alignment: .topLeading) {
                TextEditor(text: $mealText)
                    .focused($textEditorFocused)
                    .frame(minHeight: 108, maxHeight: 150)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.secondary.opacity(0.10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(
                                        dictation.isRecording ? Color.red.opacity(0.75) : Color.primary.opacity(0.08),
                                        lineWidth: dictation.isRecording ? 1.8 : 1.0
                                    )
                            )
                    )

                if mealText.isEmpty {
                    Text("e.g. 3 eggs, 2 slices sourdough toast with 1 tbsp butter, and 200g greek yogurt...")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 16)
                        .allowsHitTesting(false)
                }
            }
        }
    }

    private var voiceAndPhotoToolbar: some View {
        HStack(spacing: 8) {
            Button {
                textEditorFocused = false
                let prefix = mealText
                dictation.toggleRecording(existingPrefix: prefix) { updated in
                    mealText = updated
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: dictation.isRecording ? "stop.circle.fill" : "mic.fill")
                        .symbolEffect(.pulse, isActive: dictation.isRecording)
                    Text(dictation.isRecording ? "Stop Dictation" : "Voice Dictate")
                        .fontWeight(.semibold)
                }
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity)
                .background(
                    dictation.isRecording ? Color.red : Color.accentColor.opacity(0.15),
                    in: RoundedRectangle(cornerRadius: 10)
                )
                .foregroundStyle(dictation.isRecording ? Color.white : Color.accentColor)
            }
            .buttonStyle(.plain)

            #if canImport(UIKit)
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button {
                    textEditorFocused = false
                    showingCameraCapture = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "camera.fill")
                        Text("Snap Plate")
                            .fontWeight(.semibold)
                    }
                    .font(.caption)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(Color.secondary.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
            #endif

            PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                HStack(spacing: 5) {
                    Image(systemName: "photo.on.rectangle")
                    Text("Photo")
                        .fontWeight(.semibold)
                }
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(Color.secondary.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
        }
    }

    #if canImport(UIKit)
    private func attachedPhotoCard(image: UIImage) -> some View {
        HStack(spacing: 12) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 3) {
                Text("Meal Photo Attached")
                    .font(.subheadline.weight(.semibold))
                Text("Add optional notes above (e.g. \"cooked in 1 tbsp butter\") or analyze directly with Gemini Vision.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                attachedPreviewImage = nil
                attachedJPEGData = nil
                selectedPhotoItem = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove Attached Meal Photo")
        }
        .padding(10)
        .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
    }
    #endif

    private func statusBanner(text: String, color: Color, icon: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(color)
            Text(text)
                .font(.caption)
                .foregroundStyle(.primary)
            Spacer()
        }
        .padding(10)
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }

    private var actionButtonsSection: some View {
        let trimmedText = mealText.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasText = !trimmedText.isEmpty
        let hasPhoto = (attachedJPEGData != nil)

        return VStack(spacing: 10) {
            Button {
                runOfflineParse()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "bolt.fill")
                    Text("Parse Offline (Instant USDA + History)")
                        .fontWeight(.bold)
                }
                .font(.subheadline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!hasText || isAnalyzingGemini || isAnalyzingVision)

            #if canImport(UIKit)
            if hasPhoto {
                Button {
                    runAppleVisionAnalysis()
                } label: {
                    HStack(spacing: 8) {
                        if isAnalyzingVision {
                            ProgressView()
                                .controlSize(.small)
                            Text("Identifying Plate on Neural Engine...")
                                .fontWeight(.semibold)
                        } else {
                            Image(systemName: "camera.viewfinder")
                            Text("Identify Plate On-Device (Apple Vision AI)")
                                .fontWeight(.semibold)
                        }
                    }
                    .font(.subheadline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(isAnalyzingVision || isAnalyzingGemini)
            }
            #endif

            if GeminiConfigStore.isEnabled {
                Button {
                    if GeminiConfigStore.hasConfiguredKey {
                        runGeminiAnalysis()
                    } else {
                        showingGeminiKeySetup = true
                    }
                } label: {
                    HStack(spacing: 8) {
                        if isAnalyzingGemini {
                            ProgressView()
                                .controlSize(.small)
                            Text("Analyzing Meal with Gemini...")
                                .fontWeight(.semibold)
                        } else {
                            Image(systemName: "sparkles")
                            Text(
                                hasPhoto
                                    ? "Analyze Photo\(hasText ? " + Notes" : "") with Gemini AI"
                                    : (GeminiConfigStore.hasConfiguredKey
                                        ? "Parse Complex Meal with Gemini AI"
                                        : "Set Optional Gemini API Key for AI / Photo Logging")
                            )
                            .fontWeight(.semibold)
                        }
                    }
                    .font(.subheadline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled((!hasText && !hasPhoto && GeminiConfigStore.hasConfiguredKey) || isAnalyzingGemini)
            }
        }
    }

    private var exampleChipsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Try a 1-Tap Example")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(examplePrompts, id: \.self) { sample in
                Button {
                    mealText = sample
                    errorMessage = nil
                } label: {
                    HStack {
                        Image(systemName: "quote.opening")
                            .font(.caption2)
                            .foregroundStyle(Color.accentColor)
                        Text(sample)
                            .font(.caption)
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                        Spacer()
                        Image(systemName: "arrow.up.left")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(10)
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 4)
    }

    // MARK: - Actions

    #if canImport(UIKit)
    private func runAppleVisionAnalysis() {
        guard let preview = attachedPreviewImage else { return }
        if dictation.isRecording {
            dictation.stopRecording()
        }
        textEditorFocused = false
        errorMessage = nil
        isAnalyzingVision = true

        Task {
            let detected = await AppleVisionFoodClassifier.classifyFood(in: preview)
            await MainActor.run {
                isAnalyzingVision = false
                guard !detected.isEmpty else {
                    errorMessage = "Apple Vision couldn't recognize specific foods in this photo. Add notes above or analyze with Gemini AI."
                    return
                }

                let queries = detected.map(\.suggestedSearchQuery)
                let existing = mealText.trimmingCharacters(in: .whitespacesAndNewlines)
                let combinedText = existing.isEmpty ? queries.joined(separator: ", ") : "\(existing), \(queries.joined(separator: ", "))"
                mealText = combinedText

                let matcherFoods = persistedFoods.map(\.asPersistedFoodMatcherItem)
                let catalog = OfflineUSDACatalogService.shared.index
                let items = NaturalLanguageMealParser.parse(
                    text: combinedText,
                    persistedFoods: matcherFoods,
                    offlineCatalog: catalog
                )
                if !items.isEmpty {
                    parsedItems = items
                    showingConfirmation = true
                }
            }
        }
    }
    #endif

    private func runOfflineParse() {
        if dictation.isRecording {
            dictation.stopRecording()
        }
        textEditorFocused = false
        errorMessage = nil

        let matcherFoods = persistedFoods.map(\.asPersistedFoodMatcherItem)
        let catalog = OfflineUSDACatalogService.shared.index
        let items = NaturalLanguageMealParser.parse(
            text: mealText,
            persistedFoods: matcherFoods,
            offlineCatalog: catalog
        )

        if items.isEmpty {
            errorMessage = "Couldn't match food names offline. Try simple quantities + foods (e.g. \"3 eggs, 100g oats\") or analyze with Gemini AI."
            return
        }
        parsedItems = items
        showingConfirmation = true
    }

    private func runGeminiAnalysis() {
        if dictation.isRecording {
            dictation.stopRecording()
        }
        textEditorFocused = false
        errorMessage = nil
        isAnalyzingGemini = true

        let textCopy = mealText
        let photoCopy = attachedJPEGData
        Task {
            do {
                let items = try await GeminiMealParserService().analyzeMeal(
                    descriptionText: textCopy,
                    jpegImageData: photoCopy
                )
                await MainActor.run {
                    isAnalyzingGemini = false
                    parsedItems = items
                    showingConfirmation = true
                }
            } catch {
                await MainActor.run {
                    isAnalyzingGemini = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

// MARK: - 1-Tap Multi-Item Confirmation Sheet

struct MultiItemMealConfirmationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(HealthKitService.self) private var healthService

    @State private var items: [ParsedMealDraftItem]
    let dayKey: String
    @State private var mealTag: MealTag
    let persistedFoods: [Food]
    let onConfirmed: () -> Void

    init(
        initialItems: [ParsedMealDraftItem],
        dayKey: String,
        initialMealTag: MealTag,
        persistedFoods: [Food],
        onConfirmed: @escaping () -> Void
    ) {
        self._items = State(initialValue: initialItems)
        self.dayKey = dayKey
        self._mealTag = State(initialValue: initialMealTag)
        self.persistedFoods = persistedFoods
        self.onConfirmed = onConfirmed
    }

    private var includedItems: [ParsedMealDraftItem] {
        items.filter(\.isIncluded)
    }

    private var totalNutrients: NutrientsPer100g {
        var total = NutrientsPer100g()
        for item in includedItems {
            let sc = item.scaledNutrients
            total.calories += sc.calories
            total.protein += sc.protein
            total.carbs += sc.carbs
            total.fat += sc.fat
            total.fiber += sc.fiber
            total.sugar += sc.sugar
            total.sodiumMg += sc.sodiumMg
        }
        return total
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                mealSummaryBanner
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)

                Divider()

                List {
                    ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                        draftItemRow(index: idx, item: item)
                    }
                }
                .listStyle(.plain)

                Divider()

                VStack(spacing: 8) {
                    Button {
                        logConfirmedItems()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                            Text("Log \(includedItems.count) \(includedItems.count == 1 ? "Item" : "Items") (\(Int(totalNutrients.calories.rounded())) kcal)")
                                .fontWeight(.bold)
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(includedItems.isEmpty)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial)
            }
            .navigationTitle("Confirm Meal Items")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Back") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        ForEach(MealTag.allCases) { tag in
                            Button {
                                mealTag = tag
                            } label: {
                                if mealTag == tag {
                                    Label(tag.displayName, systemImage: "checkmark")
                                } else {
                                    Text(tag.displayName)
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "fork.knife")
                            Text(mealTag == .none ? "Meal" : mealTag.displayName)
                        }
                        .font(.caption.weight(.semibold))
                    }
                }
            }
        }
    }

    private var mealSummaryBanner: some View {
        let totals = totalNutrients
        return VStack(spacing: 8) {
            HStack(spacing: 6) {
                summaryTile("Calories", "\(Int(totals.calories.rounded()))", "kcal", .orange)
                summaryTile("Protein", String(format: "%.1f", totals.protein), "g", .red)
                summaryTile("Carbs", String(format: "%.1f", totals.carbs), "g", .blue)
                summaryTile("Fat", String(format: "%.1f", totals.fat), "g", .yellow)
            }
            HStack(spacing: 14) {
                Text("\(includedItems.count) of \(items.count) items selected")
                Text("•")
                Text("Fiber \(String(format: "%.1f", totals.fiber))g")
                Text("•")
                Text("Syncs to Apple Health")
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(Color.secondary.opacity(0.09), in: RoundedRectangle(cornerRadius: 14))
    }

    private func summaryTile(_ title: String, _ value: String, _ unit: String, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.subheadline.weight(.bold).monospacedDigit()).foregroundStyle(color)
            Text(unit).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func draftItemRow(index: Int, item: ParsedMealDraftItem) -> some View {
        let scaled = item.scaledNutrients
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Button {
                    items[index].isIncluded.toggle()
                } label: {
                    Image(systemName: item.isIncluded ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(item.isIncluded ? Color.accentColor : .secondary)
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(item.foodName)
                            .font(.subheadline.weight(.semibold))
                            .strikethrough(!item.isIncluded)
                            .foregroundStyle(item.isIncluded ? .primary : .secondary)
                            .lineLimit(2)

                        Text(item.matchOriginBadge)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.13), in: Capsule())
                            .foregroundStyle(Color.accentColor)
                    }

                    Text("\(item.servingLabel) • \(Int(scaled.calories.rounded())) kcal • \(Int(scaled.protein.rounded()))P \(Int(scaled.carbs.rounded()))C \(Int(scaled.fat.rounded()))F")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            if item.isIncluded {
                HStack(spacing: 8) {
                    Text("Portion:")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Button("-25g") { adjustGrams(at: index, delta: -25) }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)

                    Button("-10g") { adjustGrams(at: index, delta: -10) }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)

                    HStack(spacing: 3) {
                        TextField(
                            "g",
                            value: Binding(
                                get: { Int(items[index].grams.rounded()) },
                                set: { newVal in
                                    let clamped = Double(max(1, newVal))
                                    items[index].grams = clamped
                                    items[index].servingLabel = "\(Int(clamped)) g"
                                }
                            ),
                            format: .number
                        )
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .frame(width: 48)
                        Text("g")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))

                    Button("+10g") { adjustGrams(at: index, delta: 10) }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)

                    Button("+25g") { adjustGrams(at: index, delta: 25) }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)

                    Spacer()
                }
                .padding(.leading, 30)
            }
        }
        .padding(.vertical, 4)
    }

    private func adjustGrams(at index: Int, delta: Double) {
        let updated = max(5.0, (items[index].grams + delta).rounded())
        items[index].grams = updated
        items[index].servingLabel = "\(Int(updated)) g"
    }

    private func logConfirmedItems() {
        let selected = includedItems
        guard !selected.isEmpty else { return }

        let persistedByID = Dictionary(persistedFoods.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let catalog = OfflineUSDACatalogService.shared.index
        let timestamp = (dayKey == DayKey.today) ? Date.now : (DayKey.date(from: dayKey) ?? .now)
        let currentHour = Calendar.current.component(.hour, from: .now)

        var createdEntries: [FoodLogEntry] = []

        for draft in selected {
            var resolvedFood: Food? = nil
            if let fid = draft.matchedPersistedFoodID, let existing = persistedByID[fid] {
                resolvedFood = existing
            } else if let sid = draft.matchedOfflineUSDASourceID, let entry = catalog.entry(forSourceID: sid) {
                resolvedFood = OfflineUSDACatalogService.shared.materialize(entry, in: modelContext)
            }

            let logEntry: FoodLogEntry
            if let food = resolvedFood {
                food.lastLoggedGrams = draft.grams
                food.lastLoggedServingLabel = draft.servingLabel
                food.useCount += 1
                food.lastUsed = .now
                food.typicalHourOfDay = currentHour

                logEntry = FoodLogEntry(
                    food: food,
                    grams: draft.grams,
                    servingLabel: draft.servingLabel,
                    mealTag: mealTag,
                    timestamp: timestamp,
                    dayKey: dayKey
                )
            } else {
                // Direct AI-parsed dish entry (preserves per-100g macros + fiber + sugar + sodium + portion grams)
                let entry = FoodLogEntry(
                    quickTitle: draft.foodName,
                    calories: draft.nutrientsPer100g.calories,
                    protein: draft.nutrientsPer100g.protein,
                    carbs: draft.nutrientsPer100g.carbs,
                    fat: draft.nutrientsPer100g.fat,
                    mealTag: mealTag,
                    timestamp: timestamp,
                    dayKey: dayKey
                )
                entry.foodBrand = draft.brand
                entry.snapshotFiberPer100g = draft.nutrientsPer100g.fiber
                entry.snapshotSugarPer100g = draft.nutrientsPer100g.sugar
                entry.snapshotSodiumMgPer100g = draft.nutrientsPer100g.sodiumMg
                entry.grams = draft.grams
                entry.servingLabel = draft.servingLabel
                logEntry = entry
            }

            modelContext.insert(logEntry)
            createdEntries.append(logEntry)
        }

        try? modelContext.save()
        let entriesToSync = createdEntries
        Task {
            for entry in entriesToSync {
                await healthService.syncFoodEntry(entry)
            }
        }
        _ = CoachingCoordinator.evaluate(forDayKey: dayKey, context: modelContext)
        InlineFoodKeypadHaptics.lightTap()
        dismiss()
        onConfirmed()
    }
}

// MARK: - Inline Gemini Key Setup Sheet

private struct GeminiQuickKeySetupSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var apiKeyInput: String = GeminiConfigStore.loadAPIKey()
    @State private var selectedModel: String = GeminiConfigStore.selectedModel
    let onSaved: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("Paste Gemini API Key (AI Studio)", text: $apiKeyInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    Picker("Gemini Model", selection: $selectedModel) {
                        ForEach(GeminiConfigStore.availableModels, id: \.self) { m in
                            Text(m).tag(m)
                        }
                    }
                } header: {
                    Text("Optional Gemini AI Setup")
                } footer: {
                    Text("Stored privately in your iPhone Keychain. You can change or clear this key anytime in Settings → Food Databases & AI Meal Parsing.")
                }
            }
            .navigationTitle("Gemini AI Key")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save & Analyze") {
                        GeminiConfigStore.saveAPIKey(apiKeyInput)
                        GeminiConfigStore.selectedModel = selectedModel
                        GeminiConfigStore.isEnabled = true
                        dismiss()
                        onSaved()
                    }
                    .disabled(apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

#if canImport(UIKit)
private struct MealPhotoCameraPicker: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    let onCapture: (UIImage) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.allowsEditing = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: MealPhotoCameraPicker

        init(parent: MealPhotoCameraPicker) {
            self.parent = parent
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let img = info[.originalImage] as? UIImage {
                parent.onCapture(img)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
#endif
