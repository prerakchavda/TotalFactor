import Foundation
import SwiftData

@Model
public final class ExpenditureEstimate {
    public var id: UUID = UUID()
    public var date: Date = Date()
    public var dayKey: String = ""
    public var value: Double = 2400.0
    public var confidenceRaw: String = ConfidenceLevel.low.rawValue
    public var methodRaw: String = ExpenditureMethod.formula.rawValue
    public var completeDaysCount: Int = 0
    public var weighInsCount: Int = 0

    public init(
        date: Date = .now,
        dayKey: String? = nil,
        value: Double,
        confidence: ConfidenceLevel = .low,
        method: ExpenditureMethod = .formula,
        completeDaysCount: Int = 0,
        weighInsCount: Int = 0
    ) {
        self.date = date
        self.dayKey = dayKey ?? DayKey.from(date)
        self.value = value
        self.confidenceRaw = confidence.rawValue
        self.methodRaw = method.rawValue
        self.completeDaysCount = completeDaysCount
        self.weighInsCount = weighInsCount
    }

    public var confidence: ConfidenceLevel {
        get { ConfidenceLevel(rawValue: confidenceRaw) ?? .low }
        set { confidenceRaw = newValue.rawValue }
    }

    public var method: ExpenditureMethod {
        get { ExpenditureMethod(rawValue: methodRaw) ?? .formula }
        set { methodRaw = newValue.rawValue }
    }
}

@Model
public final class WeeklyCheckIn {
    public var id: UUID = UUID()
    public var date: Date = Date()
    public var dayKey: String = ""
    public var expenditure: Double = 2400.0
    public var previousExpenditure: Double = 2400.0
    public var weightTrendChangeKg: Double = 0.0
    public var targetsJSON: Data = Data()
    public var trainingDayTargetsJSON: Data = Data()
    public var restDayTargetsJSON: Data = Data()
    public var explanation: String = ""

    // Phase 8 (§12): Check-in includes training summary
    public var sessionsCompleted: Int = 0
    public var weeklyVolumeKg: Double = 0.0
    public var prsHitCount: Int = 0

    /// `true` once accepted, `false` while pending or skipped.
    public var accepted: Bool = false
    public var skipped: Bool = false

    public init(
        date: Date = .now,
        dayKey: String? = nil,
        expenditure: Double,
        previousExpenditure: Double,
        weightTrendChangeKg: Double,
        targets: MacroTargets,
        trainingDayTargets: MacroTargets,
        restDayTargets: MacroTargets,
        explanation: String,
        sessionsCompleted: Int = 0,
        weeklyVolumeKg: Double = 0,
        prsHitCount: Int = 0,
        accepted: Bool = false
    ) {
        self.date = date
        self.dayKey = dayKey ?? DayKey.from(date)
        self.expenditure = expenditure
        self.previousExpenditure = previousExpenditure
        self.weightTrendChangeKg = weightTrendChangeKg
        self.explanation = explanation
        self.sessionsCompleted = sessionsCompleted
        self.weeklyVolumeKg = weeklyVolumeKg
        self.prsHitCount = prsHitCount
        self.accepted = accepted
        self.targets = targets
        self.trainingDayTargets = trainingDayTargets
        self.restDayTargets = restDayTargets
    }

    public var targets: MacroTargets {
        get {
            (try? JSONDecoder().decode(MacroTargets.self, from: targetsJSON)) ??
            MacroTargets(calories: 2200, protein: 165, carbs: 220, fat: 70, proteinFloor: 140, fatFloor: 50)
        }
        set {
            targetsJSON = (try? JSONEncoder().encode(newValue)) ?? Data()
        }
    }

    public var trainingDayTargets: MacroTargets {
        get {
            (try? JSONDecoder().decode(MacroTargets.self, from: trainingDayTargetsJSON)) ?? targets
        }
        set {
            trainingDayTargetsJSON = (try? JSONEncoder().encode(newValue)) ?? Data()
        }
    }

    public var restDayTargets: MacroTargets {
        get {
            (try? JSONDecoder().decode(MacroTargets.self, from: restDayTargetsJSON)) ?? targets
        }
        set {
            restDayTargetsJSON = (try? JSONEncoder().encode(newValue)) ?? Data()
        }
    }
}
