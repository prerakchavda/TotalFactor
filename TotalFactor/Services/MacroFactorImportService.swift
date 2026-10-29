import Foundation
import SwiftData

public struct MacroFactorImportSummary: Sendable, Equatable {
    public var foodsImported: Int = 0
    public var foodsSkipped: Int = 0
    public var weighInsImported: Int = 0
    public var weighInsSkipped: Int = 0
    public var daysTouched: Int = 0

    public init(
        foodsImported: Int = 0,
        foodsSkipped: Int = 0,
        weighInsImported: Int = 0,
        weighInsSkipped: Int = 0,
        daysTouched: Int = 0
    ) {
        self.foodsImported = foodsImported
        self.foodsSkipped = foodsSkipped
        self.weighInsImported = weighInsImported
        self.weighInsSkipped = weighInsSkipped
        self.daysTouched = daysTouched
    }
}

@MainActor
public enum MacroFactorImportService {

    /// Imports food logs and optional weigh-ins from a MacroFactor CSV export.
    /// Uses deterministic fingerprinting to guarantee zero duplicate food entries or weigh-ins.
    public static func importCSV(
        content: String,
        context: ModelContext,
        defaultMealTag: MealTag = .none
    ) -> MacroFactorImportSummary {
        let lines = content.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        guard lines.count >= 2 else {
            return MacroFactorImportSummary()
        }

        let headers = parseCSVLine(lines[0]).map { $0.lowercased().trimmingCharacters(in: .punctuationCharacters) }

        // Detect column mappings flexibly
        var dateIdx: Int?
        var timeIdx: Int?
        var nameIdx: Int?
        var servingIdx: Int?
        var gramsIdx: Int?
        var calIdx: Int?
        var proIdx: Int?
        var carbIdx: Int?
        var fatIdx: Int?
        var fiberIdx: Int?
        var sugarIdx: Int?
        var sodiumIdx: Int?
        var mealIdx: Int?
        var weightIdx: Int?

        for (i, h) in headers.enumerated() {
            if h.contains("date") || h == "day" {
                if dateIdx == nil { dateIdx = i }
            } else if h.contains("time") && !h.contains("date") {
                if timeIdx == nil { timeIdx = i }
            } else if (h.contains("food") || h.contains("name") || h.contains("description") || h == "item") && !h.contains("brand") {
                if nameIdx == nil { nameIdx = i }
            } else if h.contains("serving") || h.contains("portion") || h.contains("quantity") || h.contains("amount") {
                if servingIdx == nil { servingIdx = i }
            } else if h.contains("gram") || h == "weight (g)" || h == "g" {
                if gramsIdx == nil { gramsIdx = i }
            } else if h.contains("calorie") || h.contains("energy") || h.contains("kcal") {
                if calIdx == nil { calIdx = i }
            } else if h.contains("protein") || h == "pro" || h.contains("pro (g)") {
                if proIdx == nil { proIdx = i }
            } else if h.contains("carb") || h.contains("carbohydrate") {
                if carbIdx == nil { carbIdx = i }
            } else if (h.contains("fat") || h.contains("lipid")) && !h.contains("sat") {
                if fatIdx == nil { fatIdx = i }
            } else if h.contains("fiber") || h.contains("fibre") {
                if fiberIdx == nil { fiberIdx = i }
            } else if h.contains("sugar") {
                if sugarIdx == nil { sugarIdx = i }
            } else if h.contains("sodium") || h.contains("salt") {
                if sodiumIdx == nil { sodiumIdx = i }
            } else if h.contains("meal") || h.contains("category") || h.contains("slot") {
                if mealIdx == nil { mealIdx = i }
            } else if h.contains("scale") || (h.contains("weight") && !h.contains("(g)")) {
                if weightIdx == nil { weightIdx = i }
            }
        }

        // Must have at least a date column, plus either food calories or scale weight
        guard let dCol = dateIdx else {
            return MacroFactorImportSummary()
        }

        // Build existing database fingerprint cache for 100% duplicate protection
        let existingFoods = (try? context.fetch(FetchDescriptor<FoodLogEntry>())) ?? []
        var existingFoodSignatures = Set<String>()
        for f in existingFoods {
            let sig = makeFoodSignature(
                dayKey: f.dayKey,
                date: f.timestamp,
                name: f.foodName,
                calories: f.calories,
                protein: f.protein
            )
            existingFoodSignatures.insert(sig)
        }

        let existingWeighIns = (try? context.fetch(FetchDescriptor<WeighIn>())) ?? []
        var existingWeighInDays = Set<String>(existingWeighIns.map(\.dayKey))

        var summary = MacroFactorImportSummary()
        var touchedDayKeys = Set<String>()

        for line in lines.dropFirst() {
            let cols = parseCSVLine(line)
            guard cols.count > dCol else { continue }

            let rawDate = cols[dCol]
            let rawTime = timeIdx.flatMap { cols.indices.contains($0) ? cols[$0] : nil }
            guard let entryDate = parseDateTime(dateStr: rawDate, timeStr: rawTime) else {
                continue
            }

            let dayKey = DayKey.from(entryDate)

            // Case A: Row contains scale body weight
            if let wCol = weightIdx, cols.indices.contains(wCol),
               let rawW = Double(cols[wCol].replacingOccurrences(of: "[^0-9.]", with: "", options: .regularExpression)),
               rawW > 20.0 {
                // If value is > 90, assume pounds and convert to kg, else assume kg
                let weightKg = rawW > 90.0 ? (rawW * 0.45359237) : rawW
                if existingWeighInDays.contains(dayKey) {
                    summary.weighInsSkipped += 1
                } else {
                    let weighIn = WeighIn(
                        date: entryDate,
                        dayKey: dayKey,
                        weightKg: weightKg,
                        source: .manual
                    )
                    context.insert(weighIn)
                    existingWeighInDays.insert(dayKey)
                    summary.weighInsImported += 1
                    touchedDayKeys.insert(dayKey)
                }
            }

            // Case B: Row contains food log item
            let foodName: String = {
                if let nCol = nameIdx, cols.indices.contains(nCol), !cols[nCol].isEmpty {
                    return cols[nCol]
                }
                return "MacroFactor Item"
            }()

            let calories: Double = {
                if let cCol = calIdx, cols.indices.contains(cCol) {
                    return Double(cols[cCol].replacingOccurrences(of: "[^0-9.]", with: "", options: .regularExpression)) ?? 0
                }
                return 0
            }()

            let protein: Double = {
                if let pCol = proIdx, cols.indices.contains(pCol) {
                    return Double(cols[pCol].replacingOccurrences(of: "[^0-9.]", with: "", options: .regularExpression)) ?? 0
                }
                return 0
            }()

            let carbs: Double = {
                if let cbCol = carbIdx, cols.indices.contains(cbCol) {
                    return Double(cols[cbCol].replacingOccurrences(of: "[^0-9.]", with: "", options: .regularExpression)) ?? 0
                }
                return 0
            }()

            let fat: Double = {
                if let fCol = fatIdx, cols.indices.contains(fCol) {
                    return Double(cols[fCol].replacingOccurrences(of: "[^0-9.]", with: "", options: .regularExpression)) ?? 0
                }
                return 0
            }()

            // Only log if this row has nutritional value or food name
            guard calories > 0 || protein > 0 || carbs > 0 || fat > 0 else {
                continue
            }

            let fiber: Double = {
                if let fbCol = fiberIdx, cols.indices.contains(fbCol) {
                    return Double(cols[fbCol].replacingOccurrences(of: "[^0-9.]", with: "", options: .regularExpression)) ?? 0
                }
                return 0
            }()

            let sugar: Double = {
                if let sCol = sugarIdx, cols.indices.contains(sCol) {
                    return Double(cols[sCol].replacingOccurrences(of: "[^0-9.]", with: "", options: .regularExpression)) ?? 0
                }
                return 0
            }()

            let sodiumMg: Double = {
                if let sodCol = sodiumIdx, cols.indices.contains(sodCol) {
                    return Double(cols[sodCol].replacingOccurrences(of: "[^0-9.]", with: "", options: .regularExpression)) ?? 0
                }
                return 0
            }()

            let grams: Double = {
                if let gCol = gramsIdx, cols.indices.contains(gCol),
                   let val = Double(cols[gCol].replacingOccurrences(of: "[^0-9.]", with: "", options: .regularExpression)), val > 0 {
                    return val
                }
                return 100.0
            }()

            let servingLabel: String = {
                if let srvCol = servingIdx, cols.indices.contains(srvCol), !cols[srvCol].isEmpty {
                    return cols[srvCol]
                }
                return "\(Int(grams.rounded()))g"
            }()

            let mealTag: MealTag = {
                if let mCol = mealIdx, cols.indices.contains(mCol) {
                    let rawM = cols[mCol].lowercased()
                    if rawM.contains("breakfast") { return .breakfast }
                    if rawM.contains("lunch") { return .lunch }
                    if rawM.contains("dinner") { return .dinner }
                    if rawM.contains("snack") { return .snack }
                    if rawM.contains("pre") { return .preWorkout }
                    if rawM.contains("post") { return .postWorkout }
                }
                // Fallback to time-of-day
                let hour = Calendar.current.component(.hour, from: entryDate)
                switch hour {
                case 5..<11:  return .breakfast
                case 11..<15: return .lunch
                case 15..<18: return .snack
                case 18..<22: return .dinner
                default:      return .snack
                }
            }()

            // Deterministic Fingerprint Deduplication Check
            let signature = makeFoodSignature(
                dayKey: dayKey,
                date: entryDate,
                name: foodName,
                calories: calories,
                protein: protein
            )

            if existingFoodSignatures.contains(signature) {
                summary.foodsSkipped += 1
                continue
            }

            // Create and insert non-duplicate entry
            let entry = FoodLogEntry(
                quickTitle: foodName,
                calories: calories,
                protein: protein,
                carbs: carbs,
                fat: fat,
                mealTag: mealTag,
                timestamp: entryDate,
                dayKey: dayKey
            )
            entry.foodBrand = "MacroFactor"
            entry.foodSourceRaw = FoodSource.custom.rawValue
            entry.grams = grams
            entry.servingLabel = servingLabel
            entry.snapshotFiberPer100g = (fiber / grams) * 100.0
            entry.snapshotSugarPer100g = (sugar / grams) * 100.0
            entry.snapshotSodiumMgPer100g = (sodiumMg / grams) * 100.0

            context.insert(entry)
            existingFoodSignatures.insert(signature)
            summary.foodsImported += 1
            touchedDayKeys.insert(dayKey)
        }

        _ = try? context.save()
        summary.daysTouched = touchedDayKeys.count

        // Update coaching coordinator calculations for affected days
        for dayKey in touchedDayKeys {
            _ = CoachingCoordinator.evaluate(forDayKey: dayKey, context: context)
        }

        return summary
    }

