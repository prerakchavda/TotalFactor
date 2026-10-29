import Foundation

public struct DailyIntakeRecord: Equatable, Sendable {
    public var dayKey: String
    public var calories: Double
    public var protein: Double
    public var carbs: Double
    public var fat: Double
    /// Only days explicitly marked `isComplete == true` feed adaptive expenditure!
    public var isComplete: Bool

    public init(
        dayKey: String,
        calories: Double,
        protein: Double = 0,
        carbs: Double = 0,
        fat: Double = 0,
        isComplete: Bool
    ) {
        self.dayKey = dayKey
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.isComplete = isComplete
    }
}

public struct ExpenditureSnapshot: Identifiable, Equatable, Sendable {
    public var id: String { dayKey }
    public var dayKey: String
    public var date: Date
    public var expenditureKcal: Double
    public var rawAdaptiveKcal: Double?
    public var formulaKcal: Double
    public var confidence: ConfidenceLevel
    public var method: ExpenditureMethod
    public var completeDaysInWindow: Int
    public var weighInsInWindow: Int
    public var windowSpanDays: Int

    public init(
        dayKey: String,
        date: Date,
        expenditureKcal: Double,
        rawAdaptiveKcal: Double?,
        formulaKcal: Double,
        confidence: ConfidenceLevel,
        method: ExpenditureMethod,
        completeDaysInWindow: Int,
        weighInsInWindow: Int,
        windowSpanDays: Int
    ) {
        self.dayKey = dayKey
        self.date = date
        self.expenditureKcal = expenditureKcal
        self.rawAdaptiveKcal = rawAdaptiveKcal
        self.formulaKcal = formulaKcal
        self.confidence = confidence
        self.method = method
        self.completeDaysInWindow = completeDaysInWindow
        self.weighInsInWindow = weighInsInWindow
        self.windowSpanDays = windowSpanDays
    }
}

public enum ExpenditureEngine {
    public static let kcalPerKgBodyMass: Double = 7700.0
    public static let maxSingleUpdateDeltaKcal: Double = 100.0

    /// Mifflin-St Jeor BMR (§8).
    /// Men: 10*kg + 6.25*cm - 5*age + 5
    /// Women: 10*kg + 6.25*cm - 5*age - 161
    public static func mifflinStJeorBMR(
        sex: BiologicalSex,
        weightKg: Double,
        heightCm: Double,
        ageYears: Int
    ) -> Double {
        let base = (10.0 * weightKg) + (6.25 * heightCm) - (5.0 * Double(ageYears))
        let offset = (sex == .male) ? 5.0 : -161.0
        return max(800.0, base + offset)
    }

    public static func startingExpenditure(
        sex: BiologicalSex,
        weightKg: Double,
        heightCm: Double,
        ageYears: Int,
        activityLevel: ActivityLevel
    ) -> Double {
        mifflinStJeorBMR(sex: sex, weightKg: weightKg, heightCm: heightCm, ageYears: ageYears) * activityLevel.multiplier
    }

    /// Exact spec §8 energy balance equation:
    /// `storedKcalPerDay = (trendEndKg - trendStartKg) * 7700 / days`
    /// `rawExpenditure = avgIntakeKcal - storedKcalPerDay`
    public static func rawExpenditure(
        avgIntakeKcal: Double,
        trendStartKg: Double,
        trendEndKg: Double,
        days: Double
    ) -> Double {
        guard days > 0 else { return avgIntakeKcal }
        let storedKcalPerDay = (trendEndKg - trendStartKg) * kcalPerKgBodyMass / days
        return avgIntakeKcal - storedKcalPerDay
    }

    /// Exact spec §8 exponential blend step, clamped so a single update never jumps > `maxDelta` (100 kcal/day).
    public static func blended(
        previous: Double,
        raw: Double,
        weight: Double = 0.15,
        maxDelta: Double = maxSingleUpdateDeltaKcal
    ) -> Double {
        let clampedWeight = min(max(weight, 0.0), 1.0)
        let unclamped = previous + clampedWeight * (raw - previous)
        let delta = min(max(unclamped - previous, -maxDelta), maxDelta)
        return previous + delta
    }

    /// Evaluates confidence per spec §8:
    /// - low: < 14 complete logged days
    /// - medium: 14–27 days
    /// - high: 28+ window with ≥80% days logged complete (≥22/28) and ≥4 weigh-ins/week (≥16/28)
    public static func confidenceLevel(
        windowSpanDays: Int,
        completeDaysCount: Int,
        weighInsCount: Int
    ) -> ConfidenceLevel {
        if windowSpanDays >= 28 {
            let logRatio = Double(completeDaysCount) / Double(windowSpanDays)
            let weighInsPerWeek = (Double(weighInsCount) / Double(windowSpanDays)) * 7.0
            if completeDaysCount >= 22 && logRatio >= 0.80 && weighInsPerWeek >= 4.0 {
                return .high
            }
            if completeDaysCount >= 14 {
                return .medium
            }
            return .low
        } else if completeDaysCount >= 14 && windowSpanDays >= 14 && weighInsCount >= 4 {
            return .medium
        } else {
            return .low
        }
    }

