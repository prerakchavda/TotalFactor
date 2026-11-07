import Foundation
import SwiftData

/// One place that turns a program workout into planned sets, and keeps those plans honest during the
/// workout: rep progression schemes, machine weight stacks, set-to-set adjustment and rep-range widening.
@MainActor
public enum WorkoutPlannerService {

    // MARK: - Lookups

    /// How many times this program workout has been finished (the session index inside the block).
    public static func completedCount(of programWorkout: ProgramWorkout, excludingSessionID: UUID? = nil) -> Int {
        (programWorkout.completedSessions ?? []).filter { $0.end != nil && $0.id != excludingSessionID }.count
    }

    /// The rep range this slot should use for its next (or current) session.
    public static func repTarget(for slot: ExerciseSlot, excludingSessionID: UUID? = nil) -> SchemeRepTarget {
        let index = slot.workout.map { completedCount(of: $0, excludingSessionID: excludingSessionID) } ?? 0
        return ProgressionEngine.schemeRepTarget(
            scheme: slot.repScheme,
            baseLow: slot.repRangeLow,
            baseHigh: slot.repRangeHigh,
            sessionIndex: index,
            blockLengthWeeks: slot.workout?.program?.blockLengthWeeks ?? 4
        )
    }

    public static func slot(for exercise: Exercise, in session: WorkoutSession) -> ExerciseSlot? {
        session.programWorkout?.sortedSlots.first { $0.exercise?.id == exercise.id }
    }

    public static func increment(for exercise: Exercise, gym: GymProfile?) -> Double {
        gym?.effectiveIncrementKg(for: exercise) ?? exercise.loadIncrementKg
    }

    /// Snaps a weight to what this exercise's equipment can actually be set to.
    public static func snap(_ weightKg: Double, for exercise: Exercise, gym: GymProfile?, roundingUp: Bool = false) -> Double {
        ProgressionEngine.snapToAvailable(
            weightKg,
            available: exercise.availableWeightsKg,
            increment: increment(for: exercise, gym: gym),
            roundingUp: roundingUp
        )
    }

    // MARK: - Starting a program workout