    // MARK: - Private Helpers

    public static func makeFoodSignature(
        dayKey: String,
        date: Date,
        name: String,
        calories: Double,
        protein: Double
    ) -> String {
        let cal = Calendar.current
        let hour = cal.component(.hour, from: date)
        let minute = cal.component(.minute, from: date)
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let roundedKcal = Int(calories.rounded())
        let roundedP = Int(protein.rounded())
        return "\(dayKey)_\(hour):\(minute)_\(cleanName)_\(roundedKcal)_\(roundedP)"
    }

    private static func parseDateTime(dateStr: String, timeStr: String?) -> Date? {
        let cleanDate = dateStr.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanDate.isEmpty { return nil }

        let dateOnlyFormatters: [DateFormatter] = {
            let formats = [
                "yyyy-MM-dd",
                "MM/dd/yyyy",
                "M/d/yyyy",
                "yyyy/MM/dd",
                "dd/MM/yyyy",
                "yyyy-MM-dd'T'HH:mm:ss",
                "yyyy-MM-dd'T'HH:mm:ssZ"
            ]
            return formats.map { f in
                let df = DateFormatter()
                df.dateFormat = f
                df.locale = Locale(identifier: "en_US_POSIX")
                df.timeZone = .current
                return df
            }
        }()

        var baseDate: Date? = nil
        for df in dateOnlyFormatters {
            if let d = df.date(from: cleanDate) {
                baseDate = d
                break
            }
        }

        guard let validDate = baseDate else { return nil }

        // If time string is provided, overlay hour and minute
        guard let time = timeStr?.trimmingCharacters(in: .whitespacesAndNewlines), !time.isEmpty else {
            return validDate
        }

        let timeFormatters: [DateFormatter] = {
            let formats = ["h:mm a", "hh:mm a", "h:mma", "HH:mm", "HH:mm:ss", "h:mm:ss a"]
            return formats.map { f in
                let df = DateFormatter()
                df.dateFormat = f
                df.locale = Locale(identifier: "en_US_POSIX")
                df.timeZone = .current
                return df
            }
        }()

        for tf in timeFormatters {
            if let tDate = tf.date(from: time) {
                let cal = Calendar.current
                let hour = cal.component(.hour, from: tDate)
                let minute = cal.component(.minute, from: tDate)
                var components = cal.dateComponents([.year, .month, .day], from: validDate)
                components.hour = hour
                components.minute = minute
                components.second = 0
                return cal.date(from: components) ?? validDate
            }
        }

        return validDate
    }

    private static func parseCSVLine(_ line: String) -> [String] {
        var result: [String] = []
        var current = ""
        var insideQuotes = false
        var iterator = line.makeIterator()

        while let char = iterator.next() {
            if char == "\"" {
                insideQuotes.toggle()
            } else if char == "," && !insideQuotes {
                result.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(char)
            }
        }
        result.append(current.trimmingCharacters(in: .whitespaces))
        return result.map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\"")) }
    }
}
