import Foundation
import SwiftData
#if canImport(UIKit)
import UIKit
#endif

/// Comprehensive data export service that bundles all app records into universal CSVs, structured JSON,
/// and an AI-prompt-ready Markdown analysis digest (v1.5.3).
public enum ExportAllArchiveService {

    public struct ExportPackage {
        public let folderURL: URL
        public let fileURLs: [URL]
        public let aiDigestURL: URL
        public let fullJSONURL: URL
    }

    @MainActor
    public static func generateExportPackage(context: ModelContext) throws -> ExportPackage {
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory
        let exportFolderName = "TotalFactor_Export_\(DayKey.today)_\(Int(Date().timeIntervalSince1970))"
        let folderURL = tempDir.appendingPathComponent(exportFolderName, isDirectory: true)

        try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)

        var generatedURLs: [URL] = []

        // 1. Generate Universal CSVs
        let foodLogCSVURL = try CSVExportService.exportFoodLogCSV(context: context)
        let foodDest = folderURL.appendingPathComponent("TotalFactor_FoodLog.csv")
        try? fileManager.removeItem(at: foodDest)
        try fileManager.copyItem(at: foodLogCSVURL, to: foodDest)
        generatedURLs.append(foodDest)

        let weighInsCSVURL = try CSVExportService.exportWeighInsCSV(context: context)
        let weighDest = folderURL.appendingPathComponent("TotalFactor_WeighIns.csv")
        try? fileManager.removeItem(at: weighDest)
        try fileManager.copyItem(at: weighInsCSVURL, to: weighDest)
        generatedURLs.append(weighDest)

        let workoutsCSVURL = try CSVExportService.exportWorkoutsCSV(context: context)
        let workoutDest = folderURL.appendingPathComponent("TotalFactor_Workouts.csv")
        try? fileManager.removeItem(at: workoutDest)
        try fileManager.copyItem(at: workoutsCSVURL, to: workoutDest)
        generatedURLs.append(workoutDest)

        let bodyMetricsDest = folderURL.appendingPathComponent("TotalFactor_BodyMetrics.csv")
        let bodyMetricsCSV = generateBodyMetricsCSV(context: context)
        try bodyMetricsCSV.write(to: bodyMetricsDest, atomically: true, encoding: .utf8)
        generatedURLs.append(bodyMetricsDest)

        // 2. Generate Structured AllData.json
        let jsonDest = folderURL.appendingPathComponent("TotalFactor_AllData.json")
        let fullJSONData = try generateFullJSONData(context: context)
        try fullJSONData.write(to: jsonDest)
        generatedURLs.append(jsonDest)

        // 3. Generate AI Prompt-Ready Analysis Digest (.md)
        let mdDest = folderURL.appendingPathComponent("TotalFactor_AI_Digest.md")
        let digestMarkdown = generateAIDigestMarkdown(context: context)
        try digestMarkdown.write(to: mdDest, atomically: true, encoding: .utf8)
        generatedURLs.append(mdDest)

