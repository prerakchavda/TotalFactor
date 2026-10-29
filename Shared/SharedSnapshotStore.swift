import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Lightweight App-Group-backed snapshot store so Widgets, Siri Shortcuts, and Live Activity Intents
/// can read & mutate state immediately without spinning up the full SwiftData container when unneeded.
public struct WidgetDashboardSnapshot: Codable, Equatable, Sendable {
    public var updatedAt: Date
    public var caloriesEaten: Double
    public var caloriesTarget: Double
    public var proteinEaten: Double
    public var proteinTarget: Double
    public var proteinFloor: Double
    public var carbsEaten: Double
    public var carbsTarget: Double
    public var fatEaten: Double
    public var fatTarget: Double
    public var trendWeightKg: Double?
    public var latestScaleWeightKg: Double?
    public var draftWeighInKg: Double?
    public var unitSystemRaw: String // "imperial" or "metric"
    public var expenditureKcal: Double
    public var expenditureConfidenceRaw: String
    public var nextWorkoutName: String?
    public var isTrainingDay: Bool
    public var activeRestEndDate: Date?
    public var activeRestTotalSeconds: Int
    public var activeRestExercise: String?

    public init(
        updatedAt: Date = .now,
        caloriesEaten: Double = 0,
        caloriesTarget: Double = 2200,
        proteinEaten: Double = 0,
        proteinTarget: Double = 165,
        proteinFloor: Double = 140,
        carbsEaten: Double = 0,
        carbsTarget: Double = 230,
        fatEaten: Double = 0,
        fatTarget: Double = 70,
        trendWeightKg: Double? = nil,
        latestScaleWeightKg: Double? = nil,
        draftWeighInKg: Double? = nil,
        unitSystemRaw: String = "imperial",
        expenditureKcal: Double = 2400,
        expenditureConfidenceRaw: String = "low",
        nextWorkoutName: String? = "Upper A",
        isTrainingDay: Bool = true,
        activeRestEndDate: Date? = nil,
        activeRestTotalSeconds: Int = 0,
        activeRestExercise: String? = nil
    ) {
        self.updatedAt = updatedAt
        self.caloriesEaten = caloriesEaten
        self.caloriesTarget = caloriesTarget
        self.proteinEaten = proteinEaten
        self.proteinTarget = proteinTarget
        self.proteinFloor = proteinFloor
        self.carbsEaten = carbsEaten
        self.carbsTarget = carbsTarget
        self.fatEaten = fatEaten
        self.fatTarget = fatTarget
        self.trendWeightKg = trendWeightKg
        self.latestScaleWeightKg = latestScaleWeightKg
        self.draftWeighInKg = draftWeighInKg
        self.unitSystemRaw = unitSystemRaw
        self.expenditureKcal = expenditureKcal
        self.expenditureConfidenceRaw = expenditureConfidenceRaw
        self.nextWorkoutName = nextWorkoutName
        self.isTrainingDay = isTrainingDay
        self.activeRestEndDate = activeRestEndDate
        self.activeRestTotalSeconds = activeRestTotalSeconds
        self.activeRestExercise = activeRestExercise
    }

    public var caloriesRemaining: Double {
        caloriesTarget - caloriesEaten
    }

    public var proteinRemaining: Double {
        max(0, proteinTarget - proteinEaten)
    }
}

public struct PendingQuickAction: Codable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case quickCalories
        case weighInKg
        case adjustRestSeconds
        case skipRestTimer
        case loggedFoodEntry
    }

    public var id: UUID
    public var kind: Kind
    public var numericValue: Double
    public var label: String
    public var createdAt: Date
    public var protein: Double
    public var carbs: Double
    public var fat: Double
    public var grams: Double
    public var servingLabel: String
    public var mealTagRaw: String

    public init(
        id: UUID = UUID(),
        kind: Kind,
        numericValue: Double,
        label: String = "",
        createdAt: Date = .now,
        protein: Double = 0,
        carbs: Double = 0,
        fat: Double = 0,
        grams: Double = 100,
        servingLabel: String = "1 serving",
        mealTagRaw: String = "none"
    ) {
        self.id = id
        self.kind = kind
        self.numericValue = numericValue
        self.label = label
        self.createdAt = createdAt
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.grams = grams
        self.servingLabel = servingLabel
        self.mealTagRaw = mealTagRaw
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.kind = try container.decode(Kind.self, forKey: .kind)
        self.numericValue = try container.decode(Double.self, forKey: .numericValue)
        self.label = try container.decode(String.self, forKey: .label)
        self.createdAt = try container.decode(Date.self, forKey: .createdAt)
        self.protein = try container.decodeIfPresent(Double.self, forKey: .protein) ?? 0
        self.carbs = try container.decodeIfPresent(Double.self, forKey: .carbs) ?? 0
        self.fat = try container.decodeIfPresent(Double.self, forKey: .fat) ?? 0
        self.grams = try container.decodeIfPresent(Double.self, forKey: .grams) ?? 100
        self.servingLabel = try container.decodeIfPresent(String.self, forKey: .servingLabel) ?? "1 serving"
        self.mealTagRaw = try container.decodeIfPresent(String.self, forKey: .mealTagRaw) ?? "none"
    }
}

public enum SharedSnapshotStore {
    public static let appGroupIdentifier = "group.com.totalfactor.app"
    private static let snapshotKey = "totalfactor.dashboard.snapshot.v1"
    private static let pendingActionsKey = "totalfactor.pending.actions.v1"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupIdentifier) ?? .standard
    }

    public static func load() -> WidgetDashboardSnapshot {
        guard let data = defaults.data(forKey: snapshotKey),
              let decoded = try? JSONDecoder().decode(WidgetDashboardSnapshot.self, from: data) else {
            return WidgetDashboardSnapshot()
        }
        return decoded
    }

    private static let lock = NSLock()
    private static var lastSavedNormalized: WidgetDashboardSnapshot? = nil

    public static func save(_ snapshot: WidgetDashboardSnapshot, reloadWidgets: Bool = true) {
        var normalized = snapshot
        normalized.updatedAt = Date(timeIntervalSince1970: 0)

        lock.lock()
        let unchanged = (lastSavedNormalized == normalized)
        if !unchanged {
            lastSavedNormalized = normalized
        }
        lock.unlock()

        guard !unchanged else { return }

        if let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: snapshotKey)
        }
        #if canImport(WidgetKit)
        if reloadWidgets {
            WidgetCenter.shared.reloadAllTimelines()
        }
        #endif
    }

    public static func enqueueAction(_ action: PendingQuickAction) {
        var queue = loadPendingActions()
        queue.append(action)
        if let data = try? JSONEncoder().encode(queue) {
            defaults.set(data, forKey: pendingActionsKey)
        }
    }

    public static func loadPendingActions() -> [PendingQuickAction] {
        guard let data = defaults.data(forKey: pendingActionsKey),
              let decoded = try? JSONDecoder().decode([PendingQuickAction].self, from: data) else {
            return []
        }
        return decoded
    }

    public static func consumePendingActions() -> [PendingQuickAction] {
        let actions = loadPendingActions()
        defaults.removeObject(forKey: pendingActionsKey)
        return actions
    }
}
