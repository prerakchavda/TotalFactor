import Foundation
import SwiftData

private enum NutritionModelCoding {
    static let decoder = JSONDecoder()
    static let encoder = JSONEncoder()
}

@Model
public final class Food {
    public var id: UUID = UUID()
    public var name: String = ""
    public var brand: String? = nil
    public var barcode: String? = nil
    public var sourceRaw: String = FoodSource.custom.rawValue
    public var sourceID: String? = nil
    public var isBundledGeneric: Bool = false

    public var servingSizesJSON: Data = Data()

    // Per 100 g nutrients
    public var caloriesPer100g: Double = 0
    public var proteinPer100g: Double = 0
    public var carbsPer100g: Double = 0
    public var fatPer100g: Double = 0
    public var fiberPer100g: Double = 0
    public var sugarPer100g: Double = 0
    public var sodiumMgPer100g: Double = 0
    public var micronutrientsJSON: Data = Data()

    @Transient private var _cachedServingSizes: [ServingSize]? = nil
    @Transient private var _cachedMicronutrients: [String: Double]? = nil

    // Usage & memory (§6: remembers last amount for this food)
    public var isFavorite: Bool = false
    public var lastUsed: Date? = nil
    public var useCount: Int = 0
    public var typicalHourOfDay: Int? = nil
    public var lastLoggedGrams: Double = 100.0
    public var lastLoggedServingLabel: String = "100 g"
    public var createdAt: Date = Date()

    @Relationship(deleteRule: .nullify, inverse: \RecipeIngredient.food)
    public var recipeUsages: [RecipeIngredient]? = []

    public init(
        id: UUID = UUID(),
        name: String,
        brand: String? = nil,
        barcode: String? = nil,
        source: FoodSource = .custom,
        sourceID: String? = nil,
        isBundledGeneric: Bool = false,
        servingSizes: [ServingSize] = [ServingSize(label: "100 g", grams: 100)],
        nutrientsPer100g: NutrientsPer100g = NutrientsPer100g(),
        isFavorite: Bool = false
    ) {
        self.id = id
        self.name = name
        self.brand = brand
        self.barcode = barcode
        self.sourceRaw = source.rawValue
        self.sourceID = sourceID
        self.isBundledGeneric = isBundledGeneric
        self.caloriesPer100g = nutrientsPer100g.calories
        self.proteinPer100g = nutrientsPer100g.protein
        self.carbsPer100g = nutrientsPer100g.carbs
        self.fatPer100g = nutrientsPer100g.fat
        self.fiberPer100g = nutrientsPer100g.fiber
        self.sugarPer100g = nutrientsPer100g.sugar
        self.sodiumMgPer100g = nutrientsPer100g.sodiumMg
        self.isFavorite = isFavorite
        self.servingSizes = servingSizes
        self.micronutrients = nutrientsPer100g.micronutrients
        if let firstServing = servingSizes.first {
            self.lastLoggedGrams = firstServing.grams
            self.lastLoggedServingLabel = firstServing.label
        }
    }

    public var source: FoodSource {
        get { FoodSource(rawValue: sourceRaw) ?? .custom }
        set { sourceRaw = newValue.rawValue }
    }

    public var servingSizes: [ServingSize] {
        get {
            if let cached = _cachedServingSizes { return cached }
            guard !servingSizesJSON.isEmpty,
                  let decoded = try? NutritionModelCoding.decoder.decode([ServingSize].self, from: servingSizesJSON),
                  !decoded.isEmpty else {
                let fallback = [ServingSize(label: "100 g", grams: 100)]
                _cachedServingSizes = fallback
                return fallback
            }
            _cachedServingSizes = decoded
            return decoded
        }
        set {
            _cachedServingSizes = newValue
            servingSizesJSON = (try? NutritionModelCoding.encoder.encode(newValue)) ?? Data()
        }
    }

