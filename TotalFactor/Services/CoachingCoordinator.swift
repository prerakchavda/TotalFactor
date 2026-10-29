import Foundation
import SwiftData

public struct CombinedTrendPoint: Identifiable, Equatable, Sendable {
    public var id: String { dayKey }
    public var dayKey: String
    public var date: Date
    public var trendWeightKg: Double
    /// Sum of top compound lift e1RMs on or carried forward through this date (§12 "One chart").
    public var strengthIndexKg: Double?
}

public struct CoachingDashboardDigest: Equatable, Sendable {
    public var expenditure: ExpenditureSnapshot
    public var weightSummary: WeightTrendSummary
    public var weightSeries: [DailyWeightPoint]
    public var carbCycledTargets: CarbCycledTargets
    public var todayTargets: MacroTargets
    public var isTodayTrainingDay: Bool
    public var scheduledWorkoutName: String?
    public var avgProteinLast7d: Double?
    public var isProteinGateActive: Bool
    public var preWorkoutSnackNudge: String?
    public var combinedWeightStrengthSeries: [CombinedTrendPoint]
}

@MainActor
public enum CoachingCoordinator {
    /// Reconciles any queued actions from Interactive Widgets, Dynamic Island, or Siri Shortcuts.
    public static func processPendingWidgetActions(context: ModelContext) {
        let actions = SharedSnapshotStore.consumePendingActions()
        guard !actions.isEmpty else { return }

        for action in actions {
            switch action.kind {
            case .quickCalories:
                let entry = FoodLogEntry(
                    quickTitle: action.label.isEmpty ? "Quick Add" : action.label,
                    calories: action.numericValue,
                    timestamp: action.createdAt
                )
                context.insert(entry)
                Task { await HealthKitService.shared.syncFoodEntry(entry) }

            case .loggedFoodEntry:
                let entry = FoodLogEntry(
                    quickTitle: action.label.isEmpty ? "Siri Quick Food" : action.label,
                    calories: action.numericValue,
                    protein: action.protein,
                    carbs: action.carbs,
                    fat: action.fat,
                    mealTag: MealTag(rawValue: action.mealTagRaw) ?? .none,
                    timestamp: action.createdAt
                )
                entry.grams = max(0.1, action.grams)
                entry.servingLabel = action.servingLabel.isEmpty ? "1 serving" : action.servingLabel
                context.insert(entry)
                Task { await HealthKitService.shared.syncFoodEntry(entry) }

            case .weighInKg:
                let weighIn = WeighIn(date: action.createdAt, weightKg: action.numericValue, source: .manual)
                context.insert(weighIn)
                Task { await HealthKitService.shared.saveManualWeighIn(weighIn) }

            case .adjustRestSeconds:
                RestTimerService.shared.adjust(bySeconds: Int(action.numericValue))

            case .skipRestTimer:
                RestTimerService.shared.skip()
            }
        }

        try? context.save()
    }

    private static var cachedDigests: [String: CoachingDashboardDigest] = [:]

    public static func invalidateCache() {
        cachedDigests.removeAll()
    }

    /// Pure, O(1)-cached digest accessor safe to read during SwiftUI `View.body` rendering
    /// without triggering SwiftData mutations or WidgetKit XPC reloads during scrolling.
    public static func cachedOrComputeDigest(
        forDayKey targetDayKey: String = DayKey.today,
        context: ModelContext
    ) -> CoachingDashboardDigest {
        if let hit = cachedDigests[targetDayKey] {
            return hit
        }
        let computed = computeDigest(forDayKey: targetDayKey, context: context, persistSideEffects: false)
        cachedDigests[targetDayKey] = computed
        return computed
    }

