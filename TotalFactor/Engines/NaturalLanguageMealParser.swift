import Foundation
#if canImport(NaturalLanguage)
import NaturalLanguage
#endif

/// Pure-Swift representation of a user's persisted `Food` item for offline natural-language matching.
public struct PersistedFoodMatcherItem: Sendable, Equatable {
    public var id: UUID
    public var sourceID: String?
    public var name: String
    public var brand: String?
    public var source: FoodSource
    public var isFavorite: Bool
    public var useCount: Int
    public var lastUsed: Date?
    public var lastLoggedGrams: Double
    public var lastLoggedServingLabel: String
    public var servingSizes: [ServingSize]
    public var nutrientsPer100g: NutrientsPer100g

    public init(
        id: UUID,
        sourceID: String? = nil,
        name: String,
        brand: String? = nil,
        source: FoodSource = .custom,
        isFavorite: Bool = false,
        useCount: Int = 0,
        lastUsed: Date? = nil,
        lastLoggedGrams: Double = 100.0,
        lastLoggedServingLabel: String = "100 g",
        servingSizes: [ServingSize] = [ServingSize(label: "100 g", grams: 100)],
        nutrientsPer100g: NutrientsPer100g
    ) {
        self.id = id
        self.sourceID = sourceID
        self.name = name
        self.brand = brand
        self.source = source
        self.isFavorite = isFavorite
        self.useCount = useCount
        self.lastUsed = lastUsed
        self.lastLoggedGrams = lastLoggedGrams
        self.lastLoggedServingLabel = lastLoggedServingLabel
        self.servingSizes = servingSizes
        self.nutrientsPer100g = nutrientsPer100g
    }
}

/// Editable draft item produced by either `NaturalLanguageMealParser` (offline) or `GeminiMealParserService` (AI text/photo)
/// and reviewed in the 1-tap `MultiItemMealConfirmationSheet`.
public struct ParsedMealDraftItem: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var rawSegment: String
    public var foodName: String
    public var brand: String?
    public var quantity: Double
    public var servingLabel: String
    public var grams: Double
    public var nutrientsPer100g: NutrientsPer100g
    public var source: FoodSource
    public var matchedPersistedFoodID: UUID?
    public var matchedOfflineUSDASourceID: String?
    public var matchOriginBadge: String
    public var isIncluded: Bool

    public init(
        id: UUID = UUID(),
        rawSegment: String,
        foodName: String,
        brand: String? = nil,
        quantity: Double = 1.0,
        servingLabel: String,
        grams: Double,
        nutrientsPer100g: NutrientsPer100g,
        source: FoodSource = .usda,
        matchedPersistedFoodID: UUID? = nil,
        matchedOfflineUSDASourceID: String? = nil,
        matchOriginBadge: String = "USDA Offline",
        isIncluded: Bool = true
    ) {
        self.id = id
        self.rawSegment = rawSegment
        self.foodName = foodName
        self.brand = brand
        self.quantity = max(0.05, quantity)
        self.servingLabel = servingLabel
        self.grams = max(0.5, grams)
        self.nutrientsPer100g = nutrientsPer100g
        self.source = source
        self.matchedPersistedFoodID = matchedPersistedFoodID
        self.matchedOfflineUSDASourceID = matchedOfflineUSDASourceID
        self.matchOriginBadge = matchOriginBadge
        self.isIncluded = isIncluded
    }

    public var scaledNutrients: NutrientsPer100g {
        nutrientsPer100g.scaled(forGrams: grams)
    }
}

/// Deterministic, 100% offline multi-item natural-language meal parser (`§4 / Voice & Text Logging`).
/// Splits spoken or typed meal descriptions (e.g. `"3 eggs, 2 slices sourdough toast with 1 tbsp butter, and 200g greek yogurt"`),
/// extracts quantities, fractions, mass/volume/household units, resolves against user history + ~8,156 offline USDA foods,
/// and computes exact gram portions & macros.
public enum NaturalLanguageMealParser {

    private enum ParsedUnitKind: Equatable {
        case exactGrams(perUnitGrams: Double, unitSymbol: String)
        case householdUnit(canonicalToken: String, fallbackGrams: Double, displayUnit: String)
        case sizeDescriptor(sizeWord: String) // small, medium, large
        case countImplicit
    }

    private struct ExtractedQuantityAndFood {
        var rawSegment: String
        var quantity: Double
        var hadExplicitQuantity: Bool
        var unitKind: ParsedUnitKind
        var cleanedFoodQuery: String
    }