    public var micronutrients: [String: Double] {
        get {
            if let cached = _cachedMicronutrients { return cached }
            guard !micronutrientsJSON.isEmpty,
                  let decoded = try? NutritionModelCoding.decoder.decode([String: Double].self, from: micronutrientsJSON) else {
                _cachedMicronutrients = [:]
                return [:]
            }
            _cachedMicronutrients = decoded
            return decoded
        }
        set {
            _cachedMicronutrients = newValue
            micronutrientsJSON = (try? NutritionModelCoding.encoder.encode(newValue)) ?? Data()
        }
    }

    /// Zero-allocation macro-only snapshot for fast scroll rendering & search ranking.
    public var macrosOnlyPer100g: NutrientsPer100g {
        NutrientsPer100g(
            calories: caloriesPer100g,
            protein: proteinPer100g,
            carbs: carbsPer100g,
            fat: fatPer100g,
            fiber: fiberPer100g,
            sugar: sugarPer100g,
            sodiumMg: sodiumMgPer100g
        )
    }

    public var nutrientsPer100g: NutrientsPer100g {
        get {
            NutrientsPer100g(
                calories: caloriesPer100g,
                protein: proteinPer100g,
                carbs: carbsPer100g,
                fat: fatPer100g,
                fiber: fiberPer100g,
                sugar: sugarPer100g,
                sodiumMg: sodiumMgPer100g,
                micronutrients: micronutrients
            )
        }
        set {
            caloriesPer100g = newValue.calories
            proteinPer100g = newValue.protein
            carbsPer100g = newValue.carbs
            fatPer100g = newValue.fat
            fiberPer100g = newValue.fiber
            sugarPer100g = newValue.sugar
            sodiumMgPer100g = newValue.sodiumMg
            micronutrients = newValue.micronutrients
        }
    }

    public var asRankableCandidate: RankableFoodCandidate {
        RankableFoodCandidate(
            id: id,
            sourceID: sourceID,
            name: name,
            brand: brand,
            source: source,
            isBundledGeneric: isBundledGeneric,
            isFavorite: isFavorite,
            useCount: useCount,
            lastUsed: lastUsed,
            typicalHourOfDay: typicalHourOfDay,
            nutrientsPer100g: macrosOnlyPer100g
        )
    }

    public var asPersistedFoodMatcherItem: PersistedFoodMatcherItem {
        PersistedFoodMatcherItem(
            id: id,
            sourceID: sourceID,
            name: name,
            brand: brand,
            source: source,
            isFavorite: isFavorite,
            useCount: useCount,
            lastUsed: lastUsed,
            lastLoggedGrams: lastLoggedGrams,
            lastLoggedServingLabel: lastLoggedServingLabel,
            servingSizes: servingSizes,
            nutrientsPer100g: macrosOnlyPer100g
        )
    }

    /// Creates an editable user-owned Custom Food copy (§4: "'Copy to custom' button on any food to fix bad data").
    public func duplicateAsCustom() -> Food {
        Food(
            name: name,
            brand: brand,
            barcode: barcode,
            source: .custom,
            sourceID: nil,
            isBundledGeneric: false,
            servingSizes: servingSizes,
            nutrientsPer100g: nutrientsPer100g,
            isFavorite: isFavorite
        )
    }
}

