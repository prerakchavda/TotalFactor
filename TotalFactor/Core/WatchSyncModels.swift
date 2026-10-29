import Foundation

/// Shared `WatchConnectivity` (`WCSession`) wire models between iOS (`com.prerak.totalfactor`)
/// and watchOS 10+ (`com.prerak.totalfactor.watchkitapp`), requiring zero paid App Group entitlements.
public struct WatchWorkoutTemplateDTO: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var exerciseCount: Int
    public var workingSetCount: Int

    public init(id: UUID, name: String, exerciseCount: Int, workingSetCount: Int) {
        self.id = id
        self.name = name
        self.exerciseCount = exerciseCount
        self.workingSetCount = workingSetCount
    }
}

public struct WatchSetItemDTO: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var order: Int
    public var exerciseID: UUID
    public var exerciseName: String
    public var setNumberInExercise: Int
    public var totalSetsInExercise: Int
    public var setTypeBadge: String
    public var weightKg: Double
    public var reps: Int
    public var rir: Int
    public var restSeconds: Int
    public var loadIncrementKg: Double
    public var isCompleted: Bool

    public init(
        id: UUID,
        order: Int,
        exerciseID: UUID,
        exerciseName: String,
        setNumberInExercise: Int,
        totalSetsInExercise: Int,
        setTypeBadge: String,
        weightKg: Double,
        reps: Int,
        rir: Int,
        restSeconds: Int,
        loadIncrementKg: Double,
        isCompleted: Bool
    ) {
        self.id = id
        self.order = order
        self.exerciseID = exerciseID
        self.exerciseName = exerciseName
        self.setNumberInExercise = setNumberInExercise
        self.totalSetsInExercise = totalSetsInExercise
        self.setTypeBadge = setTypeBadge
        self.weightKg = weightKg
        self.reps = reps
        self.rir = rir
        self.restSeconds = restSeconds
        self.loadIncrementKg = max(0.5, loadIncrementKg)
        self.isCompleted = isCompleted
    }
}

public struct WatchActiveSessionDTO: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var startedAt: Date
    public var sets: [WatchSetItemDTO]

    public init(id: UUID, title: String, startedAt: Date, sets: [WatchSetItemDTO]) {
        self.id = id
        self.title = title
        self.startedAt = startedAt
        self.sets = sets
    }

    public var completedCount: Int {
        sets.filter(\.isCompleted).count
    }
}

public struct WatchSyncStateSnapshot: Codable, Equatable, Sendable {
    public static let contextKey = "tf_watch_snapshot_v1"

    public var updatedAt: Date
    public var unitSystemRaw: String // "imperial" or "metric"
    public var caloriesRemaining: Double
    public var caloriesTarget: Double
    public var caloriesEaten: Double
    public var proteinRemaining: Double
    public var proteinTarget: Double
    public var carbsRemaining: Double
    public var carbsTarget: Double
    public var fatRemaining: Double
    public var fatTarget: Double
    public var isTrainingDay: Bool
    public var trendWeightKg: Double?
    public var latestScaleWeightKg: Double?
    public var scheduledWorkoutID: UUID?
    public var scheduledWorkoutName: String?
    public var availableWorkouts: [WatchWorkoutTemplateDTO]
    public var activeSession: WatchActiveSessionDTO?
    public var restEndDate: Date?
    public var restTotalSeconds: Int
    public var restExerciseName: String
    public var restNextSummary: String

    public init(
        updatedAt: Date = .now,
        unitSystemRaw: String = "imperial",
        caloriesRemaining: Double = 2200,
        caloriesTarget: Double = 2200,
        caloriesEaten: Double = 0,
        proteinRemaining: Double = 165,
        proteinTarget: Double = 165,
        carbsRemaining: Double = 220,
        carbsTarget: Double = 220,
        fatRemaining: Double = 70,
        fatTarget: Double = 70,
        isTrainingDay: Bool = true,
        trendWeightKg: Double? = nil,
        latestScaleWeightKg: Double? = nil,
        scheduledWorkoutID: UUID? = nil,
        scheduledWorkoutName: String? = nil,
        availableWorkouts: [WatchWorkoutTemplateDTO] = [],
        activeSession: WatchActiveSessionDTO? = nil,
        restEndDate: Date? = nil,
        restTotalSeconds: Int = 0,
        restExerciseName: String = "",
        restNextSummary: String = ""
    ) {
        self.updatedAt = updatedAt
        self.unitSystemRaw = unitSystemRaw
        self.caloriesRemaining = caloriesRemaining
        self.caloriesTarget = caloriesTarget
        self.caloriesEaten = caloriesEaten
        self.proteinRemaining = proteinRemaining
        self.proteinTarget = proteinTarget
        self.carbsRemaining = carbsRemaining
        self.carbsTarget = carbsTarget
        self.fatRemaining = fatRemaining
        self.fatTarget = fatTarget
        self.isTrainingDay = isTrainingDay
        self.trendWeightKg = trendWeightKg
        self.latestScaleWeightKg = latestScaleWeightKg
        self.scheduledWorkoutID = scheduledWorkoutID
        self.scheduledWorkoutName = scheduledWorkoutName
        self.availableWorkouts = availableWorkouts
        self.activeSession = activeSession
        self.restEndDate = restEndDate
        self.restTotalSeconds = restTotalSeconds
        self.restExerciseName = restExerciseName
        self.restNextSummary = restNextSummary
    }

