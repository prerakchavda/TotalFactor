import Foundation
import SwiftData

/// Represents a standardized, verified composite dish or street food with natural piece/serving units.
/// Designed for real-world eating where food scales are unavailable (e.g. street food, takeout, social meals).
public struct CompositeFoodEntry: Identifiable, Sendable, Equatable {
    public enum Category: String, Sendable, CaseIterable {
        case streetFood = "Street Food & Bites"
        case culturalStaple = "Home-Cooked Staples"
        case takeout = "Takeout & Diner"
        case handPortion = "Hand-Size Estimates"
        case snackAndTreat = "Snacks, Dips & Treats"
    }

    public var id: UUID
    public var name: String
    public var aliases: [String]
    public var category: Category
    public var defaultServingLabel: String
    public var servingGrams: Double
    public var defaultQuantity: Double
    public var pieceUnitName: String // e.g. "piece", "taco", "roll", "slice", "katori", "cup"
    public var nutrientsPer100g: NutrientsPer100g

    public init(
        id: UUID = UUID(),
        name: String,
        aliases: [String],
        category: Category,
        defaultServingLabel: String,
        servingGrams: Double,
        defaultQuantity: Double = 1.0,
        pieceUnitName: String = "piece",
        nutrientsPer100g: NutrientsPer100g
    ) {
        self.id = id
        self.name = name
        self.aliases = aliases
        self.category = category
        self.defaultServingLabel = defaultServingLabel
        self.servingGrams = max(1.0, servingGrams)
        self.defaultQuantity = max(0.1, defaultQuantity)
        self.pieceUnitName = pieceUnitName
        self.nutrientsPer100g = nutrientsPer100g
    }

    /// Single serving / piece nutrition
    public var perServingNutrients: NutrientsPer100g {
        nutrientsPer100g.scaled(forGrams: servingGrams)
    }

    /// Scaled nutrition for a specific count/multiplier
    public func nutrients(forQuantity qty: Double) -> NutrientsPer100g {
        nutrientsPer100g.scaled(forGrams: servingGrams * qty)
    }

    public var defaultServing: ServingSize {
        ServingSize(label: defaultServingLabel, grams: servingGrams)
    }

    public var servingSizes: [ServingSize] {
        [
            ServingSize(label: defaultServingLabel, grams: servingGrams),
            ServingSize(label: "100 g", grams: 100.0)
        ]
    }
}

/// Offline, zero-network repository of verified composite dishes, cultural foods, and hand-size benchmarks.
public enum CompositeFoodLibrary {

