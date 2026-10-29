import Foundation

public struct CarbCycledTargets: Codable, Hashable, Sendable {
    public var dailyAverage: MacroTargets
    public var trainingDay: MacroTargets
    public var restDay: MacroTargets
    public var trainingDaysPerWeek: Int

    public init(
        dailyAverage: MacroTargets,
        trainingDay: MacroTargets,
        restDay: MacroTargets,
        trainingDaysPerWeek: Int
    ) {
        self.dailyAverage = dailyAverage
        self.trainingDay = trainingDay
        self.restDay = restDay
        self.trainingDaysPerWeek = trainingDaysPerWeek
    }
}

public enum MacroTargetEngine {
    /// Calculates daily calorie & macro targets per spec §8:
    /// - Goal rate as % bodyweight per week (cut subtracts energy, bulk adds energy).
    /// - Calorie floor: never below `max(bmr, 1200 women / 1500 men)` without explicit override.
    /// - Protein: 2.0 g/kg when cutting, 1.8 g/kg otherwise (floor 1.6 g/kg).
    /// - Fat: `max(0.6 g/kg, 20% of calories)`.
    /// - Carbs: remaining calories.
    public static func calculateTargets(
        expenditureKcal: Double,
        goalType: GoalType,
        ratePercentPerWeek: Double,
        bodyWeightKg: Double,
        sex: BiologicalSex,
        bmrKcal: Double,
        overrideCalorieFloor: Bool = false
    ) -> MacroTargets {
        let magnitudePct = abs(ratePercentPerWeek)
        let signedRateKgPerWeek: Double
        switch goalType {
        case .cut:
            signedRateKgPerWeek = -(bodyWeightKg * (magnitudePct / 100.0))
        case .maintain:
            signedRateKgPerWeek = 0.0
        case .bulk:
            signedRateKgPerWeek = +(bodyWeightKg * (magnitudePct / 100.0))
        }

        let dailyEnergyDelta = (signedRateKgPerWeek * ExpenditureEngine.kcalPerKgBodyMass) / 7.0
        let rawTargetKcal = expenditureKcal + dailyEnergyDelta
        let minimumFloor = max(bmrKcal, sex.defaultCalorieFloor)

        let calorieFloorApplied: Bool
        let finalCalories: Double
        if !overrideCalorieFloor && rawTargetKcal < minimumFloor {
            finalCalories = minimumFloor.rounded()
            calorieFloorApplied = true
        } else {
            finalCalories = max(1000.0, rawTargetKcal).rounded()
            calorieFloorApplied = false
        }

        let proteinPerKg = (goalType == .cut) ? 2.0 : 1.8
        var proteinGrams = (bodyWeightKg * proteinPerKg).rounded()
        let proteinFloorGrams = (bodyWeightKg * 1.6).rounded()

        let fatFloorGrams = (bodyWeightKg * 0.6).rounded()
        let fatFromTwentyPercent = ((finalCalories * 0.20) / 9.0).rounded()
        var fatGrams = max(fatFloorGrams, fatFromTwentyPercent)

        // Ensure at least 40 g of carbs remain on aggressive cuts at high body mass
        let minCarbGrams = 40.0
        let maxProteinAndFatKcal = finalCalories - (minCarbGrams * 4.0)
        if (proteinGrams * 4.0 + fatGrams * 9.0) > maxProteinAndFatKcal {
            // Trim fat down toward fatFloor first, then trim protein toward proteinFloor
            let availableForFat = max(fatFloorGrams * 9.0, maxProteinAndFatKcal - proteinGrams * 4.0)
            fatGrams = max(30.0, min(fatGrams, (availableForFat / 9.0).rounded()))
            if (proteinGrams * 4.0 + fatGrams * 9.0) > maxProteinAndFatKcal {
                proteinGrams = max(proteinFloorGrams, ((maxProteinAndFatKcal - fatGrams * 9.0) / 4.0).rounded())
            }
        }

        let remainingKcal = max(0.0, finalCalories - (proteinGrams * 4.0) - (fatGrams * 9.0))
        let carbGrams = (remainingKcal / 4.0).rounded()

        // Fiber floor ~14g per 1000 kcal, clamped to [25, 45]
        let fiberFloor = min(45.0, max(25.0, ((finalCalories / 1000.0) * 14.0).rounded()))

        return MacroTargets(
            calories: finalCalories,
            protein: proteinGrams,
            carbs: carbGrams,
            fat: fatGrams,
            proteinFloor: min(proteinFloorGrams, proteinGrams),
            fatFloor: min(fatFloorGrams, fatGrams),
            fiberFloor: fiberFloor,
            sodiumCeilingMg: 2300,
            calorieFloorApplied: calorieFloorApplied
        )
    }