    private static let numberWords: [String: Double] = [
        "a": 1.0, "an": 1.0, "one": 1.0, "two": 2.0, "three": 3.0, "four": 4.0,
        "five": 5.0, "six": 6.0, "seven": 7.0, "eight": 8.0, "nine": 9.0, "ten": 10.0,
        "eleven": 11.0, "twelve": 12.0, "dozen": 12.0,
        "half": 0.5, "quarter": 0.25, "couple": 2.0, "double": 2.0, "triple": 3.0
    ]

    private static let unicodeFractions: [Character: String] = [
        "½": " 0.5 ", "¼": " 0.25 ", "¾": " 0.75 ",
        "⅓": " 0.333 ", "⅔": " 0.667 ", "⅛": " 0.125 "
    ]

    /// Common everyday spoken aliases mapped to high-signal USDA / pantry search queries.
    private static let phraseAliases: [(pattern: String, replacement: String)] = [
        ("sourdough toast", "sourdough bread"),
        ("wheat toast", "whole wheat bread"),
        ("white toast", "white bread"),
        ("toast", "bread"),
        ("oj", "orange juice"),
        ("pb", "peanut butter"),
        ("evoo", "olive oil"),
        ("olive oil", "olive oil"),
        ("greek yogurt", "greek yogurt plain"),
        ("protein shake", "whey protein isolate"),
        ("whey protein", "whey protein"),
        ("protein powder", "whey protein"),
        ("egg whites", "egg white raw"),
        ("egg white", "egg white raw"),
        ("scrambled eggs", "egg whole cooked"),
        ("fried eggs", "egg whole cooked"),
        ("boiled eggs", "egg whole cooked"),
        ("eggs", "eggs whole"),
        ("egg", "eggs whole"),
        ("oatmeal", "rolled oats"),
        ("oats", "rolled oats"),
        ("white rice", "white rice cooked"),
        ("brown rice", "brown rice cooked"),
        ("jasmine rice", "white rice cooked"),
        ("sweet potato", "sweet potato cooked"),
        ("chicken breast", "chicken breast cooked"),
        ("grilled chicken", "chicken breast cooked"),
        ("chicken thigh", "chicken thigh cooked"),
        ("ground turkey", "ground turkey"),
        ("ground beef", "ground beef"),
        ("steak", "beef top sirloin steak cooked"),
        ("salmon", "salmon cooked"),
        ("tuna", "tuna canned"),
        ("avocado", "avocado raw"),
        ("banana", "banana raw"),
        ("apple", "apple raw"),
        ("blueberries", "blueberries raw"),
        ("strawberries", "strawberries raw"),
        ("almond milk", "almond milk unsweetened"),
        ("whole milk", "milk whole"),
        ("skim milk", "milk nonfat"),
        ("pasta", "pasta cooked"),
        ("spaghetti", "spaghetti cooked"),
        ("bagel", "bagel plain"),
        ("protein bar", "protein bar"),
        ("almonds", "almonds raw"),
        ("peanut butter", "peanut butter"),
        ("honey", "honey")
    ]

    public static func parse(
        text: String,
        persistedFoods: [PersistedFoodMatcherItem] = [],
        offlineCatalog: OfflineUSDACatalogIndex
    ) -> [ParsedMealDraftItem] {
        let segments = splitIntoItemSegments(text, offlineCatalog: offlineCatalog)
        guard !segments.isEmpty else { return [] }

        var results: [ParsedMealDraftItem] = []
        results.reserveCapacity(segments.count)

        for segment in segments {
            guard let extracted = extractQuantityUnitAndFood(from: segment),
                  !extracted.cleanedFoodQuery.isEmpty else {
                continue
            }
            if let resolved = resolveItem(extracted, persistedFoods: persistedFoods, offlineCatalog: offlineCatalog) {
                results.append(resolved)
            }
        }
        return results
    }

    // MARK: - 1. Multi-Item Segment Splitting

