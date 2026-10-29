import Foundation

/// Lightweight, value-type representation of one lab-verified USDA whole food from `BundledUSDAFoods.json`.
/// Kept outside SwiftData until first log/favorite/recipe use so `@Query var foods: [Food]` stays near-zero cost for 120Hz scrolling.
public struct OfflineUSDAFoodEntry: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public let sourceID: String
    public let name: String
    public let brand: String
    public let calories: Double
    public let protein: Double
    public let carbs: Double
    public let fat: Double
    public let fiber: Double
    public let sugar: Double
    public let sodiumMg: Double
    public let servingSizes: [ServingSize]
    public let micronutrients: [String: Double]

    private enum CodingKeys: String, CodingKey {
        case sourceID
        case name
        case brand
        case calories
        case protein
        case carbs
        case fat
        case fiber
        case sugar
        case sodiumMg
        case servingSizes
        case micronutrients
    }

    public init(
        sourceID: String,
        name: String,
        brand: String = "USDA Foundation",
        calories: Double,
        protein: Double,
        carbs: Double,
        fat: Double,
        fiber: Double = 0,
        sugar: Double = 0,
        sodiumMg: Double = 0,
        servingSizes: [ServingSize] = [ServingSize(label: "100 g", grams: 100)],
        micronutrients: [String: Double] = [:]
    ) {
        self.id = Self.deterministicUUID(forSourceID: sourceID)
        self.sourceID = sourceID
        self.name = name
        self.brand = brand
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.fiber = fiber
        self.sugar = sugar
        self.sodiumMg = sodiumMg
        self.servingSizes = servingSizes.isEmpty ? [ServingSize(label: "100 g", grams: 100)] : servingSizes
        self.micronutrients = micronutrients
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let sid = try c.decode(String.self, forKey: .sourceID)
        self.id = Self.deterministicUUID(forSourceID: sid)
        self.sourceID = sid
        self.name = try c.decode(String.self, forKey: .name)
        self.brand = (try? c.decode(String.self, forKey: .brand)) ?? "USDA Foundation"
        self.calories = (try? c.decode(Double.self, forKey: .calories)) ?? 0
        self.protein = (try? c.decode(Double.self, forKey: .protein)) ?? 0
        self.carbs = (try? c.decode(Double.self, forKey: .carbs)) ?? 0
        self.fat = (try? c.decode(Double.self, forKey: .fat)) ?? 0
        self.fiber = (try? c.decode(Double.self, forKey: .fiber)) ?? 0
        self.sugar = (try? c.decode(Double.self, forKey: .sugar)) ?? 0
        self.sodiumMg = (try? c.decode(Double.self, forKey: .sodiumMg)) ?? 0
        let decodedServings = (try? c.decode([ServingSize].self, forKey: .servingSizes)) ?? []
        self.servingSizes = decodedServings.isEmpty ? [ServingSize(label: "100 g", grams: 100)] : decodedServings
        self.micronutrients = (try? c.decode([String: Double].self, forKey: .micronutrients)) ?? [:]
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(sourceID, forKey: .sourceID)
        try c.encode(name, forKey: .name)
        try c.encode(brand, forKey: .brand)
        try c.encode(calories, forKey: .calories)
        try c.encode(protein, forKey: .protein)
        try c.encode(carbs, forKey: .carbs)
        try c.encode(fat, forKey: .fat)
        try c.encode(fiber, forKey: .fiber)
        try c.encode(sugar, forKey: .sugar)
        try c.encode(sodiumMg, forKey: .sodiumMg)
        try c.encode(servingSizes, forKey: .servingSizes)
        try c.encode(micronutrients, forKey: .micronutrients)
    }

    public var defaultServing: ServingSize {
        servingSizes.first ?? ServingSize(label: "100 g", grams: 100)
    }

    public var macrosOnlyPer100g: NutrientsPer100g {
        NutrientsPer100g(
            calories: calories,
            protein: protein,
            carbs: carbs,
            fat: fat,
            fiber: fiber,
            sugar: sugar,
            sodiumMg: sodiumMg
        )
    }

    public var nutrientsPer100g: NutrientsPer100g {
        NutrientsPer100g(
            calories: calories,
            protein: protein,
            carbs: carbs,
            fat: fat,
            fiber: fiber,
            sugar: sugar,
            sodiumMg: sodiumMg,
            micronutrients: micronutrients
        )
    }

    public var asRankableCandidate: RankableFoodCandidate {
        RankableFoodCandidate(
            id: id,
            sourceID: sourceID,
            name: name,
            brand: brand,
            source: .usda,
            isBundledGeneric: true,
            isFavorite: false,
            useCount: 0,
            lastUsed: nil,
            typicalHourOfDay: nil,
            nutrientsPer100g: macrosOnlyPer100g
        )
    }

    /// Generates a deterministic UUID (v5-shaped) from `"totalfactor.usda.<sourceID>"` using FNV-1a 128-bit mixing.
    public static func deterministicUUID(forSourceID sourceID: String) -> UUID {
        let seed = "totalfactor.usda.\(sourceID)"
        var h1: UInt64 = 0xcbf29ce484222325
        var h2: UInt64 = 0x84222325cbf29ce4
        for byte in seed.utf8 {
            h1 ^= UInt64(byte)
            h1 &*= 0x100000001b3
            h2 ^= UInt64(byte &+ 0x9e)
            h2 &*= 0x100000001b3
        }
        var bytes: uuid_t = (
            UInt8((h1 >> 56) & 0xff), UInt8((h1 >> 48) & 0xff),
            UInt8((h1 >> 40) & 0xff), UInt8((h1 >> 32) & 0xff),
            UInt8((h1 >> 24) & 0xff), UInt8((h1 >> 16) & 0xff),
            UInt8(((h1 >> 8) & 0x0f) | 0x50), UInt8(h1 & 0xff),
            UInt8(((h2 >> 56) & 0x3f) | 0x80), UInt8((h2 >> 48) & 0xff),
            UInt8((h2 >> 40) & 0xff), UInt8((h2 >> 32) & 0xff),
            UInt8((h2 >> 24) & 0xff), UInt8((h2 >> 16) & 0xff),
            UInt8((h2 >> 8) & 0xff), UInt8(h2 & 0xff)
        )
        return withUnsafePointer(to: &bytes) { ptr in
            UUID(uuid: ptr.pointee)
        }
    }
}

