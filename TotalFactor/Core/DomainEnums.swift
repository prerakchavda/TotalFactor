import Foundation

// MARK: - User & Coaching Enums

public enum UnitSystem: String, Codable, CaseIterable, Identifiable, Sendable {
    case imperial
    case metric

    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .imperial: return "Imperial (lb, ft/in)"
        case .metric: return "Metric (kg, cm)"
        }
    }
    public var weightSymbol: String { self == .imperial ? "lb" : "kg" }
    public var lengthSymbol: String { self == .imperial ? "in" : "cm" }
}

public enum BiologicalSex: String, Codable, CaseIterable, Identifiable, Sendable {
    case male
    case female

    public var id: String { rawValue }
    public var displayName: String { rawValue.capitalized }
    public var defaultCalorieFloor: Double {
        switch self {
        case .male: return 1500
        case .female: return 1200
        }
    }
}

public enum ActivityLevel: String, Codable, CaseIterable, Identifiable, Sendable {
    case sedentary
    case light
    case moderate
    case veryActive

    public var id: String { rawValue }

    public var multiplier: Double {
        switch self {
        case .sedentary: return 1.2
        case .light: return 1.375
        case .moderate: return 1.55
        case .veryActive: return 1.725
        }
    }

    public var displayName: String {
        switch self {
        case .sedentary: return "Sedentary (desk job, <5k steps)"
        case .light: return "Lightly Active (1-3 workouts or 6-8k steps)"
        case .moderate: return "Moderately Active (3-5 workouts or 8-11k steps)"
        case .veryActive: return "Very Active (hard training / physical job, 12k+ steps)"
        }
    }
}

public enum GoalType: String, Codable, CaseIterable, Identifiable, Sendable {
    case cut
    case maintain
    case bulk

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .cut: return "Lose Fat (Cut)"
        case .maintain: return "Maintain"
        case .bulk: return "Gain Muscle (Bulk)"
        }
    }

    /// Suggested weekly rate magnitude (% bodyweight / week) per spec §8.
    public var suggestedRateRangePercent: ClosedRange<Double> {
        switch self {
        case .cut: return 0.25...1.0
        case .maintain: return 0.0...0.0
        case .bulk: return 0.10...0.50
        }
    }

    public var defaultRatePercent: Double {
        switch self {
        case .cut: return 0.50
        case .maintain: return 0.0
        case .bulk: return 0.25
        }
    }
}

public enum ConfidenceLevel: String, Codable, CaseIterable, Identifiable, Sendable {
    case low
    case medium
    case high

    public var id: String { rawValue }
    public var displayName: String { rawValue.capitalized }

    public var explanation: String {
        switch self {
        case .low:
            return "Fewer than 14 complete logged days — heavily anchored to Mifflin-St Jeor formula."
        case .medium:
            return "14–27 days of intake & trend weight data — adaptive estimate is calibrating."
        case .high:
            return "28+ days with ≥80% food logging & ≥4 weigh-ins/wk — high-trust personal TDEE."
        }
    }
}

public enum ExpenditureMethod: String, Codable, CaseIterable, Sendable {
    case formula
    case adaptive

    public var displayName: String {
        switch self {
        case .formula: return "Formula Baseline"
        case .adaptive: return "Adaptive Feedback"
        }
    }
}

// MARK: - Nutrition Enums & Value Structs

public enum FoodSource: String, Codable, CaseIterable, Identifiable, Sendable {
    case usda
    case off
    case custom
    case recipe
    case healthKit

    public var id: String { rawValue }

    public var badgeTitle: String {
        switch self {
        case .usda: return "USDA Verified"
        case .off: return "Open Food Facts (Crowdsourced)"
        case .custom: return "Custom"
        case .recipe: return "Recipe"
        case .healthKit: return "Apple Health (External)"
        }
    }

    public var shortBadge: String {
        switch self {
        case .usda: return "USDA"
        case .off: return "OFF"
        case .custom: return "Custom"
        case .recipe: return "Recipe"
        case .healthKit: return "Health"
        }
    }

    public var trustScore: Int {
        switch self {
        case .usda: return 3
        case .custom, .recipe, .healthKit: return 2
        case .off: return 1
        }
    }
}

public enum FastingProtocol: String, Codable, CaseIterable, Identifiable, Sendable {
    case sixteenEight = "16:8"
    case eighteenSix = "18:6"
    case twentyFour = "20:4"
    case omad = "OMAD"
    case fourteenTen = "14:10"
    case circadian = "Circadian"

    public var id: String { rawValue }

