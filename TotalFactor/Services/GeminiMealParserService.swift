import Foundation
import Security
#if canImport(UIKit)
import UIKit
#endif

/// Secure Keychain + UserDefaults store for optional Gemini API meal-text & meal-photo parsing.
/// Stored outside SwiftData so API secrets never leak into CSV/CloudKit exports and never touch SQLite schema migrations.
public enum GeminiConfigStore {
    private static let keychainService = "com.prerak.totalfactor.gemini"
    private static let keychainAccount = "gemini_api_key"
    private static let modelDefaultsKey = "totalfactor.gemini.model"
    private static let enabledDefaultsKey = "totalfactor.gemini.enabled"

    public static let availableModels = [
        "gemini-2.5-flash",
        "gemini-2.5-pro",
        "gemini-2.0-flash",
        "gemini-1.5-flash"
    ]

    public static var selectedModel: String {
        get {
            let stored = UserDefaults.standard.string(forKey: modelDefaultsKey) ?? "gemini-2.5-flash"
            return availableModels.contains(stored) ? stored : "gemini-2.5-flash"
        }
        set {
            UserDefaults.standard.set(newValue, forKey: modelDefaultsKey)
        }
    }

    public static var isEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: enabledDefaultsKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: enabledDefaultsKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: enabledDefaultsKey)
        }
    }

    public static var hasConfiguredKey: Bool {
        !loadAPIKey().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public static func loadAPIKey() -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let str = String(data: data, encoding: .utf8) else {
            return ""
        }
        return str
    }

    public static func saveAPIKey(_ rawKey: String) {
        let trimmed = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return }
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        SecItemAdd(addQuery as CFDictionary, nil)
    }
}

public enum GeminiMealParseError: LocalizedError {
    case missingAPIKey
    case invalidResponse(statusCode: Int, detail: String)
    case emptyItems

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Add your optional Gemini API key in Settings → Food Databases & AI Meal Parsing to analyze meal photos or use Gemini AI."
        case .invalidResponse(let code, let detail):
            return "Gemini API error (HTTP \(code)): \(detail)"
        case .emptyItems:
            return "Could not identify distinct food items. Try adding a short description or clearer photo."
        }
    }
}

/// Optional multimodal Gemini API parser for complex restaurant dishes and meal photos.
public struct GeminiMealParserService: Sendable {
    public init() {}

    #if canImport(UIKit)
    public static func downsampleJPEGData(from image: UIImage, maxDimension: CGFloat = 1024) -> Data? {
        let size = image.size
        guard size.width > 0 && size.height > 0 else { return nil }
        let scale = min(1.0, maxDimension / max(size.width, size.height))
        let targetSize = CGSize(width: round(size.width * scale), height: round(size.height * scale))
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1.0
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
        return resized.jpegData(compressionQuality: 0.78)
    }
    #endif