    /// Computes a full up-to-date `CoachingDashboardDigest`, updates today's `ExpenditureEstimate`,
    /// checks if a `WeeklyCheckIn` is due, and syncs `SharedSnapshotStore` for Widgets & Siri.
    @discardableResult
    public static func evaluate(
        forDayKey targetDayKey: String = DayKey.today,
        context: ModelContext
    ) -> CoachingDashboardDigest {
        cachedDigests.removeAll()
        let computed = computeDigest(forDayKey: targetDayKey, context: context, persistSideEffects: true)
        cachedDigests[targetDayKey] = computed
        if targetDayKey == DayKey.today {
            PhoneWatchSyncService.shared.pushCurrentState(context: context)
        }
        return computed
    }

    private static func computeDigest(
        forDayKey targetDayKey: String,
        context: ModelContext,
        persistSideEffects: Bool
    ) -> CoachingDashboardDigest {
        let profile = fetchOrCreateProfile(context: context)
        let goal = fetchOrCreateGoal(profile: profile, context: context)

        let allWeighIns = (try? context.fetch(FetchDescriptor<WeighIn>())) ?? []
        let allEntries = (try? context.fetch(FetchDescriptor<FoodLogEntry>())) ?? []
        let allNotes = (try? context.fetch(FetchDescriptor<DailyNote>())) ?? []
        let allPrograms = (try? context.fetch(FetchDescriptor<Program>())) ?? []
        let allSessions = (try? context.fetch(FetchDescriptor<WorkoutSession>())) ?? []

        // 1. Weight Trend Series
        let samples = allWeighIns.map(\.asSample)
        let weightSeries = WeightTrendEngine.buildDailySeries(
            samples: samples,
            rule: profile.weighInRule,
            alpha: 0.1,
            through: targetDayKey
        )
        let weightSummary = WeightTrendEngine.summarize(series: weightSeries, referenceDayKey: targetDayKey)
        let currentWeightKg = weightSummary.latestTrendKg ?? profile.startingWeightKg

        // 2. Daily Intake Records (strictly honoring `DailyNote.isComplete`!)
        let notesByDay = Dictionary(grouping: allNotes, by: \.dayKey).compactMapValues(\.first)
        let entriesByDay = Dictionary(grouping: allEntries, by: \.dayKey)
        let allKnownIntakeKeys = Set(notesByDay.keys).union(entriesByDay.keys)

        let intakeRecords: [DailyIntakeRecord] = allKnownIntakeKeys.map { key in
            let dayEntries = entriesByDay[key] ?? []
            let cals = dayEntries.reduce(0.0) { $0 + $1.calories }
            let p = dayEntries.reduce(0.0) { $0 + $1.protein }
            let c = dayEntries.reduce(0.0) { $0 + $1.carbs }
            let f = dayEntries.reduce(0.0) { $0 + $1.fat }
            let complete = notesByDay[key]?.isComplete ?? false
            return DailyIntakeRecord(dayKey: key, calories: cals, protein: p, carbs: c, fat: f, isComplete: complete)
        }

        // 3. Expenditure Trajectory
        let trajectory = ExpenditureEngine.computeTrajectory(
            sex: profile.biologicalSex,
            initialWeightKg: profile.startingWeightKg,
            heightCm: profile.heightCm,
            ageYears: profile.ageYears,
            activityLevel: profile.activityLevel,
            intakes: intakeRecords,
            weightSeries: weightSeries,
            through: targetDayKey
        )

        let bmr = ExpenditureEngine.mifflinStJeorBMR(
            sex: profile.biologicalSex,
            weightKg: currentWeightKg,
            heightCm: profile.heightCm,
            ageYears: profile.ageYears
        )
        let fallbackFormula = bmr * profile.activityLevel.multiplier

        let latestExpenditure = trajectory.last ?? ExpenditureSnapshot(
            dayKey: targetDayKey,
            date: DayKey.date(from: targetDayKey) ?? .now,
            expenditureKcal: fallbackFormula,
            rawAdaptiveKcal: nil,
            formulaKcal: fallbackFormula,
            confidence: .low,
            method: .formula,
            completeDaysInWindow: 0,
            weighInsInWindow: 0,
            windowSpanDays: 1
        )

        if persistSideEffects {
            upsertExpenditureEstimate(snapshot: latestExpenditure, context: context)
        }

        // 4. Active Program & Training-Day Carb Cycling (§12)
        let activeProgram = allPrograms.first(where: \.isActive) ?? allPrograms.first
        let weekday = DayKey.weekday(for: targetDayKey)
        let isTrainingDay: Bool
        let scheduledWorkout: ProgramWorkout?
        if let prog = activeProgram, prog.scheduleMode == .rollingSplit {
            isTrainingDay = true
            scheduledWorkout = prog.nextRollingWorkout
        } else {
            isTrainingDay = activeProgram?.isTrainingWeekday(weekday) ?? false
            scheduledWorkout = activeProgram?.sortedWorkouts.first(where: { $0.scheduledWeekday == weekday }) ??
                (isTrainingDay ? activeProgram?.sortedWorkouts.first : nil)
        }

        let baseTargets = MacroTargetEngine.calculateTargets(
            expenditureKcal: latestExpenditure.expenditureKcal,
            goalType: goal.type,
            ratePercentPerWeek: goal.ratePercentPerWeek,
            bodyWeightKg: currentWeightKg,
            sex: profile.biologicalSex,
            bmrKcal: bmr,
            overrideCalorieFloor: profile.overrideCalorieFloor
        )

        let cycled = MacroTargetEngine.carbCycledTargets(
            base: baseTargets,
            trainingDaysPerWeek: activeProgram?.daysPerWeek ?? 0
        )

        let todayTargets: MacroTargets
        if profile.enableTrainingDayCarbCycling, activeProgram != nil {
            todayTargets = isTrainingDay ? cycled.trainingDay : cycled.restDay
        } else {
            todayTargets = baseTargets
        }

        // 5. Phase 8 Combined Insights: Protein Gate & Pre-Workout Snack Nudge
        let trailing7Start = DayKey.addingDays(-7, to: targetDayKey)
        let trailing7Complete = intakeRecords.filter { $0.dayKey >= trailing7Start && $0.dayKey < targetDayKey && $0.isComplete }
        let avgProtein7d: Double? = trailing7Complete.count >= 3
            ? (trailing7Complete.reduce(0.0) { $0 + $1.protein } / Double(trailing7Complete.count))
            : nil
        let isProteinGated = (avgProtein7d != nil) && (avgProtein7d! < baseTargets.proteinFloor)

        let completedWorkoutToday = allSessions.contains { $0.dayKey == targetDayKey && $0.isFinished }
        var snackNudge: String? = nil
        if targetDayKey == DayKey.today, isTrainingDay, !completedWorkoutToday, let workoutTitle = scheduledWorkout?.name {
            let latestMealTime = (entriesByDay[targetDayKey] ?? []).map(\.timestamp).max() ??
                (entriesByDay[DayKey.addingDays(-1, to: targetDayKey)] ?? []).map(\.timestamp).max()
            let hoursFasted = latestMealTime.map { Date.now.timeIntervalSince($0) / 3600.0 } ?? 12.0
            if hoursFasted >= 4.0 {
                snackNudge = "It's been \(Int(hoursFasted))h since your last logged food before \(workoutTitle) — consider 25–40g fast carbs + 20g protein."
            }
        }

        // 6. Phase 8 Combined Weight Trend × Strength Index Series (§12)
        let combinedSeries = buildCombinedWeightStrengthSeries(
            weightSeries: weightSeries,
            sessions: allSessions
        )

        // 7. Update Widget & Siri Snapshot for Today (only during explicit evaluations, never inside View.body)
        if persistSideEffects && targetDayKey == DayKey.today {
            let todayFood = entriesByDay[targetDayKey] ?? []
            let snap = WidgetDashboardSnapshot(
                updatedAt: .now,
                caloriesEaten: todayFood.reduce(0) { $0 + $1.calories },
                caloriesTarget: todayTargets.calories,
                proteinEaten: todayFood.reduce(0) { $0 + $1.protein },
                proteinTarget: todayTargets.protein,
                proteinFloor: todayTargets.proteinFloor,
                carbsEaten: todayFood.reduce(0) { $0 + $1.carbs },
                carbsTarget: todayTargets.carbs,
                fatEaten: todayFood.reduce(0) { $0 + $1.fat },
                fatTarget: todayTargets.fat,
                trendWeightKg: weightSummary.latestTrendKg,
                latestScaleWeightKg: weightSummary.latestScaleKg,
                unitSystemRaw: profile.unitSystemRaw,
                expenditureKcal: latestExpenditure.expenditureKcal,
                expenditureConfidenceRaw: latestExpenditure.confidence.rawValue,
                nextWorkoutName: scheduledWorkout?.name ?? activeProgram?.sortedWorkouts.first?.name,
                isTrainingDay: isTrainingDay,
                activeRestEndDate: RestTimerService.shared.endDate,
                activeRestTotalSeconds: RestTimerService.shared.totalSeconds,
                activeRestExercise: RestTimerService.shared.exerciseName
            )
            SharedSnapshotStore.save(snap)
        }

        return CoachingDashboardDigest(
            expenditure: latestExpenditure,
            weightSummary: weightSummary,
            weightSeries: weightSeries,
            carbCycledTargets: cycled,
            todayTargets: todayTargets,
            isTodayTrainingDay: isTrainingDay,
            scheduledWorkoutName: scheduledWorkout?.name,
            avgProteinLast7d: avgProtein7d,
            isProteinGateActive: isProteinGated,
            preWorkoutSnackNudge: snackNudge,
            combinedWeightStrengthSeries: combinedSeries
        )
    }

