import Foundation

public struct RemoteFoodDTO: Identifiable, Equatable, Sendable {
    public var id: String { "\(source.rawValue)-\(sourceID)" }
    public var name: String
    public var brand: String?
    public var barcode: String?
    public var source: FoodSource
    public var sourceID: String
    public var servingSizes: [ServingSize]
    public var nutrientsPer100g: NutrientsPer100g
}

/// Client for USDA FoodData Central v1 (`https://api.nal.usda.gov/fdc/v1/foods/search`).
public struct USDAFoodClient: Sendable {
    public var apiKey: String

    public init(apiKey: String = "DEMO_KEY") {
        self.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "DEMO_KEY" : apiKey
    }

    public func searchFoods(query: String, pageSize: Int = 20) async throws -> [RemoteFoodDTO] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var comps = URLComponents(string: "https://api.nal.usda.gov/fdc/v1/foods/search")!
        comps.queryItems = [
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "query", value: trimmed),
            URLQueryItem(name: "pageSize", value: String(pageSize)),
            URLQueryItem(name: "dataType", value: "Foundation,SR Legacy,Branded")
        ]
        guard let url = comps.url else { return [] }

        var req = URLRequest(url: url)
        req.timeoutInterval = 8.0
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            return []
        }

        let decoded = try JSONDecoder().decode(USDASearchResponse.self, from: data)
        return decoded.foods.compactMap { mapUSDAFood($0) }
    }

    public func lookupBarcode(_ barcode: String) async throws -> RemoteFoodDTO? {
        let digits = barcode.filter(\.isNumber)
        guard !digits.isEmpty else { return nil }
        let results = try await searchFoods(query: digits, pageSize: 10)
        return results.first { item in
            guard let gtin = item.barcode?.filter(\.isNumber) else { return false }
            return gtin == digits || gtin.hasSuffix(digits) || digits.hasSuffix(gtin)
        }
    }

    private func mapUSDAFood(_ raw: USDAFoodItem) -> RemoteFoodDTO? {
        let title = raw.description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }

        // FDC search returns nutrients per 100g for Foundation/SR Legacy AND per 100g in `foodNutrients` for Branded!
        var kcal = 0.0
        var protein = 0.0
        var carbs = 0.0
        var fat = 0.0
        var fiber = 0.0
        var sugar = 0.0
        var sodiumMg = 0.0
        var micros: [String: Double] = [:]

        for n in raw.foodNutrients ?? [] {
            let num = n.nutrientNumber ?? (n.nutrientId.map(String.init) ?? "")
            let val = n.value ?? 0
            switch num {
            case "208", "1008": kcal = val
            case "957", "958", "2047", "2048":
                if kcal <= 0 { kcal = val }
            case "268", "1062":
                if kcal <= 0 && val > 0 { kcal = val / 4.184 }
            case "203", "1003": protein = val
            case "205", "1005": carbs = val
            case "205.2", "1050":
                if carbs <= 0 { carbs = val }
            case "204", "1004": fat = val
            case "298", "1085":
                if fat <= 0 { fat = val }
            case "291", "1079": fiber = val
            case "293", "2033":
                if fiber <= 0 { fiber = val }
            case "269", "2000": sugar = val
            case "269.3", "1063":
                if sugar <= 0 { sugar = val }
            case "307", "1093": sodiumMg = val
            case "306", "1092": micros[MicronutrientKey.potassiumMg.rawValue] = val
            case "301", "1087": micros[MicronutrientKey.calciumMg.rawValue] = val
            case "303", "1089": micros[MicronutrientKey.ironMg.rawValue] = val
            case "328", "1114": micros[MicronutrientKey.vitaminDMcg.rawValue] = val
            case "401", "1162": micros[MicronutrientKey.vitaminCMg.rawValue] = val
            case "304", "1090": micros[MicronutrientKey.magnesiumMg.rawValue] = val
            case "309", "1095": micros[MicronutrientKey.zincMg.rawValue] = val
            case "601", "1253": micros[MicronutrientKey.cholesterolMg.rawValue] = val
            case "606", "1258": micros[MicronutrientKey.saturatedFatG.rawValue] = val
            default: break
            }
        }
        if kcal <= 0 && (protein > 0 || carbs > 0 || fat > 0) {
            kcal = protein * 4.0 + carbs * 4.0 + fat * 9.0
        }

        var servings: [ServingSize] = []
        if let sSize = raw.servingSize, sSize > 0 {
            let unit = (raw.servingSizeUnit ?? "g").lowercased()
            if unit == "g" || unit == "ml" || unit == "grm" {
                let label = raw.householdServingFullText?.trimmingCharacters(in: .whitespacesAndNewlines)
                let displayLabel = (label?.isEmpty == false) ? "\(label!) (\(Int(sSize.rounded()))g)" : "1 serving (\(Int(sSize.rounded()))g)"
                servings.append(ServingSize(label: displayLabel, grams: sSize))
            }
        }
        servings.append(ServingSize(label: "100 g", grams: 100.0))

        return RemoteFoodDTO(
            name: formatUSDACase(title),
            brand: raw.brandName ?? raw.brandOwner,
            barcode: raw.gtinUpc,
            source: .usda,
            sourceID: String(raw.fdcId),
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

    private func formatUSDACase(_ s: String) -> String {
        if s == s.uppercased() {
            return s.capitalized
        }
        return s
    }
}

private struct USDASearchResponse: Decodable {
    var foods: [USDAFoodItem]
}

private struct USDAFoodItem: Decodable {
    var fdcId: Int
    var description: String
    var dataType: String?
    var brandOwner: String?
    var brandName: String?
    var gtinUpc: String?
    var servingSize: Double?
    var servingSizeUnit: String?
    var householdServingFullText: String?
    var foodNutrients: [USDANutrientItem]?
}

private struct USDANutrientItem: Decodable {
    var nutrientId: Int?
    var nutrientNumber: String?
    var value: Double?
}
