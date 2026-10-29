import Foundation
import SwiftData

/// Unified search row wrapping either an already-materialized SwiftData `Food` (user history, favorites, custom, recipe)
/// or a zero-allocation `OfflineUSDAFoodEntry` from the ~8,156-item bundled USDA Foundation + SR Legacy catalog.
public enum CatalogSearchItem: Identifiable {
    case persisted(Food)
    case offlineUSDA(OfflineUSDAFoodEntry)

    public var id: UUID {
        switch self {
        case .persisted(let food): return food.id
        case .offlineUSDA(let entry): return entry.id
        }
    }

    public var name: String {
        switch self {
        case .persisted(let food): return food.name
        case .offlineUSDA(let entry): return entry.name
        }
    }

    public var brand: String? {
        switch self {
        case .persisted(let food): return food.brand
        case .offlineUSDA(let entry): return entry.brand
        }
    }

    public var source: FoodSource {
        switch self {
        case .persisted(let food): return food.source
        case .offlineUSDA: return .usda
        }
    }

    public var isFavorite: Bool {
        switch self {
        case .persisted(let food): return food.isFavorite
        case .offlineUSDA: return false
        }
    }

    public var allowOneTapRepeat: Bool {
        switch self {
        case .persisted(let food): return food.useCount > 0
        case .offlineUSDA: return false
        }
    }

    public var caloriesPer100g: Double {
        switch self {
        case .persisted(let food): return food.caloriesPer100g
        case .offlineUSDA(let entry): return entry.calories
        }
    }

    public var previewServingLabel: String {
        switch self {
        case .persisted(let food): return food.lastLoggedServingLabel
        case .offlineUSDA(let entry): return entry.defaultServing.label
        }
    }

    public var previewNutrients: NutrientsPer100g {
        switch self {
        case .persisted(let food):
            return food.macrosOnlyPer100g.scaled(forGrams: food.lastLoggedGrams)
        case .offlineUSDA(let entry):
            return entry.macrosOnlyPer100g.scaled(forGrams: entry.defaultServing.grams)
        }
    }

    public var servingSizes: [ServingSize] {
        switch self {
        case .persisted(let food): return food.servingSizes
        case .offlineUSDA(let entry): return entry.servingSizes
        }
    }

    public var defaultServing: ServingSize {
        switch self {
        case .persisted(let food):
            return food.servingSizes.first ?? ServingSize(label: "100 g", grams: 100)
        case .offlineUSDA(let entry):
            return entry.defaultServing
        }
    }

    public var nutrientsPer100g: NutrientsPer100g {
        switch self {
        case .persisted(let food): return food.nutrientsPer100g
        case .offlineUSDA(let entry): return entry.nutrientsPer100g
        }
    }
}

/// Manages off-main-thread loading, inverted-token indexing, ranked search, and lazy on-first-use SwiftData materialization
/// of the ~8,156-food USDA Foundation + SR Legacy offline catalog (`BundledUSDAFoods.json`).
public final class OfflineUSDACatalogService: @unchecked Sendable {
    public static let shared = OfflineUSDACatalogService()

    private let lock = NSLock()
    private var _index: OfflineUSDACatalogIndex? = nil
    private var _isPreloading: Bool = false
    private var loadCallbacks: [() -> Void] = []

    public init() {}