@Model
public final class Recipe {
    public var id: UUID = UUID()
    public var name: String = ""
    /// Total cooked/finished weight in grams (§6: log by grams of the finished dish or by servings).
    public var totalYieldGrams: Double = 500.0
    public var servings: Double = 4.0
    public var linkedFoodID: UUID? = nil
    public var waterLossPercent: Double? = nil
    public var notes: String = ""
    public var createdAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \RecipeIngredient.recipe)
    public var ingredients: [RecipeIngredient]? = []

    public init(
        id: UUID = UUID(),
        name: String,
        totalYieldGrams: Double = 500.0,
        servings: Double = 4.0
    ) {
        self.id = id
        self.name = name
        self.totalYieldGrams = max(1, totalYieldGrams)
        self.servings = max(1, servings)
    }

    public var safeIngredients: [RecipeIngredient] {
        ingredients ?? []
    }

    public var totalBatchNutrients: NutrientsPer100g {
        var total = NutrientsPer100g()
        var micros: [String: Double] = [:]
        for ing in safeIngredients {
            let scaled = ing.scaledNutrients
            total.calories += scaled.calories
            total.protein += scaled.protein
            total.carbs += scaled.carbs
            total.fat += scaled.fat
            total.fiber += scaled.fiber
            total.sugar += scaled.sugar
            total.sodiumMg += scaled.sodiumMg
            for (k, v) in scaled.micronutrients {
                micros[k, default: 0] += v
            }
        }
        total.micronutrients = micros
        return total
    }

    public var nutrientsPer100gCooked: NutrientsPer100g {
        let yield = max(1.0, totalYieldGrams)
        let batch = totalBatchNutrients
        let scale = 100.0 / yield
        var micros: [String: Double] = [:]
        for (k, v) in batch.micronutrients {
            micros[k] = v * scale
        }
        return NutrientsPer100g(
            calories: batch.calories * scale,
            protein: batch.protein * scale,
            carbs: batch.carbs * scale,
            fat: batch.fat * scale,
            fiber: batch.fiber * scale,
            sugar: batch.sugar * scale,
            sodiumMg: batch.sodiumMg * scale,
            micronutrients: micros
        )
    }

    public func makeOrUpdateShadowFood(existing: Food? = nil) -> Food {
        let gramsPerServing = max(1.0, totalYieldGrams / max(1.0, servings))
        let sizes = [
            ServingSize(label: "1 serving (\(Int(gramsPerServing.rounded()))g)", grams: gramsPerServing),
            ServingSize(label: "100 g cooked", grams: 100.0),
            ServingSize(label: "Whole recipe", grams: max(1.0, totalYieldGrams))
        ]
        if let existing {
            existing.name = name
            existing.source = .recipe
            existing.servingSizes = sizes
            existing.nutrientsPer100g = nutrientsPer100gCooked
            return existing
        } else {
            let food = Food(
                name: name,
                brand: "Homemade Recipe",
                source: .recipe,
                servingSizes: sizes,
                nutrientsPer100g: nutrientsPer100gCooked
            )
            self.linkedFoodID = food.id
            return food
        }
    }
}

@Model
public final class RecipeIngredient {
    public var id: UUID = UUID()
    public var grams: Double = 100.0
    public var snapshotName: String = ""
    public var snapshotNutrientsJSON: Data = Data()

    public var recipe: Recipe? = nil
    public var food: Food? = nil

    public init(food: Food, grams: Double) {
        self.food = food
        self.grams = max(0.1, grams)
        self.snapshotName = food.name
        self.snapshotNutrientsJSON = (try? JSONEncoder().encode(food.nutrientsPer100g)) ?? Data()
    }

    public var baseNutrientsPer100g: NutrientsPer100g {
        if let food {
            return food.nutrientsPer100g
        }
        if let decoded = try? JSONDecoder().decode(NutrientsPer100g.self, from: snapshotNutrientsJSON) {
            return decoded
        }
        return NutrientsPer100g()
    }

    public var scaledNutrients: NutrientsPer100g {
        baseNutrientsPer100g.scaled(forGrams: grams)
    }
}

/// Immutable nutrient snapshot at log time (§2) so future edits to a `Food` never rewrite history.
@Model
public final class FoodLogEntry {
    public var id: UUID = UUID()
    public var foodID: UUID? = nil
    public var foodName: String = ""
    public var foodBrand: String? = nil
    public var foodSourceRaw: String = FoodSource.custom.rawValue

    // Snapshot per 100 g at log time
    public var snapshotCaloriesPer100g: Double = 0
    public var snapshotProteinPer100g: Double = 0
    public var snapshotCarbsPer100g: Double = 0
    public var snapshotFatPer100g: Double = 0
    public var snapshotFiberPer100g: Double = 0
    public var snapshotSugarPer100g: Double = 0
    public var snapshotSodiumMgPer100g: Double = 0
    public var snapshotMicronutrientsJSON: Data = Data()

    public var grams: Double = 100.0
    public var servingLabel: String = "100 g"
    public var mealTagRaw: String = MealTag.none.rawValue
    public var timestamp: Date = Date()
    public var dayKey: String = ""
    public var healthKitSampleIDsJSON: Data = Data()