    public static func splitIntoItemSegments(
        _ rawText: String,
        offlineCatalog: OfflineUSDACatalogIndex = .empty
    ) -> [String] {
        var normalized = rawText
        for (ch, rep) in unicodeFractions {
            normalized = normalized.replacingOccurrences(of: String(ch), with: rep)
        }

        // First split on explicit list delimiters: newlines, commas (when not inside numbers like 1,200), semicolons, +, &, "•"
        // Replace bullet/newline/semicolon/+ with pipe delimiter
        var working = normalized
            .replacingOccurrences(of: "\r\n", with: "|")
            .replacingOccurrences(of: "\n", with: "|")
            .replacingOccurrences(of: ";", with: "|")
            .replacingOccurrences(of: " + ", with: "|")
            .replacingOccurrences(of: "+", with: "|")
            .replacingOccurrences(of: "•", with: "|")

        // Split commas except thousands separators (e.g. "1,000")
        working = replaceCommasOutsideNumbers(working)

        let coarseParts = working
            .split(separator: "|")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var fineParts: [String] = []
        for part in coarseParts {
            fineParts.append(contentsOf: splitConjunctionsSmartly(part, offlineCatalog: offlineCatalog))
        }
        return fineParts
    }

    private static func replaceCommasOutsideNumbers(_ s: String) -> String {
        let chars = Array(s)
        var out = ""
        out.reserveCapacity(chars.count)
        for i in chars.indices {
            if chars[i] == "," {
                let prevIsDigit = i > 0 && chars[i - 1].isNumber
                let nextIsDigit = (i + 1 < chars.count) && chars[i + 1].isNumber
                if prevIsDigit && nextIsDigit {
                    // Remove thousands comma inside number
                    continue
                } else {
                    out.append("|")
                }
            } else {
                out.append(chars[i])
            }
        }
        return out
    }

    private static func splitConjunctionsSmartly(
        _ clause: String,
        offlineCatalog: OfflineUSDACatalogIndex
    ) -> [String] {
        // Connectors spoken naturally between meal items
        let connectors = [" and ", " with ", " plus ", " & ", " w/ "]
        var currentSegments = [clause]

        for connector in connectors {
            var nextPass: [String] = []
            for seg in currentSegments {
                let parts = splitCaseInsensitive(seg, separator: connector)
                if parts.count <= 1 {
                    nextPass.append(seg)
                    continue
                }

                // Re-join adjacent parts ONLY when they form a single compound food (e.g. "mac and cheese", "peanut butter and jelly")
                var merged: [String] = []
                var accumulator = parts[0]
                for idx in 1..<parts.count {
                    let rhs = parts[idx].trimmingCharacters(in: .whitespacesAndNewlines)
                    if rhs.isEmpty { continue }

                    if startsWithQuantityIndicator(rhs) {
                        merged.append(accumulator.trimmingCharacters(in: .whitespacesAndNewlines))
                        accumulator = rhs
                    } else {
                        let combinedPhrase = "\(accumulator)\(connector)\(rhs)"
                        // Keep together if combined phrase directly hits a known compound food in USDA catalog
                        let combinedHits = offlineCatalog.searchCandidates(query: combinedPhrase, limit: 3)
                        if !combinedHits.isEmpty {
                            accumulator = combinedPhrase
                        } else {
                            merged.append(accumulator.trimmingCharacters(in: .whitespacesAndNewlines))
                            accumulator = rhs
                        }
                    }
                }
                if !accumulator.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    merged.append(accumulator.trimmingCharacters(in: .whitespacesAndNewlines))
                }
                nextPass.append(contentsOf: merged)
            }
            currentSegments = nextPass
        }

