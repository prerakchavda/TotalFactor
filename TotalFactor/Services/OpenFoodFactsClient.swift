import Foundation
import SwiftData

/// Client for Open Food Facts (`https://world.openfoodfacts.org`).
/// Data licensed under Open Database License (ODbL) — attributed in UI & Settings per spec §4.
public struct OpenFoodFactsClient: Sendable {
    private static let userAgent = "TotalFactor/1.0 (iOS; Adaptive Nutrition + Strength Training; ODbL)"

    public init() {}

    public func lookupBarcode(_ barcode: String) async throws -> RemoteFoodDTO? {
        let digits = barcode.filter(\.isNumber)
        guard !digits.isEmpty,
              let url = URL(string: "https://world.openfoodfacts.org/api/v2/product/\(digits).json") else {
            return nil
        }

        var req = URLRequest(url: url)
        req.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 7.0

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            return nil
        }

        let decoded = try JSONDecoder().decode(OFFProductLookupResponse.self, from: data)
        guard decoded.status == 1, let product = decoded.product else { return nil }
        return mapProduct(product, fallbackBarcode: digits)
    }

    public func searchFoods(query: String, pageSize: Int = 15) async throws -> [RemoteFoodDTO] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var comps = URLComponents(string: "https://world.openfoodfacts.org/cgi/search.pl")!
        comps.queryItems = [
            URLQueryItem(name: "search_terms", value: trimmed),
            URLQueryItem(name: "search_simple", value: "1"),
            URLQueryItem(name: "action", value: "process"),
            URLQueryItem(name: "json", value: "1"),
            URLQueryItem(name: "page_size", value: String(pageSize))
        ]
        guard let url = comps.url else { return [] }

        var req = URLRequest(url: url)
        req.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 8.0

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            return []
        }

        let decoded = try JSONDecoder().decode(OFFSearchResponse.self, from: data)
        return (decoded.products ?? []).compactMap { mapProduct($0, fallbackBarcode: $0.code) }
    }

    private func mapProduct(_ product: OFFProduct, fallbackBarcode: String?) -> RemoteFoodDTO? {
        let name = (product.product_name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let n = product.nutriments else { return nil }

        let kcal = n.energyKcal100g ?? ((n.energyKj100g ?? 0) / 4.184)
        let protein = n.proteins100g ?? 0
        let carbs = n.carbohydrates100g ?? 0
        let fat = n.fat100g ?? 0
        let fiber = n.fiber100g ?? 0
        let sugar = n.sugars100g ?? 0
        // Note: OFF `sodium_100g` is reported in GRAMS per 100g; convert to mg (* 1000).
        let sodiumMg: Double = {
            if let naG = n.sodium100g { return naG * 1000.0 }
            if let saltG = n.salt100g { return (saltG / 2.5) * 1000.0 }
            return 0
        }()

        var micros: [String: Double] = [:]
        if let sat = n.saturatedFat100g { micros[MicronutrientKey.saturatedFatG.rawValue] = sat }
        if let kG = n.potassium100g { micros[MicronutrientKey.potassiumMg.rawValue] = kG * 1000.0 }
        if let caG = n.calcium100g { micros[MicronutrientKey.calciumMg.rawValue] = caG * 1000.0 }
        if let feG = n.iron100g { micros[MicronutrientKey.ironMg.rawValue] = feG * 1000.0 }

        var servings: [ServingSize] = []
        if let sQty = product.serving_quantity?.doubleValue, sQty > 0 {
            let lbl = product.serving_size?.trimmingCharacters(in: .whitespacesAndNewlines)
            servings.append(ServingSize(label: (lbl?.isEmpty == false) ? lbl! : "1 serving (\(Int(sQty.rounded()))g)", grams: sQty))
        }
        servings.append(ServingSize(label: "100 g", grams: 100.0))

        let code = product.code ?? fallbackBarcode ?? UUID().uuidString
        return RemoteFoodDTO(
            name: name,
            brand: product.brands,
            barcode: product.code ?? fallbackBarcode,
            source: .off,
            sourceID: code,
            servingSizes: servings,
            nutrientsPer100g: NutrientsPer100g(
                calories: kcal,
                protein: protein,
                carbs: carbs,
                fat: fat,
                fiber: fiber,
                sugar: sugar,
                sodiumMg: sodiumMg,
                micronutrients: micros
            )
        )
    }
}

/// Implements exact Spec §4 Barcode Lookup Cascade:
/// 1. Check local SwiftData cache
/// 2. Miss -> Open Food Facts
/// 3. Miss -> USDA Branded by `gtinUpc`
/// 4. Miss -> `.notFound` (UI opens Label Scanner with barcode pre-filled)
public enum BarcodeLookupOutcome {
    case found(Food)
    case notFound(barcode: String)
}

public enum BarcodeLookupCoordinator {
    @MainActor
    public static func resolve(
        barcode: String,
        usdaApiKey: String,
        context: ModelContext
    ) async -> BarcodeLookupOutcome {
        let cleaned = barcode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return .notFound(barcode: barcode) }