    /// Phase 8 (§12): Training-day vs rest-day carb cycling with exact weekly calorie conservation.
    /// `T * trainKcal + (7 - T) * restKcal == 7 * base.calories`.
    public static func carbCycledTargets(
        base: MacroTargets,
        trainingDaysPerWeek: Int,
        trainingCarbBoostFraction: Double = 0.15
    ) -> CarbCycledTargets {
        let tDays = min(max(trainingDaysPerWeek, 0), 7)
        let rDays = 7 - tDays
        guard tDays > 0 && rDays > 0 && base.carbs >= 60 else {
            return CarbCycledTargets(
                dailyAverage: base,
                trainingDay: base,
                restDay: base,
                trainingDaysPerWeek: tDays
            )
        }

        let maxExtraCarbsFromRestBudget = ((base.carbs - 40.0) * Double(rDays)) / Double(tDays)
        let desiredExtraTrainCarbs = min(base.carbs * trainingCarbBoostFraction, maxExtraCarbsFromRestBudget).rounded()
        let restCarbReduction = (desiredExtraTrainCarbs * Double(tDays)) / Double(rDays)

        let trainCarbs = base.carbs + desiredExtraTrainCarbs
        let restCarbs = max(35.0, (base.carbs - restCarbReduction).rounded())

        let trainKcal = (base.protein * 4.0) + (trainCarbs * 4.0) + (base.fat * 9.0)
        // Compute rest calories to preserve the exact 7-day calorie budget
        let weeklyBudget = base.calories * 7.0
        let restKcal = ((weeklyBudget - (trainKcal * Double(tDays))) / Double(rDays)).rounded()

        let trainTargets = MacroTargets(
            calories: trainKcal.rounded(),
            protein: base.protein,
            carbs: trainCarbs,
            fat: base.fat,
            proteinFloor: base.proteinFloor,
            fatFloor: base.fatFloor,
            fiberFloor: base.fiberFloor,
            sodiumCeilingMg: base.sodiumCeilingMg,
            calorieFloorApplied: base.calorieFloorApplied
        )

        let restTargets = MacroTargets(
            calories: restKcal,
            protein: base.protein,
            carbs: restCarbs,
            fat: base.fat,
            proteinFloor: base.proteinFloor,
            fatFloor: base.fatFloor,
            fiberFloor: base.fiberFloor,
            sodiumCeilingMg: base.sodiumCeilingMg,
            calorieFloorApplied: base.calorieFloorApplied
        )

        return CarbCycledTargets(
            dailyAverage: base,
            trainingDay: trainTargets,
            restDay: restTargets,
            trainingDaysPerWeek: tDays
        )
    }