    public static let entries: [CompositeFoodEntry] = [
        // MARK: - Street Food & Bites
        CompositeFoodEntry(
            name: "Panipuri (Golgappa / Puchka)",
            aliases: ["panipuri", "pani puri", "golgappa", "gol gappa", "puchka", "phuchka"],
            category: .streetFood,
            defaultServingLabel: "1 piece (28g)",
            servingGrams: 28.0,
            defaultQuantity: 10.0,
            pieceUnitName: "piece",
            // 1 pc: 28 kcal, 0.5g P, 4.8g C, 0.8g F (100g: 100 kcal, 1.8g P, 17.1g C, 2.9g F)
            nutrientsPer100g: NutrientsPer100g(
                calories: 100.0,
                protein: 1.8,
                carbs: 17.1,
                fat: 2.9,
                fiber: 1.4,
                sugar: 2.0,
                sodiumMg: 160.0
            )
        ),
        CompositeFoodEntry(
            name: "Samosa (Standard Spiced Potato & Pea)",
            aliases: ["samosa", "samosas", "punjabi samosa", "potato samosa"],
            category: .streetFood,
            defaultServingLabel: "1 samosa (100g)",
            servingGrams: 100.0,
            defaultQuantity: 1.0,
            pieceUnitName: "samosa",
            nutrientsPer100g: NutrientsPer100g(
                calories: 260.0,
                protein: 4.2,
                carbs: 32.0,
                fat: 13.0,
                fiber: 3.5,
                sugar: 2.5,
                sodiumMg: 420.0
            )
        ),
        CompositeFoodEntry(
            name: "Cocktail Samosa (Mini)",
            aliases: ["mini samosa", "cocktail samosa"],
            category: .streetFood,
            defaultServingLabel: "1 cocktail samosa (35g)",
            servingGrams: 35.0,
            defaultQuantity: 3.0,
            pieceUnitName: "piece",
            nutrientsPer100g: NutrientsPer100g(
                calories: 257.0,
                protein: 4.3,
                carbs: 31.4,
                fat: 12.9,
                fiber: 3.0,
                sugar: 2.0,
                sodiumMg: 380.0
            )
        ),
        CompositeFoodEntry(
            name: "Street Taco (Corn Tortilla, Meat, Onion, Cilantro)",
            aliases: ["street taco", "street tacos", "taco", "tacos", "carne asada taco", "chicken taco"],
            category: .streetFood,
            defaultServingLabel: "1 taco (90g)",
            servingGrams: 90.0,
            defaultQuantity: 2.0,
            pieceUnitName: "taco",
            nutrientsPer100g: NutrientsPer100g(
                calories: 200.0,
                protein: 13.3,
                carbs: 17.8,
                fat: 8.9,
                fiber: 2.2,
                sugar: 1.1,
                sodiumMg: 310.0
            )
        ),
        CompositeFoodEntry(
            name: "Steamed Dumplings / Momos",
            aliases: ["dumpling", "dumplings", "momo", "momos", "steamed momos", "steamed dumplings", "gyoza"],
            category: .streetFood,
            defaultServingLabel: "1 piece (25g)",
            servingGrams: 25.0,
            defaultQuantity: 6.0,
            pieceUnitName: "piece",
            nutrientsPer100g: NutrientsPer100g(
                calories: 180.0,
                protein: 10.0,
                carbs: 20.0,
                fat: 6.0,
                fiber: 1.5,
                sugar: 1.2,
                sodiumMg: 360.0
            )
        ),
        CompositeFoodEntry(
            name: "Sushi Roll (Standard 6-8 Pcs, e.g. California / Tuna)",
            aliases: ["sushi roll", "sushi", "california roll", "tuna roll", "salmon roll", "maki roll"],
            category: .streetFood,
            defaultServingLabel: "1 roll (200g, ~6-8 pcs)",
            servingGrams: 200.0,
            defaultQuantity: 1.0,
            pieceUnitName: "roll",
            nutrientsPer100g: NutrientsPer100g(
                calories: 160.0,
                protein: 6.0,
                carbs: 25.0,
                fat: 3.5,
                fiber: 1.8,
                sugar: 3.0,
                sodiumMg: 380.0
            )
        ),
        CompositeFoodEntry(
            name: "Pizza Slice (Standard 14\" Large Crust, Pepperoni/Cheese)",
            aliases: ["pizza slice", "slice of pizza", "pizza", "pepperoni pizza", "cheese pizza"],
            category: .streetFood,
            defaultServingLabel: "1 slice (107g)",
            servingGrams: 107.0,
            defaultQuantity: 2.0,
            pieceUnitName: "slice",
            nutrientsPer100g: NutrientsPer100g(
                calories: 266.0,
                protein: 11.2,
                carbs: 33.6,
                fat: 9.3,
                fiber: 2.1,
                sugar: 3.5,
                sodiumMg: 590.0
            )
        ),
        CompositeFoodEntry(
            name: "Chicken Wing (Bone-In, Cooked with Sauce)",
            aliases: ["chicken wing", "chicken wings", "hot wing", "hot wings", "buffalo wings"],
            category: .streetFood,
            defaultServingLabel: "1 wing (34g edible)",
            servingGrams: 34.0,
            defaultQuantity: 6.0,
            pieceUnitName: "wing",
            nutrientsPer100g: NutrientsPer100g(
                calories: 250.0,
                protein: 23.5,
                carbs: 2.9,
                fat: 17.6,
                fiber: 0.2,
                sugar: 1.5,
                sodiumMg: 620.0
            )
        ),
        CompositeFoodEntry(
            name: "Falafel (Spiced Chickpea Patty)",
            aliases: ["falafel", "falafels", "falafel ball"],
            category: .streetFood,
            defaultServingLabel: "1 piece (25g)",
            servingGrams: 25.0,
            defaultQuantity: 4.0,
            pieceUnitName: "piece",
            nutrientsPer100g: NutrientsPer100g(
                calories: 240.0,
                protein: 8.0,
                carbs: 24.0,
                fat: 12.0,
                fiber: 4.5,
                sugar: 1.8,
                sodiumMg: 290.0
            )
        ),

        // MARK: - Home-Cooked Staples
        CompositeFoodEntry(
            name: "Roti / Chapati (Plain, Whole Wheat)",
            aliases: ["roti", "chapati", "phulka", "plain roti", "wheat roti", "rotis"],
            category: .culturalStaple,
            defaultServingLabel: "1 roti (35g)",
            servingGrams: 35.0,
            defaultQuantity: 2.0,
            pieceUnitName: "roti",
            nutrientsPer100g: NutrientsPer100g(
                calories: 228.0,
                protein: 8.6,
                carbs: 42.9,
                fat: 2.9,
                fiber: 5.7,
                sugar: 1.0,
                sodiumMg: 110.0
            )
        ),
        CompositeFoodEntry(
            name: "Roti with Ghee / Butter",
            aliases: ["roti with ghee", "ghee roti", "chapati with ghee", "buttered roti"],
            category: .culturalStaple,
            defaultServingLabel: "1 roti with ghee (40g)",
            servingGrams: 40.0,
            defaultQuantity: 2.0,
            pieceUnitName: "roti",
            nutrientsPer100g: NutrientsPer100g(
                calories: 275.0,
                protein: 7.5,
                carbs: 37.5,
                fat: 11.2,
                fiber: 5.0,
                sugar: 1.0,
                sodiumMg: 120.0
            )
        ),
        CompositeFoodEntry(
            name: "Dal Tadka (Spiced Yellow Lentil Katori)",
            aliases: ["dal", "daal", "dal tadka", "yellow dal", "toor dal", "moong dal"],
            category: .culturalStaple,
            defaultServingLabel: "1 katori / small bowl (180g)",
            servingGrams: 180.0,
            defaultQuantity: 1.0,
            pieceUnitName: "bowl",
            nutrientsPer100g: NutrientsPer100g(
                calories: 83.0,
                protein: 4.4,
                carbs: 11.1,
                fat: 2.2,
                fiber: 2.8,
                sugar: 1.1,
                sodiumMg: 240.0
            )
        ),
        CompositeFoodEntry(
            name: "Chicken Biryani (Spiced Basmati Rice & Marinated Chicken)",
            aliases: ["biryani", "chicken biryani", "biriyani", "mutton biryani", "lamb biryani"],
            category: .culturalStaple,
            defaultServingLabel: "1 cup / takeout portion (200g)",
            servingGrams: 200.0,
            defaultQuantity: 1.5,
            pieceUnitName: "cup",
            nutrientsPer100g: NutrientsPer100g(
                calories: 160.0,
                protein: 8.0,
                carbs: 21.0,
                fat: 4.5,
                fiber: 1.2,
                sugar: 1.0,
                sodiumMg: 340.0
            )
        ),
        CompositeFoodEntry(
            name: "Pav Bhaji (Spiced Vegetable Mash with 2 Buttered Pav)",
            aliases: ["pav bhaji", "bhaji pav", "pav baji"],
            category: .culturalStaple,
            defaultServingLabel: "1 order (250g bhaji + 2 pav)",
            servingGrams: 250.0,
            defaultQuantity: 1.0,
            pieceUnitName: "order",
            nutrientsPer100g: NutrientsPer100g(
                calories: 180.0,
                protein: 4.0,
                carbs: 26.0,
                fat: 6.4,
                fiber: 3.5,
                sugar: 3.0,
                sodiumMg: 420.0
            )
        ),
        CompositeFoodEntry(
            name: "Chole Bhature (Spiced Chickpeas with 2 Fried Bhature)",
            aliases: ["chole bhature", "chana bhatura", "chole bhatura"],
            category: .culturalStaple,
            defaultServingLabel: "1 plate (300g)",
            servingGrams: 300.0,
            defaultQuantity: 1.0,
            pieceUnitName: "plate",
            nutrientsPer100g: NutrientsPer100g(
                calories: 207.0,
                protein: 5.3,
                carbs: 24.0,
                fat: 10.0,
                fiber: 3.2,
                sugar: 2.0,
                sodiumMg: 450.0
            )
        ),
        CompositeFoodEntry(
            name: "Masala Dosa Set (Crisp Rice Crepe with Potato Masala & Sambar)",
            aliases: ["dosa", "masala dosa", "plain dosa", "sambar dosa"],
            category: .culturalStaple,
            defaultServingLabel: "1 dosa set (220g)",
            servingGrams: 220.0,
            defaultQuantity: 1.0,
            pieceUnitName: "dosa",
            nutrientsPer100g: NutrientsPer100g(
                calories: 172.0,
                protein: 3.6,
                carbs: 25.5,
                fat: 6.4,
                fiber: 2.3,
                sugar: 2.1,
                sodiumMg: 310.0
            )
        ),

        // MARK: - Takeout & Diner
        CompositeFoodEntry(
            name: "Chipotle Burrito Bowl (Chicken, Rice, Black Beans, Fajitas, Salsa)",
            aliases: ["burrito bowl", "chipotle bowl", "chipotle burrito bowl"],
            category: .takeout,
            defaultServingLabel: "1 bowl (450g)",
            servingGrams: 450.0,
            defaultQuantity: 1.0,
            pieceUnitName: "bowl",
            nutrientsPer100g: NutrientsPer100g(
                calories: 160.0,
                protein: 10.0,
                carbs: 15.6,
                fat: 5.3,
                fiber: 2.7,
                sugar: 1.5,
                sodiumMg: 340.0
            )
        ),
        CompositeFoodEntry(
            name: "Pad Thai (Stir-Fried Rice Noodles, Chicken, Egg, Peanuts)",
            aliases: ["pad thai", "pad thai noodles"],
            category: .takeout,
            defaultServingLabel: "1 order / takeout box (380g)",
            servingGrams: 380.0,
            defaultQuantity: 1.0,
            pieceUnitName: "order",
            nutrientsPer100g: NutrientsPer100g(
                calories: 171.0,
                protein: 5.8,
                carbs: 22.4,
                fat: 6.3,
                fiber: 1.8,
                sugar: 5.5,
                sodiumMg: 410.0
            )
        ),
        CompositeFoodEntry(
            name: "Cheeseburger (Standard Diner / Fast-Food Style)",
            aliases: ["burger", "cheeseburger", "hamburger"],
            category: .takeout,
            defaultServingLabel: "1 burger (220g)",
            servingGrams: 220.0,
            defaultQuantity: 1.0,
            pieceUnitName: "burger",
            nutrientsPer100g: NutrientsPer100g(
                calories: 218.0,
                protein: 11.8,
                carbs: 19.1,
                fat: 10.5,
                fiber: 1.4,
                sugar: 3.5,
                sodiumMg: 480.0
            )
        ),
        CompositeFoodEntry(
            name: "French Fries (Medium Takeout Order)",
            aliases: ["french fries", "fries", "medium fries"],
            category: .takeout,
            defaultServingLabel: "1 medium order (117g)",
            servingGrams: 117.0,
            defaultQuantity: 1.0,
            pieceUnitName: "order",
            nutrientsPer100g: NutrientsPer100g(
                calories: 312.0,
                protein: 3.4,
                carbs: 41.0,
                fat: 14.5,
                fiber: 3.8,
                sugar: 0.3,
                sodiumMg: 210.0
            )
        ),

        // MARK: - Hand-Size & Container References
        CompositeFoodEntry(
            name: "Palm of Protein (Cooked Chicken / Steak / Fish)",
            aliases: ["palm of protein", "palm of chicken", "palm of steak", "palm of meat", "palm protein"],
            category: .handPortion,
            defaultServingLabel: "1 palm (~130g cooked)",
            servingGrams: 130.0,
            defaultQuantity: 1.0,
            pieceUnitName: "palm",
            nutrientsPer100g: NutrientsPer100g(
                calories: 165.0,
                protein: 31.0,
                carbs: 0.0,
                fat: 3.6,
                fiber: 0.0,
                sugar: 0.0,
                sodiumMg: 74.0
            )
        ),
        CompositeFoodEntry(
            name: "Fist of Carbs (Cooked Rice / Pasta / Potato)",
            aliases: ["fist of carbs", "fist of rice", "fist of pasta", "fist of potato", "fist carbs"],
            category: .handPortion,
            defaultServingLabel: "1 fist (~1 cup / 158g)",
            servingGrams: 158.0,
            defaultQuantity: 1.0,
            pieceUnitName: "fist",
            nutrientsPer100g: NutrientsPer100g(
                calories: 130.0,
                protein: 2.7,
                carbs: 28.2,
                fat: 0.3,
                fiber: 0.4,
                sugar: 0.1,
                sodiumMg: 1.0
            )
        ),
        CompositeFoodEntry(
            name: "Cupped Hand of Snacks (Nuts / Chips / Berries)",
            aliases: ["cupped hand of nuts", "cupped hand of snacks", "cupped hand", "handful of nuts", "handful of snacks"],
            category: .handPortion,
            defaultServingLabel: "1 cupped hand (~½ cup / 50g)",
            servingGrams: 50.0,
            defaultQuantity: 1.0,
            pieceUnitName: "handful",
            nutrientsPer100g: NutrientsPer100g(
                calories: 450.0,
                protein: 14.0,
                carbs: 22.0,
                fat: 36.0,
                fiber: 6.0,
                sugar: 4.5,
                sodiumMg: 180.0
            )
        ),
        CompositeFoodEntry(
            name: "Thumb of Fat (Oil / Butter / Peanut Butter)",
            aliases: ["thumb of oil", "thumb of butter", "thumb of fat", "thumb of peanut butter", "thumb fat"],
            category: .handPortion,
            defaultServingLabel: "1 thumb (~1 tbsp / 14g)",
            servingGrams: 14.0,
            defaultQuantity: 1.0,
            pieceUnitName: "thumb",
            nutrientsPer100g: NutrientsPer100g(
                calories: 785.0,
                protein: 1.0,
                carbs: 1.0,
                fat: 88.0,
                fiber: 0.0,
                sugar: 0.5,
                sodiumMg: 50.0
            )
        ),
        CompositeFoodEntry(
            name: "Deli Pint Container (Curry / Soup / Stew)",
            aliases: ["deli pint", "pint of curry", "pint of soup", "pint container"],
            category: .handPortion,
            defaultServingLabel: "1 pint container (~2 cups / 450g)",
            servingGrams: 450.0,
            defaultQuantity: 1.0,
            pieceUnitName: "pint",
            nutrientsPer100g: NutrientsPer100g(
                calories: 95.0,
                protein: 5.5,
                carbs: 10.0,
                fat: 3.8,
                fiber: 2.2,
                sugar: 2.5,
                sodiumMg: 350.0
            )
        ),
        CompositeFoodEntry(
            name: "Deli Quart Container (Family-Size Curry / Soup)",
            aliases: ["deli quart", "quart of curry", "quart of soup", "quart container"],
            category: .handPortion,
            defaultServingLabel: "1 quart container (~4 cups / 900g)",
            servingGrams: 900.0,
            defaultQuantity: 1.0,
            pieceUnitName: "quart",
            nutrientsPer100g: NutrientsPer100g(
                calories: 95.0,
                protein: 5.5,
                carbs: 10.0,
                fat: 3.8,
                fiber: 2.2,
                sugar: 2.5,
                sodiumMg: 350.0
            )
        ),
        CompositeFoodEntry(
            name: "3-Compartment Takeout Box (Meat + Rice + Veggies)",
            aliases: ["3 compartment takeout", "takeout box", "3 compartment box", "takeout platter"],
            category: .handPortion,
            defaultServingLabel: "1 full box (~650g)",
            servingGrams: 650.0,
            defaultQuantity: 1.0,
            pieceUnitName: "box",
            nutrientsPer100g: NutrientsPer100g(
                calories: 145.0,
                protein: 8.5,
                carbs: 18.0,
                fat: 4.2,
                fiber: 2.0,
                sugar: 2.0,
                sodiumMg: 380.0
            )
        ),

        // MARK: - Snacks, Dips & Real-World Treats
        CompositeFoodEntry(
            name: "Caramel Dip (Single-Serve / 2 tbsp)",
            aliases: ["caramel dip", "caramel apple dip", "marzetti caramel dip", "caramel dipping sauce", "caramel cup"],
            category: .snackAndTreat,
            defaultServingLabel: "2 tbsp (38g)",
            servingGrams: 38.0,
            defaultQuantity: 1.0,
            pieceUnitName: "serving",
            // 2 tbsp (38g): 140 kcal, 0.5g P, 30g C, 2.5g F (Per 100g: 368 kcal, 1.3g P, 78.9g C, 6.6g F)
            nutrientsPer100g: NutrientsPer100g(
                calories: 368.0,
                protein: 1.3,
                carbs: 78.9,
                fat: 6.6,
                fiber: 0.0,
                sugar: 52.6,
                sodiumMg: 210.0
            )
        ),
        CompositeFoodEntry(
            name: "Heath English Toffee Candy Bar",
            aliases: ["heath candy", "heath bar", "heath toffee", "heath candy bar", "heath bites", "heath toffee bar", "heath"],
            category: .snackAndTreat,
            defaultServingLabel: "1 bar / serving (39g)",
            servingGrams: 39.0,
            defaultQuantity: 1.0,
            pieceUnitName: "bar",
            // 1 bar (39g): 210 kcal, 1.5g P, 25g C, 12g F (Per 100g: 538 kcal, 3.8g P, 64.1g C, 30.8g F)
            nutrientsPer100g: NutrientsPer100g(
                calories: 538.0,
                protein: 3.8,
                carbs: 64.1,
                fat: 30.8,
                fiber: 1.5,
                sugar: 61.5,
                sodiumMg: 245.0
            )
        ),
        CompositeFoodEntry(
            name: "Apple Slices with Caramel Dip & Heath Candy",
            aliases: [
                "apples with caramel dip and heath candy",
                "apples with caramel dip and heath",
                "apples with caramel and heath candy",
                "apple with caramel dip and heath candy",
                "apple slices with caramel and heath"
            ],
            category: .snackAndTreat,
            defaultServingLabel: "1 platter (~260g)",
            servingGrams: 260.0,
            defaultQuantity: 1.0,
            pieceUnitName: "platter",
            // 1 platter (260g: 1 medium apple 182g + 2 tbsp caramel 39g + 1 toffee bar 39g): 445 kcal, 2.8g P, 80.1g C, 14.8g F
            nutrientsPer100g: NutrientsPer100g(
                calories: 171.0,
                protein: 1.1,
                carbs: 30.8,
                fat: 5.7,
                fiber: 2.1,
                sugar: 27.5,
                sodiumMg: 125.0
            )
        )
    ]

