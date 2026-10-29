import Foundation

public struct ParsedNutritionLabel: Equatable, Sendable {
    public var servingLabel: String
    public var servingGrams: Double
    public var perServing: NutrientsPer100g
    public var per100g: NutrientsPer100g
    public var matchedFieldsCount: Int

    public var isUsable: Bool {
        matchedFieldsCount >= 2 && (perServing.calories > 0 || perServing.protein > 0 || perServing.carbs > 0 || perServing.fat > 0)
    }
}

/// Pure-Swift parser that extracts Nutrition Facts from recognized Vision OCR text lines.
/// Supports US FDA ("Serving size 1 cup (228g)", "Calories 280", "Total Fat 9g", "Protein 15g")
/// and metric per-100g labels.
public enum NutritionLabelParser {
    public static func parse(lines: [String]) -> ParsedNutritionLabel {
        let joined = lines.joined(separator: "\n")
        let normalizedLines = lines.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }

        // 1. Serving size & gram weight
        var servingLabel = "1 serving"
        var servingGrams: Double = 100.0
        var foundExplicitGrams = false

        for line in normalizedLines {
            let lower = line.lowercased()
            if lower.contains("serving size") || lower.contains("per serving") {
                if let gMatch = firstRegexCapture(in: line, pattern: #"\((\d+(?:\.\d+)?)\s*(?:g|ml)\)"#) ??
                    firstRegexCapture(in: line, pattern: #"(\d+(?:\.\d+)?)\s*(?:g|grams)\b"#),
                   let g = Double(gMatch), g > 0 {
                    servingGrams = g
                    foundExplicitGrams = true
                }
                let cleaned = line
                    .replacingOccurrences(of: #"(?i)serving\s*size\s*:?\s*"#, with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleaned.isEmpty {
                    servingLabel = cleaned
                }
            } else if !foundExplicitGrams, lower.contains("per 100") {
                servingLabel = "100 g"
                servingGrams = 100.0
                foundExplicitGrams = true
            }
        }

        // 2. Extract core nutrients across individual or adjacent lines
        var matched = 0
        let calories = extractCalories(lines: normalizedLines, fullText: joined, matched: &matched)
        let fat = extractNutrientGrams(
            patterns: [#"(?i)total\s*fat\s*:?\s*(\d+(?:\.\d+)?)\s*g?"#, #"(?i)^fat\s*:?\s*(\d+(?:\.\d+)?)\s*g"#],
            in: joined,
            matched: &matched
        )
        let satFat = extractNutrientGrams(
            patterns: [#"(?i)saturated\s*fat\s*:?\s*(\d+(?:\.\d+)?)\s*g?"#],
            in: joined,
            matched: &matched
        )
        let cholesterol = extractNutrientGrams(
            patterns: [#"(?i)cholesterol\s*:?\s*(\d+(?:\.\d+)?)\s*mg"#],
            in: joined,
            matched: &matched
        )
        let sodium = extractNutrientGrams(
            patterns: [#"(?i)sodium\s*:?\s*(\d+(?:\.\d+)?)\s*mg"#],
            in: joined,
            matched: &matched
        )
        let carbs = extractNutrientGrams(
            patterns: [
                #"(?i)total\s*carb(?:ohydrate)?s?\s*:?\s*(\d+(?:\.\d+)?)\s*g?"#,
                #"(?i)^carbohydrate\s*:?\s*(\d+(?:\.\d+)?)\s*g"#
            ],
            in: joined,
            matched: &matched
        )
        let fiber = extractNutrientGrams(
            patterns: [#"(?i)(?:dietary\s*)?fib(?:er|re)\s*:?\s*(\d+(?:\.\d+)?)\s*g?"#],
            in: joined,
            matched: &matched
        )
        let sugar = extractNutrientGrams(
            patterns: [#"(?i)(?:total\s*)?sugars?\s*:?\s*(\d+(?:\.\d+)?)\s*g?"#],
            in: joined,
            matched: &matched
        )
        let protein = extractNutrientGrams(
            patterns: [#"(?i)protein\s*:?\s*(\d+(?:\.\d+)?)\s*g?"#],
            in: joined,
            matched: &matched
        )

        var micros: [String: Double] = [:]
        var ignoredMatch = 0
        if satFat > 0 { micros[MicronutrientKey.saturatedFatG.rawValue] = satFat }
        if cholesterol > 0 { micros[MicronutrientKey.cholesterolMg.rawValue] = cholesterol }

        let vitD = extractNutrientGrams(patterns: [#"(?i)vitamin\s*d\s*:?\s*(\d+(?:\.\d+)?)\s*mcg"#], in: joined, matched: &ignoredMatch)
        if vitD > 0 { micros[MicronutrientKey.vitaminDMcg.rawValue] = vitD }

        let calcium = extractNutrientGrams(patterns: [#"(?i)calcium\s*:?\s*(\d+(?:\.\d+)?)\s*mg"#], in: joined, matched: &ignoredMatch)
        if calcium > 0 { micros[MicronutrientKey.calciumMg.rawValue] = calcium }

        let iron = extractNutrientGrams(patterns: [#"(?i)iron\s*:?\s*(\d+(?:\.\d+)?)\s*mg"#], in: joined, matched: &ignoredMatch)
        if iron > 0 { micros[MicronutrientKey.ironMg.rawValue] = iron }

        let potassium = extractNutrientGrams(patterns: [#"(?i)potassium\s*:?\s*(\d+(?:\.\d+)?)\s*mg"#], in: joined, matched: &ignoredMatch)
        if potassium > 0 { micros[MicronutrientKey.potassiumMg.rawValue] = potassium }

        let inferredKcal = calories > 0 ? calories : ((protein * 4.0) + (carbs * 4.0) + (fat * 9.0))

        let perServing = NutrientsPer100g(
            calories: inferredKcal,
            protein: protein,
            carbs: carbs,
            fat: fat,
            fiber: fiber,
            sugar: sugar,
            sodiumMg: sodium,
            micronutrients: micros
        )

        let scaleTo100 = 100.0 / max(1.0, servingGrams)
        var microsPer100: [String: Double] = [:]
        for (k, v) in micros {
            microsPer100[k] = v * scaleTo100
        }

        let per100g = NutrientsPer100g(
            calories: inferredKcal * scaleTo100,
            protein: protein * scaleTo100,
            carbs: carbs * scaleTo100,
            fat: fat * scaleTo100,
            fiber: fiber * scaleTo100,
            sugar: sugar * scaleTo100,
            sodiumMg: sodium * scaleTo100,
            micronutrients: microsPer100
        )

        return ParsedNutritionLabel(
            servingLabel: servingLabel,
            servingGrams: servingGrams,
            perServing: perServing,
            per100g: per100g,
            matchedFieldsCount: matched
        )
    }

    private static func extractCalories(lines: [String], fullText: String, matched: inout Int) -> Double {
        if let cap = firstRegexCapture(in: fullText, pattern: #"(?i)calories\s*:?\s*(\d{1,4})\b"#),
           let val = Double(cap) {
            matched += 1
            return val
        }
        // US FDA two-line layout where "Calories" is on one line and bold "240" is on the next line
        for idx in lines.indices {
            if lines[idx].lowercased() == "calories", idx + 1 < lines.count {
                if let cap = firstRegexCapture(in: lines[idx + 1], pattern: #"^(\d{1,4})$"#),
                   let val = Double(cap) {
                    matched += 1
                    return val
                }
            }
        }
        if let kjCap = firstRegexCapture(in: fullText, pattern: #"(?i)(\d{1,4})\s*kcal"#),
           let val = Double(kjCap) {
            matched += 1
            return val
        }
        return 0
    }

    private static func extractNutrientGrams(patterns: [String], in text: String, matched: inout Int) -> Double {
        for pattern in patterns {
            if let cap = firstRegexCapture(in: text, pattern: pattern),
               let val = Double(cap) {
                matched += 1
                return val
            }
        }
        return 0
    }

    private static func firstRegexCapture(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges >= 2,
              let captureRange = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[captureRange])
    }
}