    /// Generates a new `WeeklyCheckIn` incorporating both adaptive nutrition AND training summary (§8 & §12).
    public static func createWeeklyCheckIn(context: ModelContext) -> WeeklyCheckIn {
        let todayKey = DayKey.today
        let digest = evaluate(forDayKey: todayKey, context: context)
        let profile = fetchOrCreateProfile(context: context)
        let goal = fetchOrCreateGoal(profile: profile, context: context)

        let existingCheckIns = ((try? context.fetch(FetchDescriptor<WeeklyCheckIn>())) ?? [])
            .sorted { $0.date < $1.date }
        let prevCheckIn = existingCheckIns.last
        let prevExp = prevCheckIn?.expenditure ?? digest.expenditure.formulaKcal
        let prevCals = prevCheckIn?.targets.calories ?? digest.carbCycledTargets.dailyAverage.calories

        let start7 = DayKey.addingDays(-7, to: todayKey)
        let sessions = ((try? context.fetch(FetchDescriptor<WorkoutSession>())) ?? [])
            .filter { $0.dayKey >= start7 && $0.dayKey <= todayKey && $0.isFinished }
        let prs = ((try? context.fetch(FetchDescriptor<PersonalRecord>())) ?? [])
            .filter { $0.dayKey >= start7 && $0.dayKey <= todayKey }

        let weeklyVol = sessions.reduce(0.0) { $0 + $1.totalWorkingVolumeKg }
        let weeklyWeightDelta = digest.weightSummary.change7dKg ?? digest.weightSummary.weeklyRateKg ?? 0.0
        let currentBW = digest.weightSummary.latestTrendKg ?? profile.startingWeightKg

        let reason = MacroTargetEngine.checkInExplanation(
            previousCalories: prevCals,
            newCalories: digest.carbCycledTargets.dailyAverage.calories,
            actualWeeklyChangeKg: weeklyWeightDelta,
            goalType: goal.type,
            goalRatePercent: goal.ratePercentPerWeek,
            bodyWeightKg: currentBW,
            unitSystem: profile.unitSystem
        )

        let checkIn = WeeklyCheckIn(
            date: .now,
            dayKey: todayKey,
            expenditure: digest.expenditure.expenditureKcal,
            previousExpenditure: prevExp,
            weightTrendChangeKg: weeklyWeightDelta,
            targets: digest.carbCycledTargets.dailyAverage,
            trainingDayTargets: digest.carbCycledTargets.trainingDay,
            restDayTargets: digest.carbCycledTargets.restDay,
            explanation: reason,
            sessionsCompleted: sessions.count,
            weeklyVolumeKg: weeklyVol,
            prsHitCount: prs.count,
            accepted: false
        )
        context.insert(checkIn)
        try? context.save()
        return checkIn
    }