    /// Matches a natural query string against composite aliases and names.
    public static func find(matching query: String) -> CompositeFoodEntry? {
        let clean = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !clean.isEmpty else { return nil }

        // Exact name or alias match
        for entry in entries {
            if entry.name.lowercased() == clean { return entry }
            for alias in entry.aliases {
                if alias == clean { return entry }
            }
        }

        // Substring match
        for entry in entries {
            for alias in entry.aliases {
                if clean.contains(alias) || (alias.contains(clean) && Double(clean.count) >= Double(alias.count) * 0.8) {
                    return entry
                }
            }
            if clean.contains(entry.name.lowercased()) {
                return entry
            }
        }
        return nil
    }

    /// Search candidates for catalog lookup
    public static func search(query: String, limit: Int = 10) -> [CompositeFoodEntry] {
        let clean = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !clean.isEmpty else { return Array(entries.prefix(limit)) }

        var matches: [CompositeFoodEntry] = []
        for entry in entries {
            if entry.name.lowercased().contains(clean) || entry.aliases.contains(where: { $0.contains(clean) }) {
                matches.append(entry)
                if matches.count >= limit { break }
            }
        }
        return matches
    }

    /// Materializes a `CompositeFoodEntry` into a persisted SwiftData `Food` entity
    @MainActor
    public static func materialize(_ entry: CompositeFoodEntry, in context: ModelContext) -> Food {
        let sid = "composite-\(entry.name.lowercased().replacingOccurrences(of: " ", with: "-"))"
        let customRaw = FoodSource.custom.rawValue
        let descriptor = FetchDescriptor<Food>(
            predicate: #Predicate { $0.sourceRaw == customRaw && $0.sourceID == sid }
        )
        if let existing = (try? context.fetch(descriptor))?.first {
            return existing
        }

        let food = Food(
            id: entry.id,
            name: entry.name,
            brand: "Composite / Street Food",
            barcode: nil,
            source: .custom,
            sourceID: sid,
            isBundledGeneric: false,
            servingSizes: entry.servingSizes,
            nutrientsPer100g: entry.nutrientsPer100g
        )
        food.lastLoggedServingLabel = entry.defaultServingLabel
        food.lastLoggedGrams = entry.servingGrams
        context.insert(food)
        try? context.save()
        return food
    }
}