    /// Optional parent recipe linkage for 1-tap "Explode Recipe" (§MacroFactor Kitchen)
    public var recipeID: UUID? = nil
    public var recipeYieldFraction: Double? = nil

    public init(
        food: Food,
        grams: Double,
        servingLabel: String,
        mealTag: MealTag = .none,
        timestamp: Date = .now,
        dayKey: String? = nil
    ) {
        self.foodID = food.id
        self.foodName = food.name
        self.foodBrand = food.brand
        self.foodSourceRaw = food.sourceRaw
        self.snapshotCaloriesPer100g = food.caloriesPer100g
        self.snapshotProteinPer100g = food.proteinPer100g
        self.snapshotCarbsPer100g = food.carbsPer100g
        self.snapshotFatPer100g = food.fatPer100g
        self.snapshotFiberPer100g = food.fiberPer100g
        self.snapshotSugarPer100g = food.sugarPer100g
        self.snapshotSodiumMgPer100g = food.sodiumMgPer100g
        self.snapshotMicronutrientsJSON = food.micronutrientsJSON
        self.grams = max(0.1, grams)
        self.servingLabel = servingLabel
        self.mealTagRaw = mealTag.rawValue
        self.timestamp = timestamp
        self.dayKey = dayKey ?? DayKey.from(timestamp)
    }

    /// Direct Quick-Add initializer (raw calories & macros without creating a permanent catalog item).
    public init(
        quickTitle: String,
        calories: Double,
        protein: Double = 0,
        carbs: Double = 0,
        fat: Double = 0,
        mealTag: MealTag = .none,
        timestamp: Date = .now,
        dayKey: String? = nil
    ) {
        self.foodID = nil
        self.foodName = quickTitle.isEmpty ? "Quick Add" : quickTitle
        self.foodBrand = nil
        self.foodSourceRaw = FoodSource.custom.rawValue
        self.snapshotCaloriesPer100g = calories
        self.snapshotProteinPer100g = protein
        self.snapshotCarbsPer100g = carbs
        self.snapshotFatPer100g = fat
        self.grams = 100.0
        self.servingLabel = "1 quick entry"
        self.mealTagRaw = mealTag.rawValue
        self.timestamp = timestamp
        self.dayKey = dayKey ?? DayKey.from(timestamp)
    }

    public var foodSource: FoodSource {
        FoodSource(rawValue: foodSourceRaw) ?? .custom
    }

    public var mealTag: MealTag {
        get { MealTag(rawValue: mealTagRaw) ?? .none }
        set { mealTagRaw = newValue.rawValue }
    }

    public var healthKitSampleIDs: [UUID] {
        get {
            guard !healthKitSampleIDsJSON.isEmpty,
                  let decoded = try? JSONDecoder().decode([UUID].self, from: healthKitSampleIDsJSON) else {
                return []
            }
            return decoded
        }
        set {
            healthKitSampleIDsJSON = (try? JSONEncoder().encode(newValue)) ?? Data()
        }
    }

    public var loggedNutrients: NutrientsPer100g {
        let micros = snapshotMicronutrientsJSON.isEmpty
            ? [:]
            : ((try? NutritionModelCoding.decoder.decode([String: Double].self, from: snapshotMicronutrientsJSON)) ?? [:])
        let base = NutrientsPer100g(
            calories: snapshotCaloriesPer100g,
            protein: snapshotProteinPer100g,
            carbs: snapshotCarbsPer100g,
            fat: snapshotFatPer100g,
            fiber: snapshotFiberPer100g,
            sugar: snapshotSugarPer100g,
            sodiumMg: snapshotSodiumMgPer100g,
            micronutrients: micros
        )
        return base.scaled(forGrams: grams)
    }

    private var gramScaleFactor: Double { max(0, grams) / 100.0 }
    public var calories: Double { snapshotCaloriesPer100g * gramScaleFactor }
    public var protein: Double { snapshotProteinPer100g * gramScaleFactor }
    public var carbs: Double { snapshotCarbsPer100g * gramScaleFactor }
    public var fat: Double { snapshotFatPer100g * gramScaleFactor }
    public var fiber: Double { snapshotFiberPer100g * gramScaleFactor }
    public var sugar: Double { snapshotSugarPer100g * gramScaleFactor }
    public var sodiumMg: Double { snapshotSodiumMgPer100g * gramScaleFactor }