    public var fastHours: Double {
        switch self {
        case .circadian: return 13.0
        case .fourteenTen: return 14.0
        case .sixteenEight: return 16.0
        case .eighteenSix: return 18.0
        case .twentyFour: return 20.0
        case .omad: return 23.0
        }
    }

    public var eatingHours: Double {
        24.0 - fastHours
    }

    public var displayName: String {
        switch self {
        case .circadian: return "Circadian (13:11)"
        case .fourteenTen: return "14:10 Moderate"
        case .sixteenEight: return "16:8 LeanGains (Standard)"
        case .eighteenSix: return "18:6 Deep Fast"
        case .twentyFour: return "20:4 Warrior Diet"
        case .omad: return "OMAD (One Meal A Day)"
        }
    }
}

public enum ProgramScheduleMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case fixedWeekdays = "fixedWeekdays"
    case rollingSplit = "rollingSplit"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .fixedWeekdays: return "Fixed Weekdays (Mon/Wed/Fri...)"
        case .rollingSplit: return "Rolling Split (Any Day / Flexible)"
        }
    }

    public var summary: String {
        switch self {
        case .fixedWeekdays: return "Assigns workouts to specific calendar days."
        case .rollingSplit: return "Sequentially cycles workouts whenever you train, on any day."
        }
    }
}

public enum MealTag: String, Codable, CaseIterable, Identifiable, Sendable {
    case none
    case breakfast
    case lunch
    case dinner
    case snack
    case preWorkout
    case postWorkout

    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .none: return "Untagged"
        case .breakfast: return "Breakfast"
        case .lunch: return "Lunch"
        case .dinner: return "Dinner"
        case .snack: return "Snack"
        case .preWorkout: return "Pre-Workout"
        case .postWorkout: return "Post-Workout"
        }
    }
}

public struct ServingSize: Codable, Hashable, Identifiable, Sendable {
    public var id: String { "\(label)-\(grams)" }
    public var label: String
    public var grams: Double

    public init(label: String, grams: Double) {
        self.label = label
        self.grams = max(0.1, grams)
    }
}

public enum MicronutrientKey: String, Codable, CaseIterable, Identifiable, Sendable {
    case potassiumMg = "potassium_mg"
    case calciumMg = "calcium_mg"
    case ironMg = "iron_mg"
    case vitaminDMcg = "vitamin_d_mcg"
    case vitaminCMg = "vitamin_c_mg"
    case magnesiumMg = "magnesium_mg"
    case zincMg = "zinc_mg"
    case cholesterolMg = "cholesterol_mg"
    case saturatedFatG = "saturated_fat_g"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .potassiumMg: return "Potassium"
        case .calciumMg: return "Calcium"
        case .ironMg: return "Iron"
        case .vitaminDMcg: return "Vitamin D"
        case .vitaminCMg: return "Vitamin C"
        case .magnesiumMg: return "Magnesium"
        case .zincMg: return "Zinc"
        case .cholesterolMg: return "Cholesterol"
        case .saturatedFatG: return "Saturated Fat"
        }
    }

    public var unit: String {
        switch self {
        case .vitaminDMcg: return "mcg"
        case .saturatedFatG: return "g"
        default: return "mg"
        }
    }
}

public struct NutrientsPer100g: Codable, Hashable, Sendable {
    public var calories: Double
    public var protein: Double
    public var carbs: Double
    public var fat: Double
    public var fiber: Double
    public var sugar: Double
    public var sodiumMg: Double
    public var micronutrients: [String: Double]

    public init(
        calories: Double = 0,
        protein: Double = 0,
        carbs: Double = 0,
        fat: Double = 0,
        fiber: Double = 0,
        sugar: Double = 0,
        sodiumMg: Double = 0,
        micronutrients: [String: Double] = [:]
    ) {
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.fiber = fiber
        self.sugar = sugar
        self.sodiumMg = sodiumMg
        self.micronutrients = micronutrients
    }

    public func scaled(forGrams grams: Double) -> NutrientsPer100g {
        let factor = max(0, grams) / 100.0
        var scaledMicros: [String: Double] = [:]
        for (k, v) in micronutrients {
            scaledMicros[k] = v * factor
        }
        return NutrientsPer100g(
            calories: calories * factor,
            protein: protein * factor,
            carbs: carbs * factor,
            fat: fat * factor,
            fiber: fiber * factor,
            sugar: sugar * factor,
            sodiumMg: sodiumMg * factor,
            micronutrients: scaledMicros
        )
    }

    /// Atwater implied calories: 4 * P + 4 * C + 9 * F.
    public var atwaterCalories: Double {
        (protein * 4.0) + (carbs * 4.0) + (fat * 9.0)
    }
}

