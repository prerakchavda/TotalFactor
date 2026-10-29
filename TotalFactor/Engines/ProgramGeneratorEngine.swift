import Foundation

public struct ExerciseBlueprint: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var primaryMuscles: [MuscleGroup]
    public var secondaryMuscles: [MuscleGroup]
    public var equipment: Equipment
    public var movementPattern: MovementPattern
    public var loadIncrementKg: Double

    public init(
        id: UUID = UUID(),
        name: String,
        primaryMuscles: [MuscleGroup],
        secondaryMuscles: [MuscleGroup] = [],
        equipment: Equipment,
        movementPattern: MovementPattern,
        loadIncrementKg: Double = 2.5
    ) {
        self.id = id
        self.name = name
        self.primaryMuscles = primaryMuscles
        self.secondaryMuscles = secondaryMuscles
        self.equipment = equipment
        self.movementPattern = movementPattern
        self.loadIncrementKg = loadIncrementKg
    }
}

public struct GeneratedSlotBlueprint: Hashable, Sendable {
    public var exercise: ExerciseBlueprint
    public var sets: Int
    public var repRangeLow: Int
    public var repRangeHigh: Int
    public var targetRIR: Int
    public var restSeconds: Int
    public var progressionRule: ProgressionRule
    public var supersetGroup: Int?
}

public struct GeneratedWorkoutBlueprint: Hashable, Sendable {
    public var name: String
    public var scheduledWeekday: Int?
    public var slots: [GeneratedSlotBlueprint]
}

public struct GeneratedProgramBlueprint: Hashable, Sendable {
    public var name: String
    public var daysPerWeek: Int
    public var workouts: [GeneratedWorkoutBlueprint]
}

public enum BuiltInProgramTemplate: String, CaseIterable, Identifiable, Sendable {
    case planetFitnessSplit = "Planet Fitness Split (Push / Pull / Lower / Upper)"
    case fullBodyAB = "Full Body A/B (3 Days)"
    case upperLower = "Upper / Lower (4 Days)"
    case pushPullLegs = "Push / Pull / Legs (6 Days)"

    public var id: String { rawValue }
    public var daysPerWeek: Int {
        switch self {
        case .planetFitnessSplit: return 4
        case .fullBodyAB: return 3
        case .upperLower: return 4
        case .pushPullLegs: return 6
        }
    }
}

public enum ProgramGeneratorEngine {
    /// Phase 6 (§10): Auto-swaps an exercise unsupported by the active Gym Profile
    /// to the closest matching movement pattern & primary muscle available at that gym.
    public static func autoSwapIfNeeded(
        exercise: ExerciseBlueprint,
        availableEquipment: Set<Equipment>,
        maxDumbbellKg: Double,
        pool: [ExerciseBlueprint],
        preferredHistoryIDs: Set<UUID> = []
    ) -> ExerciseBlueprint {
        if availableEquipment.contains(exercise.equipment) {
            if exercise.equipment != .dumbbell || maxDumbbellKg > 0 {
                return exercise
            }
        }

        let candidates = pool.filter { candidate in
            availableEquipment.contains(candidate.equipment) &&
            candidate.id != exercise.id
        }

        let scored = candidates.map { candidate -> (ExerciseBlueprint, Int) in
            var score = 0
            if candidate.movementPattern == exercise.movementPattern { score += 50 }
            let sharedPrimary = Set(candidate.primaryMuscles).intersection(exercise.primaryMuscles).count
            score += sharedPrimary * 30
            let sharedSecondary = Set(candidate.secondaryMuscles).intersection(exercise.secondaryMuscles).count
            score += sharedSecondary * 10
            if preferredHistoryIDs.contains(candidate.id) { score += 15 }
            return (candidate, score)
        }

        return scored.max(by: { $0.1 < $1.1 })?.0 ?? exercise
    }

