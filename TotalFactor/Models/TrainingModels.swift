import Foundation
import SwiftData

private enum TrainingModelCoding {
    static let decoder = JSONDecoder()
    static let encoder = JSONEncoder()
}

@Model
public final class Exercise {
    public var id: UUID = UUID()
    public var name: String = ""
    public var primaryMusclesJSON: Data = Data()
    public var secondaryMusclesJSON: Data = Data()
    public var equipmentRaw: String = Equipment.barbell.rawValue
    public var movementPatternRaw: String = MovementPattern.horizontalPush.rawValue
    public var isCustom: Bool = false
    public var instructions: String = ""
    public var loadIncrementKg: Double = 2.5
    /// Personal strength/endurance curve parameter `k` (§11); default Epley k = 30.0.
    public var personalRepCurveK: Double = 30.0
    /// Persistent machine/rack setup notes (e.g., "Seat #4, Pin #12, neutral grip"). Persists across workouts.
    public var machineSetupNotes: String = ""
    /// Whether this exercise defaults to unilateral (Left / Right) tracking.
    public var isUnilateralDefault: Bool = false
    public var bodyweightModeRaw: String = BodyweightMode.standardLoad.rawValue

    @Transient private var _cachedPrimaryMuscles: [MuscleGroup]? = nil
    @Transient private var _cachedSecondaryMuscles: [MuscleGroup]? = nil

    @Relationship(deleteRule: .nullify, inverse: \ExerciseSlot.exercise)
    public var programSlots: [ExerciseSlot]? = []

    @Relationship(deleteRule: .nullify, inverse: \SetLog.exercise)
    public var setLogs: [SetLog]? = []

    @Relationship(deleteRule: .cascade, inverse: \PersonalRecord.exercise)
    public var personalRecords: [PersonalRecord]? = []

    public init(
        id: UUID = UUID(),
        name: String,
        primaryMuscles: [MuscleGroup],
        secondaryMuscles: [MuscleGroup] = [],
        equipment: Equipment = .barbell,
        movementPattern: MovementPattern = .horizontalPush,
        isCustom: Bool = false,
        instructions: String = "",
        loadIncrementKg: Double = 2.5,
        personalRepCurveK: Double = 30.0,
        machineSetupNotes: String = "",
        isUnilateralDefault: Bool = false,
        bodyweightMode: BodyweightMode = .standardLoad
    ) {
        self.id = id
        self.name = name
        self.equipmentRaw = equipment.rawValue
        self.movementPatternRaw = movementPattern.rawValue
        self.isCustom = isCustom
        self.instructions = instructions
        self.loadIncrementKg = loadIncrementKg
        self.personalRepCurveK = personalRepCurveK
        self.machineSetupNotes = machineSetupNotes
        self.isUnilateralDefault = isUnilateralDefault
        self.bodyweightModeRaw = bodyweightMode.rawValue
        self.primaryMuscles = primaryMuscles
        self.secondaryMuscles = secondaryMuscles
    }

    public var bodyweightMode: BodyweightMode {
        get { BodyweightMode(rawValue: bodyweightModeRaw) ?? .standardLoad }
        set { bodyweightModeRaw = newValue.rawValue }
    }

    public var primaryMuscles: [MuscleGroup] {
        get {
            if let cached = _cachedPrimaryMuscles { return cached }
            let decoded = (try? TrainingModelCoding.decoder.decode([MuscleGroup].self, from: primaryMusclesJSON)) ?? [.chest]
            _cachedPrimaryMuscles = decoded
            return decoded
        }
        set {
            _cachedPrimaryMuscles = newValue
            primaryMusclesJSON = (try? TrainingModelCoding.encoder.encode(newValue)) ?? Data()
        }
    }