/// Fast, immutable inverted-token + first-character vocabulary index over ~8,156 USDA whole foods.
/// Token intersection runs in < 0.3 ms on Apple Silicon with zero CoreData / SwiftData overhead.
public final class OfflineUSDACatalogIndex: Sendable {
    public static let empty = OfflineUSDACatalogIndex(entries: [])

    public let entries: [OfflineUSDAFoodEntry]
    private let indexByUUID: [UUID: Int]
    private let indexBySourceID: [String: Int]
    private let postingsByToken: [String: [Int]]
    private let vocabByFirstChar: [Character: [String]]

    public var count: Int { entries.count }

    public convenience init(jsonData: Data) throws {
        let decoded = try JSONDecoder().decode([OfflineUSDAFoodEntry].self, from: jsonData)
        self.init(entries: decoded)
    }

    public init(entries: [OfflineUSDAFoodEntry]) {
        self.entries = entries

        var byUUID: [UUID: Int] = [:]
        byUUID.reserveCapacity(entries.count)
        var bySource: [String: Int] = [:]
        bySource.reserveCapacity(entries.count)
        var postings: [String: [Int]] = [:]
        postings.reserveCapacity(4096)

        for (idx, item) in entries.enumerated() {
            byUUID[item.id] = idx
            bySource[item.sourceID] = idx

            let tokens = Self.tokenize("\(item.name) \(item.brand)")
            var seenInDoc = Set<String>()
            for tok in tokens {
                if seenInDoc.insert(tok).inserted {
                    postings[tok, default: []].append(idx)
                }
                let singular = FoodSearchTokenizer.singularize(tok)
                if singular != tok, seenInDoc.insert(singular).inserted {
                    postings[singular, default: []].append(idx)
                }
            }
        }

        var byChar: [Character: [String]] = [:]
        for word in postings.keys {
            if let first = word.first {
                byChar[first, default: []].append(word)
            }
        }

        self.indexByUUID = byUUID
        self.indexBySourceID = bySource
        self.postingsByToken = postings
        self.vocabByFirstChar = byChar
    }

    public func entry(forID id: UUID) -> OfflineUSDAFoodEntry? {
        guard let idx = indexByUUID[id] else { return nil }
        return entries[idx]
    }

    public func entry(forSourceID sourceID: String) -> OfflineUSDAFoodEntry? {
        guard let idx = indexBySourceID[sourceID] else { return nil }
        return entries[idx]
    }