    /// Phase 6 (§10): Rule-based Plan Generator.
    /// 1. Picks split from `daysPerWeek`
    /// 2. Fills each day with movement patterns (squat, hinge, horizontal push/pull, vertical push/pull, isolations)
    /// 3. Chooses exercises available at the gym, preferring ones with history
    /// 4. Scales weekly hard sets (~10 beginner to ~16 advanced)
    /// 5. Fits session length at ~2.75 min per set including rest
    public static func generateProgram(
        goalFocus: TrainingGoalFocus,
        experience: ExperienceLevel,
        daysPerWeek: Int,
        minutesPerSession: Int,
        availableEquipment: Set<Equipment>,
        exercisePool: [ExerciseBlueprint],
        historicalExerciseIDs: Set<UUID> = []
    ) -> GeneratedProgramBlueprint {
        let clampedDays = min(max(daysPerWeek, 2), 6)
        // ~2.75 minutes per working set (including transitions & warmups amortized)
        let maxSetsPerSession = max(8, min(28, Int((Double(minutesPerSession) / 2.75).rounded())))

        let splitTemplates = dayTemplates(for: clampedDays)
        let filteredPool = exercisePool.filter { availableEquipment.contains($0.equipment) }
        let workingPool = filteredPool.isEmpty ? exercisePool : filteredPool

        let baseSetsScale: Double = {
            switch experience {
            case .beginner: return 0.80      // ~10 sets/muscle/wk
            case .intermediate: return 1.00  // ~13 sets/muscle/wk
            case .advanced: return 1.22      // ~16 sets/muscle/wk
            }
        }()

        var usedPerDay: Set<UUID> = []
        var workouts: [GeneratedWorkoutBlueprint] = []

        // Default training weekdays spaced smartly across the week (1=Sun..7=Sat)
        let weekdays = defaultWeekdays(for: clampedDays)

        for (dayIdx, daySpec) in splitTemplates.enumerated() {
            usedPerDay.removeAll()
            var slots: [GeneratedSlotBlueprint] = []
            var totalSetsToday = 0

            for patternReq in daySpec.patterns {
                guard totalSetsToday < maxSetsPerSession else { break }
                guard let chosen = pickBestExercise(
                    pattern: patternReq.pattern,
                    targetMuscle: patternReq.targetMuscle,
                    pool: workingPool,
                    excluding: usedPerDay,
                    historicalIDs: historicalExerciseIDs,
                    dayOffset: dayIdx
                ) else { continue }

                usedPerDay.insert(chosen.id)

                let rawSets = Int((Double(patternReq.baseSets) * baseSetsScale).rounded())
                let remainingBudget = maxSetsPerSession - totalSetsToday
                let sets = max(2, min(5, min(rawSets, remainingBudget)))
                totalSetsToday += sets

                let (repLow, repHigh, rir, restSec) = prescription(
                    for: chosen.movementPattern,
                    goalFocus: goalFocus
                )

                slots.append(
                    GeneratedSlotBlueprint(
                        exercise: chosen,
                        sets: sets,
                        repRangeLow: repLow,
                        repRangeHigh: repHigh,
                        targetRIR: rir,
                        restSeconds: restSec,
                        progressionRule: chosen.movementPattern.isCompound && goalFocus == .strength ? .rpeAutoRegulated : .doubleProgression,
                        supersetGroup: nil
                    )
                )
            }

            workouts.append(
                GeneratedWorkoutBlueprint(
                    name: daySpec.title,
                    scheduledWeekday: dayIdx < weekdays.count ? weekdays[dayIdx] : nil,
                    slots: slots
                )
            )
        }

        let splitLabel: String = {
            switch clampedDays {
            case 2, 3: return "Full Body"
            case 4: return "Upper / Lower"
            case 5: return "Upper / Lower + PPL"
            default: return "Push / Pull / Legs"
            }
        }()

        return GeneratedProgramBlueprint(
            name: "\(clampedDays)x \(splitLabel) (\(goalFocus.displayName))",
            daysPerWeek: clampedDays,
            workouts: workouts
        )
    }

