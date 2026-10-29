import Foundation
import SwiftData

public enum CSVExportService {
    @MainActor
    public static func exportFoodLogCSV(context: ModelContext) throws -> URL {
        let entries = ((try? context.fetch(FetchDescriptor<FoodLogEntry>())) ?? [])
            .sorted { $0.timestamp < $1.timestamp }

        var rows = ["Date,TimestampISO,FoodName,Brand,Source,MealTag,ServingLabel,Grams,Calories,ProteinG,CarbsG,FatG,FiberG,SugarG,SodiumMg"]
        let iso = ISO8601DateFormatter()

        for e in entries {
            let n = e.loggedNutrients
            let cols: [String] = [
                escape(e.dayKey),
                escape(iso.string(from: e.timestamp)),
                escape(e.foodName),
                escape(e.foodBrand ?? ""),
                escape(e.foodSource.rawValue),
                escape(e.mealTag.rawValue),
                escape(e.servingLabel),
                String(format: "%.1f", e.grams),
                String(format: "%.1f", n.calories),
                String(format: "%.1f", n.protein),
                String(format: "%.1f", n.carbs),
                String(format: "%.1f", n.fat),
                String(format: "%.1f", n.fiber),
                String(format: "%.1f", n.sugar),
                String(format: "%.1f", n.sodiumMg)
            ]
            rows.append(cols.joined(separator: ","))
        }

        return try writeTempCSV(filename: "TotalFactor_FoodLog_\(DayKey.today).csv", content: rows.joined(separator: "\n"))
    }

    @MainActor
    public static func exportWeighInsCSV(context: ModelContext) throws -> URL {
        let weighIns = ((try? context.fetch(FetchDescriptor<WeighIn>())) ?? [])
            .sorted { $0.date < $1.date }
        let trendSeries = WeightTrendEngine.buildDailySeries(samples: weighIns.map(\.asSample))
        let trendByDay = Dictionary(trendSeries.map { ($0.dayKey, $0.trendKg) }, uniquingKeysWith: { _, latest in latest })

        var rows = ["Date,TimestampISO,WeightKg,WeightLb,TrendWeightKg,TrendWeightLb,Source"]
        let iso = ISO8601DateFormatter()

        for w in weighIns {
            let tKg = trendByDay[w.dayKey] ?? w.weightKg
            let cols: [String] = [
                escape(w.dayKey),
                escape(iso.string(from: w.date)),
                String(format: "%.2f", w.weightKg),
                String(format: "%.2f", UnitsFormatter.kgToLb(w.weightKg)),
                String(format: "%.2f", tKg),
                String(format: "%.2f", UnitsFormatter.kgToLb(tKg)),
                escape(w.source.rawValue)
            ]
            rows.append(cols.joined(separator: ","))
        }

        return try writeTempCSV(filename: "TotalFactor_WeighIns_\(DayKey.today).csv", content: rows.joined(separator: "\n"))
    }

    @MainActor
    public static func exportWorkoutsCSV(context: ModelContext) throws -> URL {
        let sessions = ((try? context.fetch(FetchDescriptor<WorkoutSession>())) ?? [])
            .sorted { $0.start < $1.start }

        var rows = ["Date,SessionTitle,GymProfile,StartISO,EndISO,SetOrder,Exercise,SetType,WeightKg,WeightLb,Reps,RIR,Estimated1RMKg"]
        let iso = ISO8601DateFormatter()

        for s in sessions {
            let endStr = s.end.map { iso.string(from: $0) } ?? ""
            for setLog in s.sortedSets where setLog.isCompleted {
                let cols: [String] = [
                    escape(s.dayKey),
                    escape(s.title),
                    escape(s.gymProfile?.name ?? ""),
                    escape(iso.string(from: s.start)),
                    escape(endStr),
                    String(setLog.order),
                    escape(setLog.exercise?.name ?? "Unknown"),
                    escape(setLog.type.rawValue),
                    String(format: "%.2f", setLog.weightKg),
                    String(format: "%.2f", UnitsFormatter.kgToLb(setLog.weightKg)),
                    String(setLog.reps),
                    String(setLog.rir),
                    String(format: "%.2f", setLog.estimated1RMKg)
                ]
                rows.append(cols.joined(separator: ","))
            }
        }

        return try writeTempCSV(filename: "TotalFactor_Workouts_\(DayKey.today).csv", content: rows.joined(separator: "\n"))
    }

    private static func escape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            let doubled = value.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(doubled)\""
        }
        return value
    }

    private static func writeTempCSV(filename: String, content: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