        return ExportPackage(
            folderURL: folderURL,
            fileURLs: generatedURLs,
            aiDigestURL: mdDest,
            fullJSONURL: jsonDest
        )
    }

    // MARK: - Body Metrics CSV

    @MainActor
    private static func generateBodyMetricsCSV(context: ModelContext) -> String {
        let metrics = ((try? context.fetch(FetchDescriptor<BodyMetric>())) ?? [])
            .sorted { $0.date < $1.date }

        var rows = ["Date,TimestampISO,MetricType,Value,Unit,HealthKitUUID"]
        let iso = ISO8601DateFormatter()

        for m in metrics {
            let unitStr = m.type == .bodyFat ? "%" : (m.type == .leanBodyMass ? "kg" : "cm")
            let cols: [String] = [
                escape(DayKey.from(m.date)),
                escape(iso.string(from: m.date)),
                escape(m.type.displayName),
                String(format: "%.2f", m.value),
                unitStr,
                escape(m.healthKitUUID?.uuidString ?? "")
            ]
            rows.append(cols.joined(separator: ","))
        }

        return rows.joined(separator: "\n")
    }

    // MARK: - Full Structured JSON Archive

    @MainActor
    private static func generateFullJSONData(context: ModelContext) throws -> Data {
        let profile = (try? context.fetch(FetchDescriptor<UserProfile>()))?.first
        let goals = (try? context.fetch(FetchDescriptor<Goal>())) ?? []
        let weighIns = (try? context.fetch(FetchDescriptor<WeighIn>()))?.sorted { $0.date < $1.date } ?? []
        let foodEntries = (try? context.fetch(FetchDescriptor<FoodLogEntry>()))?.sorted { $0.timestamp < $1.timestamp } ?? []
        let sessions = (try? context.fetch(FetchDescriptor<WorkoutSession>()))?.sorted { $0.start < $1.start } ?? []
        let metrics = (try? context.fetch(FetchDescriptor<BodyMetric>()))?.sorted { $0.date < $1.date } ?? []
        let photos = (try? context.fetch(FetchDescriptor<ProgressPhoto>()))?.sorted { $0.date < $1.date } ?? []

        let iso = ISO8601DateFormatter()

        let profileDict: [String: Any] = [
            "biologicalSex": profile?.biologicalSex.rawValue ?? "male",
            "heightCm": profile?.heightCm ?? 0,
            "unitSystem": profile?.unitSystem.rawValue ?? "imperial",
            "weighInRule": profile?.weighInRule.rawValue ?? "firstMorning",
            "carbCyclingEnabled": profile?.enableTrainingDayCarbCycling ?? false,
            "intermittentFastingEnabled": profile?.enableIntermittentFasting ?? false,
            "fastingProtocol": profile?.fastingProtocol.rawValue ?? "16:8"
        ]

        let goalsList: [[String: Any]] = goals.map { g in
            [
                "type": g.type.rawValue,
                "ratePercentPerWeek": g.ratePercentPerWeek,
                "targetWeightKg": g.targetWeightKg ?? 0,
                "isActive": g.isActive,
                "startDate": iso.string(from: g.startDate)
            ]
        }

        let weighInsList: [[String: Any]] = weighIns.map { w in
            [
                "dayKey": w.dayKey,
                "timestamp": iso.string(from: w.date),
                "weightKg": w.weightKg,
                "weightLb": UnitsFormatter.kgToLb(w.weightKg),
                "source": w.source.rawValue
            ]
        }

        let foodList: [[String: Any]] = foodEntries.map { f in
            let n = f.loggedNutrients
            return [
                "dayKey": f.dayKey,
                "timestamp": iso.string(from: f.timestamp),
                "foodName": f.foodName,
                "brand": f.foodBrand ?? "",
                "source": f.foodSource.rawValue,
                "mealTag": f.mealTag.rawValue,
                "servingLabel": f.servingLabel,
                "grams": f.grams,
                "calories": n.calories,
                "proteinG": n.protein,
                "carbsG": n.carbs,
                "fatG": n.fat,
                "fiberG": n.fiber,
                "sugarG": n.sugar,
                "sodiumMg": n.sodiumMg
            ]
        }

        let workoutsList: [[String: Any]] = sessions.map { s in
            let sets: [[String: Any]] = (s.sortedSets).filter(\.isCompleted).map { setLog in
                [
                    "order": setLog.order,
                    "exercise": setLog.exercise?.name ?? "Unknown",
                    "type": setLog.type.rawValue,
                    "weightKg": setLog.weightKg,
                    "weightLb": UnitsFormatter.kgToLb(setLog.weightKg),
                    "reps": setLog.reps,
                    "rir": setLog.rir,
                    "estimated1RMKg": setLog.estimated1RMKg
                ]
            }
            return [
                "dayKey": s.dayKey,
                "title": s.title,
                "start": iso.string(from: s.start),
                "end": s.end.map { iso.string(from: $0) } ?? "",
                "isFinished": s.isFinished,
                "sets": sets
            ]
        }

        let metricsList: [[String: Any]] = metrics.map { m in
            [
                "date": iso.string(from: m.date),
                "type": m.type.rawValue,
                "value": m.value
            ]
        }

        let photosList: [[String: Any]] = photos.map { p in
            [
                "dayKey": p.dayKey,
                "date": iso.string(from: p.date),
                "pose": p.pose.rawValue,
                "weightKgAtCapture": p.weightKgAtCapture ?? 0
            ]
        }

        let fullPayload: [String: Any] = [
            "exportVersion": "1.5.2",
            "exportTimestamp": iso.string(from: Date()),
            "profile": profileDict,
            "goals": goalsList,
            "weighIns": weighInsList,
            "foodLog": foodList,
            "workouts": workoutsList,
            "bodyMetrics": metricsList,
            "progressPhotos": photosList
        ]

        return try JSONSerialization.data(withJSONObject: fullPayload, options: [.prettyPrinted, .sortedKeys])
    }

    // MARK: - AI Prompt-Ready Markdown Analysis Digest

    @MainActor
    private static func generateAIDigestMarkdown(context: ModelContext) -> String {
        let digest = CoachingCoordinator.cachedOrComputeDigest(context: context)
        let profile = (try? context.fetch(FetchDescriptor<UserProfile>()))?.first
        let goal = (try? context.fetch(FetchDescriptor<Goal>()))?.first(where: \.isActive)
        let weighIns = (try? context.fetch(FetchDescriptor<WeighIn>()))?.sorted { $0.date < $1.date } ?? []
        let foodEntries = (try? context.fetch(FetchDescriptor<FoodLogEntry>()))?.sorted { $0.timestamp < $1.timestamp } ?? []
        let sessions = (try? context.fetch(FetchDescriptor<WorkoutSession>()))?.sorted { $0.start < $1.start } ?? []

        let system = profile?.unitSystem ?? .imperial

        let latestTrendKg = digest.weightSummary.latestTrendKg
        let latestScaleKg = digest.weightSummary.latestScaleKg
        let startWeightKg = weighIns.first?.weightKg

        var doc = """
        # Total Factor — Health & Fitness Coaching Data Digest
        **Exported:** \(DayKey.today)
        **App Version:** Total Factor v1.5.2 (Build 11)

        ---

        ## User Profile & Current Status
        - **Sex:** \(profile?.biologicalSex.displayName ?? "Not specified")
        - **Height:** \(profile.map { String(format: "%.1f cm (%.1f in)", $0.heightCm, $0.heightCm / 2.54) } ?? "Unknown")
        - **Unit System:** \(system.displayName)
        - **Active Goal:** \(goal?.type.displayName ?? "Maintenance") (\(String(format: "%.2f%% BW / wk", goal?.ratePercentPerWeek ?? 0)))
        - **Current Trend Weight:** \(latestTrendKg.map { UnitsFormatter.formatWeight($0, system: system) } ?? "N/A")
        - **Current Scale Weight:** \(latestScaleKg.map { UnitsFormatter.formatWeight($0, system: system) } ?? "N/A")
        - **Starting Weight:** \(startWeightKg.map { UnitsFormatter.formatWeight($0, system: system) } ?? "N/A")
        """

        if let startKg = startWeightKg, let currKg = latestTrendKg {
            let diffKg = currKg - startKg
            doc += "\n- **Net Trend Weight Change:** \(UnitsFormatter.formatSignedWeightDelta(diffKg, system: system))"
        }

        let exp = digest.expenditure
        let targets = digest.todayTargets
        doc += """

        - **Estimated Daily TDEE / Expenditure:** \(Int(exp.expenditureKcal.rounded())) kcal/day (\(exp.method.rawValue.capitalized), \(exp.confidence.displayName) Confidence)
        - **Caloric Intake Target:** \(Int(targets.calories.rounded())) kcal/day
        - **Macro Targets:** \(Int(targets.protein.rounded()))g Protein • \(Int(targets.carbs.rounded()))g Carbs • \(Int(targets.fat.rounded()))g Fat
        """

        // Daily aggregated matrix (last 60 days)
        doc += """


        ---

        ## Daily Nutrition, Weight & Workout Matrix (Last 60 Days)
        | Date | Calories (kcal) | Protein (g) | Carbs (g) | Fat (g) | Fiber (g) | Scale Weight | Trend Weight | Completed Workout |
        |---|---|---|---|---|---|---|---|---|
        """

        let calendar = Calendar.current
        let cutoffDate = calendar.date(byAdding: .day, value: -60, to: .now) ?? .distantPast
        let cutoffKey = DayKey.from(cutoffDate)

        let foodByDay = Dictionary(grouping: foodEntries.filter { $0.dayKey >= cutoffKey }, by: \.dayKey)
        let weighInByDay = Dictionary(grouping: weighIns.filter { $0.dayKey >= cutoffKey }, by: \.dayKey)
        let trendByDay = Dictionary(digest.weightSeries.map { ($0.dayKey, $0.trendKg) }, uniquingKeysWith: { _, b in b })
        let sessionsByDay = Dictionary(grouping: sessions.filter { $0.isFinished && $0.dayKey >= cutoffKey }, by: \.dayKey)

        var allDays = Set(foodByDay.keys)
            .union(weighInByDay.keys)
            .union(sessionsByDay.keys)
        if allDays.isEmpty {
            allDays.insert(DayKey.today)
        }

        for day in allDays.sorted(by: >) {
            let foods = foodByDay[day] ?? []
            let totalKcal = foods.reduce(0.0) { $0 + $1.loggedNutrients.calories }
            let totalP = foods.reduce(0.0) { $0 + $1.loggedNutrients.protein }
            let totalC = foods.reduce(0.0) { $0 + $1.loggedNutrients.carbs }
            let totalF = foods.reduce(0.0) { $0 + $1.loggedNutrients.fat }
            let totalFiber = foods.reduce(0.0) { $0 + $1.loggedNutrients.fiber }

            let scaleWeightStr = weighInByDay[day]?.last.map { UnitsFormatter.formatWeight($0.weightKg, system: system) } ?? "-"
            let trendWeightStr = trendByDay[day].map { UnitsFormatter.formatWeight($0, system: system) } ?? "-"

            let daySessions = sessionsByDay[day] ?? []
            let workoutStr = daySessions.isEmpty
                ? "-"
                : daySessions.map { s in
                    let count = (s.sortedSets).filter(\.isCompleted).count
                    return "\(s.title) (\(count) sets)"
                }.joined(separator: "; ")

            doc += "\n| \(day) | \(Int(totalKcal.rounded())) | \(Int(totalP.rounded())) | \(Int(totalC.rounded())) | \(Int(totalF.rounded())) | \(Int(totalFiber.rounded())) | \(scaleWeightStr) | \(trendWeightStr) | \(workoutStr) |"
        }

        // Strength 1RM PR records
        doc += """


        ---

        ## Strength Milestones & Personal Records
        | Exercise | Best Estimated 1RM | Top Set (Weight × Reps) |
        |---|---|---|
        """

        var exerciseBest1RM: [String: (oneRM: Double, bestSet: SetLog)] = [:]
        for s in sessions where s.isFinished {
            for setLog in s.sortedSets where setLog.isCompleted {
                guard let ex = setLog.exercise else { continue }
                let currentBest = exerciseBest1RM[ex.name]?.oneRM ?? 0
                if setLog.estimated1RMKg > currentBest {
                    exerciseBest1RM[ex.name] = (setLog.estimated1RMKg, setLog)
                }
            }
        }

        let sortedPRs = exerciseBest1RM.sorted { $0.value.oneRM > $1.value.oneRM }
        for (name, pr) in sortedPRs.prefix(15) {
            let loadStr = UnitsFormatter.formatGymLoad(pr.bestSet.weightKg, system: system)
            let oneRMStr = UnitsFormatter.formatGymLoad(pr.oneRM, system: system)
            doc += "\n| \(name) | \(oneRMStr) | \(loadStr) × \(pr.bestSet.reps) reps (RIR \(pr.bestSet.rir)) |"
        }

        // AI Coaching Instructions Prompt
        doc += """


        ---

        ## Prompt for AI Coaching & Deep Adherence Analysis
        *Copy and paste the instructions below together with this entire document into ChatGPT, Claude, or Google Gemini:*

        ```text
        You are an elite evidence-based sports nutritionist, physique scientist, and strength coach.
        Review my complete Total Factor fitness and dietary logs above and provide a comprehensive audit covering:

        1. ENERGY BALANCE & RATE OF LOSS/GAIN:
           - Compare my actual trend weight velocity against my daily caloric deficit/surplus and target rate.
           - Are metabolic adaptations or fluid retention masking fat loss or muscle gain?

        2. MACRONUTRIENT & DIETARY ADHERENCE:
           - Assess protein intake adequacy relative to preserving lean body mass during this phase.
           - Evaluate carbohydrate distribution relative to training days vs rest days.
           - Review dietary fiber and micronutrient density.

        3. TRAINING VOLUME & PROGRESSIVE OVERLOAD:
           - Analyze volume distribution and strength progression across major compound lifts.
           - Highlight any muscle groups that may be under-trained or accumulating excessive fatigue.

        4. 3 HIGH-IMPACT ACTIONABLE RECOMMENDATIONS:
           - Provide the 3 most impactful, specific adjustments to my caloric intake, daily habits, or training plan for the next 4 weeks.
        ```
        """

        return doc
    }

    private static func escape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            let doubled = value.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(doubled)\""
        }
        return value
    }
}
