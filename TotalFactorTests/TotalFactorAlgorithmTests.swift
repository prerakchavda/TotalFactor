import XCTest
#if canImport(TotalFactorCore)
@testable import TotalFactorCore
#else
@testable import TotalFactor
#endif

final class TotalFactorAlgorithmTests: XCTestCase {

    // MARK: - 1. Weight Trend EMA & Missing-Day Carry-Forward (§7)

    func testWeightTrendEMAAndMissingDaysCarryForward() {
        let cal = Calendar(identifier: .gregorian)
        let d1 = DayKey.date(from: "2026-10-01", calendar: cal)!
        let d4 = DayKey.date(from: "2026-10-04", calendar: cal)!

        let samples = [
            RawWeighInSample(timestamp: d1, dayKey: "2026-10-01", weightKg: 80.0),
            RawWeighInSample(timestamp: d4, dayKey: "2026-10-04", weightKg: 79.0)
        ]

        let series = WeightTrendEngine.buildDailySeries(
            samples: samples,
            rule: .firstMorning,
            alpha: 0.1,
            through: "2026-10-05",
            calendar: cal
        )

        XCTAssertEqual(series.count, 5)
        // Day 1: measured 80.0 -> trend 80.0
        XCTAssertEqual(series[0].scaleKg, 80.0)
        XCTAssertEqual(series[0].trendKg, 80.0, accuracy: 0.001)

        // Days 2 & 3: missing -> scaleKg MUST be nil (never fake weigh-ins) and trend carries forward unchanged!
        XCTAssertNil(series[1].scaleKg)
        XCTAssertEqual(series[1].trendKg, 80.0, accuracy: 0.001)
        XCTAssertNil(series[2].scaleKg)
        XCTAssertEqual(series[2].trendKg, 80.0, accuracy: 0.001)

        // Day 4: measured 79.0 -> trend = 80.0 + 0.1 * (79.0 - 80.0) = 79.9
        XCTAssertEqual(series[3].scaleKg, 79.0)
        XCTAssertEqual(series[3].trendKg, 79.9, accuracy: 0.001)

        // Day 5: missing -> carries 79.9 forward
        XCTAssertNil(series[4].scaleKg)
        XCTAssertEqual(series[4].trendKg, 79.9, accuracy: 0.001)
    }

    func testDailyWeighInResolutionRules() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!

        let morning = cal.date(from: DateComponents(year: 2026, month: 10, day: 10, hour: 7, minute: 30))!
        let evening = cal.date(from: DateComponents(year: 2026, month: 10, day: 10, hour: 20, minute: 0))!

        let samples = [
            RawWeighInSample(timestamp: morning, dayKey: "2026-10-10", weightKg: 80.0),
            RawWeighInSample(timestamp: evening, dayKey: "2026-10-10", weightKg: 81.4)
        ]

        let firstMap = WeightTrendEngine.resolveDailyScaleWeights(samples: samples, rule: .firstMorning, calendar: cal)
        let avgMap = WeightTrendEngine.resolveDailyScaleWeights(samples: samples, rule: .average, calendar: cal)
        let lastMap = WeightTrendEngine.resolveDailyScaleWeights(samples: samples, rule: .last, calendar: cal)

