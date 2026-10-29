import Foundation
import SwiftData

@Model
public final class UserProfile {
    public var id: UUID = UUID()
    public var createdAt: Date = Date()
    public var onboardingCompleted: Bool = false

    public var unitSystemRaw: String = UnitSystem.imperial.rawValue
    public var biologicalSexRaw: String = BiologicalSex.male.rawValue
    public var birthYear: Int = 1996
    public var heightCm: Double = 178.0
    public var startingWeightKg: Double = 82.0
    public var activityLevelRaw: String = ActivityLevel.moderate.rawValue

    /// Settings (§5): first day of week (1=Sun, 2=Mon), weekly check-in weekday, daily weigh-in rule.
    public var firstDayOfWeek: Int = 2
    public var checkInWeekday: Int = 2 // Monday
    public var weighInRuleRaw: String = WeighInRule.firstMorning.rawValue
    public var enableTrainingDayCarbCycling: Bool = true
    public var overrideCalorieFloor: Bool = false
    public var usdaApiKey: String = "DEMO_KEY"
    public var enableCloudKitSync: Bool = false

    // Intermittent Fasting
    public var enableIntermittentFasting: Bool = false
    public var fastingProtocolRaw: String = FastingProtocol.sixteenEight.rawValue
    public var manualFastStartTime: Date? = nil
    public var isManualFastActive: Bool = false

    public init(
        onboardingCompleted: Bool = false,
        unitSystem: UnitSystem = .imperial,
        biologicalSex: BiologicalSex = .male,
        birthYear: Int = 1996,
        heightCm: Double = 178.0,
        startingWeightKg: Double = 82.0,
        activityLevel: ActivityLevel = .moderate
    ) {
        self.onboardingCompleted = onboardingCompleted
        self.unitSystemRaw = unitSystem.rawValue
        self.biologicalSexRaw = biologicalSex.rawValue
        self.birthYear = birthYear
        self.heightCm = heightCm
        self.startingWeightKg = startingWeightKg
        self.activityLevelRaw = activityLevel.rawValue
    }

    public var unitSystem: UnitSystem {
        get { UnitSystem(rawValue: unitSystemRaw) ?? .imperial }
        set { unitSystemRaw = newValue.rawValue }
    }

    public var biologicalSex: BiologicalSex {
        get { BiologicalSex(rawValue: biologicalSexRaw) ?? .male }
        set { biologicalSexRaw = newValue.rawValue }
    }

    public var activityLevel: ActivityLevel {
        get { ActivityLevel(rawValue: activityLevelRaw) ?? .moderate }
        set { activityLevelRaw = newValue.rawValue }
    }

    public var weighInRule: WeighInRule {
        get { WeighInRule(rawValue: weighInRuleRaw) ?? .firstMorning }
        set { weighInRuleRaw = newValue.rawValue }
    }

    public var fastingProtocol: FastingProtocol {
        get { FastingProtocol(rawValue: fastingProtocolRaw) ?? .sixteenEight }
        set { fastingProtocolRaw = newValue.rawValue }
    }

    public var ageYears: Int {
        let currentYear = Calendar.current.component(.year, from: .now)
        return max(15, min(100, currentYear - birthYear))
    }
}

@Model
public final class Goal {
    public var id: UUID = UUID()
    public var typeRaw: String = GoalType.cut.rawValue
    /// Magnitude as % of bodyweight per week (e.g. 0.5 = 0.5%/wk).
    public var ratePercentPerWeek: Double = 0.5
    public var startDate: Date = Date()
    public var startWeightKg: Double = 82.0
    public var targetWeightKg: Double? = nil
    public var isActive: Bool = true

    public init(
        type: GoalType = .cut,
        ratePercentPerWeek: Double = 0.5,
        startDate: Date = .now,
        startWeightKg: Double = 82.0,
        targetWeightKg: Double? = nil,
        isActive: Bool = true
    ) {
        self.typeRaw = type.rawValue
        self.ratePercentPerWeek = ratePercentPerWeek
        self.startDate = startDate
        self.startWeightKg = startWeightKg
        self.targetWeightKg = targetWeightKg
        self.isActive = isActive
    }

    public var type: GoalType {
        get { GoalType(rawValue: typeRaw) ?? .maintain }
        set { typeRaw = newValue.rawValue }
    }
}

@Model
public final class NutrientTarget {
    public var id: UUID = UUID()
    public var nutrient: String = ""
    public var unit: String = "g"
    public var floor: Double? = nil
    public var target: Double? = nil
    public var ceiling: Double? = nil

    public init(
        nutrient: String,
        unit: String = "g",
        floor: Double? = nil,
        target: Double? = nil,
        ceiling: Double? = nil
    ) {
        self.nutrient = nutrient
        self.unit = unit
        self.floor = floor
        self.target = target
        self.ceiling = ceiling
    }

    public var asStruct: NutrientZoneTarget {
        NutrientZoneTarget(nutrient: nutrient, unit: unit, floor: floor, target: target, ceiling: ceiling)
    }
}