    public static func fetchOrCreateProfile(context: ModelContext) -> UserProfile {
        if let existing = (try? context.fetch(FetchDescriptor<UserProfile>()))?.first {
            return existing
        }
        let created = UserProfile()
        context.insert(created)
        return created
    }

    public static func fetchOrCreateGoal(profile: UserProfile, context: ModelContext) -> Goal {
        let all = (try? context.fetch(FetchDescriptor<Goal>())) ?? []
        if let active = all.first(where: \.isActive) ?? all.first {
            return active
        }
        let created = Goal(type: .cut, ratePercentPerWeek: 0.5, startDate: .now, startWeightKg: profile.startingWeightKg)
        context.insert(created)
        return created
    }

    private static func upsertExpenditureEstimate(snapshot: ExpenditureSnapshot, context: ModelContext) {
        let all = (try? context.fetch(FetchDescriptor<ExpenditureEstimate>())) ?? []
        if let existing = all.first(where: { $0.dayKey == snapshot.dayKey }) {
            let changed = abs(existing.value - snapshot.expenditureKcal) > 0.05 ||
                existing.confidence != snapshot.confidence ||
                existing.method != snapshot.method ||
                existing.completeDaysCount != snapshot.completeDaysInWindow ||
                existing.weighInsCount != snapshot.weighInsInWindow
            if changed {
                existing.value = snapshot.expenditureKcal
                existing.confidence = snapshot.confidence
                existing.method = snapshot.method
                existing.completeDaysCount = snapshot.completeDaysInWindow
                existing.weighInsCount = snapshot.weighInsInWindow
            }
        } else {
            let record = ExpenditureEstimate(
                date: snapshot.date,
                dayKey: snapshot.dayKey,
                value: snapshot.expenditureKcal,
                confidence: snapshot.confidence,
                method: snapshot.method,
                completeDaysCount: snapshot.completeDaysInWindow,
                weighInsCount: snapshot.weighInsInWindow
            )
            context.insert(record)
        }
    }