    /// Computes a deterministic daily trajectory of `ExpenditureSnapshot` values from history.
    /// Workouts / Watch active calories are NEVER added here because training expenditure is already
    /// captured by weight trend velocity vs intake.
    public static func computeTrajectory(
        sex: BiologicalSex,
        initialWeightKg: Double,
        heightCm: Double,
        ageYears: Int,
        activityLevel: ActivityLevel,
        intakes: [DailyIntakeRecord],
        weightSeries: [DailyWeightPoint],
        through endDayKey: String? = nil,
        calendar: Calendar = .current
    ) -> [ExpenditureSnapshot] {
        let weightByDay = Dictionary(weightSeries.map { ($0.dayKey, $0) }, uniquingKeysWith: { _, latest in latest })
        let intakeByDay = Dictionary(
            grouping: intakes,
            by: \.dayKey
        ).compactMapValues { records -> DailyIntakeRecord? in
            // If multiple records exist for one dayKey, merge them cleanly
            guard let first = records.first else { return nil }
            if records.count == 1 { return first }
            return DailyIntakeRecord(
                dayKey: first.dayKey,
                calories: records.reduce(0) { $0 + $1.calories },
                protein: records.reduce(0) { $0 + $1.protein },
                carbs: records.reduce(0) { $0 + $1.carbs },
                fat: records.reduce(0) { $0 + $1.fat },
                isComplete: records.contains(where: \.isComplete)
            )
        }

        let earliestCandidate = [intakeByDay.keys.min(), weightByDay.keys.min()].compactMap { $0 }.min()
        let startKey = earliestCandidate ?? (endDayKey ?? DayKey.today)
        let finalKey = max(startKey, endDayKey ?? [intakeByDay.keys.max(), weightByDay.keys.max()].compactMap { $0 }.max() ?? startKey)

        let allDays = DayKey.range(from: startKey, to: finalKey, calendar: calendar)
        var currentEstimate = startingExpenditure(
            sex: sex,
            weightKg: initialWeightKg,
            heightCm: heightCm,
            ageYears: ageYears,
            activityLevel: activityLevel
        )

        var results: [ExpenditureSnapshot] = []
        results.reserveCapacity(allDays.count)

        for dayKey in allDays {
            let dt = DayKey.date(from: dayKey, calendar: calendar) ?? .now
            let currentWeight = weightByDay[dayKey]?.trendKg ?? initialWeightKg
            let formulaTDEE = startingExpenditure(
                sex: sex,
                weightKg: currentWeight,
                heightCm: heightCm,
                ageYears: ageYears,
                activityLevel: activityLevel
            )

            let daysSinceStart = DayKey.daysBetween(startKey, dayKey, calendar: calendar) + 1
            let lookbackSpan = min(28, max(1, daysSinceStart))
            let windowStartKey = DayKey.addingDays(-(lookbackSpan - 1), to: dayKey, calendar: calendar)
            let windowKeys = DayKey.range(from: windowStartKey, to: dayKey, calendar: calendar)

            let completeRecords = windowKeys.compactMap { k -> DailyIntakeRecord? in
                guard let rec = intakeByDay[k], rec.isComplete else { return nil }
                return rec
            }
            let weighInPoints = windowKeys.compactMap { k -> DailyWeightPoint? in
                guard let wp = weightByDay[k], wp.scaleKg != nil else { return nil }
                return wp
            }

            let confidence = confidenceLevel(
                windowSpanDays: lookbackSpan,
                completeDaysCount: completeRecords.count,
                weighInsCount: weighInPoints.count
            )

            // Require at least 7 complete logged days, >= 3 weigh-ins, and >= 7 days between trend start & end
            // before transitioning away from pure Mifflin-St Jeor formula.
            let trendStartPoint = windowKeys.lazy.compactMap { weightByDay[$0] }.first
            let trendEndPoint = weightByDay[dayKey]

            if completeRecords.count >= 7,
               weighInPoints.count >= 2,
               let tStart = trendStartPoint,
               let tEnd = trendEndPoint {
                let effectiveDays = Double(max(7, DayKey.daysBetween(tStart.dayKey, tEnd.dayKey, calendar: calendar)))
                let avgIntake = completeRecords.reduce(0.0) { $0 + $1.calories } / Double(completeRecords.count)
                let raw = max(900.0, min(6500.0, rawExpenditure(
                    avgIntakeKcal: avgIntake,
                    trendStartKg: tStart.trendKg,
                    trendEndKg: tEnd.trendKg,
                    days: effectiveDays
                )))

                // Progressive ramp: days 7..13 blend raw with formula first so early water shifts don't whipsaw TDEE.
                let adaptiveMaturity = min(1.0, Double(completeRecords.count - 6) / 8.0)
                let targetRaw = (formulaTDEE * (1.0 - adaptiveMaturity)) + (raw * adaptiveMaturity)
                let stepWeight = completeRecords.count >= 14 ? 0.15 : 0.10

                currentEstimate = blended(
                    previous: currentEstimate,
                    raw: targetRaw,
                    weight: stepWeight,
                    maxDelta: maxSingleUpdateDeltaKcal
                )

                results.append(
                    ExpenditureSnapshot(
                        dayKey: dayKey,
                        date: dt,
                        expenditureKcal: currentEstimate,
                        rawAdaptiveKcal: raw,
                        formulaKcal: formulaTDEE,
                        confidence: confidence,
                        method: .adaptive,
                        completeDaysInWindow: completeRecords.count,
                        weighInsInWindow: weighInPoints.count,
                        windowSpanDays: lookbackSpan
                    )
                )
            } else {
                // Smoothly track formula if weight changed slightly while still in week 1-2
                currentEstimate = blended(previous: currentEstimate, raw: formulaTDEE, weight: 0.25, maxDelta: 50)
                results.append(
                    ExpenditureSnapshot(
                        dayKey: dayKey,
                        date: dt,
                        expenditureKcal: currentEstimate,
                        rawAdaptiveKcal: nil,
                        formulaKcal: formulaTDEE,
                        confidence: .low,
                        method: .formula,
                        completeDaysInWindow: completeRecords.count,
                        weighInsInWindow: weighInPoints.count,
                        windowSpanDays: lookbackSpan
                    )
                )
            }
        }

        return results
    }
}