public struct NutrientZoneTarget: Codable, Hashable, Identifiable, Sendable {
    public var id: String { nutrient }
    public var nutrient: String
    public var unit: String
    public var floor: Double?
    public var target: Double?
    public var ceiling: Double?

    public init(nutrient: String, unit: String, floor: Double? = nil, target: Double? = nil, ceiling: Double? = nil) {
        self.nutrient = nutrient
        self.unit = unit
        self.floor = floor
        self.target = target
        self.ceiling = ceiling
    }
}

public struct MacroTargets: Codable, Hashable, Sendable {
    public var calories: Double
    public var protein: Double
    public var carbs: Double
    public var fat: Double
    public var proteinFloor: Double
    public var fatFloor: Double
    public var fiberFloor: Double
    public var sodiumCeilingMg: Double
    public var calorieFloorApplied: Bool

    public init(
        calories: Double,
        protein: Double,
        carbs: Double,
        fat: Double,
        proteinFloor: Double,
        fatFloor: Double,
        fiberFloor: Double = 28,
        sodiumCeilingMg: Double = 2300,
        calorieFloorApplied: Bool = false
    ) {
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.proteinFloor = proteinFloor
        self.fatFloor = fatFloor
        self.fiberFloor = fiberFloor
        self.sodiumCeilingMg = sodiumCeilingMg
        self.calorieFloorApplied = calorieFloorApplied
    }
}

// MARK: - Body Tracking Enums

public enum WeighInSource: String, Codable, CaseIterable, Sendable {
    case manual
    case healthKit
}

public enum WeighInRule: String, Codable, CaseIterable, Identifiable, Sendable {
    case firstMorning
    case average
    case last

    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .firstMorning: return "First Morning Weigh-In"
        case .average: return "Daily Average"
        case .last: return "Latest Weigh-In"
        }
    }

    public var explanation: String {
        switch self {
        case .firstMorning: return "Uses the earliest recorded weigh-in of the day for expenditure trend calculations."
        case .average: return "Averages all scale weigh-ins logged within the calendar day."
        case .last: return "Uses the most recent scale weigh-in logged on that day."
        }
    }
}

public enum BodyMetricType: String, Codable, CaseIterable, Identifiable, Sendable {
    case leanBodyMass
    case bodyFat
    case waist
    case chest
    case arm
    case thigh
    case hips
    case neck

    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .leanBodyMass: return "Lean Body Mass"
        case .bodyFat: return "Body Fat %"
        case .waist: return "Waist"
        case .chest: return "Chest"
        case .arm: return "Arm (Flexed)"
        case .thigh: return "Thigh"
        case .hips: return "Hips"
        case .neck: return "Neck"
        }
    }

    public func unitLabel(for system: UnitSystem) -> String {
        switch self {
        case .bodyFat: return "%"
        case .leanBodyMass: return system.weightSymbol
        default: return system.lengthSymbol
        }
    }

    /// Converts canonical stored metric (`kg` for `.leanBodyMass`, `%` for `.bodyFat`, `cm` for circumferences) to display units.
    public func displayValue(_ storedValue: Double, system: UnitSystem) -> Double {
        switch self {
        case .bodyFat: return storedValue
        case .leanBodyMass: return UnitsFormatter.displayWeight(storedValue, system: system)
        default: return UnitsFormatter.displayLength(storedValue, system: system)
        }
    }

    /// Converts user-entered display units back to canonical internal storage (`kg` / `%` / `cm`).
    public func internalValue(fromDisplay displayVal: Double, system: UnitSystem) -> Double {
        switch self {
        case .bodyFat: return displayVal
        case .leanBodyMass: return UnitsFormatter.internalKg(fromDisplay: displayVal, system: system)
        default: return UnitsFormatter.internalCm(fromDisplay: displayVal, system: system)
        }
    }
}

public enum PhotoPose: String, Codable, CaseIterable, Identifiable, Sendable {
    case front
    case side
    case back

    public var id: String { rawValue }
    public var displayName: String { rawValue.capitalized }
}

// MARK: - Training Enums

public enum MuscleGroup: String, Codable, CaseIterable, Identifiable, Sendable {
    case chest
    case lats
    case upperBack
    case frontDelts
    case sideDelts
    case rearDelts
    case biceps
    case triceps
    case forearms
    case quads
    case hamstrings
    case glutes
    case calves
    case abs
    case traps

    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .chest: return "Chest"
        case .lats: return "Lats"
        case .upperBack: return "Upper Back"
        case .frontDelts: return "Front Delts"
        case .sideDelts: return "Side Delts"
        case .rearDelts: return "Rear Delts"
        case .biceps: return "Biceps"
        case .triceps: return "Triceps"
        case .forearms: return "Forearms"
        case .quads: return "Quads"
        case .hamstrings: return "Hamstrings"
        case .glutes: return "Glutes"
        case .calves: return "Calves"
        case .abs: return "Abs / Core"
        case .traps: return "Traps"
        }
    }
}

