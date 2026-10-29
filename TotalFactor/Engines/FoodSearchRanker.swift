import Foundation

public struct RankableFoodCandidate: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var sourceID: String?
    public var name: String
    public var brand: String?
    public var source: FoodSource
    public var isBundledGeneric: Bool
    public var isFavorite: Bool
    public var useCount: Int
    public var lastUsed: Date?
    public var typicalHourOfDay: Int?
    public var nutrientsPer100g: NutrientsPer100g

    public init(
        id: UUID,
        sourceID: String? = nil,
        name: String,
        brand: String? = nil,
        source: FoodSource,
        isBundledGeneric: Bool = false,
        isFavorite: Bool = false,
        useCount: Int = 0,
        lastUsed: Date? = nil,
        typicalHourOfDay: Int? = nil,
        nutrientsPer100g: NutrientsPer100g
    ) {
        self.id = id
        self.sourceID = sourceID
        self.name = name
        self.brand = brand
        self.source = source
        self.isBundledGeneric = isBundledGeneric
        self.isFavorite = isFavorite
        self.useCount = useCount
        self.lastUsed = lastUsed
        self.typicalHourOfDay = typicalHourOfDay
        self.nutrientsPer100g = nutrientsPer100g
    }
}

public struct FoodQualityCheckResult: Equatable, Sendable {
    public var isFlagged: Bool
    public var listedCalories: Double
    public var impliedAtwaterCalories: Double
    public var relativeError: Double
    public var warningMessage: String?
}

public enum FoodSearchRanker {
    /// Spec §4 Data Quality Check:
    /// Flags any food where `protein*4 + carbs*4 + fat*9` is more than ~15% off from listed calories.
    public static func validateMacroCalorieConsistency(
        nutrients: NutrientsPer100g,
        tolerance: Double = 0.15
    ) -> FoodQualityCheckResult {
        let listed = nutrients.calories
        let implied = nutrients.atwaterCalories

        guard listed > 15 || implied > 15 else {
            return FoodQualityCheckResult(
                isFlagged: false,
                listedCalories: listed,
                impliedAtwaterCalories: implied,
                relativeError: 0,
                warningMessage: nil
            )
        }

        let denominator = max(listed, implied)
        let relError = abs(implied - listed) / denominator
        if relError > tolerance {
            let pct = Int((relError * 100.0).rounded())
            return FoodQualityCheckResult(
                isFlagged: true,
                listedCalories: listed,
                impliedAtwaterCalories: implied,
                relativeError: relError,
                warningMessage: "Macros imply \(Int(implied.rounded())) kcal vs \(Int(listed.rounded())) kcal listed (\(pct)% gap — fiber/sugar alcohols or label error). Use 'Copy to Custom' to edit."
            )
        }

        return FoodQualityCheckResult(
            isFlagged: false,
            listedCalories: listed,
            impliedAtwaterCalories: implied,
            relativeError: relError,
            warningMessage: nil
        )
    }

    /// Spec §4 Search Ranking Order:
    /// 1. Your own history (weighted by useCount + recency + time of day)
    /// 2. Your custom foods and recipes
    /// 3. Bundled USDA generic foods
    /// 4. Online USDA Branded
    /// 5. Online Open Food Facts
    public static func rank(
        candidates: [RankableFoodCandidate],
        query: String,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [RankableFoodCandidate] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let allTokens = FoodSearchTokenizer.tokenize(trimmed)
        let stopwords: Set<String> = ["in", "on", "at", "into", "the", "a", "an", "and", "with", "of", "some", "my"]
        let queryTokens = allTokens.filter { !stopwords.contains($0) }.isEmpty ? allTokens : allTokens.filter { !stopwords.contains($0) }
        let tokenVariants = queryTokens.map { FoodSearchTokenizer.inflectionVariants($0) }
        let currentHour = calendar.component(.hour, from: now)

        var matched = candidates.filter { item in
            guard !queryTokens.isEmpty else { return true }
            let haystack = "\(item.name) \(item.brand ?? "")".lowercased()
            return tokenVariants.allSatisfy { variants in
                variants.contains { haystack.contains($0) }
            }
        }

        // Auxiliary descriptor relaxation fallback
        if matched.isEmpty && queryTokens.count > 1 {
            let auxiliaryDescriptors: Set<String> = [
                "dip", "sauce", "topping", "toppings", "spread", "dressing", "bites", "bite",
                "bar", "bars", "snack", "snacks", "candy", "candies", "piece", "pieces", "cup", "cups"
            ]
            let coreVariants = zip(queryTokens, tokenVariants).compactMap { tok, vars in
                auxiliaryDescriptors.contains(tok) ? nil : vars
            }
            if !coreVariants.isEmpty {
                matched = candidates.filter { item in
                    let haystack = "\(item.name) \(item.brand ?? "")".lowercased()
                    return coreVariants.allSatisfy { vars in
                        vars.contains { haystack.contains($0) }
                    }
                }
            }
        }

        return matched.sorted { lhs, rhs in
            let lScore = score(lhs, query: trimmed, now: now, currentHour: currentHour)
            let rScore = score(rhs, query: trimmed, now: now, currentHour: currentHour)
            if abs(lScore - rScore) > 0.01 {
                return lScore > rScore
            }
            return lhs.name.count < rhs.name.count
        }
    }