    public var secondaryMuscles: [MuscleGroup] {
        get {
            if let cached = _cachedSecondaryMuscles { return cached }
            let decoded = (try? TrainingModelCoding.decoder.decode([MuscleGroup].self, from: secondaryMusclesJSON)) ?? []
            _cachedSecondaryMuscles = decoded
            return decoded
        }
        set {
            _cachedSecondaryMuscles = newValue
            secondaryMusclesJSON = (try? TrainingModelCoding.encoder.encode(newValue)) ?? Data()
        }
    }

    public var equipment: Equipment {
        get { Equipment(rawValue: equipmentRaw) ?? .barbell }
        set { equipmentRaw = newValue.rawValue }
    }

    public var movementPattern: MovementPattern {
        get { MovementPattern(rawValue: movementPatternRaw) ?? .isolation }
        set { movementPatternRaw = newValue.rawValue }
    }

    public var asBlueprint: ExerciseBlueprint {
        ExerciseBlueprint(
            id: id,
            name: name,
            primaryMuscles: primaryMuscles,
            secondaryMuscles: secondaryMuscles,
            equipment: equipment,
            movementPattern: movementPattern,
            loadIncrementKg: loadIncrementKg
        )
    }
}

@Model
public final class GymProfile {
    public var id: UUID = UUID()
    public var name: String = "Commercial Gym"
    public var isDefault: Bool = false
    public var availableEquipmentJSON: Data = Data()
    public var availablePlatesKgJSON: Data = Data()
    public var barWeightKg: Double = 20.0
    public var minDumbbellKg: Double = 2.5
    public var maxDumbbellKg: Double = 50.0
    public var dumbbellIncrementKg: Double = 2.5
    public var cableIncrementKg: Double = 2.5

    @Transient private var _cachedAvailableEquipment: [Equipment]? = nil
    @Transient private var _cachedAvailablePlatesKg: [Double]? = nil

    @Relationship(deleteRule: .nullify, inverse: \WorkoutSession.gymProfile)
    public var sessions: [WorkoutSession]? = []

    public init(
        id: UUID = UUID(),
        name: String,
        isDefault: Bool = false,
        availableEquipment: [Equipment] = Equipment.allCases,
        availablePlatesKg: [Double] = [25, 20, 15, 10, 5, 2.5, 1.25],
        barWeightKg: Double = 20.0,
        minDumbbellKg: Double = 2.5,
        maxDumbbellKg: Double = 50.0,
        dumbbellIncrementKg: Double = 2.5,
        cableIncrementKg: Double = 2.5
    ) {
        self.id = id
        self.name = name
        self.isDefault = isDefault
        self.barWeightKg = barWeightKg
        self.minDumbbellKg = minDumbbellKg
        self.maxDumbbellKg = maxDumbbellKg
        self.dumbbellIncrementKg = dumbbellIncrementKg
        self.cableIncrementKg = cableIncrementKg
        self.availableEquipment = availableEquipment
        self.availablePlatesKg = availablePlatesKg
    }

    public var availableEquipment: [Equipment] {
        get {
            if let cached = _cachedAvailableEquipment { return cached }
            let decoded = (try? TrainingModelCoding.decoder.decode([Equipment].self, from: availableEquipmentJSON)) ?? Equipment.allCases
            _cachedAvailableEquipment = decoded
            return decoded
        }
        set {
            _cachedAvailableEquipment = newValue
            availableEquipmentJSON = (try? TrainingModelCoding.encoder.encode(newValue)) ?? Data()
        }
    }

    public var availablePlatesKg: [Double] {
        get {
            if let cached = _cachedAvailablePlatesKg { return cached }
            let decoded = (try? TrainingModelCoding.decoder.decode([Double].self, from: availablePlatesKgJSON)) ?? [25, 20, 15, 10, 5, 2.5, 1.25]
            _cachedAvailablePlatesKg = decoded
            return decoded
        }
        set {
            _cachedAvailablePlatesKg = newValue
            availablePlatesKgJSON = (try? TrainingModelCoding.encoder.encode(newValue)) ?? Data()
        }
    }