public enum Equipment: String, Codable, CaseIterable, Identifiable, Sendable {
    case barbell
    case dumbbell
    case cable
    case machine
    case bodyweight
    case ezBar
    case smithMachine
    case kettlebell
    case trapBar
    case bands

    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .barbell: return "Barbell"
        case .dumbbell: return "Dumbbells"
        case .cable: return "Cable Stack"
        case .machine: return "Machine"
        case .bodyweight: return "Bodyweight"
        case .ezBar: return "EZ-Curl Bar"
        case .smithMachine: return "Smith Machine"
        case .kettlebell: return "Kettlebell"
        case .trapBar: return "Trap / Hex Bar"
        case .bands: return "Resistance Bands"
        }
    }

    public var usesBarbellPlates: Bool {
        self == .barbell || self == .ezBar || self == .trapBar || self == .smithMachine
    }
}

public enum MovementPattern: String, Codable, CaseIterable, Identifiable, Sendable {
    case squat
    case hinge
    case horizontalPush
    case verticalPush
    case horizontalPull
    case verticalPull
    case carry
    case isolation

    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .squat: return "Squat"
        case .hinge: return "Hinge"
        case .horizontalPush: return "Horizontal Push"
        case .verticalPush: return "Vertical Push"
        case .horizontalPull: return "Horizontal Pull"
        case .verticalPull: return "Vertical Pull"
        case .carry: return "Loaded Carry"
        case .isolation: return "Isolation"
        }
    }

    public var isCompound: Bool {
        self != .isolation
    }
}

public enum SetType: String, Codable, CaseIterable, Identifiable, Sendable {
    case warmup
    case working
    case drop
    case failure
    case partial
    case myorep

    public var id: String { rawValue }
    public var badge: String {
        switch self {
        case .warmup: return "W"
        case .working: return "WK"
        case .drop: return "D"
        case .failure: return "F"
        case .partial: return "P"
        case .myorep: return "M"
        }
    }
    public var displayName: String {
        switch self {
        case .myorep: return "Myo-rep"
        default: return rawValue.capitalized
        }
    }

    public var countsTowardWorkingStats: Bool {
        switch self {
        case .working, .drop, .failure, .myorep: return true
        case .warmup, .partial: return false
        }
    }
}

public enum BodyweightMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case standardLoad
    case bodyweightOnly
    case weightedBodyweight
    case assistedBodyweight

    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .standardLoad: return "Standard Load (Bar / Dumbbell / Cable)"
        case .bodyweightOnly: return "Bodyweight (0)"
        case .weightedBodyweight: return "Weighted Bodyweight (+)"
        case .assistedBodyweight: return "Assisted Bodyweight (-)"
        }
    }
}

public enum ProgressionRule: String, Codable, CaseIterable, Identifiable, Sendable {
    case doubleProgression
    case linearLoad
    case rpeAutoRegulated

    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .doubleProgression: return "Double Progression (Rep Range -> Add Weight)"
        case .linearLoad: return "Linear Load"
        case .rpeAutoRegulated: return "RIR / e1RM Auto-Regulated"
        }
    }
}

public enum PRType: String, Codable, CaseIterable, Identifiable, Sendable {
    case e1RM
    case heaviestWeight
    case mostRepsAtWeight
    case bestSessionVolume

    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .e1RM: return "Estimated 1RM"
        case .heaviestWeight: return "Heaviest Load"
        case .mostRepsAtWeight: return "Rep PR"
        case .bestSessionVolume: return "Best Volume"
        }
    }
}

public enum TrainingGoalFocus: String, Codable, CaseIterable, Identifiable, Sendable {
    case strength
    case hypertrophy
    case both

    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .strength: return "Maximal Strength"
        case .hypertrophy: return "Muscle Size (Hypertrophy)"
        case .both: return "Powerbuilding (Strength + Size)"
        }
    }
}

public enum ExperienceLevel: String, Codable, CaseIterable, Identifiable, Sendable {
    case beginner
    case intermediate
    case advanced

    public var id: String { rawValue }
    public var displayName: String { rawValue.capitalized }

    public var targetWeeklyHardSetsPerMuscle: Int {
        switch self {
        case .beginner: return 10
        case .intermediate: return 13
        case .advanced: return 16
        }
    }
}
