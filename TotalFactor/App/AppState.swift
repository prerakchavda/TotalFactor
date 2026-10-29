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

    public init() {}

    public func openQuickAdd(tab: Int = 0, mealTag: MealTag = .none, autoStartDictation: Bool = false) {
        quickAddInitialTab = tab
        quickAddDefaultMealTag = mealTag
        quickAddAutoStartDictation = autoStartDictation
        showingQuickAddFood = true
    }
}
