import Foundation
import AppIntents

public enum SiriMealSlot: String, AppEnum {
    case automatic = "auto"
    case breakfast = "breakfast"
    case lunch = "lunch"
    case dinner = "dinner"
    case snack = "snack"

    public static var typeDisplayRepresentation: TypeDisplayRepresentation = "Meal Period"

    public static var caseDisplayRepresentations: [SiriMealSlot: DisplayRepresentation] = [
        .automatic: "Automatic (By Time of Day)",
        .breakfast: "Breakfast",
        .lunch: "Lunch",
        .dinner: "Dinner",
        .snack: "Snack"
    ]

    public var resolvedMealTag: MealTag {
        switch self {
        case .automatic:
            let hour = Calendar.current.component(.hour, from: .now)
            if hour < 11 { return .breakfast }
            else if hour < 15 { return .lunch }
            else if hour < 21 { return .dinner }
            else { return .snack }
        case .breakfast: return .breakfast
        case .lunch: return .lunch
        case .dinner: return .dinner
        case .snack: return .snack
        }
    }
}

public struct LogFoodIntent: AppIntent {
    public static var title: LocalizedStringResource = "Log Food via Siri"
    public static var description = IntentDescription("Log foods or meals hands-free with Siri and Apple Intelligence using on-device USDA parsing.")

    @Parameter(
        title: "Food Description",
        description: "What you ate (e.g. 3 eggs and toast, or 200g chicken)",
        inputConnectionBehavior: .connectToPreviousIntentResult
    )
    public var foodDescription: String

    @Parameter(title: "Meal", default: .automatic)
    public var mealSlot: SiriMealSlot

    public init() {}

    public init(foodDescription: String, mealSlot: SiriMealSlot = .automatic) {
        self.foodDescription = foodDescription
        self.mealSlot = mealSlot
    }

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let trimmed = foodDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .result(dialog: "Please say what you ate, for example '3 scrambled eggs and toast'.")
        }

        let mealTag = mealSlot.resolvedMealTag
        let catalog = OfflineUSDACatalogService.shared.index
        let parsedItems = NaturalLanguageMealParser.parse(text: trimmed, offlineCatalog: catalog)

        var snap = SharedSnapshotStore.load()

        if parsedItems.isEmpty {
            let fallbackKcal = NaturalLanguageMealParser.extractExplicitCalorieNumber(from: trimmed) ?? 250.0
            let action = PendingQuickAction(
                kind: .loggedFoodEntry,
                numericValue: fallbackKcal,
                label: trimmed,
                protein: 0,
                carbs: 0,
                fat: 0,
                grams: 100,
                servingLabel: "1 entry",
                mealTagRaw: mealTag.rawValue
            )
            SharedSnapshotStore.enqueueAction(action)
            snap.caloriesEaten += fallbackKcal
            SharedSnapshotStore.save(snap)

            return .result(dialog: "Logged '\(trimmed)' (\(Int(fallbackKcal)) kcal) to \(mealTag.displayName) in Total Factor.")
        }

        var totalKcal: Double = 0
        var totalP: Double = 0
        var totalC: Double = 0
        var totalF: Double = 0
        var itemTitles: [String] = []

        for item in parsedItems {
            let nutrients = item.scaledNutrients
            totalKcal += nutrients.calories
            totalP += nutrients.protein
            totalC += nutrients.carbs
            totalF += nutrients.fat
            itemTitles.append(item.foodName)

            let action = PendingQuickAction(
                kind: .loggedFoodEntry,
                numericValue: nutrients.calories,
                label: item.foodName,
                protein: nutrients.protein,
                carbs: nutrients.carbs,
                fat: nutrients.fat,
                grams: item.grams,
                servingLabel: item.servingLabel,
                mealTagRaw: mealTag.rawValue
            )
            SharedSnapshotStore.enqueueAction(action)
        }

        snap.caloriesEaten += totalKcal
        snap.proteinEaten += totalP
        snap.carbsEaten += totalC
        snap.fatEaten += totalF
        SharedSnapshotStore.save(snap)

        let titleList = itemTitles.prefix(3).joined(separator: ", ") + (itemTitles.count > 3 ? " + \(itemTitles.count - 3) more" : "")
        let pGrams = Int(totalP.rounded())
        let calTotal = Int(totalKcal.rounded())

        return .result(dialog: "Logged \(titleList) (\(calTotal) kcal, \(pGrams)g protein) to \(mealTag.displayName).")
    }
}

