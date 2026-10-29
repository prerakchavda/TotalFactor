import SwiftUI
import SwiftData

/// Spec §6 Recipe Builder:
/// Add ingredients from personal foods or the ~8,156-item offline USDA catalog, set total cooked weight (`totalYieldGrams`),
/// and log by grams of the finished dish!
struct RecipeBuilderSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Food.name) private var allFoods: [Food]

    @State private var recipeName: String = ""
    @State private var servings: Double = 4
    @State private var totalCookedGrams: Double = 600
    @State private var draftIngredients: [(id: UUID, food: Food, grams: Double)] = []
    @State private var ingredientSearch: String = ""
    @State private var pickerResults: [CatalogSearchItem] = []
    @State private var showingIngredientPicker: Bool = false

    private var rawBatchGrams: Double {
        draftIngredients.reduce(0.0) { $0 + $1.grams }
    }

    private var totalBatchNutrients: NutrientsPer100g {
        var total = NutrientsPer100g()
        for item in draftIngredients {
            let scaled = item.food.nutrientsPer100g.scaled(forGrams: item.grams)
            total.calories += scaled.calories
            total.protein += scaled.protein
            total.carbs += scaled.carbs
            total.fat += scaled.fat
            total.fiber += scaled.fiber
            total.sugar += scaled.sugar
            total.sodiumMg += scaled.sodiumMg
        }
        return total
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Recipe Details") {
                    TextField("Recipe Name (e.g. Chili Meal Prep)", text: $recipeName)
                    HStack {
                        Text("Servings")
                        Spacer()
                        TextField("4", value: $servings, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Finished Cooked Weight (g)")
                            Text("Raw sum: \(Int(rawBatchGrams.rounded())) g")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        TextField("600", value: $totalCookedGrams, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    if rawBatchGrams > 0 {
                        Button("Set Cooked Weight = Raw Sum (\(Int(rawBatchGrams.rounded()))g)") {
                            totalCookedGrams = rawBatchGrams.rounded()
                        }
                        .font(.caption)
                    }
                }

                Section("Ingredients") {
                    ForEach(Array(draftIngredients.enumerated()), id: \.element.id) { idx, item in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(item.food.name)
                                    .font(.subheadline)
                                let sc = item.food.nutrientsPer100g.scaled(forGrams: item.grams)
                                Text("\(Int(sc.calories.rounded())) kcal • \(Int(sc.protein.rounded()))P")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            TextField(
                                "g",
                                value: Binding(
                                    get: { draftIngredients[idx].grams },
                                    set: { draftIngredients[idx].grams = max(1, $0) }
                                ),
                                format: .number
                            )
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 72)
                            Text("g").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .onDelete { offsets in
                        draftIngredients.remove(atOffsets: offsets)
                    }

                    Button {
                        refreshPickerResults()
                        showingIngredientPicker = true
                    } label: {
                        Label("Add Ingredient", systemImage: "plus.circle.fill")
                    }
                }

                let batch = totalBatchNutrients
                let perServingDiv = max(1.0, servings)
                let per100CookedScale = 100.0 / max(1.0, totalCookedGrams)

                Section("Nutrition Summary") {
                    LabeledContent(
                        "Per Serving (\(Int((totalCookedGrams / perServingDiv).rounded()))g cooked)",
                        value: "\(Int((batch.calories / perServingDiv).rounded())) kcal • \(Int((batch.protein / perServingDiv).rounded()))g P"
                    )
                    LabeledContent(
                        "Per 100g Cooked Dish",
                        value: "\(Int((batch.calories * per100CookedScale).rounded())) kcal • \(String(format: "%.1f", batch.protein * per100CookedScale))g P"
                    )
                }
            }
            .navigationTitle("Recipe Builder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save Recipe") {
                        saveRecipe()
                    }
                    .disabled(recipeName.trimmingCharacters(in: .whitespaces).isEmpty || draftIngredients.isEmpty)
                }
            }
            .sheet(isPresented: $showingIngredientPicker) {
                NavigationStack {
                    List(pickerResults) { item in
                        Button {
                            let resolvedFood: Food
                            switch item {
                            case .persisted(let f):
                                resolvedFood = f
                            case .offlineUSDA(let entry):
                                resolvedFood = OfflineUSDACatalogService.shared.materialize(entry, in: modelContext)
                            }
                            draftIngredients.append((UUID(), resolvedFood, resolvedFood.lastLoggedGrams))
                            totalCookedGrams = draftIngredients.reduce(0.0) { $0 + $1.grams }
                            showingIngredientPicker = false
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name)
                                        .font(.subheadline)
                                    if let brand = item.brand, !brand.isEmpty {
                                        Text(brand)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Text("\(Int(item.caloriesPer100g.rounded())) kcal/100g")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .searchable(text: $ingredientSearch, prompt: "Search 8,100+ USDA & custom ingredients")
                    .onChange(of: ingredientSearch) { _, _ in
                        refreshPickerResults()
                    }
                    .navigationTitle("Pick Ingredient")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { showingIngredientPicker = false }
                        }
                    }
                }
            }
        }
    }

    private func refreshPickerResults() {
        pickerResults = OfflineUSDACatalogService.shared.rankedResults(
            query: ingredientSearch,
            persistedFoods: allFoods,
            limit: 60
        )
    }

    private func saveRecipe() {
        let recipe = Recipe(
            name: recipeName.trimmingCharacters(in: .whitespacesAndNewlines),
            totalYieldGrams: max(1, totalCookedGrams),
            servings: max(1, servings)
        )
        modelContext.insert(recipe)

        for item in draftIngredients {
            let ing = RecipeIngredient(food: item.food, grams: item.grams)
            ing.recipe = recipe
            modelContext.insert(ing)
        }

        let shadowFood = recipe.makeOrUpdateShadowFood()
        modelContext.insert(shadowFood)
        try? modelContext.save()
        dismiss()
    }
}