    public static func builtInTemplate(
        _ template: BuiltInProgramTemplate,
        exercisePool: [ExerciseBlueprint],
        availableEquipment: Set<Equipment> = Set(Equipment.allCases)
    ) -> GeneratedProgramBlueprint {
        if template == .planetFitnessSplit {
            return planetFitnessProgramBlueprint(exercisePool: exercisePool)
        }
        var generated = generateProgram(
            goalFocus: .both,
            experience: .intermediate,
            daysPerWeek: template.daysPerWeek,
            minutesPerSession: 60,
            availableEquipment: availableEquipment,
            exercisePool: exercisePool
        )
        generated.name = template.rawValue
        return generated
    }

    public static func planetFitnessProgramBlueprint(
        exercisePool: [ExerciseBlueprint]
    ) -> GeneratedProgramBlueprint {
        let byName = Dictionary(
            exercisePool.map { ($0.name.lowercased(), $0) },
            uniquingKeysWith: { first, _ in first }
        )

        func slot(
            _ name: String,
            fallbackPattern: MovementPattern,
            fallbackMuscle: MuscleGroup,
            sets: Int = 2,
            low: Int = 6,
            high: Int = 8,
            rir: Int = 1,
            rest: Int = 90
        ) -> GeneratedSlotBlueprint? {
            let ex = byName[name.lowercased()] ?? exercisePool.first {
                $0.movementPattern == fallbackPattern && $0.primaryMuscles.contains(fallbackMuscle)
            } ?? exercisePool.first
            guard let ex else { return nil }
            return GeneratedSlotBlueprint(
                exercise: ex,
                sets: sets,
                repRangeLow: low,
                repRangeHigh: high,
                targetRIR: rir,
                restSeconds: rest,
                progressionRule: .doubleProgression,
                supersetGroup: nil
            )
        }

        let pushSlots = [
            slot("Machine Chest Press", fallbackPattern: .horizontalPush, fallbackMuscle: .chest, sets: 2, low: 6, high: 8, rir: 1, rest: 120),
            slot("Pec Deck / Machine Fly", fallbackPattern: .isolation, fallbackMuscle: .chest, sets: 2, low: 6, high: 8, rir: 1, rest: 90),
            slot("Machine Shoulder Press", fallbackPattern: .verticalPush, fallbackMuscle: .frontDelts, sets: 2, low: 6, high: 8, rir: 1, rest: 120),
            slot("Cable Lateral Raise", fallbackPattern: .isolation, fallbackMuscle: .sideDelts, sets: 2, low: 8, high: 12, rir: 1, rest: 75),
            slot("Overhead Cable Triceps Extension", fallbackPattern: .isolation, fallbackMuscle: .triceps, sets: 2, low: 6, high: 10, rir: 1, rest: 90),
            slot("Seated Triceps Press Machine", fallbackPattern: .isolation, fallbackMuscle: .triceps, sets: 2, low: 6, high: 8, rir: 1, rest: 90)
        ].compactMap { $0 }

        let pullSlots = [
            slot("Wide-Grip Lat Pulldown", fallbackPattern: .verticalPull, fallbackMuscle: .lats, sets: 2, low: 6, high: 8, rir: 1, rest: 120),
            slot("Seated Machine Row", fallbackPattern: .horizontalPull, fallbackMuscle: .upperBack, sets: 2, low: 6, high: 8, rir: 1, rest: 120),
            slot("Straight-Arm Cable Pulldown", fallbackPattern: .isolation, fallbackMuscle: .lats, sets: 2, low: 8, high: 12, rir: 1, rest: 75),
            slot("Pull-Up / Weighted Pull-Up", fallbackPattern: .verticalPull, fallbackMuscle: .lats, sets: 2, low: 6, high: 10, rir: 1, rest: 120),
            slot("Machine Bicep Curl", fallbackPattern: .isolation, fallbackMuscle: .biceps, sets: 2, low: 6, high: 8, rir: 1, rest: 90),
            slot("Dumbbell Bicep Curl", fallbackPattern: .isolation, fallbackMuscle: .biceps, sets: 2, low: 8, high: 12, rir: 1, rest: 75)
        ].compactMap { $0 }

        let lowerSlots = [
            slot("Calf Extension Machine", fallbackPattern: .isolation, fallbackMuscle: .calves, sets: 2, low: 8, high: 12, rir: 1, rest: 75),
            slot("Seated Leg Press Machine", fallbackPattern: .squat, fallbackMuscle: .quads, sets: 2, low: 6, high: 10, rir: 2, rest: 150),
            slot("Leg Extension", fallbackPattern: .isolation, fallbackMuscle: .quads, sets: 2, low: 6, high: 10, rir: 1, rest: 90),
            slot("Seated Leg Curl", fallbackPattern: .isolation, fallbackMuscle: .hamstrings, sets: 2, low: 6, high: 10, rir: 1, rest: 90),
            slot("Hip Abduction Machine", fallbackPattern: .isolation, fallbackMuscle: .glutes, sets: 2, low: 6, high: 8, rir: 1, rest: 75),
            slot("Hip Adduction Machine", fallbackPattern: .isolation, fallbackMuscle: .glutes, sets: 2, low: 6, high: 8, rir: 1, rest: 75)
        ].compactMap { $0 }

        let upperSlots = [
            slot("Incline Machine Chest Press", fallbackPattern: .horizontalPush, fallbackMuscle: .chest, sets: 2, low: 6, high: 8, rir: 1, rest: 120),
            slot("Pec Deck / Machine Fly", fallbackPattern: .isolation, fallbackMuscle: .chest, sets: 2, low: 6, high: 8, rir: 1, rest: 90),
            slot("Machine Lat Pulldown", fallbackPattern: .verticalPull, fallbackMuscle: .lats, sets: 2, low: 6, high: 8, rir: 1, rest: 120),
            slot("Seated Machine Row", fallbackPattern: .horizontalPull, fallbackMuscle: .upperBack, sets: 2, low: 6, high: 8, rir: 1, rest: 120),
            slot("Cable Lateral Raise", fallbackPattern: .isolation, fallbackMuscle: .sideDelts, sets: 2, low: 8, high: 12, rir: 1, rest: 75),
            slot("Overhead Cable Triceps Extension", fallbackPattern: .isolation, fallbackMuscle: .triceps, sets: 2, low: 6, high: 8, rir: 1, rest: 90),
            slot("Machine Bicep Curl", fallbackPattern: .isolation, fallbackMuscle: .biceps, sets: 2, low: 6, high: 8, rir: 1, rest: 90)
        ].compactMap { $0 }

        return GeneratedProgramBlueprint(
            name: "Planet Fitness Split",
            daysPerWeek: 4,
            workouts: [
                GeneratedWorkoutBlueprint(name: "Push", scheduledWeekday: 2, slots: pushSlots),
                GeneratedWorkoutBlueprint(name: "Back and Biceps", scheduledWeekday: 3, slots: pullSlots),
                GeneratedWorkoutBlueprint(name: "Lower", scheduledWeekday: 5, slots: lowerSlots),
                GeneratedWorkoutBlueprint(name: "Upper", scheduledWeekday: 7, slots: upperSlots)
            ]
        )
    }

