import SwiftUI
import SwiftData

/// Spec MacroFactor "Kitchen Hub" (v1.5.1 Kitchen Rehaul):
/// - Centralized management of Recipes, Saved Meals, and Custom Foods
/// - Recipe builder with cooked weight yield and water loss %
/// - Saved multi-food meals for 1-tap logging
/// - Custom food pantry with nutrition label re-scanning and sorting
struct KitchenHubView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState

    @Query(sort: \Recipe.name) private var recipes: [Recipe]
    @Query(sort: \SavedMeal.name) private var savedMeals: [SavedMeal]
    @Query(sort: \Food.name) private var allFoods: [Food]

    @State private var selectedSegment: Int = 0 // 0: Recipes, 1: Saved Meals, 2: Custom Foods
    @State private var searchText: String = ""
    @State private var showingRecipeBuilder: Bool = false
    @State private var showingCustomFoodCreator: Bool = false
    @State private var editingRecipe: Recipe? = nil
    @State private var editingFood: Food? = nil
    @State private var selectedFoodForDetail: CatalogSearchItem? = nil

    private var customFoods: [Food] {
        allFoods.filter { $0.source == .custom }
    }

    private var filteredRecipes: [Recipe] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return recipes }
        return recipes.filter { $0.name.lowercased().contains(q) }
    }

    private var filteredSavedMeals: [SavedMeal] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return savedMeals }
        return savedMeals.filter { $0.name.lowercased().contains(q) }
    }

    private var filteredCustomFoods: [Food] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return customFoods }
        return customFoods.filter { $0.name.lowercased().contains(q) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Segment Picker
                Picker("Kitchen Category", selection: $selectedSegment) {
                    Text("Recipes (\(recipes.count))").tag(0)
                    Text("Saved Meals (\(savedMeals.count))").tag(1)
                    Text("Custom Foods (\(customFoods.count))").tag(2)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                // Search Bar
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search your Kitchen...", text: $searchText)
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(9)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 16)
                .padding(.bottom, 6)

                // Content Views
                switch selectedSegment {
                case 0:
                    recipesList
                case 1:
                    savedMealsList
                default:
                    customFoodsList
                }
            }
            .navigationTitle("Kitchen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        if selectedSegment == 0 {
                            showingRecipeBuilder = true
                        } else if selectedSegment == 1 {
                            // Prompt to stage from search
                            appState.openQuickAdd(tab: 0)
                            dismiss()
                        } else {
                            showingCustomFoodCreator = true
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .bold))
                    }
                }
            }
            .sheet(isPresented: $showingRecipeBuilder) {
                RecipeBuilderSheet()
            }
            .sheet(isPresented: $showingCustomFoodCreator) {
                CustomFoodEditorSheet(existingFood: nil, prefilledBarcode: nil, parsedLabel: nil) { created in
                    selectedFoodForDetail = .persisted(created)
                }
            }
            .sheet(item: $editingFood) { food in
                CustomFoodEditorSheet(existingFood: food, prefilledBarcode: food.barcode, parsedLabel: nil) { _ in }
            }
            .sheet(item: $selectedFoodForDetail) { item in
                FoodDetailSheet(target: item, dayKey: appState.selectedDayKey, initialMealTag: .none) {
                    dismiss()
                }
            }
        }
    }

    // MARK: - 1. Recipes Tab

    private var recipesList: some View {
        List {
            Section {
                Button {
                    showingRecipeBuilder = true
                } label: {
                    Label("Create Cooked-Weight Recipe", systemImage: "plus.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color(red: 0.18, green: 0.48, blue: 0.96))
                }
            }

            if filteredRecipes.isEmpty {
                Section {
                    Text("No recipes saved yet. Build batch recipes with raw ingredients and finished cooked weight to log exact grams.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Section("Saved Recipes") {
                    ForEach(filteredRecipes) { recipe in
                        recipeRow(recipe: recipe)
                    }
                    .onDelete { offsets in
                        for idx in offsets {
                            modelContext.delete(filteredRecipes[idx])
                        }
                        try? modelContext.save()
                    }
                }
            }
        }
    }

    private func recipeRow(recipe: Recipe) -> some View {
        let per100 = recipe.nutrientsPer100gCooked

        return Button {
            let existingFood = allFoods.first(where: { $0.id == recipe.linkedFoodID })
            let shadow = recipe.makeOrUpdateShadowFood(existing: existingFood)
            if existingFood == nil {
                modelContext.insert(shadow)
            }
            try? modelContext.save()
            selectedFoodForDetail = .persisted(shadow)
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(recipe.name)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.primary)
                    Spacer()
                    Text("\(Int(per100.calories.rounded())) kcal/100g")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color(red: 0.18, green: 0.48, blue: 0.96))
                }

                HStack(spacing: 8) {
                    Text("\(Int(recipe.servings)) servings")
                    Text("•")
                    Text("Yield: \(Int(recipe.totalYieldGrams))g cooked")
                    if let wl = recipe.waterLossPercent, wl > 0 {
                        Text("•")
                        Text("-\(Int(wl.rounded()))% water loss")
                            .foregroundStyle(.orange)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)

                Text("\(Int(per100.protein.rounded()))g P • \(Int(per100.carbs.rounded()))g C • \(Int(per100.fat.rounded()))g F per 100g")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    // MARK: - 2. Saved Meals Tab

    private var savedMealsList: some View {
        List {
            Section {
                Button {
                    appState.openQuickAdd(tab: 0)
                    dismiss()
                } label: {
                    Label("Build New Saved Meal (via The Plate)", systemImage: "tray.and.arrow.down.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color(red: 0.18, green: 0.48, blue: 0.96))
                }
            }

            if filteredSavedMeals.isEmpty {
                Section {
                    Text("No saved meals yet. Stage multiple foods onto The Plate during search and tap 'Save Plate as Saved Meal' to save reusable staple combos.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Section("Saved Staples") {
                    ForEach(filteredSavedMeals) { meal in
                        savedMealRow(meal: meal)
                    }
                    .onDelete { offsets in
                        for idx in offsets {
                            modelContext.delete(filteredSavedMeals[idx])
                        }
                        try? modelContext.save()
                    }
                }
            }
        }
    }

    private func savedMealRow(meal: SavedMeal) -> some View {
        let total = meal.totalNutrients
        let itemCount = meal.safeItems.count

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(meal.name)
                        .font(.system(size: 15, weight: .bold))
                    Text("\(itemCount) items • \(meal.defaultMealTag.displayName)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(Int(total.calories.rounded())) kcal")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color(red: 0.18, green: 0.48, blue: 0.96))
            }

            // Quick Log Button
            HStack {
                Text("\(Int(total.protein.rounded()))P \(Int(total.carbs.rounded()))C \(Int(total.fat.rounded()))F")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    logSavedMeal(meal)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle.fill")
                        Text("Log Meal")
                    }
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color(red: 0.18, green: 0.48, blue: 0.96), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - 3. Custom Foods Tab

    private var customFoodsList: some View {
        List {
            Section {
                Button {
                    showingCustomFoodCreator = true
                } label: {
                    Label("Create Custom Food", systemImage: "plus.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color(red: 0.18, green: 0.48, blue: 0.96))
                }
            }

            if filteredCustomFoods.isEmpty {
                Section {
                    Text("No custom foods created yet. Create personal foods manually or scan packaging nutrition labels with your camera.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Section("Custom Food Pantry") {
                    ForEach(filteredCustomFoods) { food in
                        Button {
                            selectedFoodForDetail = .persisted(food)
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Text(food.name)
                                        .font(.system(size: 15, weight: .semibold))
                                    Spacer()
                                    Text("\(Int(food.caloriesPer100g.rounded())) kcal/100g")
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                                Text("\(Int(food.proteinPer100g.rounded()))P \(Int(food.carbsPer100g.rounded()))C \(Int(food.fatPer100g.rounded()))F • \(food.lastLoggedServingLabel)")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                modelContext.delete(food)
                                try? modelContext.save()
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            Button {
                                editingFood = food
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            .tint(.orange)
                        }
                    }
                }
            }
        }
    }

    private func logSavedMeal(_ meal: SavedMeal) {
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif

        let dayKey = appState.selectedDayKey
        for item in meal.safeItems {
            guard let food = item.food else { continue }
            let entry = FoodLogEntry(
                food: food,
                grams: item.grams,
                servingLabel: "\(InlineQuantityCalculator.formatClean(item.quantity)) × \(item.servingLabel)",
                mealTag: meal.defaultMealTag,
                timestamp: .now,
                dayKey: dayKey
            )
            modelContext.insert(entry)
        }
        meal.lastUsed = .now
        meal.useCount += 1
        try? modelContext.save()
        _ = CoachingCoordinator.evaluate(forDayKey: dayKey, context: modelContext)
        dismiss()
    }
}