public struct LogQuickCaloriesIntent: AppIntent {
    public static var title: LocalizedStringResource = "Log Quick Calories"
    public static var description = IntentDescription("Log calories and optional protein directly via Siri.")

    @Parameter(title: "Calories")
    public var calories: Double

    @Parameter(title: "Protein (g)", default: 0)
    public var protein: Double

    @Parameter(title: "Note", default: "Quick Add")
    public var note: String

    public init() {}

    public init(calories: Double, protein: Double = 0, note: String = "Quick Add") {
        self.calories = calories
        self.protein = protein
        self.note = note
    }

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        var snap = SharedSnapshotStore.load()
        let cal = max(1, calories)
        let prot = max(0, protein)

        let action = PendingQuickAction(
            kind: .loggedFoodEntry,
            numericValue: cal,
            label: note.isEmpty ? "Quick Add" : note,
            protein: prot,
            carbs: 0,
            fat: 0,
            grams: 100,
            servingLabel: "1 entry",
            mealTagRaw: MealTag.none.rawValue
        )
        SharedSnapshotStore.enqueueAction(action)
        snap.caloriesEaten += cal
        snap.proteinEaten += prot
        SharedSnapshotStore.save(snap)

        let calInt = Int(cal.rounded())
        if prot > 0 {
            return .result(dialog: "Logged \(calInt) calories and \(Int(prot.rounded()))g protein to Total Factor.")
        } else {
            return .result(dialog: "Logged \(calInt) calories to Total Factor.")
        }
    }
}

public struct LogWeightIntent: AppIntent {
    public static var title: LocalizedStringResource = "Log Body Weight"
    public static var description = IntentDescription("Logs a body weight weigh-in in Total Factor and syncs to Apple Health.")

    @Parameter(title: "Weight")
    public var weight: Double

    public init() {}

    public init(weight: Double) {
        self.weight = weight
    }

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        var snap = SharedSnapshotStore.load()
        let unit = UnitSystem(rawValue: snap.unitSystemRaw) ?? .imperial
        let kg = UnitsFormatter.internalKg(fromDisplay: weight, system: unit)

        SharedSnapshotStore.enqueueAction(
            PendingQuickAction(kind: .weighInKg, numericValue: kg, label: "Siri Weigh-In")
        )
        snap.latestScaleWeightKg = kg
        if let prevTrend = snap.trendWeightKg {
            snap.trendWeightKg = prevTrend + 0.1 * (kg - prevTrend)
        } else {
            snap.trendWeightKg = kg
        }
        SharedSnapshotStore.save(snap)

        let formatted = UnitsFormatter.formatWeight(kg, system: unit)
        let trendFormatted = UnitsFormatter.formatWeight(snap.trendWeightKg ?? kg, system: unit)
        return .result(dialog: "Logged \(formatted). Your trend weight is \(trendFormatted).")
    }
}

public struct RemainingProteinIntent: AppIntent {
    public static var title: LocalizedStringResource = "Check Remaining Protein & Calories"
    public static var description = IntentDescription("Tells you how much protein and calories you have left today.")

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let snap = SharedSnapshotStore.load()
        let pLeft = Int(max(0, snap.proteinTarget - snap.proteinEaten).rounded())
        let calLeft = Int((snap.caloriesTarget - snap.caloriesEaten).rounded())
        if calLeft >= 0 {
            return .result(dialog: "You have \(pLeft) grams of protein and \(calLeft) calories remaining today.")
        } else {
            return .result(dialog: "You have \(pLeft) grams of protein left and are \(abs(calLeft)) calories over target today.")
        }
    }
}