    // MARK: - Private Helpers

    private struct PatternSlotRequest {
        var pattern: MovementPattern
        var targetMuscle: MuscleGroup?
        var baseSets: Int
    }

    private struct DaySpec {
        var title: String
        var patterns: [PatternSlotRequest]
    }

    private static func defaultWeekdays(for days: Int) -> [Int] {
        // 1=Sun, 2=Mon, 3=Tue, 4=Wed, 5=Thu, 6=Fri, 7=Sat
        switch days {
        case 2: return [2, 5]                // Mon, Thu
        case 3: return [2, 4, 6]             // Mon, Wed, Fri
        case 4: return [2, 3, 5, 6]          // Mon, Tue, Thu, Fri
        case 5: return [2, 3, 4, 6, 7]       // Mon, Tue, Wed, Fri, Sat
        default: return [2, 3, 4, 5, 6, 7]   // Mon–Sat
        }
    }

    private static func prescription(
        for pattern: MovementPattern,
        goalFocus: TrainingGoalFocus
    ) -> (low: Int, high: Int, rir: Int, restSeconds: Int) {
        if pattern.isCompound {
            switch goalFocus {
            case .strength: return (4, 6, 2, 180)
            case .both: return (6, 10, 2, 150)
            case .hypertrophy: return (8, 12, 2, 120)
            }
        } else {
            switch goalFocus {
            case .strength: return (8, 12, 2, 90)
            case .both: return (10, 15, 1, 90)
            case .hypertrophy: return (12, 16, 1, 75)
            }
        }
    }

