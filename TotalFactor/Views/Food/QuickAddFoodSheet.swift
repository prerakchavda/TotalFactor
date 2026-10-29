import SwiftUI
import SwiftData

/// Spec §6 Quick Add Sheet (Target: log a repeat food in 2 taps!):
/// - Search field focused immediately across user history + ~8,156 offline USDA foods (`OfflineUSDACatalogService`)
/// - "Usually at this time" smart history suggestions with 1-tap instant log button
/// - Modes: Search (0) · Describe / Voice (5) · Scan (1) · Label (2) · Quick (3) · Recipes (4)
struct QuickAddFoodSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(HealthKitService.self) private var healthService

    let dayKey: String
    let initialTab: Int
    var defaultMealTag: MealTag = .none
    var autoStartDictation: Bool = false

    @Query private var profiles: [UserProfile]
    @Query private var foods: [Food]
    @Query private var recipes: [Recipe]
    @Query private var recentEntries: [FoodLogEntry]

    @State private var selectedMode: Int = 0
    @State private var activeMealTag: MealTag = .none
    @State private var triggerVoiceOnDescribeOpen: Bool = false
    @State private var searchQuery: String = ""
    @State private var remoteResults: [RemoteFoodDTO] = []
    @State private var isSearchingOnline: Bool = false
    @State private var cachedUsualSuggestions: [Food] = []
    @State private var cachedCatalogResults: [CatalogSearchItem] = []
    @FocusState private var searchFocused: Bool

    // Sheet destinations
    @State private var selectedCatalogItemForDetail: CatalogSearchItem? = nil
    @State private var customFoodPrefillBarcode: String? = nil
    @State private var customFoodParsedLabel: ParsedNutritionLabel? = nil
    @State private var showingCustomFoodCreator: Bool = false
    @State private var showingRecipeBuilder: Bool = false
    @State private var showingStagedReviewSheet: Bool = false
    @State private var showingPlateWorkspace: Bool = false
    @State private var showingKitchenHub: Bool = false
    @State private var showingBallparkSheet: Bool = false
    @State private var showingNoScaleEstimatorSheet: Bool = false

    // MacroFactor Search Filters
    public enum SearchFilterCategory: String, CaseIterable, Identifiable {
        case all = "All"
        case history = "History"
        case street = "Street & Bites"
        case favorites = "Favorites"
        case custom = "Custom"
        case recipes = "Recipes"
        case common = "Common (USDA)"
        case branded = "Branded"

        public var id: String { rawValue }
    }
    @State private var selectedSearchFilter: SearchFilterCategory = .all

    // Multi-Add Staging
    @State private var stagedItems: [StagedFoodItem] = []

    // Quick Raw Macros tab state
    @State private var quickTitle: String = ""
    @State private var quickCalories: String = ""
    @State private var quickProtein: String = ""
    @State private var quickCarbs: String = ""
    @State private var quickFat: String = ""

    private struct ModeTab: Identifiable {
        let tag: Int
        let title: String
        let icon: String
        var id: Int { tag }
    }

    private let modeTabs: [ModeTab] = [
        ModeTab(tag: 0, title: "Search", icon: "magnifyingglass"),
        ModeTab(tag: 5, title: "Describe / Voice", icon: "waveform.and.mic"),
        ModeTab(tag: 1, title: "Scan", icon: "barcode.viewfinder"),
        ModeTab(tag: 2, title: "Label", icon: "doc.text.viewfinder"),
        ModeTab(tag: 3, title: "Quick", icon: "bolt.fill"),
        ModeTab(tag: 4, title: "Recipes", icon: "frying.pan")
    ]

    private var profile: UserProfile {
        profiles.first ?? CoachingCoordinator.fetchOrCreateProfile(context: modelContext)
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                VStack(spacing: 0) {
                    modePickerStrip

                    switch selectedMode {
                    case 0:
                        searchTabView
                    case 5:
                        DescribeMealView(
                            dayKey: dayKey,
                            defaultMealTag: activeMealTag,
                            autoStartDictation: triggerVoiceOnDescribeOpen,
                            persistedFoods: foods,
                            onAddToPlate: { staged in
                                stagedItems.append(contentsOf: staged)
                            }
                        ) {
                            dismiss()
                        }
                    case 1:
                        BarcodeScannerView(usdaApiKey: profile.usdaApiKey) { outcome in
                            switch outcome {
                            case .found(let food):
                                selectedCatalogItemForDetail = .persisted(food)
                            case .notFound(let missingBarcode):
                                customFoodPrefillBarcode = missingBarcode
                                selectedMode = 2 // Spec §4: Miss -> open label scanner with barcode pre-filled!
                            }
                        }
                    case 2:
                        LabelScannerView(prefilledBarcode: customFoodPrefillBarcode) { parsed, barcode in
                            customFoodParsedLabel = parsed
                            customFoodPrefillBarcode = barcode
                            showingCustomFoodCreator = true
                        }
                    case 3:
                        quickRawEntryView
                    default:
                        recipesTabView
                    }
                }

                // Persistent MacroFactor "The Plate" Dock
                if !stagedItems.isEmpty {
                    ThePlateDockView(
                        stagedItems: $stagedItems,
                        onOpenWorkspace: { showingPlateWorkspace = true },
                        onCommit: { logAllStagedItems() }
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.22), value: !stagedItems.isEmpty)
            .navigationTitle("Add Food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        Button {
                            showingKitchenHub = true
                        } label: {
                            Image(systemName: "frying.pan.fill")
                                .font(.system(size: 15))
                        }
                        .accessibilityLabel("Open Kitchen Pantry & Hub")

                        Menu {
                            ForEach(MealTag.allCases) { tag in
                                Button {
                                    activeMealTag = tag
                                } label: {
                                    if activeMealTag == tag {
                                        Label(tag.displayName, systemImage: "checkmark")
                                    } else {
                                        Text(tag.displayName)
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "fork.knife")
                                if activeMealTag != .none {
                                    Text(activeMealTag.displayName)
                                        .font(.caption.weight(.semibold))
                                }
                            }
                        }
                        .accessibilityLabel("Default Meal Tag")

                        Button {
                            customFoodParsedLabel = nil
                            customFoodPrefillBarcode = nil
                            showingCustomFoodCreator = true
                        } label: {
                            Image(systemName: "plus.rectangle.on.rectangle")
                        }
                        .accessibilityLabel("New Custom Food")
                    }
                }
            }
            .onAppear {
                activeMealTag = defaultMealTag
                triggerVoiceOnDescribeOpen = autoStartDictation
                selectedMode = initialTab
                if initialTab == 0 {
                    searchFocused = true
                }
                refreshRankedFoods()
                OfflineUSDACatalogService.shared.preloadInBackground {
                    refreshRankedFoods()
                }
            }
            .onChange(of: searchQuery) { _, _ in
                refreshRankedFoods()
            }
            .onChange(of: foods.count) { _, _ in
                refreshRankedFoods()
            }
            .onChange(of: recentEntries.count) { _, _ in
                refreshRankedFoods()
            }
            .sheet(item: $selectedCatalogItemForDetail) { targetItem in
                FoodDetailSheet(
                    target: targetItem,
                    dayKey: dayKey,
                    initialMealTag: activeMealTag
                ) {
                    dismiss()
                }
            }
            .sheet(isPresented: $showingCustomFoodCreator) {
                CustomFoodEditorSheet(
                    existingFood: nil,
                    prefilledBarcode: customFoodPrefillBarcode,
                    parsedLabel: customFoodParsedLabel
                ) { createdFood in
                    selectedCatalogItemForDetail = .persisted(createdFood)
                }
            }
            .sheet(isPresented: $showingRecipeBuilder) {
                RecipeBuilderSheet()
            }
            .sheet(isPresented: $showingPlateWorkspace) {
                ThePlateWorkspaceSheet(
                    stagedItems: $stagedItems,
                    dayKey: dayKey,
                    initialMealTag: activeMealTag,
                    onCommitAll: { targetTag, targetDate in
                        logAllStagedItems(targetMealTag: targetTag, targetTimestamp: targetDate)
                    }
                )
            }
            .sheet(isPresented: $showingKitchenHub) {
                KitchenHubView()
            }
            .sheet(isPresented: $showingBallparkSheet) {
                MealBallparkSheet(
                    dayKey: dayKey,
                    initialMealTag: activeMealTag,
                    onAddToPlate: { staged in
                        stagedItems.append(staged)
                    },
                    onLoggedDirectly: {
                        dismiss()
                    }
                )
            }
            .sheet(isPresented: $showingNoScaleEstimatorSheet) {
                NoScaleEstimatorSheet(
                    dayKey: dayKey,
                    initialMealTag: activeMealTag,
                    onAddToPlate: { staged in
                        stagedItems.append(contentsOf: staged)
                    },
                    onLoggedDirectly: {
                        dismiss()
                    }
                )
            }
        }
    }

    private var modePickerStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(modeTabs) { tab in
                    let isSelected = (selectedMode == tab.tag)
                    Button {
                        if tab.tag != 5 {
                            triggerVoiceOnDescribeOpen = false
                        }
                        selectedMode = tab.tag
                        if tab.tag == 0 {
                            searchFocused = true
                        } else {
                            searchFocused = false
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: tab.icon)
                                .font(.caption2.weight(.bold))
                            Text(tab.title)
                                .font(.caption.weight(.semibold))
                        }
                        .padding(.horizontal, 11)
                        .padding(.vertical, 7)
                        .background(
                            isSelected ? Color.accentColor : Color.secondary.opacity(0.13),
                            in: Capsule()
                        )
                        .foregroundStyle(isSelected ? Color.white : Color.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Mode 0: Ranked Offline (~8,156 USDA + History) + Online Search

    private var searchTabView: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search 8,100+ offline USDA foods or brand...", text: $searchQuery)
                    .focused($searchFocused)
                    .submitLabel(.search)
                    .onSubmit {
                        runOnlineSearch()
                    }
                if !searchQuery.isEmpty {
                    Button {
                        searchQuery = ""
                        remoteResults = []
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
                Button {
                    searchFocused = false
                    triggerVoiceOnDescribeOpen = true
                    selectedMode = 5
                } label: {
                    Image(systemName: "mic.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 4)
                }
                .accessibilityLabel("Dictate Multi-Item Meal by Voice")
            }
            .padding(10)
            .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)
            .padding(.bottom, 6)

            // MacroFactor-Style Search Filter Pills
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(SearchFilterCategory.allCases) { cat in
                        let isSel = (selectedSearchFilter == cat)
                        Button {
                            selectedSearchFilter = cat
                        } label: {
                            Text(cat.rawValue)
                                .font(.system(size: 11, weight: .semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(
                                    isSel ? Color(red: 0.18, green: 0.48, blue: 0.96) : Color.secondary.opacity(0.12),
                                    in: Capsule()
                                )
                                .foregroundStyle(isSel ? Color.white : Color.primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 6)
            }

            List {
                if searchQuery.trimmingCharacters(in: .whitespaces).isEmpty && !cachedUsualSuggestions.isEmpty && (selectedSearchFilter == .all || selectedSearchFilter == .history) {
                    Section("Usually at This Time (1-Tap Log)") {
                        ForEach(cachedUsualSuggestions) { food in
                            catalogSearchRow(item: .persisted(food), forceOneTapRepeat: true)
                        }
                    }
                }

                Section(
                    searchQuery.isEmpty
                        ? "Favorites, Recent & Offline USDA (\(OfflineUSDACatalogService.shared.isLoaded ? "\(filteredCatalogResults.count) verified" : "loading..."))"
                        : "Offline USDA & Personal Matches"
                ) {
                    ForEach(filteredCatalogResults) { item in
                        catalogSearchRow(item: item, forceOneTapRepeat: false)
                    }
                }

                if !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty && (selectedSearchFilter == .all || selectedSearchFilter == .branded) {
                    Section("Online USDA Branded & Open Food Facts") {
                        if isSearchingOnline {
                            HStack {
                                ProgressView()
                                Text("Searching USDA Branded & Open Food Facts...")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } else if remoteResults.isEmpty {
                            Button {
                                runOnlineSearch()
                            } label: {
                                Label("Search Branded Online for \"\(searchQuery)\"", systemImage: "globe")
                            }
                        } else {
                            ForEach(remoteResults) { dto in
                                Button {
                                    let persisted = BarcodeLookupCoordinator.persistRemoteDTO(dto, into: modelContext)
                                    selectedCatalogItemForDetail = .persisted(persisted)
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            HStack(spacing: 6) {
                                                Text(dto.name)
                                                    .font(.subheadline.weight(.medium))
                                                    .lineLimit(1)
                                                FoodSourceBadge(source: dto.source)
                                            }
                                            Text(dto.brand ?? "Online Result")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Text("\(Int(dto.nutrientsPer100g.calories.rounded())) kcal/100g")
                                            .font(.caption.monospacedDigit())
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
        }
    }

    private var filteredCatalogResults: [CatalogSearchItem] {
        cachedCatalogResults.filter { item in
            switch selectedSearchFilter {
            case .all: return true
            case .history: return item.allowOneTapRepeat
            case .street:
                if case .composite = item { return true }
                return item.brand?.contains("Street") == true || item.brand?.contains("Composite") == true
            case .favorites: return item.isFavorite
            case .custom: return item.source == .custom
            case .recipes: return item.source == .recipe
            case .common:
                return item.source == .usda && (item.brand == nil || item.brand?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true)
            case .branded:
                return item.source == .off || (item.brand != nil && !item.brand!.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func catalogSearchRow(item: CatalogSearchItem, forceOneTapRepeat: Bool) -> some View {
        let preview = item.previewNutrients
        let canRepeat = forceOneTapRepeat || item.allowOneTapRepeat
        let countInBatch = stagedItems.filter { $0.item.id == item.id }.count

        return HStack(spacing: 10) {
            Button {
                selectedCatalogItemForDetail = item
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            if item.isFavorite {
                                Image(systemName: "star.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.yellow)
                            }
                            Text(item.name)
                                .font(.subheadline.weight(.medium))
                                .lineLimit(1)
                            FoodSourceBadge(source: item.source)
                        }
                        Text("\(item.previewServingLabel) • \(Int(preview.calories.rounded())) kcal • \(Int(preview.protein.rounded()))P \(Int(preview.carbs.rounded()))C \(Int(preview.fat.rounded()))F")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
            .buttonStyle(.plain)

            // Multi-Add Staging Button (MacroFactor style)
            Button {
                stageItem(item)
            } label: {
                if countInBatch > 0 {
                    HStack(spacing: 2) {
                        Image(systemName: "checkmark")
                        Text("\(countInBatch)×")
                    }
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(Color.accentColor, in: Capsule())
                    .foregroundStyle(.white)
                } else {
                    Image(systemName: "plus.circle")
                        .font(.title3)
                        .foregroundStyle(Color.accentColor)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add \(item.name) to multi-add batch")

            // 2-tap repeat food logging: 1 tap on floating + -> 1 tap here logs your remembered amount immediately!
            if canRepeat, case .persisted(let persistedFood) = item {
                Button {
                    quickRepeatLog(food: persistedFood)
                } label: {
                    Image(systemName: "bolt.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.orange)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Instant log \(persistedFood.name)")
            }
        }
        .swipeActions(edge: .leading) {
            Button {
                stageItem(item)
            } label: {
                Label("Plate", systemImage: "fork.knife")
            }
            .tint(Color(red: 0.18, green: 0.48, blue: 0.96))
        }
    }

    // MARK: - Mode 3: Quick Raw Calories / Macros

    private var quickRawEntryView: some View {
        Form {
            Section("Zero-Scale & Real-World Estimators") {
                Button {
                    showingBallparkSheet = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "flame.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Ballpark My Meal (3-Sec)")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(.primary)
                            Text("Instant estimation for buffets, weddings, dining out & cheat meals")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)

                Button {
                    showingNoScaleEstimatorSheet = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "hand.raised.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.blue)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("No-Scale & Container Estimator")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(.primary)
                            Text("Hand proportions (palm, fist, thumb) & takeout containers (pint, box)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }

            Section("Manual Calorie & Macro Override") {
                TextField("Label (optional, e.g. Restaurant Dinner)", text: $quickTitle)
                TextField("Calories (kcal)", text: $quickCalories)
                    .keyboardType(.decimalPad)
                TextField("Protein (g)", text: $quickProtein)
                    .keyboardType(.decimalPad)
                TextField("Carbs (g)", text: $quickCarbs)
                    .keyboardType(.decimalPad)
                TextField("Fat (g)", text: $quickFat)
                    .keyboardType(.decimalPad)
                Picker("Meal Tag", selection: $activeMealTag) {
                    ForEach(MealTag.allCases) { tag in
                        Text(tag.displayName).tag(tag)
                    }
                }
            }

            Section {
                Button {
                    let p = Double(quickProtein) ?? 0
                    let c = Double(quickCarbs) ?? 0
                    let f = Double(quickFat) ?? 0
                    let explicitCals = Double(quickCalories) ?? 0
                    let finalCals = explicitCals > 0 ? explicitCals : (p * 4 + c * 4 + f * 9)
                    guard finalCals > 0 else { return }

                    let entry = FoodLogEntry(
                        quickTitle: quickTitle.isEmpty ? "Quick Add" : quickTitle,
                        calories: finalCals,
                        protein: p,
                        carbs: c,
                        fat: f,
                        mealTag: activeMealTag,
                        timestamp: logTimestamp(),
                        dayKey: dayKey
                    )
                    modelContext.insert(entry)
                    try? modelContext.save()
                    Task { await healthService.syncFoodEntry(entry) }
                    _ = CoachingCoordinator.evaluate(forDayKey: dayKey, context: modelContext)
                    dismiss()
                } label: {
                    Text("Log Quick Macros")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: - Mode 4: Recipes

    private var recipesTabView: some View {
        List {
            Section {
                Button {
                    showingRecipeBuilder = true
                } label: {
                    Label("Create New Cooked-Weight Recipe", systemImage: "plus.circle.fill")
                        .font(.subheadline.weight(.semibold))
                }
            }

            Section("Saved Recipes") {
                if recipes.isEmpty {
                    Text("No recipes yet. Build batch recipes with cooked weight to log exact portions in grams.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(recipes) { recipe in
                        Button {
                            let existingFood = foods.first(where: { $0.id == recipe.linkedFoodID })
                            let shadow = recipe.makeOrUpdateShadowFood(existing: existingFood)
                            if existingFood == nil {
                                modelContext.insert(shadow)
                            }
                            try? modelContext.save()
                            selectedCatalogItemForDetail = .persisted(shadow)
                        } label: {
                            let per100 = recipe.nutrientsPer100gCooked
                            VStack(alignment: .leading, spacing: 4) {
                                Text(recipe.name)
                                    .font(.subheadline.weight(.semibold))
                                Text("\(Int(recipe.servings)) servings • Cooked yield \(Int(recipe.totalYieldGrams))g • \(Int(per100.calories.rounded())) kcal/100g")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func refreshRankedFoods() {
        let foodByID = Dictionary(foods.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let rankables = foods.map(\.asRankableCandidate)

        if searchQuery.trimmingCharacters(in: .whitespaces).isEmpty {
            var logHoursByFoodID: [UUID: [Int]] = [:]
            let cal = Calendar.current
            for e in recentEntries {
                guard let fid = e.foodID else { continue }
                logHoursByFoodID[fid, default: []].append(cal.component(.hour, from: e.timestamp))
            }
            cachedUsualSuggestions = FoodSearchRanker.usuallyAtThisTime(
                candidates: rankables,
                historicalFoodLogHours: logHoursByFoodID
            ).compactMap { foodByID[$0.id] }
        } else {
            cachedUsualSuggestions = []
        }

        cachedCatalogResults = OfflineUSDACatalogService.shared.rankedResults(
            query: searchQuery,
            persistedFoods: foods,
            limit: 60
        )
    }

    private func quickRepeatLog(food: Food) {
        let entry = FoodLogEntry(
            food: food,
            grams: food.lastLoggedGrams,
            servingLabel: food.lastLoggedServingLabel,
            mealTag: activeMealTag,
            timestamp: logTimestamp(),
            dayKey: dayKey
        )
        food.useCount += 1
        food.lastUsed = .now
        food.typicalHourOfDay = Calendar.current.component(.hour, from: .now)
        modelContext.insert(entry)
        try? modelContext.save()
        Task { await healthService.syncFoodEntry(entry) }
        _ = CoachingCoordinator.evaluate(forDayKey: dayKey, context: modelContext)
        dismiss()
    }

    private func logTimestamp() -> Date {
        if dayKey == DayKey.today { return .now }
        return DayKey.date(from: dayKey) ?? .now
    }

    private func runOnlineSearch() {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        isSearchingOnline = true
        let apiKey = profile.usdaApiKey
        Task {
            let usda = (try? await USDAFoodClient(apiKey: apiKey).searchFoods(query: q, pageSize: 12)) ?? []
            let off = (try? await OpenFoodFactsClient().searchFoods(query: q, pageSize: 10)) ?? []
            await MainActor.run {
                remoteResults = usda + off
                isSearchingOnline = false
            }
        }
    }

    // MARK: - Multi-Add Staging & Batch Logging

    private var stagedItemsDock: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(stagedItems.count) Item\(stagedItems.count == 1 ? "" : "s") Staged")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                let totalCals = stagedItems.reduce(0.0) { $0 + $1.scaledNutrients.calories }
                let totalProt = stagedItems.reduce(0.0) { $0 + $1.scaledNutrients.protein }
                Text("\(Int(totalCals.rounded())) kcal • \(Int(totalProt.rounded()))g protein")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.85))
            }

            Spacer()

            Button {
                showingStagedReviewSheet = true
            } label: {
                Text("Review")
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.white.opacity(0.25), in: Capsule())
                    .foregroundStyle(.white)
            }

            Button {
                logAllStagedItems()
            } label: {
                Text("Log All (\(stagedItems.count))")
                    .font(.subheadline.weight(.bold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Color.white, in: Capsule())
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
        .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 3)
    }

    private func stageItem(_ item: CatalogSearchItem) {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
        let serving = item.defaultServing
        let staged = StagedFoodItem(
            item: item,
            quantity: 1.0,
            selectedServing: serving,
            mealTag: activeMealTag
        )
        stagedItems.append(staged)
    }

    private func logAllStagedItems(targetMealTag: MealTag? = nil, targetTimestamp: Date? = nil) {
        guard !stagedItems.isEmpty else { return }
        for staged in stagedItems {
            let food: Food
            switch staged.item {
            case .persisted(let p):
                food = p
            case .offlineUSDA(let entry):
                food = OfflineUSDACatalogService.shared.materialize(entry, in: modelContext)
            case .composite(let entry):
                food = CompositeFoodLibrary.materialize(entry, in: modelContext)
            }

            let grams = max(0.5, staged.grams)
            let displayLabel = "\(InlineQuantityCalculator.formatClean(staged.quantity)) × \(staged.selectedServing.label)"
            food.lastLoggedGrams = grams
            food.lastLoggedServingLabel = staged.selectedServing.label
            food.useCount += 1
            food.lastUsed = .now
            food.typicalHourOfDay = Calendar.current.component(.hour, from: .now)

            let finalTag = targetMealTag ?? (staged.mealTag == .none ? activeMealTag : staged.mealTag)
            let entry = FoodLogEntry(
                food: food,
                grams: grams,
                servingLabel: displayLabel,
                mealTag: finalTag,
                timestamp: targetTimestamp ?? logTimestamp(),
                dayKey: dayKey
            )
            modelContext.insert(entry)
            Task { await healthService.syncFoodEntry(entry) }
        }

        try? modelContext.save()
        _ = CoachingCoordinator.evaluate(forDayKey: dayKey, context: modelContext)
        stagedItems.removeAll()
        dismiss()
    }
}

// MARK: - Staged Food Models & Review Sheet

struct StagedFoodItem: Identifiable, Equatable {
    let id: UUID = UUID()
    let item: CatalogSearchItem
    var quantity: Double = 1.0
    var selectedServing: ServingSize
    var mealTag: MealTag

    var grams: Double {
        selectedServing.grams * quantity
    }

    var scaledNutrients: NutrientsPer100g {
        item.nutrientsPer100g.scaled(forGrams: grams)
    }

    static func == (lhs: StagedFoodItem, rhs: StagedFoodItem) -> Bool {
        lhs.id == rhs.id
    }
}

struct StagedFoodReviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var stagedItems: [StagedFoodItem]
    let dayKey: String
    let defaultMealTag: MealTag
    let onCommit: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach($stagedItems) { $staged in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(staged.item.name)
                                        .font(.subheadline.weight(.bold))
                                    Text(staged.item.brand ?? "USDA Verified")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button(role: .destructive) {
                                    stagedItems.removeAll { $0.id == staged.id }
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.caption)
                                        .foregroundStyle(.red)
                                }
                                .buttonStyle(.plain)
                            }

                            HStack {
                                Stepper("\(InlineQuantityCalculator.formatClean(staged.quantity)) ×", value: $staged.quantity, in: 0.25...20.0, step: 0.25)
                                    .font(.caption.weight(.semibold))

                                Spacer()

                                Menu {
                                    ForEach(staged.item.servingSizes) { s in
                                        Button(s.label) {
                                            staged.selectedServing = s
                                        }
                                    }
                                } label: {
                                    HStack(spacing: 4) {
                                        Text(staged.selectedServing.label)
                                            .font(.caption)
                                        Image(systemName: "chevron.up.chevron.down")
                                            .font(.caption2)
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.secondary.opacity(0.12), in: Capsule())
                                }
                            }

                            HStack {
                                Text("\(Int(staged.grams.rounded())) g total")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                let n = staged.scaledNutrients
                                Text("\(Int(n.calories.rounded())) kcal • \(Int(n.protein.rounded()))P \(Int(n.carbs.rounded()))C \(Int(n.fat.rounded()))F")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .onDelete { idxs in
                        stagedItems.remove(atOffsets: idxs)
                    }
                } header: {
                    Text("Staged Foods (\(stagedItems.count))")
                } footer: {
                    Text("Adjust quantities, swap serving sizes, or delete items before logging.")
                }
            }
            .navigationTitle("Review Staged Meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Log All (\(stagedItems.count))") {
                        dismiss()
                        onCommit()
                    }
                    .font(.headline)
                    .disabled(stagedItems.isEmpty)
                }
            }
        }
    }
}