    /// Builds floor / target / ceiling per nutrient for Today zone bars & Micronutrient panel (§8 & §13),
    /// applying any user-configured `NutrientZoneTarget` overrides from `NutrientTarget` SwiftData rows.
    public static func nutrientZones(
        for targets: MacroTargets,
        sex: BiologicalSex,
        customOverrides: [NutrientZoneTarget] = []
    ) -> [NutrientZoneTarget] {
        let defaults: [NutrientZoneTarget] = [
            NutrientZoneTarget(
                nutrient: "Calories",
                unit: "kcal",
                floor: (targets.calories * 0.92).rounded(),
                target: targets.calories,
                ceiling: (targets.calories * 1.05).rounded()
            ),
            NutrientZoneTarget(
                nutrient: "Protein",
                unit: "g",
                floor: targets.proteinFloor,
                target: targets.protein,
                ceiling: nil // Spec §8: protein has floor + target, no ceiling
            ),
            NutrientZoneTarget(
                nutrient: "Fat",
                unit: "g",
                floor: targets.fatFloor,
                target: targets.fat,
                ceiling: (targets.fat * 1.25).rounded()
            ),
            NutrientZoneTarget(
                nutrient: "Carbs",
                unit: "g",
                floor: nil,
                target: targets.carbs,
                ceiling: (targets.carbs * 1.20).rounded()
            ),
            NutrientZoneTarget(
                nutrient: "Fiber",
                unit: "g",
                floor: targets.fiberFloor,
                target: targets.fiberFloor + 6,
                ceiling: nil // Spec §8: fiber floor
            ),
            NutrientZoneTarget(
                nutrient: "Sugar",
                unit: "g",
                floor: nil,
                target: nil,
                ceiling: 50
            ),
            NutrientZoneTarget(
                nutrient: "Sodium",
                unit: "mg",
                floor: nil,
                target: nil,
                ceiling: targets.sodiumCeilingMg // Spec §8: sodium ceiling only
            ),
            NutrientZoneTarget(
                nutrient: MicronutrientKey.potassiumMg.displayName,
                unit: "mg",
                floor: sex == .male ? 3400 : 2600,
                target: sex == .male ? 3800 : 3000,
                ceiling: nil
            ),
            NutrientZoneTarget(
                nutrient: MicronutrientKey.calciumMg.displayName,
                unit: "mg",
                floor: 1000,
                target: 1200,
                ceiling: 2500
            ),
            NutrientZoneTarget(
                nutrient: MicronutrientKey.ironMg.displayName,
                unit: "mg",
                floor: sex == .male ? 8 : 18,
                target: sex == .male ? 11 : 18,
                ceiling: 45
            ),
            NutrientZoneTarget(
                nutrient: MicronutrientKey.vitaminDMcg.displayName,
                unit: "mcg",
                floor: 15,
                target: 25,
                ceiling: 100
            ),
            NutrientZoneTarget(
                nutrient: MicronutrientKey.vitaminCMg.displayName,
                unit: "mg",
                floor: sex == .male ? 90 : 75,
                target: sex == .male ? 120 : 100,
                ceiling: 2000
            ),
            NutrientZoneTarget(
                nutrient: MicronutrientKey.magnesiumMg.displayName,
                unit: "mg",
                floor: sex == .male ? 400 : 310,
                target: sex == .male ? 420 : 320,
                ceiling: nil
            ),
            NutrientZoneTarget(
                nutrient: MicronutrientKey.zincMg.displayName,
                unit: "mg",
                floor: sex == .male ? 11 : 8,
                target: sex == .male ? 14 : 10,
                ceiling: 40
            ),
            NutrientZoneTarget(
                nutrient: MicronutrientKey.cholesterolMg.displayName,
                unit: "mg",
                floor: nil,
                target: nil,
                ceiling: 300
            ),
            NutrientZoneTarget(
                nutrient: MicronutrientKey.saturatedFatG.displayName,
                unit: "g",
                floor: nil,
                target: nil,
                ceiling: ((targets.calories * 0.10) / 9.0).rounded()
            )
        ]

        guard !customOverrides.isEmpty else { return defaults }
        let overrideByName = Dictionary(
            customOverrides.map { ($0.nutrient.lowercased(), $0) },
            uniquingKeysWith: { _, latest in latest }
        )
        let defaultNames = Set(defaults.map { $0.nutrient.lowercased() })

        var merged = defaults.map { base -> NutrientZoneTarget in
            guard let custom = overrideByName[base.nutrient.lowercased()] else {
                return base
            }
            return NutrientZoneTarget(
                nutrient: base.nutrient,
                unit: custom.unit.isEmpty ? base.unit : custom.unit,
                floor: custom.floor,
                target: custom.target,
                ceiling: custom.ceiling
            )
        }

        for extra in customOverrides where !defaultNames.contains(extra.nutrient.lowercased()) {
            merged.append(extra)
        }
        return merged
    }

    /// Generates the plain-English one-line reason required by Weekly Check-In (§8).
    public static func checkInExplanation(
        previousCalories: Double,
        newCalories: Double,
        actualWeeklyChangeKg: Double,
        goalType: GoalType,
        goalRatePercent: Double,
        bodyWeightKg: Double,
        unitSystem: UnitSystem
    ) -> String {
        let kcalDelta = Int((newCalories - previousCalories).rounded())
        let actualStr = UnitsFormatter.formatSignedWeightDelta(actualWeeklyChangeKg, system: unitSystem)
        let goalSignedKg: Double = {
            switch goalType {
            case .cut: return -(bodyWeightKg * goalRatePercent / 100.0)
            case .maintain: return 0
            case .bulk: return +(bodyWeightKg * goalRatePercent / 100.0)
            }
        }()
        let goalStr = UnitsFormatter.formatSignedWeightDelta(goalSignedKg, system: unitSystem)

        if abs(kcalDelta) < 15 {
            return "Trend moved \(actualStr)/wk right on your \(goalStr)/wk target — keeping calories steady."
        } else if kcalDelta < 0 {
            return "Trend changed \(actualStr)/wk vs. your \(goalStr)/wk goal, so daily targets drop \(abs(kcalDelta)) kcal."
        } else {
            return "Trend changed \(actualStr)/wk vs. your \(goalStr)/wk goal, so daily targets increase \(kcalDelta) kcal."
        }
    }
}