    public func analyzeMeal(
        descriptionText: String,
        jpegImageData: Data?,
        apiKey: String? = nil,
        model: String? = nil
    ) async throws -> [ParsedMealDraftItem] {
        let key = (apiKey ?? GeminiConfigStore.loadAPIKey()).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            throw GeminiMealParseError.missingAPIKey
        }
        let chosenModel = model ?? GeminiConfigStore.selectedModel
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(chosenModel):generateContent?key=\(key)") else {
            throw GeminiMealParseError.emptyItems
        }

        let systemInstruction = """
        You are a precision sports-nutrition dietitian for Total Factor. Break the user's meal (from text, photo, or both) into individual component foods with realistic cooked/edible gram weights and accurate USDA-grounded nutrition.
        CRITICAL RULES:
        1. All calories, protein, carbs, fat, fiber, sugar, and sodium values MUST be the TOTAL for the full edible portion of the specified grams (NOT per 100g).
        2. If both a photo and notes are provided, synthesize both: visual portions from the photo and specific ingredients/cooking methods from notes.
        3. Never double-count ingredients. Return clean JSON matching the schema.
        """

        var userParts: [[String: Any]] = []
        let trimmedText = descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
        if let jpegImageData {
            userParts.append([
                "inline_data": [
                    "mime_type": "image/jpeg",
                    "data": jpegImageData.base64EncodedString()
                ]
            ])
        }
        let promptText: String
        if jpegImageData != nil && !trimmedText.isEmpty {
            promptText = "Analyze this meal photo together with the user's notes: \"\(trimmedText)\". Use the photo for visual portions and food identification, and use notes for preparation and hidden ingredients. Estimate total grams and portion nutrition for each distinct food item."
        } else if jpegImageData != nil {
            promptText = "Identify every food item visible in this meal photo and estimate edible portion grams and total nutrition (calories, protein, carbs, fat, fiber, sugar, sodium) for each item."
        } else {
            promptText = "Parse this meal into distinct items with edible portion grams and total nutrition for each item: \(trimmedText)"
        }
        userParts.append(["text": promptText])

        let itemProperties: [String: Any] = [
            "name": ["type": "STRING", "description": "Clear specific food name (e.g. 'Grilled Chicken Breast', 'Cooked White Rice')"],
            "servingLabel": ["type": "STRING", "description": "Human-friendly serving label, e.g. '6 oz cooked (170g)', '1 cup (158g)'"],
            "grams": ["type": "NUMBER", "description": "Edible weight in grams"],
            "calories": ["type": "NUMBER", "description": "TOTAL calories for this entire portion in grams (NOT per 100g)"],
            "protein": ["type": "NUMBER", "description": "TOTAL grams of protein for this portion"],
            "carbs": ["type": "NUMBER", "description": "TOTAL grams of carbohydrates for this portion"],
            "fat": ["type": "NUMBER", "description": "TOTAL grams of fat for this portion"],
            "fiber": ["type": "NUMBER", "description": "TOTAL grams of dietary fiber for this portion"],
            "sugar": ["type": "NUMBER", "description": "TOTAL grams of sugar for this portion"],
            "sodiumMg": ["type": "NUMBER", "description": "TOTAL milligrams of sodium for this portion"]
        ]

        let payload: [String: Any] = [
            "systemInstruction": [
                "parts": [["text": systemInstruction]]
            ],
            "contents": [
                ["role": "user", "parts": userParts]
            ],
            "generationConfig": [
                "temperature": 0.15,
                "responseMimeType": "application/json",
                "responseSchema": [
                    "type": "OBJECT",
                    "properties": [
                        "items": [
                            "type": "ARRAY",
                            "items": [
                                "type": "OBJECT",
                                "properties": itemProperties,
                                "required": ["name", "servingLabel", "grams", "calories", "protein", "carbs", "fat"]
                            ]
                        ]
                    ],
                    "required": ["items"]
                ]
            ]
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 22.0
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GeminiMealParseError.invalidResponse(statusCode: -1, detail: "No HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let errBody = String(data: data.prefix(240), encoding: .utf8) ?? "Request failed"
            throw GeminiMealParseError.invalidResponse(statusCode: http.statusCode, detail: errBody)
        }

        let wrapper = try JSONDecoder().decode(GeminiGenerateResponse.self, from: data)
        guard let jsonText = wrapper.candidates?.first?.content?.parts?.first?.text,
              let jsonData = jsonText.data(using: .utf8) else {
            throw GeminiMealParseError.emptyItems
        }

        let parsed = try JSONDecoder().decode(GeminiStructuredMealResponse.self, from: jsonData)
        guard !parsed.items.isEmpty else {
            throw GeminiMealParseError.emptyItems
        }

        let originBadge = (jpegImageData != nil) ? "Gemini Vision" : "Gemini AI"
        let catalog = OfflineUSDACatalogService.shared.index
        return parsed.items.compactMap { raw -> ParsedMealDraftItem? in
            let cleanName = raw.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanName.isEmpty else { return nil }
            let grams = max(1.0, raw.grams)
            let scaleTo100 = 100.0 / grams
            let p = max(0, raw.protein)
            let c = max(0, raw.carbs)
            let f = max(0, raw.fat)
            let cals = raw.calories > 0 ? raw.calories : (p * 4.0 + c * 4.0 + f * 9.0)

            // Look for closest offline USDA entry to enrich with verified micronutrients
            let usdaMatches = catalog.searchCandidates(query: cleanName, limit: 1)
            let matchedEntry = usdaMatches.first.flatMap { catalog.entry(forSourceID: $0.sourceID) }

            let per100 = NutrientsPer100g(
                calories: cals * scaleTo100,
                protein: p * scaleTo100,
                carbs: c * scaleTo100,
                fat: f * scaleTo100,
                fiber: max(0, raw.fiber ?? matchedEntry?.nutrientsPer100g.fiber ?? 0) * scaleTo100,
                sugar: max(0, raw.sugar ?? matchedEntry?.nutrientsPer100g.sugar ?? 0) * scaleTo100,
                sodiumMg: max(0, raw.sodiumMg ?? (matchedEntry?.nutrientsPer100g.sodiumMg != nil ? (matchedEntry!.nutrientsPer100g.sodiumMg * (grams / 100.0)) : 0)) * scaleTo100,
                micronutrients: matchedEntry?.nutrientsPer100g.micronutrients ?? [:]
            )
            let lbl = raw.servingLabel.trimmingCharacters(in: .whitespacesAndNewlines)
            let displayBadge = matchedEntry != nil ? "\(originBadge) + USDA" : originBadge
            return ParsedMealDraftItem(
                rawSegment: cleanName,
                foodName: cleanName,
                brand: displayBadge,
                quantity: 1.0,
                servingLabel: lbl.isEmpty ? "\(Int(grams.rounded())) g" : lbl,
                grams: grams,
                nutrientsPer100g: per100,
                source: matchedEntry != nil ? .usda : .custom,
                matchedPersistedFoodID: nil,
                matchedOfflineUSDASourceID: matchedEntry?.sourceID,
                matchOriginBadge: displayBadge
            )
        }
    }
}

private struct GeminiGenerateResponse: Decodable {
    struct Candidate: Decodable {
        struct Content: Decodable {
            struct Part: Decodable {
                var text: String?
            }
            var parts: [Part]?
        }
        var content: Content?
    }
    var candidates: [Candidate]?
}

private struct GeminiStructuredMealResponse: Decodable {
    struct Item: Decodable {
        var name: String
        var servingLabel: String
        var grams: Double
        var calories: Double
        var protein: Double
        var carbs: Double
        var fat: Double
        var fiber: Double?
        var sugar: Double?
        var sodiumMg: Double?
    }
    var items: [Item]
}