        XCTAssertEqual(firstMap["2026-10-10"]!, 80.0, accuracy: 0.001)
        XCTAssertEqual(avgMap["2026-10-10"]!, 80.7, accuracy: 0.001)
        XCTAssertEqual(lastMap["2026-10-10"]!, 81.4, accuracy: 0.001)
    }

    // MARK: - 2. 8-Week 500 kcal Deficit Adaptive Expenditure Simulation (§8 & §14)

    func testEightWeek500KcalDeficitSimulationLandsWithinFivePercent() {
        let cal = Calendar(identifier: .gregorian)
        let startKey = "2026-09-01"
        let trueTDEE = 2700.0
        let dailyIntake = 2200.0 // 500 kcal/day deficit
        let initialKg = 85.0

        var weighSamples: [RawWeighInSample] = []
        var intakeRecords: [DailyIntakeRecord] = []

        for dayOffset in 0..<56 {
            let key = DayKey.addingDays(dayOffset, to: startKey, calendar: cal)
            let dt = DayKey.date(from: key, calendar: cal)!
            let trueKg = initialKg - (500.0 / 7700.0) * Double(dayOffset)
            let waterNoise = 0.55 * sin(Double(dayOffset) * 1.7)

            // Skip weigh-in every 6th day to test real-world adherence
            if dayOffset == 0 || (dayOffset % 6 != 4) {
                weighSamples.append(RawWeighInSample(timestamp: dt, dayKey: key, weightKg: trueKg + waterNoise))
            }

            // Skip food logging every 9th day (even with a partial 400 kcal entry, `isComplete = false` must exclude it!)
            if dayOffset % 9 != 5 {
                intakeRecords.append(DailyIntakeRecord(dayKey: key, calories: dailyIntake, isComplete: true))
            } else {
                intakeRecords.append(DailyIntakeRecord(dayKey: key, calories: 400.0, isComplete: false))
            }
        }

        let endKey = DayKey.addingDays(55, to: startKey, calendar: cal)
        let weightSeries = WeightTrendEngine.buildDailySeries(
            samples: weighSamples,
            rule: .firstMorning,
            alpha: 0.1,
            through: endKey,
            calendar: cal
        )

        // Start intentionally with `.light` activity (~2499 kcal) so adaptive engine must climb +200 kcal to 2700!
        let trajectory = ExpenditureEngine.computeTrajectory(
            sex: .male,
            initialWeightKg: initialKg,
            heightCm: 178.0,
            ageYears: 30,
            activityLevel: .light,
            intakes: intakeRecords,
            weightSeries: weightSeries,
            through: endKey,
            calendar: cal
        )

        guard let finalSnapshot = trajectory.last else {
            XCTFail("Expected non-empty expenditure trajectory")
            return
        }

        let relativeError = abs(finalSnapshot.expenditureKcal - trueTDEE) / trueTDEE
        XCTAssertLessThan(relativeError, 0.05, "Expected 8-week expenditure within 5% of \(trueTDEE), got \(finalSnapshot.expenditureKcal)")
        XCTAssertEqual(finalSnapshot.confidence, .high)
        XCTAssertEqual(finalSnapshot.method, .adaptive)
    }

    func testExpenditureClampLimitsSingleUpdateTo100Kcal() {
        let clampedUp = ExpenditureEngine.blended(previous: 2400, raw: 3800, weight: 0.5)
        XCTAssertEqual(clampedUp, 2500, accuracy: 0.01)

        let clampedDown = ExpenditureEngine.blended(previous: 2400, raw: 1100, weight: 0.5)
        XCTAssertEqual(clampedDown, 2300, accuracy: 0.01)
    }

    // MARK: - 3. Target Math, Calorie Floor & Training-Day Carb Cycling (§8 & §12)

    func testMacroTargetMathAndCalorieFloorEnforcement() {
        let bmr = ExpenditureEngine.mifflinStJeorBMR(sex: .male, weightKg: 80.0, heightCm: 180.0, ageYears: 28)
        // Extreme 1.5%/wk cut from low expenditure should hit BMR floor without override
        let floored = MacroTargetEngine.calculateTargets(
            expenditureKcal: 2050,
            goalType: .cut,
            ratePercentPerWeek: 1.2,
            bodyWeightKg: 80.0,
            sex: .male,
            bmrKcal: bmr,
            overrideCalorieFloor: false
        )
        XCTAssertTrue(floored.calorieFloorApplied)
        XCTAssertGreaterThanOrEqual(floored.calories, max(bmr.rounded(), 1500))
        XCTAssertEqual(floored.protein, 160.0, accuracy: 1.0) // 2.0 g/kg when cutting
        XCTAssertGreaterThanOrEqual(floored.fat, 48.0)       // >= 0.6 g/kg floor
        XCTAssertGreaterThanOrEqual(floored.carbs, 40.0)
    }

    func testTrainingDayCarbCyclingPreservesWeeklyCalories() {
        let base = MacroTargets(
            calories: 2400,
            protein: 165,
            carbs: 260,
            fat: 75,
            proteinFloor: 132,
            fatFloor: 50
        )
        let cycled = MacroTargetEngine.carbCycledTargets(base: base, trainingDaysPerWeek: 4)

        XCTAssertGreaterThan(cycled.trainingDay.carbs, cycled.restDay.carbs)
        XCTAssertEqual(cycled.trainingDay.protein, cycled.restDay.protein)

        let weeklyCycled = (cycled.trainingDay.calories * 4.0) + (cycled.restDay.calories * 3.0)
        let weeklyBase = base.calories * 7.0
        XCTAssertEqual(weeklyCycled, weeklyBase, accuracy: 4.0)
    }

    // MARK: - 4. Effort e1RM, Personal k-Curve & Smart Progression (§11 & §12)

    func testPersonalRepCurveKFittingDistinguishesEnduranceVsFastTwitch() {
        let baseDate = Date()

        // Endurance lifter (true k = 38, true 1RM = 140 kg)
        let enduranceSamples: [LoggedSetSample] = [3, 5, 8, 10, 12, 15].enumerated().map { idx, effReps in
            let w = 140.0 / (1.0 + Double(effReps) / 38.0)
            return LoggedSetSample(sessionDate: baseDate.addingTimeInterval(Double(idx) * 86_400), weightKg: w, reps: effReps - 1, rir: 1)
        }

        // Fast-twitch lifter (true k = 23, true 1RM = 140 kg)
        let fastTwitchSamples: [LoggedSetSample] = [3, 5, 8, 10, 12, 15].enumerated().map { idx, effReps in
            let w = 140.0 / (1.0 + Double(effReps) / 23.0)
            return LoggedSetSample(sessionDate: baseDate.addingTimeInterval(Double(idx) * 86_400), weightKg: w, reps: effReps - 1, rir: 1)
        }

        let fittedEnduranceK = ProgressionEngine.fitPersonalRepCurveK(samples: enduranceSamples)
        let fittedFastK = ProgressionEngine.fitPersonalRepCurveK(samples: fastTwitchSamples)

        XCTAssertGreaterThan(fittedEnduranceK, 34.5)
        XCTAssertLessThan(fittedFastK, 25.5)
    }

    func testSmartProgressionProteinGateAndCutAwareDeloadSuppression() {
        let cal = Calendar(identifier: .gregorian)
        let d1 = DayKey.date(from: "2026-10-01", calendar: cal)!
        let d2 = DayKey.date(from: "2026-10-05", calendar: cal)!
        let d3 = DayKey.date(from: "2026-10-09", calendar: cal)!
        let d4 = DayKey.date(from: "2026-10-13", calendar: cal)!

        // Case A: Hit top of 6-10 rep range cleanly (100 kg x 10 @ 2 RIR), but protein was under floor -> Protein Gate!
        let topRangeHistory = [
            LoggedSetSample(sessionDate: d1, weightKg: 100.0, reps: 10, rir: 2)
        ]
        let gated = ProgressionEngine.suggestNextSession(
            history: topRangeHistory,
            repRangeLow: 6,
            repRangeHigh: 10,
            targetRIR: 2,
            loadIncrementKg: 2.5,
            avgProteinLast7d: 115.0,
            proteinFloor: 140.0
        )
        XCTAssertEqual(gated.action, .holdDueToProteinGate)
        XCTAssertTrue(gated.isProteinGated)
        XCTAssertEqual(gated.suggestedWeightKg, 100.0, accuracy: 0.01)

        // Same history with adequate protein -> Adds load!
        let progressed = ProgressionEngine.suggestNextSession(
            history: topRangeHistory,
            repRangeLow: 6,
            repRangeHigh: 10,
            targetRIR: 2,
            loadIncrementKg: 2.5,
            avgProteinLast7d: 165.0,
            proteinFloor: 140.0
        )
        XCTAssertEqual(progressed.action, .addWeight)
        XCTAssertGreaterThanOrEqual(progressed.suggestedWeightKg, 102.5)

        // Case B: Slight 3-session dip (<3%) during steep cut (-0.75% BW/wk) -> Cut-Aware holds steady instead of deloading!
        let slightDipHistory = [
            LoggedSetSample(sessionDate: d1, weightKg: 100.0, reps: 8, rir: 2),
            LoggedSetSample(sessionDate: d2, weightKg: 100.0, reps: 8, rir: 1),
            LoggedSetSample(sessionDate: d3, weightKg: 99.0, reps: 8, rir: 1),
            LoggedSetSample(sessionDate: d4, weightKg: 98.0, reps: 8, rir: 1)
        ]
        let cutSuggestion = ProgressionEngine.suggestNextSession(
            history: slightDipHistory,
            repRangeLow: 6,
            repRangeHigh: 10,
            targetRIR: 2,
            loadIncrementKg: 2.5,
            weeklyWeightChangePercentBW: -0.75
        )
        XCTAssertEqual(cutSuggestion.action, .holdSteadyOnCut)
        XCTAssertTrue(cutSuggestion.isCutAdjusted)
    }

    // MARK: - 5. Plate Calculator, Label OCR & Food Quality Validator (§4, §9, §13)

    func testBarbellPlateCalculator() {
        // 100 kg total on a 20 kg bar = 40 kg per side = [25, 15]
        let breakdown = ProgressionEngine.calculatePlatesPerSide(
            targetWeightKg: 100.0,
            barWeightKg: 20.0,
            availablePlatesKg: [25, 20, 15, 10, 5, 2.5, 1.25]
        )
        XCTAssertEqual(breakdown.platesPerSide, [25.0, 15.0])
        XCTAssertEqual(breakdown.achievedWeightKg, 100.0, accuracy: 0.01)
    }

    func testNutritionLabelOCRParserAndQualityFlag() {
        let ocrLines = [
            "Nutrition Facts",
            "Serving size 1 bar (60g)",
            "Calories",
            "210",
            "Total Fat 7g",
            "Sodium 190mg",
            "Total Carbohydrate 22g",
            "Dietary Fiber 5g",
            "Total Sugars 2g",
            "Protein 20g"
        ]
        let parsed = NutritionLabelParser.parse(lines: ocrLines)
        XCTAssertTrue(parsed.isUsable)
        XCTAssertEqual(parsed.servingGrams, 60.0, accuracy: 0.1)
        XCTAssertEqual(parsed.perServing.calories, 210.0, accuracy: 0.1)
        XCTAssertEqual(parsed.perServing.protein, 20.0, accuracy: 0.1)
        XCTAssertEqual(parsed.perServing.carbs, 22.0, accuracy: 0.1)
        XCTAssertEqual(parsed.perServing.fat, 7.0, accuracy: 0.1)
        XCTAssertEqual(parsed.perServing.sodiumMg, 190.0, accuracy: 0.1)

        // Verify >15% Atwater discrepancy check
        let badCrowdsourced = NutrientsPer100g(calories: 100, protein: 30, carbs: 25, fat: 10) // implies 310 kcal!
        let check = FoodSearchRanker.validateMacroCalorieConsistency(nutrients: badCrowdsourced)
        XCTAssertTrue(check.isFlagged)
    }

    func testDetectSessionPRsIncludesMostRepsAtWeightAndRejectsLighterSubPR() {
        let cal = Calendar(identifier: .gregorian)
        let d1 = DayKey.date(from: "2026-10-01", calendar: cal)!
        let d2 = DayKey.date(from: "2026-10-08", calendar: cal)!
        let d3 = DayKey.date(from: "2026-10-15", calendar: cal)!

        let priorHistory = [
            LoggedSetSample(sessionDate: d1, weightKg: 100.0, reps: 9, rir: 1),
            LoggedSetSample(sessionDate: d2, weightKg: 105.0, reps: 5, rir: 1)
        ]

        // Hitting 100 kg x 11 beats max reps ever performed at >= 100 kg (9 reps) -> Rep PR!
        let repPRSession = [
            LoggedSetSample(sessionDate: d3, weightKg: 100.0, reps: 11, rir: 1),
            LoggedSetSample(sessionDate: d3, weightKg: 100.0, reps: 10, rir: 1)
        ]
        let detected = ProgressionEngine.detectSessionPRs(
            priorSets: priorHistory,
            sessionSets: repPRSession,
            calendar: cal
        )
        let repPR = detected.first { $0.type == .mostRepsAtWeight }
        XCTAssertNotNil(repPR)
        XCTAssertEqual(repPR?.value ?? 0, 11.0, accuracy: 0.01)
        XCTAssertEqual(repPR?.secondaryValue ?? 0, 100.0, accuracy: 0.01)
        XCTAssertFalse(detected.contains { $0.type == .heaviestWeight })
        XCTAssertTrue(detected.contains { $0.type == .bestSessionVolume })

        // Hitting 95 kg x 8 should NOT trigger a Rep PR because 100 kg x 9 already did more reps at a heavier weight
        let subPRSession = [
            LoggedSetSample(sessionDate: d3, weightKg: 95.0, reps: 8, rir: 2)
        ]
        let subDetected = ProgressionEngine.detectSessionPRs(
            priorSets: priorHistory,
            sessionSets: subPRSession,
            calendar: cal
        )
        XCTAssertFalse(subDetected.contains { $0.type == .mostRepsAtWeight })
    }

    func testInlineQuantityCalculatorOverwriteAndKitchenScaleMath() {
        var calc = InlineQuantityCalculator(initialText: "150", isPreselected: true)
        XCTAssertTrue(calc.isPreselected)
        XCTAssertEqual(calc.evaluatedValue, 150.0, accuracy: 0.01)

        // First digit overwrites pre-selected remembered amount; "00" makes 200g in 2 taps!
        calc.tap(.two)
        XCTAssertFalse(calc.isPreselected)
        XCTAssertEqual(calc.expression, "2")
        calc.tap(.doubleZero)
        XCTAssertEqual(calc.expression, "200")
        XCTAssertEqual(calc.evaluatedValue, 200.0, accuracy: 0.01)

        // Kitchen scale inline addition: 200 + 65 = 265g
        calc.tap(.plus)
        XCTAssertEqual(calc.evaluatedValue, 200.0, accuracy: 0.01) // trailing '+' stays safe
        calc.tap(.six)
        calc.tap(.five)
        XCTAssertEqual(calc.expression, "200+65")
        XCTAssertEqual(calc.evaluatedValue, 265.0, accuracy: 0.01)

        calc.tap(.equals)
        XCTAssertEqual(calc.expression, "265")
        XCTAssertEqual(calc.evaluatedValue, 265.0, accuracy: 0.01)

        // Kitchen scale tare subtraction math (§MacroFactor Kitchen): 265 - 65 = 200g
        calc.tap(.minus)
        XCTAssertEqual(calc.evaluatedValue, 265.0, accuracy: 0.01) // trailing '-' evaluates safely
        calc.tap(.six)
        calc.tap(.five)
        XCTAssertEqual(calc.expression, "265-65")
        XCTAssertEqual(calc.evaluatedValue, 200.0, accuracy: 0.01)
        calc.tap(.equals)
        XCTAssertEqual(calc.expression, "200")
        XCTAssertEqual(calc.evaluatedValue, 200.0, accuracy: 0.01)
    }

    // MARK: - 6. Strong CSV Workout Importer, Planet Fitness Split & Exercise Guides

    func testStrongCSVParserRepairsSwappedWeightRepsAndCapsForgottenTimers() {
        let csv = """
        Date,Workout Name,Duration,Exercise Name,Set Order,Weight,Reps,Distance,Seconds,Notes,Workout Notes,RPE
        2025-08-30 14:10:00,Back and Biceps,238h 49m,Seated Row (Machine),1,7.0,140.0,0,0,,,
        2025-08-30 14:10:00,Back and Biceps,238h 49m,Seated Row (Machine),Rest Timer,0,0,0,120,,,
        2026-10-20 17:30:00,Push,43s,Pec Deck (Machine),1,175.0,8.0,0,0,"Deep stretch",,9
        """

        let sessions = StrongCSVParser.parse(csvContent: csv, sourceUnitSystem: .imperial)
        XCTAssertEqual(sessions.count, 2)

        // Session 1: Swapped 7.0 lb x 140 reps -> repaired to 140 lb (~63.50 kg) x 7 reps, Rest Timer row skipped, 238h capped!
        let s1 = sessions[0]
        XCTAssertEqual(s1.workoutName, "Back and Biceps")
        XCTAssertEqual(s1.sets.count, 1)
        XCTAssertEqual(s1.sets[0].canonicalExerciseName, "Seated Machine Row")
        XCTAssertEqual(s1.sets[0].reps, 7)
        XCTAssertEqual(s1.sets[0].weightKg, UnitsFormatter.lbToKg(140.0), accuracy: 0.02)
        let dur1 = s1.endDate.timeIntervalSince(s1.startDate)
        XCTAssertGreaterThanOrEqual(dur1, 15 * 60)
        XCTAssertLessThanOrEqual(dur1, 90 * 60)

        // Session 2: 175 lb x 8 @ RPE 9 -> RIR 1, 43s stub normalized to realistic duration
        let s2 = sessions[1]
        XCTAssertEqual(s2.workoutName, "Push")
        XCTAssertEqual(s2.sets[0].canonicalExerciseName, "Pec Deck / Machine Fly")
        XCTAssertEqual(s2.sets[0].reps, 8)
        XCTAssertEqual(s2.sets[0].rir, 1)
        XCTAssertEqual(s2.sets[0].weightKg, UnitsFormatter.lbToKg(175.0), accuracy: 0.02)
        XCTAssertGreaterThanOrEqual(s2.endDate.timeIntervalSince(s2.startDate), 15 * 60)
    }

    func testBundledStrongWorkoutsAndExerciseGuidesIntegrity() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let csvURL = repoRoot.appendingPathComponent("TotalFactor/Resources/BundledStrongWorkouts.csv")
        let exercisesURL = repoRoot.appendingPathComponent("TotalFactor/Resources/BundledExercises.json")

        guard FileManager.default.fileExists(atPath: csvURL.path),
              FileManager.default.fileExists(atPath: exercisesURL.path) else {
            return
        }

        let csvContent = try String(contentsOf: csvURL, encoding: .utf8)
        let sessions = StrongCSVParser.parse(csvContent: csvContent, sourceUnitSystem: .imperial)
        XCTAssertEqual(sessions.count, 124)

        let totalSets = sessions.reduce(0) { $0 + $1.sets.count }
        XCTAssertGreaterThan(totalSets, 1200)

        struct ExerciseCheckDTO: Decodable {
            var name: String
            var primaryMuscles: [MuscleGroup]
            var secondaryMuscles: [MuscleGroup]
            var equipment: Equipment
            var movementPattern: MovementPattern
            var loadIncrementKg: Double
            var mediaKey: String?
            var setupTip: String?
            var steps: [String]?
        }

        let exData = try Data(contentsOf: exercisesURL)
        let catalog = try JSONDecoder().decode([ExerciseCheckDTO].self, from: exData)
        XCTAssertGreaterThanOrEqual(catalog.count, 96)

        let byLower = Dictionary(uniqueKeysWithValues: catalog.map { ($0.name.lowercased(), $0) })
        for session in sessions {
            for setItem in session.sets {
                let match = byLower[setItem.canonicalExerciseName.lowercased()]
                XCTAssertNotNil(match, "Missing canonical exercise in BundledExercises.json: \(setItem.canonicalExerciseName)")
                XCTAssertFalse((match?.steps ?? []).isEmpty, "Missing guide steps for \(setItem.canonicalExerciseName)")
            }
        }

        // Verify Planet Fitness Split blueprint maps cleanly onto catalog
        let pool = catalog.map {
            ExerciseBlueprint(
                name: $0.name,
                primaryMuscles: $0.primaryMuscles,
                secondaryMuscles: $0.secondaryMuscles,
                equipment: $0.equipment,
                movementPattern: $0.movementPattern,
                loadIncrementKg: $0.loadIncrementKg
            )
        }
        let pfSplit = ProgramGeneratorEngine.planetFitnessProgramBlueprint(exercisePool: pool)
        XCTAssertEqual(pfSplit.name, "Planet Fitness Split")
        XCTAssertEqual(pfSplit.workouts.map(\.name), ["Push", "Back and Biceps", "Lower", "Upper"])
        for w in pfSplit.workouts {
            XCTAssertGreaterThanOrEqual(w.slots.count, 6)
            for s in w.slots {
                XCTAssertNotEqual(s.exercise.equipment, .barbell, "Planet Fitness Split should avoid free Olympic barbells")
            }
        }
    }

    // MARK: - 7. Full ~8,156-Food Offline USDA Catalog, Natural-Language Meal Parser, Custom Nutrient Zones & Watch Sync

    func testFullOfflineUSDACatalogIndexAndDeduplicatedRanking() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let usdaURL = repoRoot.appendingPathComponent("TotalFactor/Resources/BundledUSDAFoods.json")
        guard FileManager.default.fileExists(atPath: usdaURL.path) else {
            XCTFail("Expected BundledUSDAFoods.json at \(usdaURL.path)")
            return
        }

        let data = try Data(contentsOf: usdaURL)
        let catalog = try OfflineUSDACatalogIndex(jsonData: data)
        XCTAssertGreaterThan(catalog.count, 8000, "Bundled USDA Foundation + SR Legacy catalog should exceed 8,000 foods")

        // Singular/plural inverted token index should match plural queries cleanly
        let blueberryHits = catalog.searchCandidates(query: "blueberries", limit: 15)
        XCTAssertFalse(blueberryHits.isEmpty)

        let chickenHits = catalog.searchCandidates(query: "chicken breasts cooked", limit: 20)
        XCTAssertFalse(chickenHits.isEmpty)
        let topChicken = chickenHits[0]
        XCTAssertEqual(catalog.entry(forID: topChicken.id)?.sourceID, topChicken.sourceID)

        // Deduplication: if user already logged/favorited `topChicken` in SwiftData, `rankWithOfflineCatalog`
        // keeps the user's persisted candidate at #1 without duplicating the offline USDA row!
        let persistedClone = RankableFoodCandidate(
            id: UUID(),
            sourceID: topChicken.sourceID,
            name: topChicken.name,
            brand: topChicken.brand,
            source: .usda,
            isFavorite: true,
            useCount: 14,
            lastUsed: .now,
            nutrientsPer100g: topChicken.nutrientsPer100g
        )
        let merged = FoodSearchRanker.rankWithOfflineCatalog(
            persistedCandidates: [persistedClone],
            offlineCatalog: catalog,
            query: "chicken breast",
            limit: 30
        )
        XCTAssertEqual(merged.first?.id, Optional(persistedClone.id))
        let matchingSourceCount = merged.filter { $0.sourceID == topChicken.sourceID }.count
        XCTAssertEqual(matchingSourceCount, 1, "Materialized USDA food should not appear twice alongside offline catalog")
    }

    func testNaturalLanguageMealParserMultiItemQuantitiesAndUnits() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let usdaURL = repoRoot.appendingPathComponent("TotalFactor/Resources/BundledUSDAFoods.json")
        let catalog: OfflineUSDACatalogIndex
        if FileManager.default.fileExists(atPath: usdaURL.path) {
            catalog = try OfflineUSDACatalogIndex(jsonData: Data(contentsOf: usdaURL))
        } else {
            catalog = OfflineUSDACatalogIndex(entries: [
                OfflineUSDAFoodEntry(sourceID: "t1", name: "Egg, whole, cooked", calories: 155, protein: 12.6, carbs: 1.1, fat: 10.6, servingSizes: [ServingSize(label: "1 large", grams: 50)]),
                OfflineUSDAFoodEntry(sourceID: "t2", name: "Oats, rolled, dry", calories: 379, protein: 13.2, carbs: 67.7, fat: 6.5, servingSizes: [ServingSize(label: "0.5 cup", grams: 40)]),
                OfflineUSDAFoodEntry(sourceID: "t3", name: "Greek yogurt, nonfat, plain", calories: 59, protein: 10.3, carbs: 3.6, fat: 0.4, servingSizes: [ServingSize(label: "100 g", grams: 100)]),
                OfflineUSDAFoodEntry(sourceID: "t4", name: "Peanut butter, smooth", calories: 588, protein: 25.0, carbs: 20.0, fat: 50.0, servingSizes: [ServingSize(label: "1 tbsp", grams: 16)])
            ])
        }

        let items = NaturalLanguageMealParser.parse(
            text: "3 eggs, 80g oats, 200 g greek yogurt and 1.5 tbsp peanut butter",
            offlineCatalog: catalog
        )
        XCTAssertEqual(items.count, 4)

        // Item 2: explicit 80g mass should resolve to 80g exact
        XCTAssertEqual(items[1].grams, 80.0, accuracy: 0.5)
        // Item 3: explicit 200g mass should resolve to 200g exact
        XCTAssertEqual(items[2].grams, 200.0, accuracy: 0.5)
        // Item 4: 1.5 tbsp peanut butter (~24g)
        XCTAssertGreaterThan(items[3].grams, 20.0)
        XCTAssertLessThan(items[3].grams, 30.0)
        XCTAssertGreaterThan(items.reduce(0.0) { $0 + $1.scaledNutrients.protein }, 40.0)
    }

    func testCustomNutrientZoneTargetOverridesAndExpandedMicronutrients() {
        let baseTargets = MacroTargetEngine.calculateTargets(
            expenditureKcal: 2650,
            goalType: .cut,
            ratePercentPerWeek: 0.5,
            bodyWeightKg: 82.0,
            sex: .male,
            bmrKcal: 1820
        )

        let customZones = [
            NutrientZoneTarget(nutrient: "Sodium", unit: "mg", floor: 1500, target: 2500, ceiling: 3500),
            NutrientZoneTarget(nutrient: "Vitamin D", unit: "mcg", floor: 50, target: 75, ceiling: 100)
        ]

        let merged = MacroTargetEngine.nutrientZones(
            for: baseTargets,
            sex: .male,
            customOverrides: customZones
        )

        // Expanded micronutrients present (Sugar, Vitamin C, Cholesterol)
        XCTAssertTrue(merged.contains { $0.nutrient == "Sugar" })
        XCTAssertTrue(merged.contains { $0.nutrient == MicronutrientKey.vitaminCMg.displayName })
        XCTAssertTrue(merged.contains { $0.nutrient == MicronutrientKey.cholesterolMg.displayName })

        // Custom overrides applied accurately
        let sodium = merged.first { $0.nutrient == "Sodium" }
        XCTAssertEqual(sodium?.floor, 1500)
        XCTAssertEqual(sodium?.target, 2500)
        XCTAssertEqual(sodium?.ceiling, 3500)

        let vitD = merged.first { $0.nutrient == MicronutrientKey.vitaminDMcg.displayName }
        XCTAssertEqual(vitD?.floor, 50)
        XCTAssertEqual(vitD?.target, 75)
        XCTAssertEqual(vitD?.ceiling, 100)

        // BodyMetricType.leanBodyMass display <-> internal conversion
        let displayLBM = BodyMetricType.leanBodyMass.displayValue(70.0, system: .imperial)
        XCTAssertEqual(displayLBM, 154.32, accuracy: 0.05)
        let backToKg = BodyMetricType.leanBodyMass.internalValue(fromDisplay: displayLBM, system: .imperial)
        XCTAssertEqual(backToKg, 70.0, accuracy: 0.02)
    }

    func testWatchSyncWireSerializationAndUnitFormatting() {
        let exID = UUID()
        let setID = UUID()
        let sessionDTO = WatchActiveSessionDTO(
            id: UUID(),
            title: "Push",
            startedAt: Date(timeIntervalSince1970: 1_760_000_000),
            sets: [
                WatchSetItemDTO(
                    id: setID,
                    order: 0,
                    exerciseID: exID,
                    exerciseName: "Machine Chest Press",
                    setNumberInExercise: 1,
                    totalSetsInExercise: 3,
                    setTypeBadge: "W",
                    weightKg: UnitsFormatter.lbToKg(185),
                    reps: 8,
                    rir: 2,
                    restSeconds: 120,
                    loadIncrementKg: 2.26796,
                    isCompleted: false
                )
            ]
        )
        let snap = WatchSyncStateSnapshot(
            updatedAt: Date(timeIntervalSince1970: 1_760_000_060),
            unitSystemRaw: "imperial",
            caloriesRemaining: 840,
            caloriesTarget: 2350,
            caloriesEaten: 1510,
            proteinRemaining: 42,
            proteinTarget: 185,
            carbsRemaining: 95,
            carbsTarget: 240,
            fatRemaining: 22,
            fatTarget: 70,
            isTrainingDay: true,
            trendWeightKg: UnitsFormatter.lbToKg(178.4),
            latestScaleWeightKg: UnitsFormatter.lbToKg(178.0),
            activeSession: sessionDTO
        )

        XCTAssertEqual(snap.formatLoad(UnitsFormatter.lbToKg(185)), "185 lb")
        XCTAssertEqual(snap.formatBodyWeight(UnitsFormatter.lbToKg(178.4)), "178.4 lb")

        let ctxDict = snap.toApplicationContext()
        XCTAssertNotNil(ctxDict)
        let decodedSnap = WatchSyncStateSnapshot.fromApplicationContext(ctxDict ?? [:])
        XCTAssertEqual(decodedSnap?.activeSession?.title, "Push")
        XCTAssertEqual(decodedSnap?.activeSession?.sets.first?.id, setID)
        XCTAssertEqual(decodedSnap?.proteinRemaining ?? 0, 42, accuracy: 0.01)

        let cmd = WatchCommandPayload(
            action: .toggleSetComplete,
            setID: setID,
            weightKg: UnitsFormatter.lbToKg(190),
            reps: 9,
            rir: 1,
            restSeconds: 120
        )
        let userInfo = cmd.toUserInfo()
        XCTAssertNotNil(userInfo)
        let decodedCmd = WatchCommandPayload.fromUserInfo(userInfo ?? [:])
        XCTAssertEqual(decodedCmd?.id, cmd.id)
        XCTAssertEqual(decodedCmd?.action, .toggleSetComplete)
        XCTAssertEqual(decodedCmd?.reps, 9)
    }

    // MARK: - 19. MacroFactor Workouts Smart Progression Wand & Dynamic Rep Expansion

    func testProgressionWandRepRangeExpansionOnCoarseEquipmentJump() {
        // When load increment is >= 12.5% of working weight (e.g. 20kg dumbbell with 2.5kg jump = 12.5%),
        // Smart Progression must dynamically expand the rep ceiling (+3 reps) and flag repRangeExpansion!
        let suggestion = NextSessionSuggestion(
            action: .addWeight,
            suggestedWeightKg: 22.5,
            suggestedReps: 8,
            targetRIR: 2,
            estimated1RMKg: 30.0,
            personalK: 30.0,
            coachingNote: "Hit top reps",
            isProteinGated: false,
            isCutAdjusted: false
        )

        let diag = ProgressionEngine.evaluateProgressionWand(
            exerciseName: "Incline DB Press",
            suggestion: suggestion,
            repRangeLow: 8,
            repRangeHigh: 12,
            loadIncrementKg: 2.5,
            lastWorkingWeightKg: 20.0
        )

        XCTAssertEqual(diag.status, .repRangeExpansion)
        XCTAssertTrue(diag.isRepRangeExpanded)
        XCTAssertEqual(diag.repRangeLow, 8)
        XCTAssertEqual(diag.repRangeHigh, 15) // 12 + 3 expanded!
        XCTAssertEqual(diag.suggestedWeightKg, 20.0) // Held steady while expanding volume
        XCTAssertEqual(diag.equipmentJumpPercentage ?? 0, 12.5, accuracy: 0.1)
    }

    func testProgressionWandOnTrackWhenCleanHit() {
        let suggestion = NextSessionSuggestion(
            action: .addWeight,
            suggestedWeightKg: 102.5,
            suggestedReps: 5,
            targetRIR: 2,
            estimated1RMKg: 125.0,
            personalK: 30.0,
            coachingNote: "Target reached",
            isProteinGated: false,
            isCutAdjusted: false
        )

        let diag = ProgressionEngine.evaluateProgressionWand(
            exerciseName: "Barbell Back Squat",
            suggestion: suggestion,
            repRangeLow: 5,
            repRangeHigh: 8,
            loadIncrementKg: 2.5,
            lastWorkingWeightKg: 100.0 // 2.5 / 100 = 2.5% jump (< 12.5%)
        )

        XCTAssertEqual(diag.status, .onTrack)
        XCTAssertFalse(diag.isRepRangeExpanded)
        XCTAssertEqual(diag.repRangeHigh, 8)
        XCTAssertEqual(diag.suggestedWeightKg, 102.5)
    }

    // MARK: - 20. Weekly Hypertrophy Volume Landmarks

    func testHypertrophyVolumeLandmarksClassification() {
        let now = Date()
        let chestEntries = (0..<14).map { idx in
            HypertrophyVolumeEngine.VolumeSetEntry(
                timestamp: now.addingTimeInterval(-Double(idx) * 10000),
                primaryMuscles: [.chest],
                secondaryMuscles: [.triceps, .frontDelts],
                isCompleted: true,
                setType: .working
            )
        }

        let latsEntries = (0..<6).map { idx in
            HypertrophyVolumeEngine.VolumeSetEntry(
                timestamp: now.addingTimeInterval(-Double(idx) * 10000),
                primaryMuscles: [.lats],
                secondaryMuscles: [.biceps],
                isCompleted: true,
                setType: .working
            )
        }

        let statuses = HypertrophyVolumeEngine.evaluateWeeklyVolume(entries: chestEntries + latsEntries, referenceDate: now)

        let chestStatus = statuses.first(where: { $0.muscle == .chest })
        XCTAssertNotNil(chestStatus)
        XCTAssertEqual(chestStatus?.weeklyHardSets, 14.0)
        XCTAssertEqual(chestStatus?.zone, .optimal) // 12-20 MAV

        let latsStatus = statuses.first(where: { $0.muscle == .lats })
        XCTAssertNotNil(latsStatus)
        XCTAssertEqual(latsStatus?.weeklyHardSets, 6.0)
        XCTAssertEqual(latsStatus?.zone, .maintenance) // < 8 MV

        // Triceps received 14 indirect sets @ 0.5x = 7.0 sets
        let tricepsStatus = statuses.first(where: { $0.muscle == .triceps })
        XCTAssertNotNil(tricepsStatus)
        XCTAssertEqual(tricepsStatus?.weeklyHardSets, 7.0)
        XCTAssertEqual(tricepsStatus?.directSets, 0)
        XCTAssertEqual(tricepsStatus?.indirectSets, 14)
    }

    // MARK: - 21. Exercise Substitution Biomechanical Match Ranking

    func testExerciseSwapCandidatesRankingBiomechanicalSimilarity() {
        let bench = ExerciseBlueprint(
            name: "Barbell Bench Press",
            primaryMuscles: [.chest],
            secondaryMuscles: [.triceps, .frontDelts],
            equipment: .barbell,
            movementPattern: .horizontalPush
        )

        let dbBench = ExerciseBlueprint(
            name: "Dumbbell Bench Press",
            primaryMuscles: [.chest],
            secondaryMuscles: [.triceps, .frontDelts],
            equipment: .dumbbell,
            movementPattern: .horizontalPush
        )

        let dip = ExerciseBlueprint(
            name: "Parallel Bar Dips",
            primaryMuscles: [.chest, .triceps],
            secondaryMuscles: [.frontDelts],
            equipment: .bodyweight,
            movementPattern: .verticalPush
        )

        let squat = ExerciseBlueprint(
            name: "Barbell Back Squat",
            primaryMuscles: [.quads],
            secondaryMuscles: [.glutes],
            equipment: .barbell,
            movementPattern: .squat
        )

        let library = [squat, dip, dbBench]
        let candidates = ProgressionEngine.swapCandidates(for: bench, in: library)

        XCTAssertEqual(candidates.first?.name, "Dumbbell Bench Press") // Exact movementPattern match first!
        XCTAssertEqual(candidates[1].name, "Parallel Bar Dips") // Muscle overlap next
        XCTAssertEqual(candidates.last?.name, "Barbell Back Squat") // Unrelated last
    }

    // MARK: - v1.5.8 Bug Fix Tests

    func testUnitsFormatterCmToFeetInchesNo12InchRollover() {
        // Heights near 6 feet: 182.88 cm = 72.0 inches (6 ft 0 in)
        // 182.6 cm is ~71.89 in -> 5 ft 12 in if buggy truncatingRemainder used
        let (ft1, in1) = UnitsFormatter.cmToFeetInches(182.88)
        XCTAssertEqual(ft1, 6)
        XCTAssertEqual(in1, 0)

        let (ft2, in2) = UnitsFormatter.cmToFeetInches(182.6)
        XCTAssertEqual(ft2, 6)
        XCTAssertEqual(in2, 0)
        XCTAssertTrue(in2 < 12, "Inches must never equal or exceed 12")

        let (ft3, in3) = UnitsFormatter.cmToFeetInches(179.9)
        XCTAssertEqual(ft3, 5)
        XCTAssertEqual(in3, 11)
        XCTAssertTrue(in3 < 12)
    }

    func testProgressionEngineEmptyHistoryDefense() {
        let suggestion = ProgressionEngine.suggestNextSession(
            history: [],
            repRangeLow: 8,
            repRangeHigh: 12,
            targetRIR: 2,
            loadIncrementKg: 2.5
        )
        XCTAssertEqual(suggestion.action, .establishBaseline)
        XCTAssertEqual(suggestion.suggestedWeightKg, 20.0)
        XCTAssertEqual(suggestion.suggestedReps, 8)
    }
}