    public func effectiveIncrementKg(for exercise: Exercise) -> Double {
        switch exercise.equipment {
        case .dumbbell: return dumbbellIncrementKg
        case .cable: return cableIncrementKg
        case .barbell, .ezBar, .trapBar, .smithMachine:
            let smallestPlate = availablePlatesKg.min() ?? 1.25
            return max(exercise.loadIncrementKg, smallestPlate * 2.0)
        default:
            return exercise.loadIncrementKg
        }
    }
}

@Model
public final class Program {
    public var id: UUID = UUID()
    public var name: String = ""
    public var daysPerWeek: Int = 4
    public var isActive: Bool = false
    public var createdAt: Date = Date()
    public var scheduleModeRaw: String = ProgramScheduleMode.fixedWeekdays.rawValue
    public var lastCompletedWorkoutOrder: Int = -1

    @Relationship(deleteRule: .cascade, inverse: \ProgramWorkout.program)
    public var workouts: [ProgramWorkout]? = []

    public init(name: String, daysPerWeek: Int = 4, isActive: Bool = false, scheduleMode: ProgramScheduleMode = .fixedWeekdays) {
        self.name = name
        self.daysPerWeek = daysPerWeek
        self.isActive = isActive
        self.scheduleModeRaw = scheduleMode.rawValue
    }

    public var scheduleMode: ProgramScheduleMode {
        get { ProgramScheduleMode(rawValue: scheduleModeRaw) ?? .fixedWeekdays }
        set { scheduleModeRaw = newValue.rawValue }
    }

    public var nextRollingWorkout: ProgramWorkout? {
        let sw = sortedWorkouts
        guard !sw.isEmpty else { return nil }
        if lastCompletedWorkoutOrder < 0 {
            return sw.first
        }
        let nextOrder = (lastCompletedWorkoutOrder + 1) % sw.count
        return sw.first(where: { $0.order == nextOrder }) ?? sw.first
    }

    public var sortedWorkouts: [ProgramWorkout] {
        (workouts ?? []).sorted { $0.order < $1.order }
    }

    public func isTrainingWeekday(_ weekday: Int) -> Bool {
        if scheduleMode == .rollingSplit {
            return true
        }
        let scheduled = sortedWorkouts.compactMap(\.scheduledWeekday)
        if !scheduled.isEmpty {
            return scheduled.contains(weekday)
        }
        // Fallback if user left weekdays unscheduled: space `daysPerWeek` starting Monday (2)
        return weekday >= 2 && weekday < (2 + daysPerWeek)
    }
}

@Model
public final class ProgramWorkout {
    public var id: UUID = UUID()
    public var name: String = ""
    public var order: Int = 0
    /// Optional 1=Sun ... 7=Sat schedule so Phase 8 Training-Day Carbs knows which days are training days.
    public var scheduledWeekday: Int? = nil

    public var program: Program? = nil

    @Relationship(deleteRule: .cascade, inverse: \ExerciseSlot.workout)
    public var slots: [ExerciseSlot]? = []

    @Relationship(deleteRule: .nullify, inverse: \WorkoutSession.programWorkout)
    public var completedSessions: [WorkoutSession]? = []

    public init(name: String, order: Int = 0, scheduledWeekday: Int? = nil) {
        self.name = name
        self.order = order
        self.scheduledWeekday = scheduledWeekday
    }

    public var sortedSlots: [ExerciseSlot] {
        (slots ?? []).sorted { $0.order < $1.order }
    }
}

@Model
public final class ExerciseSlot {
    public var id: UUID = UUID()
    public var order: Int = 0
    public var sets: Int = 3
    public var repRangeLow: Int = 6
    public var repRangeHigh: Int = 10
    public var targetRIR: Int = 2
    public var restSeconds: Int = 120
    public var progressionRuleRaw: String = ProgressionRule.doubleProgression.rawValue
    public var supersetGroup: Int? = nil