        return currentSegments.filter { !$0.isEmpty }
    }

    private static func splitCaseInsensitive(_ text: String, separator: String) -> [String] {
        var result: [String] = []
        var searchStart = text.startIndex
        while let range = text.range(of: separator, options: [.caseInsensitive], range: searchStart..<text.endIndex) {
            result.append(String(text[searchStart..<range.lowerBound]))
            searchStart = range.upperBound
        }
        result.append(String(text[searchStart..<text.endIndex]))
        return result
    }

    private static func startsWithQuantityIndicator(_ phrase: String) -> Bool {
        let trimmed = phrase.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let firstChar = trimmed.first else { return false }
        if firstChar.isNumber || firstChar == "." { return true }
        let firstWord = String(trimmed.prefix { $0.isLetter })
        return numberWords[firstWord] != nil
    }

    // MARK: - 2. Quantity, Fraction & Unit Extraction

    private static func extractQuantityUnitAndFood(from rawSegment: String) -> ExtractedQuantityAndFood? {
        // Separate glued number+unit tokens like "200g", "6oz", "1.5cups", "250ml"
        let separated = separateGluedNumbersAndLetters(rawSegment)
        var tokens = separated
            .split(whereSeparator: \.isWhitespace)
            .map { String($0).trimmingCharacters(in: CharacterSet(charactersIn: "()[]{}:-")) }
            .filter { !$0.isEmpty }

        // Strip conversational prefixes ("i had", "i ate", "for breakfast", "had")
        let conversationalPrefixes: [[String]] = [
            ["i", "had"], ["i", "ate"], ["just", "had"], ["just", "ate"],
            ["had"], ["ate"], ["logged"], ["log"]
        ]
        for pref in conversationalPrefixes {
            if tokens.count > pref.count && tokens.prefix(pref.count).map({ $0.lowercased() }) == pref {
                tokens.removeFirst(pref.count)
                break
            }
        }
        guard !tokens.isEmpty else { return nil }

        // Parse leading quantity (supports "2", "1.5", "1/2", "1 1/2", "two", "half a", "a")
        var idx = 0
        var quantity = 1.0
        var hadExplicitQuantity = false

        if let firstNum = parseNumericOrFractionToken(tokens[idx]) {
            quantity = firstNum
            hadExplicitQuantity = true
            idx += 1
            // Check mixed fraction e.g. "1 1/2"
            if idx < tokens.count, tokens[idx].contains("/"), let frac = parseFractionOnly(tokens[idx]) {
                quantity += frac
                idx += 1
            }
        } else if let wordVal = numberWords[tokens[idx].lowercased()] {
            quantity = wordVal
            hadExplicitQuantity = true
            idx += 1
            // Handle "half a" / "half an" / "couple of"
            if idx < tokens.count {
                let nextLower = tokens[idx].lowercased()
                if nextLower == "a" || nextLower == "an" || nextLower == "of" {
                    idx += 1
                }
            }
        }

        // Skip multiplier symbols like "x" or "×" ("2 x 100g" or "2x scoop")
        if idx < tokens.count && (tokens[idx].lowercased() == "x" || tokens[idx] == "×") {
            idx += 1
        }

        // Parse unit if present at current position
        var unitKind: ParsedUnitKind = .countImplicit
        if idx < tokens.count {
            let twoWordUnit: String? = (idx + 1 < tokens.count)
                ? "\(tokens[idx].lowercased()) \(tokens[idx + 1].lowercased())"
                : nil

            if let two = twoWordUnit, let matchedTwo = classifyUnit(two) {
                // Only consume unit if at least 1 food token remains after it!
                if idx + 2 < tokens.count {
                    unitKind = matchedTwo
                    idx += 2
                }
            } else if let matchedOne = classifyUnit(tokens[idx].lowercased()) {
                if idx + 1 < tokens.count {
                    unitKind = matchedOne
                    idx += 1
                }
            }
        }

        // Strip leading "of" / "a" / "an" before the food name (e.g. "200 g of grilled chicken")
        while idx < tokens.count {
            let w = tokens[idx].lowercased()
            if w == "of" || w == "a" || w == "an" || w == "the" {
                idx += 1
            } else {
                break
            }
        }

        guard idx < tokens.count else { return nil }
        let rawFoodPhrase = tokens[idx...].joined(separator: " ")
        let cleaned = normalizeFoodPhrase(rawFoodPhrase)
        guard !cleaned.isEmpty else { return nil }

        return ExtractedQuantityAndFood(
            rawSegment: rawSegment,
            quantity: max(0.05, quantity),
            hadExplicitQuantity: hadExplicitQuantity,
            unitKind: unitKind,
            cleanedFoodQuery: cleaned
        )
    }

    private static func separateGluedNumbersAndLetters(_ input: String) -> String {
        let chars = Array(input)
        var out = ""
        out.reserveCapacity(chars.count + 8)
        for i in chars.indices {
            let c = chars[i]
            out.append(c)
            if i + 1 < chars.count {
                let next = chars[i + 1]
                let cIsNum = c.isNumber
                let nextIsLetter = next.isLetter
                if cIsNum && nextIsLetter {
                    out.append(" ")
                }
            }
        }
        return out
    }

    private static func parseNumericOrFractionToken(_ token: String) -> Double? {
        if token.contains("/") {
            return parseFractionOnly(token)
        }
        return Double(token)
    }

    private static func parseFractionOnly(_ token: String) -> Double? {
        let parts = token.split(separator: "/")
        guard parts.count == 2,
              let num = Double(parts[0]),
              let den = Double(parts[1]),
              den > 0 else {
            return nil
        }
        return num / den
    }

    private static func classifyUnit(_ unit: String) -> ParsedUnitKind? {
        switch unit {
        case "g", "gram", "grams", "gm", "gms":
            return .exactGrams(perUnitGrams: 1.0, unitSymbol: "g")
        case "kg", "kilogram", "kilograms", "kilo", "kilos":
            return .exactGrams(perUnitGrams: 1000.0, unitSymbol: "kg")
        case "oz", "ounce", "ounces":
            return .exactGrams(perUnitGrams: UnitsFormatter.gramsPerOunce, unitSymbol: "oz")
        case "lb", "lbs", "pound", "pounds":
            return .exactGrams(perUnitGrams: 453.59237, unitSymbol: "lb")
        case "ml", "milliliter", "milliliters", "mL":
            return .exactGrams(perUnitGrams: 1.0, unitSymbol: "ml")
        case "fl oz", "fluid ounce", "fluid ounces":
            return .exactGrams(perUnitGrams: 29.5735, unitSymbol: "fl oz")
        case "l", "liter", "liters":
            return .exactGrams(perUnitGrams: 1000.0, unitSymbol: "L")
        case "cup", "cups", "c":
            return .householdUnit(canonicalToken: "cup", fallbackGrams: 160.0, displayUnit: "cup")
        case "tbsp", "tbs", "tablespoon", "tablespoons":
            return .householdUnit(canonicalToken: "tbsp", fallbackGrams: 15.0, displayUnit: "tbsp")
        case "tsp", "teaspoon", "teaspoons":
            return .householdUnit(canonicalToken: "tsp", fallbackGrams: 5.0, displayUnit: "tsp")
        case "slice", "slices":
            return .householdUnit(canonicalToken: "slice", fallbackGrams: 32.0, displayUnit: "slice")
        case "scoop", "scoops":
            return .householdUnit(canonicalToken: "scoop", fallbackGrams: 32.0, displayUnit: "scoop")
        case "piece", "pieces", "pc", "pcs":
            return .householdUnit(canonicalToken: "piece", fallbackGrams: 50.0, displayUnit: "piece")
        case "bar", "bars":
            return .householdUnit(canonicalToken: "bar", fallbackGrams: 60.0, displayUnit: "bar")
        case "breast", "breasts":
            return .householdUnit(canonicalToken: "breast", fallbackGrams: 170.0, displayUnit: "breast")
        case "thigh", "thighs":
            return .householdUnit(canonicalToken: "thigh", fallbackGrams: 90.0, displayUnit: "thigh")
        case "fillet", "fillets", "filet", "filets":
            return .householdUnit(canonicalToken: "fillet", fallbackGrams: 154.0, displayUnit: "fillet")
        case "strip", "strips":
            return .householdUnit(canonicalToken: "strip", fallbackGrams: 12.0, displayUnit: "strip")
        case "patty", "patties":
            return .householdUnit(canonicalToken: "patty", fallbackGrams: 113.0, displayUnit: "patty")
        case "bowl", "bowls":
            return .householdUnit(canonicalToken: "bowl", fallbackGrams: 250.0, displayUnit: "bowl")
        case "can", "cans":
            return .householdUnit(canonicalToken: "can", fallbackGrams: 140.0, displayUnit: "can")
        case "serving", "servings":
            return .householdUnit(canonicalToken: "serving", fallbackGrams: 100.0, displayUnit: "serving")
        case "small":
            return .sizeDescriptor(sizeWord: "small")
        case "medium", "med":
            return .sizeDescriptor(sizeWord: "medium")
        case "large", "lg":
            return .sizeDescriptor(sizeWord: "large")
        default:
            return nil
        }
    }

    private static func normalizeFoodPhrase(_ raw: String) -> String {
        let fillerWords: Set<String> = ["fresh", "some", "my", "about", "approx", "around"]
        let words = raw
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .filter { !fillerWords.contains($0) }
        return words.joined(separator: " ")
    }

    // MARK: - 3. Catalog + History Matching & Portion Resolution

    private static func resolveItem(
        _ item: ExtractedQuantityAndFood,
        persistedFoods: [PersistedFoodMatcherItem],
        offlineCatalog: OfflineUSDACatalogIndex
    ) -> ParsedMealDraftItem? {
        let persistedCandidates = persistedFoods.map { pf in
            RankableFoodCandidate(
                id: pf.id,
                sourceID: pf.sourceID,
                name: pf.name,
                brand: pf.brand,
                source: pf.source,
                isBundledGeneric: false,
                isFavorite: pf.isFavorite,
                useCount: pf.useCount,
                lastUsed: pf.lastUsed,
                nutrientsPer100g: pf.nutrientsPer100g
            )
        }
        let persistedByID = Dictionary(persistedFoods.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        // Try direct query, then alias-expanded query, then relaxed token subset if cooking adjective prevented match
        let queryVariants = buildQueryVariants(for: item.cleanedFoodQuery)
        var bestCandidate: RankableFoodCandidate? = nil

        for qVariant in queryVariants {
            let ranked = FoodSearchRanker.rankWithOfflineCatalog(
                persistedCandidates: persistedCandidates,
                offlineCatalog: offlineCatalog,
                query: qVariant,
                limit: 5
            )
            if let top = ranked.first {
                bestCandidate = top
                break
            }
        }

        // Final fallback 1: drop non-noun cooking modifiers ("grilled", "steamed", "pan", "seared", "baked")
        if bestCandidate == nil {
            let cookingAdjectives: Set<String> = [
                "grilled", "baked", "steamed", "roasted", "fried", "boiled", "poached",
                "pan", "seared", "air", "sauteed", "lightly", "organic", "homemade"
            ]
            let coreTokens = FoodSearchTokenizer.tokenize(item.cleanedFoodQuery)
                .filter { !cookingAdjectives.contains($0) }
            if !coreTokens.isEmpty {
                let fallbackQuery = coreTokens.joined(separator: " ")
                bestCandidate = FoodSearchRanker.rankWithOfflineCatalog(
                    persistedCandidates: persistedCandidates,
                    offlineCatalog: offlineCatalog,
                    query: fallbackQuery,
                    limit: 5
                ).first
            }
        }

        // Final fallback 2: Apple NaturalLanguage on-device semantic embedding vector distance
        if bestCandidate == nil {
            bestCandidate = findSemanticEmbeddingCandidate(
                query: item.cleanedFoodQuery,
                persistedCandidates: persistedCandidates,
                offlineCatalog: offlineCatalog
            )
        }

        guard let winner = bestCandidate else {
            return nil
        }

        if let userFood = persistedByID[winner.id] {
            let (grams, label) = computePortion(
                quantity: item.quantity,
                hadExplicitQuantity: item.hadExplicitQuantity,
                unitKind: item.unitKind,
                servings: userFood.servingSizes,
                rememberedGrams: userFood.useCount > 0 ? userFood.lastLoggedGrams : nil,
                rememberedLabel: userFood.useCount > 0 ? userFood.lastLoggedServingLabel : nil,
                foodName: userFood.name
            )
            let badge = userFood.useCount > 0 ? "Your History" : userFood.source.shortBadge
            return ParsedMealDraftItem(
                rawSegment: item.rawSegment,
                foodName: userFood.name,
                brand: userFood.brand,
                quantity: item.quantity,
                servingLabel: label,
                grams: grams,
                nutrientsPer100g: userFood.nutrientsPer100g,
                source: userFood.source,
                matchedPersistedFoodID: userFood.id,
                matchedOfflineUSDASourceID: userFood.sourceID,
                matchOriginBadge: badge
            )
        } else if let sid = winner.sourceID, let offlineEntry = offlineCatalog.entry(forSourceID: sid) {
            let (grams, label) = computePortion(
                quantity: item.quantity,
                hadExplicitQuantity: item.hadExplicitQuantity,
                unitKind: item.unitKind,
                servings: offlineEntry.servingSizes,
                rememberedGrams: nil,
                rememberedLabel: nil,
                foodName: offlineEntry.name
            )
            return ParsedMealDraftItem(
                rawSegment: item.rawSegment,
                foodName: offlineEntry.name,
                brand: offlineEntry.brand,
                quantity: item.quantity,
                servingLabel: label,
                grams: grams,
                nutrientsPer100g: offlineEntry.nutrientsPer100g,
                source: .usda,
                matchedPersistedFoodID: nil,
                matchedOfflineUSDASourceID: offlineEntry.sourceID,
                matchOriginBadge: "USDA Offline"
            )
        }

        return nil
    }

    private static func buildQueryVariants(for query: String) -> [String] {
        var variants: [String] = [query]
        let lower = query.lowercased()
        for (pattern, replacement) in phraseAliases {
            if lower == pattern {
                variants.insert(replacement, at: 0)
            } else if lower.contains(pattern) {
                let swapped = lower.replacingOccurrences(of: pattern, with: replacement)
                if !variants.contains(swapped) {
                    variants.append(swapped)
                }
            }
        }
        return variants
    }

    private static func computePortion(
        quantity: Double,
        hadExplicitQuantity: Bool,
        unitKind: ParsedUnitKind,
        servings: [ServingSize],
        rememberedGrams: Double?,
        rememberedLabel: String?,
        foodName: String
    ) -> (grams: Double, servingLabel: String) {
        let cleanQty = InlineQuantityCalculator.formatClean(quantity)

        switch unitKind {
        case .exactGrams(let perUnit, let symbol):
            let totalGrams = max(0.5, quantity * perUnit)
            if symbol == "g" {
                return (totalGrams, "\(Int(totalGrams.rounded())) g")
            } else {
                return (totalGrams, "\(cleanQty) \(symbol) (\(Int(totalGrams.rounded()))g)")
            }

        case .householdUnit(let canonicalToken, let fallbackGrams, let displayUnit):
            if let matched = matchServing(token: canonicalToken, in: servings) {
                let unitGrams = normalizedSingleUnitGrams(from: matched)
                let totalGrams = max(0.5, quantity * unitGrams)
                return (totalGrams, "\(cleanQty) × \(matched.label)")
            }
            let adjustedFallback = smartHouseholdFallbackGrams(unit: canonicalToken, defaultGrams: fallbackGrams, foodName: foodName)
            let totalGrams = max(0.5, quantity * adjustedFallback)
            return (totalGrams, "\(cleanQty) \(displayUnit) (\(Int(totalGrams.rounded()))g)")

        case .sizeDescriptor(let sizeWord):
            if let matched = matchServing(token: sizeWord, in: servings) {
                let unitGrams = normalizedSingleUnitGrams(from: matched)
                let totalGrams = max(0.5, quantity * unitGrams)
                return (totalGrams, "\(cleanQty) × \(matched.label)")
            }
            // Fall through to count serving on the food
            if let countServing = firstCountServing(in: servings) {
                let sizeScale = (sizeWord == "small" ? 0.8 : (sizeWord == "large" ? 1.2 : 1.0))
                let totalGrams = max(0.5, quantity * countServing.grams * sizeScale)
                return (totalGrams, "\(cleanQty) \(sizeWord) (\(Int(totalGrams.rounded()))g)")
            }
            return (max(0.5, quantity * 100.0), "\(cleanQty) × 100 g")

        case .countImplicit:
            if !hadExplicitQuantity, let remG = rememberedGrams, let remLbl = rememberedLabel {
                return (remG, remLbl)
            }
            if let countServing = firstCountServing(in: servings) {
                let unitGrams = normalizedSingleUnitGrams(from: countServing)
                let totalGrams = max(0.5, quantity * unitGrams)
                return (totalGrams, "\(cleanQty) × \(countServing.label)")
            }
            if let firstHousehold = servings.first(where: { $0.label != "100 g" }) {
                let totalGrams = max(0.5, quantity * firstHousehold.grams)
                return (totalGrams, "\(cleanQty) × \(firstHousehold.label)")
            }
            return (max(0.5, quantity * 100.0), "\(Int((quantity * 100.0).rounded())) g")
        }
    }

    private static func matchServing(token: String, in servings: [ServingSize]) -> ServingSize? {
        let synonyms: [String: [String]] = [
            "tbsp": ["tbsp", "tablespoon", "tbs"],
            "tsp": ["tsp", "teaspoon"],
            "cup": ["cup", "cups"],
            "slice": ["slice", "slices"],
            "scoop": ["scoop"],
            "breast": ["breast"],
            "thigh": ["thigh"],
            "fillet": ["fillet", "filet"],
            "strip": ["strip", "slice"],
            "patty": ["patty"],
            "bar": ["bar"],
            "can": ["can"],
            "small": ["small"],
            "medium": ["medium"],
            "large": ["large"]
        ]
        let needles = synonyms[token] ?? [token]
        return servings.first { s in
            let lower = s.label.lowercased()
            return needles.contains { lower.contains($0) }
        }
    }

    private static func firstCountServing(in servings: [ServingSize]) -> ServingSize? {
        let massVolumeWords = ["100 g", " oz", "cup", "tbsp", "tablespoon", "tsp", "teaspoon", "ml", "gram"]
        return servings.first { s in
            let lower = s.label.lowercased()
            return !massVolumeWords.contains { lower.contains($0) }
        }
    }

    /// If a USDA serving label starts with a multiple like `"2 tbsp (34g)"` and the user asked for `"1 tbsp"`,
    /// normalize by the leading multiplier so `"1 tbsp"` resolves to `17g` instead of `34g`!
    private static func normalizedSingleUnitGrams(from serving: ServingSize) -> Double {
        let firstToken = serving.label.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? ""
        if let leadingMult = Double(firstToken), leadingMult > 1.01, leadingMult <= 12 {
            // Do not divide when label is "4 oz (113g)" or "100 g"
            let lower = serving.label.lowercased()
            if !lower.contains(" oz") && !lower.hasSuffix(" g") {
                return serving.grams / leadingMult
            }
        }
        return serving.grams
    }

    private static func smartHouseholdFallbackGrams(unit: String, defaultGrams: Double, foodName: String) -> Double {
        let lower = foodName.lowercased()
        if unit == "cup" {
            if lower.contains("oat") { return 80.0 }
            if lower.contains("milk") || lower.contains("yogurt") || lower.contains("juice") { return 240.0 }
            if lower.contains("spinach") || lower.contains("lettuce") || lower.contains("greens") { return 30.0 }
            if lower.contains("rice") || lower.contains("quinoa") || lower.contains("pasta") { return 158.0 }
            if lower.contains("berries") || lower.contains("blueberry") || lower.contains("strawberry") { return 148.0 }
        }
        if unit == "tbsp" {
            if lower.contains("oil") || lower.contains("butter") { return 14.0 }
            if lower.contains("peanut") || lower.contains("almond") { return 16.0 }
            if lower.contains("honey") || lower.contains("syrup") { return 21.0 }
        }
        return defaultGrams
    }

    // MARK: - 4. Apple NaturalLanguage Semantic Matching & Calorie Helpers

    #if canImport(NaturalLanguage)
    private static let semanticEmbedding = NLEmbedding.wordEmbedding(for: .english)
    #endif

    /// High-signal semantic mappings for slang or colloquial food terms on Apple Neural Engine.
    private static let semanticFoodAnchors: [String: String] = [
        "poultry": "chicken breast cooked",
        "fowl": "chicken breast cooked",
        "hen": "chicken breast cooked",
        "flapjack": "pancake",
        "flapjacks": "pancake",
        "hotcake": "pancake",
        "hotcakes": "pancake",
        "tater": "baked potato",
        "taters": "baked potato",
        "spud": "baked potato",
        "spuds": "baked potato",
        "espresso": "black coffee",
        "cappuccino": "coffee",
        "latte": "milk whole",
        "cuppa": "black coffee",
        "greens": "garden salad",
        "veggies": "broccoli cooked",
        "franks": "pork sausage",
        "frank": "pork sausage",
        "frankfurter": "pork sausage",
        "patty": "hamburger",
        "cheeseburger": "cheeseburger",
        "fudge": "chocolate candy",
        "bready": "bread"
    ]

    private static func findSemanticEmbeddingCandidate(
        query: String,
        persistedCandidates: [RankableFoodCandidate],
        offlineCatalog: OfflineUSDACatalogIndex
    ) -> RankableFoodCandidate? {
        let tokens = FoodSearchTokenizer.tokenize(query)

        for token in tokens {
            // 1. Direct semantic anchor lookup
            if let mapped = semanticFoodAnchors[token] {
                let ranked = FoodSearchRanker.rankWithOfflineCatalog(
                    persistedCandidates: persistedCandidates,
                    offlineCatalog: offlineCatalog,
                    query: mapped,
                    limit: 1
                )
                if let hit = ranked.first { return hit }
            }

            // 2. Apple Neural Engine word vector neighbor similarity
            #if canImport(NaturalLanguage)
            if let emb = semanticEmbedding {
                let neighbors = emb.neighbors(for: token, maximumCount: 4)
                for (neighbor, distance) in neighbors where distance < 0.85 {
                    let ranked = FoodSearchRanker.rankWithOfflineCatalog(
                        persistedCandidates: persistedCandidates,
                        offlineCatalog: offlineCatalog,
                        query: neighbor,
                        limit: 1
                    )
                    if let hit = ranked.first { return hit }
                }
            }
            #endif
        }
        return nil
    }

    /// Extracts an explicit calorie number if the user spoke calories directly (e.g. "450 calories" or "300 kcal").
    public static func extractExplicitCalorieNumber(from text: String) -> Double? {
        let pattern = #"(\d+(?:\.\d+)?)\s*(?:cal|cals|calorie|calories|kcal|kcals)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        if let match = regex.firstMatch(in: text, options: [], range: range),
           let numRange = Range(match.range(at: 1), in: text),
           let val = Double(text[numRange]) {
            return val
        }
        return nil
    }
}
