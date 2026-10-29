import SwiftUI
import SwiftData

struct GoalStrategySettingsView: View {
    @Environment(\.modelContext) private var modelContext

    @Query private var profiles: [UserProfile]
    @Query private var goals: [Goal]
    @Query private var customNutrientTargets: [NutrientTarget]

    private var profile: UserProfile {
        profiles.first ?? CoachingCoordinator.fetchOrCreateProfile(context: modelContext)
    }

    private var goal: Goal {
        goals.first(where: \.isActive) ?? CoachingCoordinator.fetchOrCreateGoal(profile: profile, context: modelContext)
    }

    var body: some View {
        @Bindable var bindableProfile = profile
        @Bindable var bindableGoal = goal

        Form {
            Section("Active Goal & Strategy") {
                Picker("Active Goal", selection: $bindableGoal.type) {
                    ForEach(GoalType.allCases) { g in
                        Text(g.displayName).tag(g)
                    }
                }
                .pickerStyle(.segmented)

                if bindableGoal.type != .maintain {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Weekly Target Rate")
                            Spacer()
                            let weeklyKg = bindableGoal.startWeightKg * (bindableGoal.ratePercentPerWeek / 100.0)
                            let weeklyDisp = UnitsFormatter.formatWeight(weeklyKg, system: bindableProfile.unitSystem)
                            Text(String(format: "%.2f%% BW/wk (~%@/wk)", bindableGoal.ratePercentPerWeek, weeklyDisp))
                                .font(.subheadline.weight(.semibold).monospacedDigit())
                        }

                        Slider(
                            value: $bindableGoal.ratePercentPerWeek,
                            in: bindableGoal.type.suggestedRateRangePercent,
                            step: 0.05
                        )
                    }
                } else {
                    Text("Total Factor dynamically matches your caloric intake targets to your expenditure to keep weight stable within a natural ±1.5% body weight fluid buffer.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Nutrition Rules & Cycling") {
                Toggle("Training-Day Carb Cycling (§12)", isOn: $bindableProfile.enableTrainingDayCarbCycling)
                Text("Shifts carbohydrates and calories higher on workout days and lower on rest days for improved training glycogen and recovery.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Toggle("Allow Targets Below BMR / Safety Floor", isOn: $bindableProfile.overrideCalorieFloor)
                Text("When disabled, Total Factor enforces minimum calorie safety floors (1,500 kcal for men, 1,200 kcal for women) regardless of deficit magnitude.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Section("Custom Nutrient Floors & Ceilings") {
                NavigationLink {
                    NutrientTargetsEditorView()
                } label: {
                    HStack {
                        Label("Micronutrient Targets", systemImage: "slider.horizontal.3")
                        Spacer()
                        if !customNutrientTargets.isEmpty {
                            Text("\(customNutrientTargets.count) configured")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
            }
        }
        .navigationTitle("Goals & Strategy")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: bindableGoal.ratePercentPerWeek) { _, _ in
            try? modelContext.save()
            _ = CoachingCoordinator.evaluate(context: modelContext)
        }
        .onChange(of: bindableGoal.typeRaw) { _, newRaw in
            if let newType = GoalType(rawValue: newRaw) {
                if newType == .maintain {
                    bindableGoal.ratePercentPerWeek = 0.0
                } else if !newType.suggestedRateRangePercent.contains(bindableGoal.ratePercentPerWeek) {
                    bindableGoal.ratePercentPerWeek = newType.defaultRatePercent
                }
            }
            try? modelContext.save()
            _ = CoachingCoordinator.evaluate(context: modelContext)
        }
        .onChange(of: bindableProfile.enableTrainingDayCarbCycling) { _, _ in
            try? modelContext.save()
            _ = CoachingCoordinator.evaluate(context: modelContext)
        }
        .onChange(of: bindableProfile.overrideCalorieFloor) { _, _ in
            try? modelContext.save()
            _ = CoachingCoordinator.evaluate(context: modelContext)
        }
    }
}