    public var workout: ProgramWorkout? = nil
    public var exercise: Exercise? = nil

    public init(
        order: Int = 0,
        exercise: Exercise?,
        sets: Int = 3,
        repRangeLow: Int = 6,
        repRangeHigh: Int = 10,
        targetRIR: Int = 2,
        restSeconds: Int = 120,
        progressionRule: ProgressionRule = .doubleProgression,
        supersetGroup: Int? = nil
    ) {
        self.order = order
        self.exercise = exercise
        self.sets = sets
        self.repRangeLow = repRangeLow
        self.repRangeHigh = repRangeHigh
        self.targetRIR = targetRIR
        self.restSeconds = restSeconds
        self.progressionRuleRaw = progressionRule.rawValue
        self.supersetGroup = supersetGroup
    }

    public var progressionRule: ProgressionRule {
        get { ProgressionRule(rawValue: progressionRuleRaw) ?? .doubleProgression }
        set { progressionRuleRaw = newValue.rawValue }
    }
}

@Model
public final class WorkoutSession {
    public var id: UUID = UUID()
    public var title: String = "Strength Session"
    public var start: Date = Date()
    public var end: Date? = nil
    public var dayKey: String = ""
    public var notes: String = ""
    public var healthKitWorkoutUUID: UUID? = nil

    /// Pause tracking (§MacroFactor Workout UI)
    public var isPaused: Bool = false
    public var totalPausedSeconds: Int = 0
    public var lastPausedDate: Date? = nil

    public var programWorkout: ProgramWorkout? = nil
    public var gymProfile: GymProfile? = nil

    @Relationship(deleteRule: .cascade, inverse: \SetLog.session)
    public var sets: [SetLog]? = []

    public init(
        title: String = "Strength Session",
        programWorkout: ProgramWorkout? = nil,
        gymProfile: GymProfile? = nil,
        start: Date = .now,
        notes: String = ""
    ) {
        self.title = title
        self.programWorkout = programWorkout
        self.gymProfile = gymProfile
        self.start = start
        self.dayKey = DayKey.from(start)
        self.notes = notes
    }

    public var sortedSets: [SetLog] {
        (sets ?? []).sorted { $0.order < $1.order }
    }

    public var completedSetCount: Int {
        guard let sets else { return 0 }
        var count = 0
        for s in sets where s.isCompleted {
            count += 1
        }
        return count
    }

    public var totalWorkingVolumeKg: Double {
        guard let sets else { return 0.0 }
        var total = 0.0
        for s in sets where (s.isCompleted || !isFinished) && s.type.countsTowardWorkingStats {
            total += s.effectiveTonnageKg()
        }
        return total
    }

    public var isFinished: Bool {
        end != nil
    }

    public func pauseSession() {
        guard !isPaused, end == nil else { return }
        isPaused = true
        lastPausedDate = .now
    }

    public func resumeSession() {
        guard isPaused else { return }
        if let pausedAt = lastPausedDate {
            totalPausedSeconds += max(0, Int(Date().timeIntervalSince(pausedAt)))
        }
        isPaused = false
        lastPausedDate = nil
    }

    public func effectiveElapsedSeconds(at now: Date = .now) -> Int {
        let currentPause = (isPaused && lastPausedDate != nil) ? Int(now.timeIntervalSince(lastPausedDate!)) : 0
        let gross = Int(now.timeIntervalSince(start))
        return max(0, gross - totalPausedSeconds - currentPause)
    }
}

@Model
public final class SetLog {
    public var id: UUID = UUID()
    public var order: Int = 0
    /// Stored internally in kg.
    public var weightKg: Double = 0.0
    public var reps: Int = 0
    public var rir: Int = 2
    public var typeRaw: String = SetType.working.rawValue
    public var restTakenSeconds: Int = 0
    public var isCompleted: Bool = false
    public var supersetGroup: Int? = nil
    public var timestamp: Date = Date()