    /// Merges materialized SwiftData `Food` candidates with fast-indexed `OfflineUSDACatalogIndex` whole foods,
    /// deduplicating by `sourceID` so logged/favorited USDA items keep their Tier-1 personal history priority.
    public static func rankWithOfflineCatalog(
        persistedCandidates: [RankableFoodCandidate],
        offlineCatalog: OfflineUSDACatalogIndex,
        query: String,
        limit: Int = 50,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [RankableFoodCandidate] {
        let materializedSourceIDs = Set(
            persistedCandidates.compactMap { $0.source == .usda ? $0.sourceID : nil }
        )
        let offlineMatches = offlineCatalog.searchCandidates(
            query: query,
            excludingSourceIDs: materializedSourceIDs,
            limit: max(limit * 2, 80)
        )
        let combined = persistedCandidates + offlineMatches.map(\.asRankableCandidate)
        return Array(rank(candidates: combined, query: query, now: now, calendar: calendar).prefix(limit))
    }

    /// Spec §6 Quick Add: "Usually at this time" suggestions before typing.
    public static func usuallyAtThisTime(
        candidates: [RankableFoodCandidate],
        historicalFoodLogHours: [UUID: [Int]],
        now: Date = .now,
        limit: Int = 8,
        calendar: Calendar = .current
    ) -> [RankableFoodCandidate] {
        let currentHour = calendar.component(.hour, from: now)
        let usedCandidates = candidates.filter { $0.useCount > 0 || $0.isFavorite }

        let scored = usedCandidates.map { candidate -> (RankableFoodCandidate, Double) in
            let hours = historicalFoodLogHours[candidate.id] ?? (candidate.typicalHourOfDay.map { [$0] } ?? [])
            let nearHourHits = hours.filter { circularHourDistance($0, currentHour) <= 2 }.count
            let recencyBonus: Double = {
                guard let last = candidate.lastUsed else { return 0 }
                let daysAgo = max(0, now.timeIntervalSince(last) / 86_400.0)
                return max(0, 30.0 - daysAgo)
            }()
            let total = Double(nearHourHits * 25) + Double(min(candidate.useCount, 40) * 3) + recencyBonus + (candidate.isFavorite ? 20 : 0)
            return (candidate, total)
        }

        return scored
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map(\.0)
    }

    private static func score(
        _ item: RankableFoodCandidate,
        query: String,
        now: Date,
        currentHour: Int
    ) -> Double {
        let tierBase: Double
        if item.useCount > 0 {
            tierBase = 5000 // Tier 1: personal history
        } else if item.source == .custom || item.source == .recipe {
            tierBase = 4000 // Tier 2: custom foods & recipes
        } else if item.source == .usda && item.isBundledGeneric {
            tierBase = 3000 // Tier 3: bundled USDA generic
        } else if item.source == .usda {
            tierBase = 2000 // Tier 4: online USDA branded
        } else {
            tierBase = 1000 // Tier 5: online Open Food Facts
        }

        var bonus = 0.0
        if item.isFavorite { bonus += 180 }
        bonus += Double(min(item.useCount, 100)) * 6.0

        if let last = item.lastUsed {
            let daysAgo = max(0, now.timeIntervalSince(last) / 86_400.0)
            bonus += max(0, 120.0 - daysAgo * 4.0)
        }

        if let typicalHour = item.typicalHourOfDay {
            let dist = circularHourDistance(typicalHour, currentHour)
            if dist <= 2 {
                bonus += Double(3 - dist) * 35.0
            }
        }

        if !query.isEmpty {
            let lowerName = item.name.lowercased()
            let cleanName = lowerName.replacingOccurrences(of: ",", with: " ")
            let queryFirst = query.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? query
            let nameFirst = cleanName.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? cleanName

            if lowerName == query || cleanName == query {
                bonus += 300
            } else if lowerName.hasPrefix(query) || cleanName.hasPrefix(query) {
                bonus += 200
            } else if nameFirst == queryFirst || FoodSearchTokenizer.singularize(nameFirst) == FoodSearchTokenizer.singularize(queryFirst) {
                bonus += 150
            }
        }

        return tierBase + bonus
    }

    private static func circularHourDistance(_ h1: Int, _ h2: Int) -> Int {
        let diff = abs(h1 - h2) % 24
        return min(diff, 24 - diff)
    }
}