        // 1. Local cache check
        let allCached = (try? context.fetch(FetchDescriptor<Food>())) ?? []
        if let hit = allCached.first(where: { $0.barcode == cleaned }) {
            return .found(hit)
        }

        // 2. Open Food Facts
        let offClient = OpenFoodFactsClient()
        if let offDTO = try? await offClient.lookupBarcode(cleaned) {
            let cachedFood = persistRemoteDTO(offDTO, into: context)
            return .found(cachedFood)
        }

        // 3. USDA Branded by gtinUpc
        let usdaClient = USDAFoodClient(apiKey: usdaApiKey)
        if let usdaDTO = try? await usdaClient.lookupBarcode(cleaned) {
            let cachedFood = persistRemoteDTO(usdaDTO, into: context)
            return .found(cachedFood)
        }

        // 4. Miss -> Label scanner flow
        return .notFound(barcode: cleaned)
    }

    @MainActor
    public static func persistRemoteDTO(_ dto: RemoteFoodDTO, into context: ModelContext) -> Food {
        let existing = (try? context.fetch(FetchDescriptor<Food>())) ?? []
        if let match = existing.first(where: { $0.sourceRaw == dto.source.rawValue && $0.sourceID == dto.sourceID }) {
            return match
        }
        let food = Food(
            name: dto.name,
            brand: dto.brand,
            barcode: dto.barcode,
            source: dto.source,
            sourceID: dto.sourceID,
            isBundledGeneric: false,
            servingSizes: dto.servingSizes,
            nutrientsPer100g: dto.nutrientsPer100g
        )
        context.insert(food)
        try? context.save()
        return food
    }
}

// MARK: - OFF Codable Payloads (handles string-or-number fields cleanly)

private struct OFFProductLookupResponse: Decodable {
    var status: Int?
    var product: OFFProduct?
}

private struct OFFSearchResponse: Decodable {
    var products: [OFFProduct]?
}

private struct OFFProduct: Decodable {
    var code: String?
    var product_name: String?
    var brands: String?
    var serving_size: String?
    var serving_quantity: FlexibleDouble?
    var nutriments: OFFNutriments?
}

private struct OFFNutriments: Decodable {
    var energyKcal100g: Double?
    var energyKj100g: Double?
    var proteins100g: Double?
    var carbohydrates100g: Double?
    var fat100g: Double?
    var saturatedFat100g: Double?
    var fiber100g: Double?
    var sugars100g: Double?
    var sodium100g: Double?
    var salt100g: Double?
    var potassium100g: Double?
    var calcium100g: Double?
    var iron100g: Double?

    enum CodingKeys: String, CodingKey {
        case energyKcal100g = "energy-kcal_100g"
        case energyKj100g = "energy-kj_100g"
        case proteins100g = "proteins_100g"
        case carbohydrates100g = "carbohydrates_100g"
        case fat100g = "fat_100g"
        case saturatedFat100g = "saturated-fat_100g"
        case fiber100g = "fiber_100g"
        case sugars100g = "sugars_100g"
        case sodium100g = "sodium_100g"
        case salt100g = "salt_100g"
        case potassium100g = "potassium_100g"
        case calcium100g = "calcium_100g"
        case iron100g = "iron_100g"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        energyKcal100g = (try? c.decode(FlexibleDouble.self, forKey: .energyKcal100g))?.doubleValue
        energyKj100g = (try? c.decode(FlexibleDouble.self, forKey: .energyKj100g))?.doubleValue
        proteins100g = (try? c.decode(FlexibleDouble.self, forKey: .proteins100g))?.doubleValue
        carbohydrates100g = (try? c.decode(FlexibleDouble.self, forKey: .carbohydrates100g))?.doubleValue
        fat100g = (try? c.decode(FlexibleDouble.self, forKey: .fat100g))?.doubleValue
        saturatedFat100g = (try? c.decode(FlexibleDouble.self, forKey: .saturatedFat100g))?.doubleValue
        fiber100g = (try? c.decode(FlexibleDouble.self, forKey: .fiber100g))?.doubleValue
        sugars100g = (try? c.decode(FlexibleDouble.self, forKey: .sugars100g))?.doubleValue
        sodium100g = (try? c.decode(FlexibleDouble.self, forKey: .sodium100g))?.doubleValue
        salt100g = (try? c.decode(FlexibleDouble.self, forKey: .salt100g))?.doubleValue
        potassium100g = (try? c.decode(FlexibleDouble.self, forKey: .potassium100g))?.doubleValue
        calcium100g = (try? c.decode(FlexibleDouble.self, forKey: .calcium100g))?.doubleValue
        iron100g = (try? c.decode(FlexibleDouble.self, forKey: .iron100g))?.doubleValue
    }
}

private struct FlexibleDouble: Decodable {
    var doubleValue: Double?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let d = try? container.decode(Double.self) {
            doubleValue = d
        } else if let s = try? container.decode(String.self) {
            doubleValue = Double(s.replacingOccurrences(of: ",", with: "."))
        } else {
            doubleValue = nil
        }
    }
}