    private static func pickBestExercise(
        pattern: MovementPattern,
        targetMuscle: MuscleGroup?,
        pool: [ExerciseBlueprint],
        excluding: Set<UUID>,
        historicalIDs: Set<UUID>,
        dayOffset: Int
    ) -> ExerciseBlueprint? {
        let candidates = pool.filter { !excluding.contains($0.id) }
        guard !candidates.isEmpty else { return nil }

        let ranked = candidates.map { ex -> (ExerciseBlueprint, Int) in
            var score = 0
            if ex.movementPattern == pattern { score += 60 }
            if let tm = targetMuscle {
                if ex.primaryMuscles.contains(tm) { score += 45 }
                else if ex.secondaryMuscles.contains(tm) { score += 15 }
            }
            if historicalIDs.contains(ex.id) { score += 20 }
            if ex.equipment == .barbell || ex.equipment == .dumbbell { score += 5 }
            return (ex, score)
        }.sorted { lhs, rhs in
            if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
            return lhs.0.name < rhs.0.name
        }

        let topTierScore = ranked[0].1
        let topMatches = ranked.filter { $0.1 >= topTierScore - 5 }.map(\.0)
        return topMatches[dayOffset % topMatches.count]
    }

    private static func dayTemplates(for days: Int) -> [DaySpec] {
        let fullBodyA = DaySpec(title: "Full Body A", patterns: [
            PatternSlotRequest(pattern: .squat, targetMuscle: .quads, baseSets: 3),
            PatternSlotRequest(pattern: .horizontalPush, targetMuscle: .chest, baseSets: 3),
            PatternSlotRequest(pattern: .horizontalPull, targetMuscle: .upperBack, baseSets: 3),
            PatternSlotRequest(pattern: .hinge, targetMuscle: .hamstrings, baseSets: 3),
            PatternSlotRequest(pattern: .isolation, targetMuscle: .sideDelts, baseSets: 3),
            PatternSlotRequest(pattern: .isolation, targetMuscle: .biceps, baseSets: 2)
        ])
        let fullBodyB = DaySpec(title: "Full Body B", patterns: [
            PatternSlotRequest(pattern: .hinge, targetMuscle: .glutes, baseSets: 3),
            PatternSlotRequest(pattern: .verticalPush, targetMuscle: .frontDelts, baseSets: 3),
            PatternSlotRequest(pattern: .verticalPull, targetMuscle: .lats, baseSets: 3),
            PatternSlotRequest(pattern: .squat, targetMuscle: .quads, baseSets: 3),
            PatternSlotRequest(pattern: .isolation, targetMuscle: .triceps, baseSets: 3),
            PatternSlotRequest(pattern: .isolation, targetMuscle: .calves, baseSets: 3)
        ])

        let upperA = DaySpec(title: "Upper A", patterns: [
            PatternSlotRequest(pattern: .horizontalPush, targetMuscle: .chest, baseSets: 4),
            PatternSlotRequest(pattern: .horizontalPull, targetMuscle: .upperBack, baseSets: 4),
            PatternSlotRequest(pattern: .verticalPush, targetMuscle: .frontDelts, baseSets: 3),
            PatternSlotRequest(pattern: .verticalPull, targetMuscle: .lats, baseSets: 3),
            PatternSlotRequest(pattern: .isolation, targetMuscle: .triceps, baseSets: 3),
            PatternSlotRequest(pattern: .isolation, targetMuscle: .biceps, baseSets: 3)
        ])
        let lowerA = DaySpec(title: "Lower A", patterns: [
            PatternSlotRequest(pattern: .squat, targetMuscle: .quads, baseSets: 4),
            PatternSlotRequest(pattern: .hinge, targetMuscle: .hamstrings, baseSets: 3),
            PatternSlotRequest(pattern: .isolation, targetMuscle: .quads, baseSets: 3),
            PatternSlotRequest(pattern: .isolation, targetMuscle: .hamstrings, baseSets: 3),
            PatternSlotRequest(pattern: .isolation, targetMuscle: .calves, baseSets: 3),
            PatternSlotRequest(pattern: .isolation, targetMuscle: .abs, baseSets: 3)
        ])
        let upperB = DaySpec(title: "Upper B", patterns: [
            PatternSlotRequest(pattern: .verticalPush, targetMuscle: .frontDelts, baseSets: 4),
            PatternSlotRequest(pattern: .verticalPull, targetMuscle: .lats, baseSets: 4),
            PatternSlotRequest(pattern: .horizontalPush, targetMuscle: .chest, baseSets: 3),
            PatternSlotRequest(pattern: .horizontalPull, targetMuscle: .upperBack, baseSets: 3),
            PatternSlotRequest(pattern: .isolation, targetMuscle: .sideDelts, baseSets: 4),
            PatternSlotRequest(pattern: .isolation, targetMuscle: .rearDelts, baseSets: 3)
        ])
        let lowerB = DaySpec(title: "Lower B", patterns: [
            PatternSlotRequest(pattern: .hinge, targetMuscle: .glutes, baseSets: 4),
            PatternSlotRequest(pattern: .squat, targetMuscle: .quads, baseSets: 3),
            PatternSlotRequest(pattern: .isolation, targetMuscle: .hamstrings, baseSets: 3),
            PatternSlotRequest(pattern: .isolation, targetMuscle: .glutes, baseSets: 3),
            PatternSlotRequest(pattern: .isolation, targetMuscle: .calves, baseSets: 3),
            PatternSlotRequest(pattern: .carry, targetMuscle: .forearms, baseSets: 2)
        ])

        let push = DaySpec(title: "Push", patterns: [
            PatternSlotRequest(pattern: .horizontalPush, targetMuscle: .chest, baseSets: 4),
            PatternSlotRequest(pattern: .verticalPush, targetMuscle: .frontDelts, baseSets: 3),
            PatternSlotRequest(pattern: .isolation, targetMuscle: .chest, baseSets: 3),
            PatternSlotRequest(pattern: .isolation, targetMuscle: .sideDelts, baseSets: 4),
            PatternSlotRequest(pattern: .isolation, targetMuscle: .triceps, baseSets: 4)
        ])
        let pull = DaySpec(title: "Pull", patterns: [
            PatternSlotRequest(pattern: .verticalPull, targetMuscle: .lats, baseSets: 4),
            PatternSlotRequest(pattern: .horizontalPull, targetMuscle: .upperBack, baseSets: 4),
            PatternSlotRequest(pattern: .isolation, targetMuscle: .rearDelts, baseSets: 3),
            PatternSlotRequest(pattern: .isolation, targetMuscle: .traps, baseSets: 2),
            PatternSlotRequest(pattern: .isolation, targetMuscle: .biceps, baseSets: 4)
        ])
        let legs = DaySpec(title: "Legs", patterns: [
            PatternSlotRequest(pattern: .squat, targetMuscle: .quads, baseSets: 4),
            PatternSlotRequest(pattern: .hinge, targetMuscle: .hamstrings, baseSets: 4),
            PatternSlotRequest(pattern: .isolation, targetMuscle: .quads, baseSets: 3),
            PatternSlotRequest(pattern: .isolation, targetMuscle: .hamstrings, baseSets: 3),
            PatternSlotRequest(pattern: .isolation, targetMuscle: .calves, baseSets: 4)
        ])

        switch days {
        case 2:
            return [fullBodyA, fullBodyB]
        case 3:
            var fbC = fullBodyA
            fbC.title = "Full Body C"
            return [fullBodyA, fullBodyB, fbC]
        case 4:
            return [upperA, lowerA, upperB, lowerB]
        case 5:
            return [upperA, lowerA, push, pull, legs]
        default:
            var pushB = push; pushB.title = "Push B"
            var pullB = pull; pullB.title = "Pull B"
            var legsB = legs; legsB.title = "Legs B"
            return [push, pull, legs, pushB, pullB, legsB]
        }
    }
}