    public var isImperial: Bool {
        unitSystemRaw == "imperial"
    }

    public var weightUnitSymbol: String {
        isImperial ? "lb" : "kg"
    }

    public func displayWeight(_ kg: Double) -> Double {
        isImperial ? (kg * 2.2046226218) : kg
    }

    public func internalKg(fromDisplay value: Double) -> Double {
        isImperial ? (value / 2.2046226218) : value
    }

    public func formatLoad(_ kg: Double) -> String {
        let disp = displayWeight(kg)
        let roundedHalf = (disp * 2.0).rounded() / 2.0
        if abs(roundedHalf.rounded() - roundedHalf) < 0.05 {
            return "\(Int(roundedHalf.rounded())) \(weightUnitSymbol)"
        }
        return String(format: "%.1f %@", roundedHalf, weightUnitSymbol)
    }

    public func formatBodyWeight(_ kg: Double) -> String {
        String(format: "%.1f %@", displayWeight(kg), weightUnitSymbol)
    }

    public func toApplicationContext() -> [String: Any]? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return [
            Self.contextKey: data,
            "ts": updatedAt.timeIntervalSince1970
        ]
    }

    public static func fromApplicationContext(_ dict: [String: Any]) -> WatchSyncStateSnapshot? {
        guard let data = dict[Self.contextKey] as? Data else { return nil }
        return try? JSONDecoder().decode(WatchSyncStateSnapshot.self, from: data)
    }
}

public struct WatchCommandPayload: Codable, Equatable, Identifiable, Sendable {
    public static let wireKey = "tf_watch_cmd_v1"

    public enum Action: String, Codable, Sendable {
        case requestSync
        case toggleSetComplete
        case updateSetValues
        case addSet
        case adjustRestTimer
        case skipRestTimer
        case startWorkout
        case finishWorkout
        case liveHeartRate
        case logWeighIn
    }

    public var id: UUID
    public var createdAt: Date
    public var action: Action
    public var setID: UUID?
    public var exerciseID: UUID?
    public var programWorkoutID: UUID?
    public var weightKg: Double?
    public var reps: Int?
    public var rir: Int?
    public var restSeconds: Int?
    public var deltaSeconds: Int?
    public var heartRateBPM: Double?
    public var activeCaloriesDisplayOnly: Double?

    public init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        action: Action,
        setID: UUID? = nil,
        exerciseID: UUID? = nil,
        programWorkoutID: UUID? = nil,
        weightKg: Double? = nil,
        reps: Int? = nil,
        rir: Int? = nil,
        restSeconds: Int? = nil,
        deltaSeconds: Int? = nil,
        heartRateBPM: Double? = nil,
        activeCaloriesDisplayOnly: Double? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.action = action
        self.setID = setID
        self.exerciseID = exerciseID
        self.programWorkoutID = programWorkoutID
        self.weightKg = weightKg
        self.reps = reps
        self.rir = rir
        self.restSeconds = restSeconds
        self.deltaSeconds = deltaSeconds
        self.heartRateBPM = heartRateBPM
        self.activeCaloriesDisplayOnly = activeCaloriesDisplayOnly
    }

    public func toData() -> Data? {
        try? JSONEncoder().encode(self)
    }

    public static func fromData(_ data: Data) -> WatchCommandPayload? {
        try? JSONDecoder().decode(WatchCommandPayload.self, from: data)
    }

    public func toUserInfo() -> [String: Any]? {
        guard let data = toData() else { return nil }
        return [
            Self.wireKey: data,
            "id": id.uuidString
        ]
    }

    public static func fromUserInfo(_ dict: [String: Any]) -> WatchCommandPayload? {
        guard let data = dict[Self.wireKey] as? Data else { return nil }
        return fromData(data)
    }
}