    public func duplicate(toTimestamp newTimestamp: Date, newDayKey: String) -> FoodLogEntry {
        let copy = FoodLogEntry(
            quickTitle: foodName,
            calories: snapshotCaloriesPer100g,
            protein: snapshotProteinPer100g,
            carbs: snapshotCarbsPer100g,
            fat: snapshotFatPer100g,
            mealTag: mealTag,
            timestamp: newTimestamp,
            dayKey: newDayKey
        )
        copy.foodID = foodID
        copy.foodBrand = foodBrand
        copy.foodSourceRaw = foodSourceRaw
        copy.snapshotFiberPer100g = snapshotFiberPer100g
        copy.snapshotSugarPer100g = snapshotSugarPer100g
        copy.snapshotSodiumMgPer100g = snapshotSodiumMgPer100g
        copy.snapshotMicronutrientsJSON = snapshotMicronutrientsJSON
        copy.grams = grams
        copy.servingLabel = servingLabel
        return copy
    }
}

@Model
public final class DailyNote {
    public var id: UUID = UUID()
    public var dayKey: String = ""
    public var date: Date = Date()
    /// Critical flag (§2 & §8): Only days marked `isComplete = true` feed the adaptive expenditure average!
    public var isComplete: Bool = false
    public var notes: String = ""

    public init(dayKey: String, date: Date? = nil, isComplete: Bool = false, notes: String = "") {
        self.dayKey = dayKey
        self.date = date ?? DayKey.date(from: dayKey) ?? .now
        self.isComplete = isComplete
        self.notes = notes
    }
}

// MARK: - Saved Meals (§MacroFactor Kitchen Rehaul)

/// Reusable multi-item staple meal template (e.g. "Morning Shake", "Standard Post-Workout Bowl")
@Model
public final class SavedMeal {
    public var id: UUID = UUID()
    public var name: String = ""
    public var createdAt: Date = Date()
    public var lastUsed: Date? = nil
    public var useCount: Int = 0
    public var defaultMealTagRaw: String = MealTag.none.rawValue

    @Relationship(deleteRule: .cascade, inverse: \SavedMealItem.meal)
    public var items: [SavedMealItem]? = []

    public init(name: String, defaultMealTag: MealTag = .none) {
        self.id = UUID()
        self.name = name
        self.defaultMealTagRaw = defaultMealTag.rawValue
        self.createdAt = Date()
    }

    public var defaultMealTag: MealTag {
        get { MealTag(rawValue: defaultMealTagRaw) ?? .none }
        set { defaultMealTagRaw = newValue.rawValue }
    }

    public var safeItems: [SavedMealItem] {
        items ?? []
    }

    public var totalNutrients: NutrientsPer100g {
        var total = NutrientsPer100g()
        for item in safeItems {
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
}

@Model
public final class SavedMealItem {
    public var id: UUID = UUID()
    public var grams: Double = 100.0
    public var servingLabel: String = "100 g"
    public var quantity: Double = 1.0
    public var snapshotName: String = ""
    public var snapshotNutrientsJSON: Data = Data()

    public var meal: SavedMeal? = nil
    public var food: Food? = nil

    public init(food: Food, grams: Double, servingLabel: String, quantity: Double = 1.0) {
        self.id = UUID()
        self.food = food
        self.grams = max(0.1, grams)
        self.servingLabel = servingLabel
        self.quantity = max(0.01, quantity)
        self.snapshotName = food.name
        self.snapshotNutrientsJSON = (try? JSONEncoder().encode(food.nutrientsPer100g)) ?? Data()
    }

    public var scaledNutrients: NutrientsPer100g {
        if let food {
            return food.nutrientsPer100g.scaled(forGrams: grams)
        }
        if let decoded = try? JSONDecoder().decode(NutrientsPer100g.self, from: snapshotNutrientsJSON) {
            return decoded.scaled(forGrams: grams)
        }
        return NutrientsPer100g()
    }
}