    /// Unilateral (Left vs Right) logging
    public var isUnilateral: Bool = false
    public var weightKgLeft: Double? = nil
    public var repsLeft: Int? = nil
    public var weightKgRight: Double? = nil
    public var repsRight: Int? = nil

    public var session: WorkoutSession? = nil
    public var exercise: Exercise? = nil

    public init(
        order: Int,
        session: WorkoutSession? = nil,
        exercise: Exercise? = nil,
        weightKg: Double,
        reps: Int,
        rir: Int = 2,
        type: SetType = .working,
        supersetGroup: Int? = nil,
        isCompleted: Bool = false,
        timestamp: Date = .now,
        isUnilateral: Bool = false,
        weightKgLeft: Double? = nil,
        repsLeft: Int? = nil,
        weightKgRight: Double? = nil,
        repsRight: Int? = nil
    ) {
        self.order = order
        self.session = session
        self.exercise = exercise
        self.weightKg = weightKg
        self.reps = reps
        self.rir = rir
        self.typeRaw = type.rawValue
        self.supersetGroup = supersetGroup
        self.isCompleted = isCompleted
        self.timestamp = timestamp
        self.isUnilateral = isUnilateral
        self.weightKgLeft = weightKgLeft
        self.repsLeft = repsLeft
        self.weightKgRight = weightKgRight
        self.repsRight = repsRight
    }

    public var type: SetType {
        get { SetType(rawValue: typeRaw) ?? .working }
        set { typeRaw = newValue.rawValue }
    }

    /// Calculates effective volume tonnage in kg considering bodyweight modes (standard, weighted, assisted) and unilateral sides.
    public func effectiveTonnageKg(userBodyweightKg: Double = 0.0) -> Double {
        let mode = exercise?.bodyweightMode ?? .standardLoad
        let baseLoad: Double
        switch mode {
        case .standardLoad:
            baseLoad = weightKg
        case .bodyweightOnly:
            baseLoad = userBodyweightKg > 0 ? userBodyweightKg : 70.0
        case .weightedBodyweight:
            baseLoad = (userBodyweightKg > 0 ? userBodyweightKg : 70.0) + weightKg
        case .assistedBodyweight:
            baseLoad = max(0.0, (userBodyweightKg > 0 ? userBodyweightKg : 70.0) - weightKg)
        }

        if isUnilateral {
            let leftLoad = weightKgLeft ?? weightKg
            let rightLoad = weightKgRight ?? weightKg
            let leftReps = Double(repsLeft ?? reps)
            let rightReps = Double(repsRight ?? reps)
            return (leftLoad * leftReps) + (rightLoad * rightReps)
        } else {
            return baseLoad * Double(reps)
        }
    }

    public var estimated1RMKg: Double {
        let k = exercise?.personalRepCurveK ?? ProgressionEngine.defaultEpleyK
        return ProgressionEngine.e1RM(weight: weightKg, reps: reps, rir: rir, k: k)
    }
}

@Model
public final class PersonalRecord {
    public var id: UUID = UUID()
    public var typeRaw: String = PRType.e1RM.rawValue
    public var value: Double = 0.0
    public var secondaryValue: Double = 0.0
    public var date: Date = Date()
    public var dayKey: String = ""

    public var exercise: Exercise? = nil

    public init(
        exercise: Exercise?,
        type: PRType,
        value: Double,
        secondaryValue: Double = 0.0,
        date: Date = .now
    ) {
        self.exercise = exercise
        self.typeRaw = type.rawValue
        self.value = value
        self.secondaryValue = secondaryValue
        self.date = date
        self.dayKey = DayKey.from(date)
    }

    public var type: PRType {
        get { PRType(rawValue: typeRaw) ?? .e1RM }
        set { typeRaw = newValue.rawValue }
    }
}