    /// Fills a freshly inserted session with planned working sets for every slot of `programWorkout`,
    /// swapping exercises the gym can't do, applying each slot's rep scheme and snapping to real weights.
    public static func populate(
        session: WorkoutSession,
        from programWorkout: ProgramWorkout,
        gym: GymProfile?,
        context: ModelContext
    ) {
        let digest = CoachingCoordinator.evaluate(context: context)
        let allExercises = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
        let exerciseByID = Dictionary(allExercises.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let allowedEquipment = Set(gym?.availableEquipment ?? Equipment.allCases)
        let pool = allExercises.map(\.asBlueprint)

        var order = 0
        for slot in programWorkout.sortedSlots {
            guard let baseExercise = slot.exercise else { continue }
            let swapped = ProgramGeneratorEngine.autoSwapIfNeeded(
                exercise: baseExercise.asBlueprint,
                availableEquipment: allowedEquipment,
                maxDumbbellKg: gym?.maxDumbbellKg ?? 50,
                pool: pool
            )
            let exercise = exerciseByID[swapped.id] ?? baseExercise
            let history = (exercise.setLogs ?? [])
                .filter { $0.isCompleted && $0.session?.id != session.id }
                .map {
                    LoggedSetSample(
                        sessionDate: $0.session?.start ?? $0.timestamp,
                        weightKg: $0.weightKg,
                        reps: $0.reps,
                        rir: $0.rir,
                        setType: $0.type
                    )
                }

            let inc = increment(for: exercise, gym: gym)
            let base = ProgressionEngine.suggestNextSession(
                history: history,
                repRangeLow: slot.repRangeLow,
                repRangeHigh: slot.repRangeHigh,
                targetRIR: slot.targetRIR,
                loadIncrementKg: inc,
                personalK: exercise.personalRepCurveK,
                weeklyWeightChangePercentBW: digest.weightSummary.weeklyRatePercentBW,
                avgProteinLast7d: digest.avgProteinLast7d,
                proteinFloor: digest.todayTargets.proteinFloor
            )
            let target = repTarget(for: slot, excludingSessionID: session.id)
            let suggestion = ProgressionEngine.applyRepScheme(
                to: base,
                scheme: slot.repScheme,
                target: target,
                loadIncrementKg: inc
            )
            let weight = snap(
                suggestion.suggestedWeightKg,
                for: exercise,
                gym: gym,
                roundingUp: suggestion.action == .addWeight
            )

            for _ in 0..<max(1, slot.sets) {
                let setLog = SetLog(
                    order: order,
                    session: session,
                    exercise: exercise,
                    weightKg: weight,
                    reps: suggestion.suggestedReps,
                    rir: slot.targetRIR,
                    type: .working,
                    supersetGroup: slot.supersetGroup,
                    isCompleted: false
                )
                context.insert(setLog)
                order += 1
            }
        }
    }

    // MARK: - Set-to-set adjustment

    /// After `completed` is logged, re-targets the remaining unfinished working sets of the same exercise
    /// (only the ones still matching the original plan, so manual edits are never overwritten).
    /// Returns the new targets when something changed.
    @discardableResult
    public static func adjustRemainingSets(
        after completed: SetLog,
        in session: WorkoutSession,
        mode: SetAdjustmentMode = SetAdjustmentPreference.mode
    ) -> SetAdjustment? {
        guard mode != .off,
              completed.isCompleted,
              completed.type.countsTowardWorkingStats,
              let exercise = completed.exercise,
              exercise.bodyweightMode == .standardLoad || exercise.bodyweightMode == .weightedBodyweight else { return nil }

        let remaining = session.sortedSets.filter {
            !$0.isCompleted && $0.type == .working && $0.exercise?.id == exercise.id && $0.order > completed.order
        }
        guard let next = remaining.first else { return nil }

        let slot = Self.slot(for: exercise, in: session)
        let target = slot.map { repTarget(for: $0, excludingSessionID: session.id) }
        guard let adjustment = ProgressionEngine.adjustRemainingSet(
            completedWeightKg: completed.weightKg,
            completedReps: completed.reps,
            completedRIR: completed.rir,
            plannedWeightKg: next.weightKg,
            plannedReps: next.reps,
            targetRIR: slot?.targetRIR ?? next.rir,
            repRangeLow: target?.low ?? max(1, next.reps - 2),
            repRangeHigh: target?.high ?? next.reps + 2,
            mode: mode,
            loadIncrementKg: increment(for: exercise, gym: session.gymProfile),
            availableWeightsKg: exercise.availableWeightsKg,
            k: exercise.personalRepCurveK
        ) else { return nil }

        let plannedWeight = next.weightKg
        let plannedReps = next.reps
        for set in remaining where abs(set.weightKg - plannedWeight) < 0.01 && set.reps == plannedReps {
            set.weightKg = adjustment.weightKg
            set.reps = adjustment.reps
            if set.isUnilateral {
                set.weightKgLeft = adjustment.weightKg
                set.weightKgRight = adjustment.weightKg
                set.repsLeft = adjustment.reps
                set.repsRight = adjustment.reps
            }
        }
        return adjustment
    }

    // MARK: - Rep-range widening

    /// A slot whose next weight jump is too big (≥ 12.5%) for its current rep ceiling.
    public struct RepRangeFix: Identifiable {
        public let id = UUID()
        public let exercise: Exercise
        public let slots: [ExerciseSlot]
        public let repRangeLow: Int
        public let oldHigh: Int
        public let newHigh: Int
        public let workingWeightKg: Double
        public let jumpKg: Double
    }

    /// Finds every exercise in the active program (or the session's program) that would progress better
    /// with a wider rep range, so they can all be fixed at once.
    public static func repRangeFixes(for session: WorkoutSession?, context: ModelContext) -> [RepRangeFix] {
        let program: Program? = session?.programWorkout?.program
            ?? ((try? context.fetch(FetchDescriptor<Program>()))?.first(where: \.isActive))
        guard let program else { return [] }
        let gym = session?.gymProfile

        let slots = program.sortedWorkouts.flatMap(\.sortedSlots)
        let byExercise = Dictionary(grouping: slots.filter { $0.exercise != nil }) { $0.exercise!.id }

        var fixes: [RepRangeFix] = []
        for (_, exerciseSlots) in byExercise {
            guard let exercise = exerciseSlots.first?.exercise else { continue }
            let candidates = exerciseSlots.filter { $0.repRangeHigh - $0.repRangeLow < 8 }
            guard let reference = candidates.first else { continue }
            guard let working = lastWorkingWeight(of: exercise, excludingSessionID: session?.id), working > 0 else { continue }
            let jump = ProgressionEngine.nextJumpKg(
                from: working,
                available: exercise.availableWeightsKg,
                fallbackIncrement: increment(for: exercise, gym: gym)
            )
            guard jump / working >= 0.125 else { continue }
            fixes.append(
                RepRangeFix(
                    exercise: exercise,
                    slots: candidates,
                    repRangeLow: reference.repRangeLow,
                    oldHigh: reference.repRangeHigh,
                    newHigh: reference.repRangeHigh + 3,
                    workingWeightKg: working,
                    jumpKg: jump
                )
            )
        }
        return fixes.sorted { $0.exercise.name < $1.exercise.name }
    }

    /// Widens the rep ceiling on every listed slot and, in the open session, pulls any not-yet-done sets that
    /// already jumped in weight back to the working weight so reps can climb first.
    public static func apply(_ fixes: [RepRangeFix], session: WorkoutSession?, context: ModelContext) {
        for fix in fixes {
            for slot in fix.slots {
                slot.repRangeHigh = max(slot.repRangeHigh, fix.newHigh)
            }
            guard let session else { continue }
            for set in session.sortedSets where !set.isCompleted && set.type == .working && set.exercise?.id == fix.exercise.id {
                if set.weightKg > fix.workingWeightKg + 0.01 {
                    set.weightKg = fix.workingWeightKg
                    set.reps = min(fix.newHigh, fix.oldHigh + 1)
                }
            }
        }
        try? context.save()
    }

    /// Heaviest completed working weight from the most recent finished session of this exercise.
    public static func lastWorkingWeight(of exercise: Exercise, excludingSessionID: UUID?) -> Double? {
        let past = (exercise.setLogs ?? []).filter {
            $0.isCompleted && $0.type.countsTowardWorkingStats && $0.weightKg > 0 && $0.session?.id != excludingSessionID
        }
        guard let latest = past.max(by: { ($0.session?.start ?? $0.timestamp) < ($1.session?.start ?? $1.timestamp) }) else {
            return nil
        }
        let latestSessionID = latest.session?.id
        return past.filter { $0.session?.id == latestSessionID }.map(\.weightKg).max()
    }
}

extension Exercise {
    /// YouTube search for a form/technique video of this exercise.
    var formVideoSearchURL: URL? {
        var components = URLComponents(string: "https://www.youtube.com/results")
        components?.queryItems = [URLQueryItem(name: "search_query", value: "\(name) proper form technique")]
        return components?.url
    }
}