    private static func buildCombinedWeightStrengthSeries(
        weightSeries: [DailyWeightPoint],
        sessions: [WorkoutSession]
    ) -> [CombinedTrendPoint] {
        guard !weightSeries.isEmpty else { return [] }

        // Track rolling best e1RM across top compound exercises up to each day
        var latestLiftE1RMByExercise: [UUID: Double] = [:]
        let sessionsByDay = Dictionary(grouping: sessions.filter(\.isFinished), by: \.dayKey)

        return weightSeries.map { wp in
            if let daySessions = sessionsByDay[wp.dayKey] {
                for session in daySessions {
                    for setLog in (session.sets ?? []) where setLog.isCompleted && setLog.type.countsTowardWorkingStats {
                        guard let ex = setLog.exercise, ex.movementPattern.isCompound else { continue }
                        let e1rm = setLog.estimated1RMKg
                        if e1rm > 0 {
                            let prev = latestLiftE1RMByExercise[ex.id] ?? e1rm
                            latestLiftE1RMByExercise[ex.id] = prev + 0.35 * (e1rm - prev)
                        }
                    }
                }
            }

            let top3Sum: Double? = {
                guard !latestLiftE1RMByExercise.isEmpty else { return nil }
                let topValues = latestLiftE1RMByExercise.values.sorted(by: >).prefix(3)
                return topValues.reduce(0, +)
            }()

            return CombinedTrendPoint(
                dayKey: wp.dayKey,
                date: wp.date,
                trendWeightKg: wp.trendKg,
                strengthIndexKg: top3Sum
            )
        }
    }
}