public struct StartWorkoutShortcutIntent: AppIntent {
    public static var title: LocalizedStringResource = "Start Strength Workout"
    public static var description = IntentDescription("Opens Total Factor and begins a workout session.")
    public static var openAppWhenRun: Bool = true

    @Parameter(title: "Workout Name", default: "Next Scheduled")
    public var workoutName: String

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        AppState.shared.selectedTab = .train
        AppState.shared.pendingShortcutWorkoutName = workoutName
        return .result(dialog: "Starting \(workoutName) in Total Factor.")
    }
}

public enum SiriCardioKind: String, AppEnum {
    case run
    case walk
    case inclineWalk
    case cycling
    case elliptical
    case stairClimber
    case rowing
    case swimming
    case other

    public static var typeDisplayRepresentation: TypeDisplayRepresentation = "Workout Type"

    public static var caseDisplayRepresentations: [SiriCardioKind: DisplayRepresentation] = [
        .run: "Run",
        .walk: "Walk",
        .inclineWalk: "Incline Walk / Hike",
        .cycling: "Cycling",
        .elliptical: "Elliptical",
        .stairClimber: "Stair Climber",
        .rowing: "Rowing",
        .swimming: "Swimming",
        .other: "Other Cardio / Fitness"
    ]
}

public enum SiriWeightUnit: String, AppEnum {
    case lbs
    case kg

    public static var typeDisplayRepresentation: TypeDisplayRepresentation = "Weight Unit"

    public static var caseDisplayRepresentations: [SiriWeightUnit: DisplayRepresentation] = [
        .lbs: "Pounds (lb)",
        .kg: "Kilograms (kg)"
    ]
}

public struct SyncHealthBridgeIntent: AppIntent {
    public static var title: LocalizedStringResource = "Sync Apple Health Snapshot"
    public static var description = IntentDescription("Imports daily steps, active calories, heart rate, HRV, sleep, or weight from Apple Shortcuts into Total Factor without needing HealthKit entitlements.")
    public static var openAppWhenRun: Bool = false

    @Parameter(title: "Steps")
    public var steps: Int?

    @Parameter(title: "Active Calories (kcal)")
    public var activeCalories: Double?

    @Parameter(title: "Resting Calories (kcal)")
    public var restingCalories: Double?

    @Parameter(title: "Resting Heart Rate (bpm)")
    public var restingHeartRate: Double?

    @Parameter(title: "HRV (ms)")
    public var hrvMs: Double?

    @Parameter(title: "Sleep Hours")
    public var sleepHours: Double?

    @Parameter(title: "Weight Value")
    public var weightValue: Double?

    @Parameter(title: "Weight Unit", default: .lbs)
    public var weightUnit: SiriWeightUnit

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let snap = SharedSnapshotStore.load()
        let weightKg: Double? = weightValue.flatMap { val in
            guard val > 20, val < 900 else { return nil }
            let kg = weightUnit == .lbs ? (val * 0.45359237) : val
            var updatedSnap = snap
            updatedSnap.latestScaleWeightKg = kg
            SharedSnapshotStore.save(updatedSnap)
            return kg
        }

        let payload = BridgedHealthPayload(
            steps: steps,
            activeCalories: activeCalories,
            basalCalories: restingCalories,
            restingHeartRateBPM: restingHeartRate,
            hrvSDNNMilliseconds: hrvMs,
            sleepHours: sleepHours,
            weightKg: weightKg
        )
        let encoded = (try? JSONEncoder().encode(payload)).flatMap { String(data: $0, encoding: .utf8) }
        SharedSnapshotStore.enqueueAction(
            PendingQuickAction(
                kind: .syncHealthBridge,
                numericValue: Double(steps ?? 0),
                label: "Apple Health Shortcuts Sync",
                payloadJSON: encoded
            )
        )
        let summary = ShortcutsHealthBridge.apply(payload, context: nil)
        return .result(dialog: "Synced with Total Factor: \(summary).")
    }
}

public struct ImportCardioWorkoutIntent: AppIntent {
    public static var title: LocalizedStringResource = "Import Fitness Workout"
    public static var description = IntentDescription("Logs a completed Apple Watch / Apple Fitness workout into Total Factor's cardio & activity log.")
    public static var openAppWhenRun: Bool = false

