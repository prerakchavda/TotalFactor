import Foundation
import SwiftUI

public enum AppTab: String, CaseIterable, Identifiable {
    case today
    case food
    case train
    case progress
    case settings

    public var id: String { rawValue }
}

/// More → Food Tracking switch. When off, the Food Log tab, food dock, nutrition cards, check-ins and
/// meal reminders are hidden. Logged food is never deleted, so turning it back on restores everything.
public enum FoodTrackingPreference {
    public static let key = "totalfactor.foodTrackingEnabled"

    public static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? true
    }
}

/// Settings → Workouts → "When a set goes off-target": weight first (default), reps first, or off.
public enum SetAdjustmentPreference {
    public static let key = "totalfactor.setAdjustmentMode"

    public static var mode: SetAdjustmentMode {
        get {
            guard let raw = UserDefaults.standard.string(forKey: key) else { return .weightFirst }
            return SetAdjustmentMode(rawValue: raw) ?? .weightFirst
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: key) }
    }
}

@MainActor
@Observable
public final class AppState {
    public static let shared = AppState()

    public var selectedTab: AppTab = .today
    public var selectedDayKey: String = DayKey.today
    public var showingQuickAddFood: Bool = false
    public var quickAddInitialTab: Int = 0 // 0=Search, 1=Scan, 2=Label, 3=Quick, 4=Recipes, 5=Describe/Voice
    public var quickAddDefaultMealTag: MealTag = .none
    public var quickAddAutoStartDictation: Bool = false
    public var showingWeighInSheet: Bool = false
    public var showingWeeklyCheckInSheet: Bool = false

    public var activeWorkoutSessionID: UUID? = nil
    public var showingActiveWorkoutFullScreen: Bool = false
    public var pendingShortcutWorkoutName: String? = nil

    public init() {
        for arg in ProcessInfo.processInfo.arguments {
            if arg.starts(with: "--tab="), let tab = AppTab(rawValue: String(arg.dropFirst("--tab=".count))) {
                selectedTab = tab
            }
        }
    }

    public func openQuickAdd(tab: Int = 0, mealTag: MealTag = .none, autoStartDictation: Bool = false) {
        quickAddInitialTab = tab
        quickAddDefaultMealTag = mealTag
        quickAddAutoStartDictation = autoStartDictation
        showingQuickAddFood = true
    }
}