    public var isLoaded: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _index != nil
    }

    public var totalCatalogCount: Int {
        index.count
    }

    public var index: OfflineUSDACatalogIndex {
        lock.lock()
        if let existing = _index {
            lock.unlock()
            return existing
        }
        lock.unlock()

        let built = Self.loadFromBundle()
        lock.lock()
        if _index == nil {
            _index = built
        }
        let resolved = _index ?? built
        lock.unlock()
        return resolved
    }

    /// Kicks off non-blocking background JSON decoding + inverted index construction at app launch.
    public func preloadInBackground(onLoaded: (@Sendable @MainActor () -> Void)? = nil) {
        lock.lock()
        if _index != nil {
            lock.unlock()
            if let onLoaded {
                Task { @MainActor in onLoaded() }
            }
            return
        }
        if let onLoaded {
            loadCallbacks.append {
                Task { @MainActor in onLoaded() }
            }
        }
        guard !_isPreloading else {
            lock.unlock()
            return
        }
        _isPreloading = true
        lock.unlock()

        Task.detached(priority: .userInitiated) { [weak self] in
            let built = Self.loadFromBundle()
            guard let self else { return }
            let callbacks = self.finishPreload(with: built)
            for cb in callbacks {
                cb()
            }
        }
    }

    private func finishPreload(with built: OfflineUSDACatalogIndex) -> [() -> Void] {
        lock.lock()
        defer { lock.unlock() }
        if _index == nil {
            _index = built
        }
        _isPreloading = false
        let callbacks = loadCallbacks
        loadCallbacks.removeAll()
        return callbacks
    }

    /// Combines user's SwiftData `Food` rows with the ~8,156-item offline USDA catalog and ranks via `FoodSearchRanker`.
    @MainActor
    public func rankedResults(
        query: String,
        persistedFoods: [Food],
        limit: Int = 50,
        now: Date = .now
    ) -> [CatalogSearchItem] {
        let currentIndex: OfflineUSDACatalogIndex = {
            lock.lock()
            let cached = _index
            lock.unlock()
            if let cached { return cached }
            // If user already started typing before background preload finished, load synchronously once
            if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return index
            }
            return .empty
        }()

        let foodByID = Dictionary(persistedFoods.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let persistedCandidates = persistedFoods.map(\.asRankableCandidate)

        let ranked = FoodSearchRanker.rankWithOfflineCatalog(
            persistedCandidates: persistedCandidates,
            offlineCatalog: currentIndex,
            query: query,
            limit: limit,
            now: now
        )

        return ranked.compactMap { candidate in
            if let existing = foodByID[candidate.id] {
                return .persisted(existing)
            }
            if let sid = candidate.sourceID, let entry = currentIndex.entry(forSourceID: sid) {
                return .offlineUSDA(entry)
            }
            if let entry = currentIndex.entry(forID: candidate.id) {
                return .offlineUSDA(entry)
            }
            return nil
        }
    }

    /// Materializes an `OfflineUSDAFoodEntry` as a persistent SwiftData `Food` `@Model` row on first log, favorite, or recipe use,
    /// deduplicating by `sourceID` so repeat uses always resolve to the same `Food` record.
    @MainActor
    public func materialize(
        _ entry: OfflineUSDAFoodEntry,
        in context: ModelContext,
        markFavorite: Bool = false
    ) -> Food {
        let sid = entry.sourceID
        let usdaRaw = FoodSource.usda.rawValue
        let descriptor = FetchDescriptor<Food>(
            predicate: #Predicate { $0.sourceRaw == usdaRaw && $0.sourceID == sid }
        )
        if let existing = (try? context.fetch(descriptor))?.first {
            if markFavorite && !existing.isFavorite {
                existing.isFavorite = true
                try? context.save()
            }
            return existing
        }

        let food = Food(
            id: entry.id,
            name: entry.name,
            brand: entry.brand,
            barcode: nil,
            source: .usda,
            sourceID: entry.sourceID,
            isBundledGeneric: true,
            servingSizes: entry.servingSizes,
            nutrientsPer100g: entry.nutrientsPer100g,
            isFavorite: markFavorite
        )
        context.insert(food)
        try? context.save()
        return food
    }

    private static func loadFromBundle() -> OfflineUSDACatalogIndex {
        guard let url = Bundle.main.url(forResource: "BundledUSDAFoods", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let parsed = try? OfflineUSDACatalogIndex(jsonData: data) else {
            return .empty
        }
        return parsed
    }
}