    /// Returns fast pre-filtered candidate entries for `FoodSearchRanker` or `NaturalLanguageMealParser`.
    public func searchCandidates(
        query: String,
        excludingSourceIDs: Set<String> = [],
        limit: Int = 80
    ) -> [OfflineUSDAFoodEntry] {
        let rawTokens = Self.tokenize(query)
        guard !rawTokens.isEmpty else {
            var browse: [OfflineUSDAFoodEntry] = []
            browse.reserveCapacity(min(limit, 40))
            for item in entries {
                if !excludingSourceIDs.contains(item.sourceID) {
                    browse.append(item)
                    if browse.count >= limit { break }
                }
            }
            return browse
        }

        var tokenPostingSets: [[Int]] = []
        tokenPostingSets.reserveCapacity(rawTokens.count)

        for rawTok in rawTokens {
            let matches = matchingDocIndices(forQueryToken: rawTok)
            if matches.isEmpty {
                return []
            }
            tokenPostingSets.append(matches)
        }

        // Intersect from smallest posting list to largest
        tokenPostingSets.sort { $0.count < $1.count }
        var current = tokenPostingSets[0]
        for i in 1..<tokenPostingSets.count {
            current = Self.intersectSorted(current, tokenPostingSets[i])
            if current.isEmpty { return [] }
        }

        // Score matched offline entries quickly so the top `limit` passed to FoodSearchRanker include exact/short names first
        let lowerQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var scored: [(idx: Int, quickScore: Int)] = []
        scored.reserveCapacity(current.count)

        for docIdx in current {
            let entry = entries[docIdx]
            if excludingSourceIDs.contains(entry.sourceID) { continue }
            let lowerName = entry.name.lowercased()
            var s = 0
            // Curated front-of-catalog staple bonus (indices < 80 are curated staple whole foods)
            if docIdx < 85 { s += 220 }
            if entry.brand == "USDA Foundation" { s += 40 }
            if lowerName == lowerQuery {
                s += 500
            } else if lowerName.hasPrefix(lowerQuery) {
                s += 260
            } else if let firstTok = rawTokens.first, lowerName.hasPrefix(firstTok) {
                s += 140
            }
            // Prefer concise canonical whole-food descriptions over obscure sub-preparations
            s -= min(entry.name.count, 120)
            scored.append((docIdx, s))
        }

        scored.sort {
            if $0.quickScore != $1.quickScore { return $0.quickScore > $1.quickScore }
            return $0.idx < $1.idx
        }

        return scored.prefix(limit).map { entries[$0.idx] }
    }

    private func matchingDocIndices(forQueryToken token: String) -> [Int] {
        let normalized = FoodSearchTokenizer.singularize(token)
        var unionLists: [[Int]] = []

        if let exact = postingsByToken[token] {
            unionLists.append(exact)
        }
        if normalized != token, let sing = postingsByToken[normalized] {
            unionLists.append(sing)
        }

        if let first = token.first, let bucket = vocabByFirstChar[first] {
            for word in bucket where word != token && word != normalized {
                if word.hasPrefix(token) || (normalized.count >= 3 && word.hasPrefix(normalized)) {
                    if let list = postingsByToken[word] {
                        unionLists.append(list)
                    }
                }
            }
        }

        if unionLists.isEmpty { return [] }
        if unionLists.count == 1 { return unionLists[0] }

        var combined = Set<Int>()
        for l in unionLists {
            combined.formUnion(l)
        }
        return combined.sorted()
    }

    private static func intersectSorted(_ a: [Int], _ b: [Int]) -> [Int] {
        var i = 0
        var j = 0
        var out: [Int] = []
        out.reserveCapacity(min(a.count, b.count))
        while i < a.count && j < b.count {
            let va = a[i]
            let vb = b[j]
            if va == vb {
                out.append(va)
                i += 1
                j += 1
            } else if va < vb {
                i += 1
            } else {
                j += 1
            }
        }
        return out
    }

    public static func tokenize(_ text: String) -> [String] {
        FoodSearchTokenizer.tokenize(text)
    }
}

public enum FoodSearchTokenizer {
    public static func tokenize(_ text: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        for scalar in text.lowercased().unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                current.unicodeScalars.append(scalar)
            } else if !current.isEmpty {
                tokens.append(current)
                current = ""
            }
        }
        if !current.isEmpty {
            tokens.append(current)
        }
        return tokens
    }

    /// Lightweight deterministic English food singularizer (e.g. "eggs" -> "egg", "berries" -> "berry", "tomatoes" -> "tomato").
    public static func singularize(_ word: String) -> String {
        guard word.count >= 4 else { return word }
        let keepAsIs: Set<String> = [
            "swiss", "grass", "hummus", "couscous", "asparagus", "molasses", "citrus", "lentils", "grits", "oats"
        ]
        if keepAsIs.contains(word) {
            return word == "oats" ? "oat" : (word == "lentils" ? "lentil" : word)
        }
        if word.hasSuffix("ies") && word.count >= 5 {
            return String(word.dropLast(3)) + "y"
        }
        if (word.hasSuffix("oes") || word.hasSuffix("ches") || word.hasSuffix("shes") || word.hasSuffix("xes")) && word.count >= 5 {
            return String(word.dropLast(2))
        }
        if word.hasSuffix("s") && !word.hasSuffix("ss") && !word.hasSuffix("us") && !word.hasSuffix("is") {
            return String(word.dropLast())
        }
        return word
    }
}