    @Parameter(title: "Workout Title", default: "Apple Fitness Workout")
    public var workoutTitle: String

    @Parameter(title: "Workout Type", default: .run)
    public var activityKind: SiriCardioKind

    @Parameter(title: "Duration (minutes)", default: 30)
    public var durationMinutes: Int

    @Parameter(title: "Active Calories (kcal)")
    public var activeCalories: Double?

    @Parameter(title: "Distance (km)")
    public var distanceKm: Double?

    @Parameter(title: "Average Heart Rate (bpm)")
    public var avgHeartRate: Double?

    @Parameter(title: "Source App", default: "Apple Fitness (Shortcuts)")
    public var sourceName: String

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let clampedMins = max(1, durationMinutes)
        let payload = BridgedHealthPayload(
            workoutTitle: workoutTitle,
            workoutKindRaw: activityKind.rawValue,
            workoutDurationSeconds: clampedMins * 60,
            workoutDistanceMeters: distanceKm.map { $0 * 1000.0 },
            workoutCalories: activeCalories,
            workoutAvgHeartRate: avgHeartRate,
            workoutSourceName: sourceName,
            workoutStartDate: Date.now.addingTimeInterval(-TimeInterval(clampedMins * 60))
        )
        let encoded = (try? JSONEncoder().encode(payload)).flatMap { String(data: $0, encoding: .utf8) }
        SharedSnapshotStore.enqueueAction(
            PendingQuickAction(
                kind: .syncHealthBridge,
                numericValue: Double(clampedMins),
                label: workoutTitle,
                payloadJSON: encoded
            )
        )
        _ = ShortcutsHealthBridge.apply(payload, context: nil)
        return .result(dialog: "Imported \(workoutTitle) (\(clampedMins) min) into Total Factor.")
    }
}

public struct TotalFactorShortcutsProvider: AppShortcutsProvider {
    public static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogFoodIntent(),
            phrases: [
                "Log food in \(.applicationName)",
                "Record meal in \(.applicationName)",
                "Log meal in \(.applicationName)",
                "Track food in \(.applicationName)",
                "Log food for \(\.$mealSlot) in \(.applicationName)"
            ],
            shortTitle: "Log Food",
            systemImageName: "fork.knife"
        )
        AppShortcut(
            intent: LogQuickCaloriesIntent(),
            phrases: [
                "Log calories in \(.applicationName)",
                "Quick calories in \(.applicationName)",
                "Record calories in \(.applicationName)"
            ],
            shortTitle: "Log Calories",
            systemImageName: "flame"
        )
        AppShortcut(
            intent: LogWeightIntent(),
            phrases: [
                "Log my weight in \(.applicationName)",
                "Record weigh in with \(.applicationName)"
            ],
            shortTitle: "Log Weight",
            systemImageName: "scalemass.fill"
        )
        AppShortcut(
            intent: RemainingProteinIntent(),
            phrases: [
                "How much protein do I have left in \(.applicationName)",
                "Macros remaining in \(.applicationName)"
            ],
            shortTitle: "Protein Left",
            systemImageName: "flame.fill"
        )
        AppShortcut(
            intent: StartWorkoutShortcutIntent(),
            phrases: [
                "Start workout in \(.applicationName)",
                "Begin training in \(.applicationName)"
            ],
            shortTitle: "Start Workout",
            systemImageName: "dumbbell.fill"
        )
        AppShortcut(
            intent: SyncHealthBridgeIntent(),
            phrases: [
                "Sync Apple Health to \(.applicationName)",
                "Update fitness stats in \(.applicationName)"
            ],
            shortTitle: "Sync Health Bridge",
            systemImageName: "heart.circle.fill"
        )
        AppShortcut(
            intent: ImportCardioWorkoutIntent(),
            phrases: [
                "Import cardio workout to \(.applicationName)",
                "Sync workout to \(.applicationName)"
            ],
            shortTitle: "Import Workout",
            systemImageName: "figure.run.circle.fill"
        )
    }
}
