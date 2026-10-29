import SwiftUI
import SwiftData

/// Spec v1.5.2 "Ballpark My Meal" Quick Add Sheet:
/// 3-second logging for buffets, weddings, dining out, and unmeasured restaurant meals.
/// Lets users log realistic macro ballparks without diet guilt or friction.
struct MealBallparkSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(HealthKitService.self) private var healthService

    let dayKey: String
    var initialMealTag: MealTag = .none
    var onAddToPlate: ((StagedFoodItem) -> Void)? = nil
    var onLoggedDirectly: (() -> Void)? = nil

    public enum BallparkTier: String, CaseIterable, Identifiable {
        case snack = "Light Snack / Small"
        case standard = "Standard Meal"
        case hearty = "Hearty Restaurant"
        case feast = "Feast / Buffet"

        public var id: String { rawValue }

        public var baseCalories: Double {
            switch self {
            case .snack: return 300.0
            case .standard: return 650.0
            case .hearty: return 950.0
            case .feast: return 1350.0
            }
        }

        public var baseProtein: Double {
            switch self {
            case .snack: return 15.0
            case .standard: return 35.0
            case .hearty: return 45.0
            case .feast: return 50.0
            }
        }

        public var baseCarbs: Double {
            switch self {
            case .snack: return 35.0
            case .standard: return 65.0
            case .hearty: return 100.0
            case .feast: return 140.0
            }
        }

        public var baseFat: Double {
            switch self {
            case .snack: return 10.0
            case .standard: return 25.0
            case .hearty: return 40.0
            case .feast: return 65.0
            }
        }

        public var icon: String {
            switch self {
            case .snack: return "leaf.fill"
            case .standard: return "fork.knife"
            case .hearty: return "flame.fill"
            case .feast: return "crown.fill"
            }
        }

        public var themeColor: Color {
            switch self {
            case .snack: return .green
            case .standard: return .blue
            case .hearty: return .orange
            case .feast: return .purple
            }
        }

        public var subtitle: String {
            switch self {
            case .snack: return "Salad, small sandwich, shake, or light breakfast"
            case .standard: return "Normal dinner plate, lunch bowl, or protein + carb side"
            case .hearty: return "Pasta dinner, burger with sides, or rich takeout curry"
            case .feast: return "Wedding buffet, holiday feast, all-you-can-eat, or cheat meal"
            }
        }
    }

    @State private var selectedTier: BallparkTier = .standard
    @State private var mealTitle: String = ""
    @State private var activeMealTag: MealTag = .none
    @State private var calorieDelta: Double = 0.0

    // Vibe Modifiers
    @State private var isHighProtein: Bool = false
    @State private var isFriedOily: Bool = false
    @State private var isCarbHeavy: Bool = false

    private var computedCalories: Double {
        var cals = selectedTier.baseCalories + calorieDelta
        if isFriedOily { cals += 135.0 }
        if isCarbHeavy { cals += 120.0 }
        return max(50.0, cals)
    }

    private var computedProtein: Double {
        var p = selectedTier.baseProtein
        if isHighProtein { p += 15.0 }
        return max(0.0, p)
    }

    private var computedCarbs: Double {
        var c = selectedTier.baseCarbs
        if isCarbHeavy { c += 30.0 }
        if isHighProtein { c = max(5.0, c - 15.0) }
        return max(0.0, c)
    }

    private var computedFat: Double {
        var f = selectedTier.baseFat
        if isFriedOily { f += 15.0 }
        return max(0.0, f)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Macro Summary Display Card
                    macroDisplayCard

                    // Meal Name Input
                    HStack(spacing: 8) {
                        Image(systemName: "pencil.line")
                            .foregroundStyle(.secondary)
                        TextField("Meal Title (e.g. Wedding Feast, Indian Buffet)", text: $mealTitle)
                            .font(.subheadline)
                    }
                    .padding(12)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))

                    // Tier Selection Cards
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Choose General Size")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)

                        ForEach(BallparkTier.allCases) { tier in
                            tierCard(tier: tier)
                        }
                    }

                    // Vibe Modifier Chips
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Adjust Meal Vibe (Optional)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)

                        HStack(spacing: 8) {
                            vibeToggle("🍗 High Protein", isOn: $isHighProtein, color: .red)
                            vibeToggle("🍟 Fried / Oily", isOn: $isFriedOily, color: .orange)
                            vibeToggle("🍚 Carb Heavy", isOn: $isCarbHeavy, color: .blue)
                        }
                    }

                    // Calorie Nudge Stepper
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Fine-Tune Calories")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(Int(computedCalories.rounded())) kcal")
                                .font(.subheadline.weight(.heavy).monospacedDigit())
                        }

                        HStack(spacing: 12) {
                            Button("-100") { calorieDelta -= 100 }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            Button("-50") { calorieDelta -= 50 }
                                .buttonStyle(.bordered)
                                .controlSize(.small)

                            Slider(
                                value: $calorieDelta,
                                in: -300...500,
                                step: 25
                            )

                            Button("+50") { calorieDelta += 50 }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            Button("+100") { calorieDelta += 100 }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                        }
                    }
                    .padding(12)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))

                    // Action Buttons
                    actionButtons
                        .padding(.top, 4)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Ballpark My Meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        ForEach(MealTag.allCases) { tag in
                            Button {
                                activeMealTag = tag
                            } label: {
                                if activeMealTag == tag {
                                    Label(tag.displayName, systemImage: "checkmark")
                                } else {
                                    Text(tag.displayName)
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "fork.knife")
                            Text(activeMealTag == .none ? "Meal Tag" : activeMealTag.displayName)
                        }
                        .font(.caption.weight(.semibold))
                    }
                }
            }
            .onAppear {
                activeMealTag = initialMealTag
            }
        }
    }

    // MARK: - Subviews

    private var macroDisplayCard: some View {
        VStack(spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(selectedTier.rawValue)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(selectedTier.themeColor)
                    Text("\(Int(computedCalories.rounded())) kcal")
                        .font(.system(size: 32, weight: .heavy, design: .rounded))
                        .foregroundStyle(.primary)
                }
                Spacer()
                Image(systemName: selectedTier.icon)
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(selectedTier.themeColor)
            }

            Divider()

            HStack(spacing: 12) {
                macroTile("Protein", computedProtein, .red)
                macroTile("Carbs", computedCarbs, .blue)
                macroTile("Fat", computedFat, .yellow)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private func macroTile(_ label: String, _ value: Double, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text("\(Int(value.rounded()))g")
                .font(.headline.weight(.bold).monospacedDigit())
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
    }

    private func tierCard(tier: BallparkTier) -> some View {
        let isSelected = selectedTier == tier
        return Button {
            selectedTier = tier
            calorieDelta = 0.0
        } label: {
            HStack(spacing: 12) {
                Image(systemName: tier.icon)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(isSelected ? .white : tier.themeColor)
                    .frame(width: 36, height: 36)
                    .background(isSelected ? tier.themeColor : tier.themeColor.opacity(0.15), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(tier.rawValue)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(isSelected ? .primary : .primary)
                    Text(tier.subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 1) {
                    Text("~\(Int(tier.baseCalories)) kcal")
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(tier.themeColor)
                    Text("\(Int(tier.baseProtein))P • \(Int(tier.baseCarbs))C • \(Int(tier.baseFat))F")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? tier.themeColor.opacity(0.12) : Color(.secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? tier.themeColor : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }

    private func vibeToggle(_ title: String, isOn: Binding<Bool>, color: Color) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            Text(title)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(isOn.wrappedValue ? color : Color(.secondarySystemGroupedBackground), in: Capsule())
                .foregroundStyle(isOn.wrappedValue ? .white : .primary)
        }
        .buttonStyle(.plain)
    }

    private var actionButtons: some View {
        HStack(spacing: 12) {
            if onAddToPlate != nil {
                Button {
                    stageBallparkOntoPlate()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "fork.knife")
                        Text("Add to Plate")
                            .fontWeight(.semibold)
                    }
                    .font(.subheadline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }

            Button {
                logBallparkDirectly()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Log \(Int(computedCalories.rounded())) kcal")
                        .fontWeight(.bold)
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    // MARK: - Actions

    private func createMaterializedFood() -> Food {
        let title = mealTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTitle = title.isEmpty ? "\(selectedTier.rawValue) (Ballpark)" : title
        let cals = computedCalories
        let p = computedProtein
        let c = computedCarbs
        let f = computedFat

        // Use 100g as nominal serving
        let nutrients = NutrientsPer100g(
            calories: cals,
            protein: p,
            carbs: c,
            fat: f
        )

        let food = Food(
            id: UUID(),
            name: resolvedTitle,
            brand: "Quick Ballpark Estimate",
            barcode: nil,
            source: .custom,
            sourceID: "ballpark-\(UUID().uuidString.prefix(8))",
            isBundledGeneric: false,
            servingSizes: [
                ServingSize(label: "1 meal", grams: 100.0)
            ],
            nutrientsPer100g: nutrients
        )
        food.lastLoggedServingLabel = "1 meal"
        food.lastLoggedGrams = 100.0
        modelContext.insert(food)
        try? modelContext.save()
        return food
    }

    private func stageBallparkOntoPlate() {
        guard let onAddToPlate else { return }
        let food = createMaterializedFood()
        let staged = StagedFoodItem(
            item: .persisted(food),
            quantity: 1.0,
            selectedServing: ServingSize(label: "1 meal", grams: 100.0),
            mealTag: activeMealTag
        )
        onAddToPlate(staged)
        dismiss()
    }

    private func logBallparkDirectly() {
        let food = createMaterializedFood()
        let timestamp = (dayKey == DayKey.today) ? Date.now : (DayKey.date(from: dayKey) ?? .now)
        let currentHour = Calendar.current.component(.hour, from: .now)

        food.lastLoggedGrams = 100.0
        food.lastLoggedServingLabel = "1 meal"
        food.useCount += 1
        food.lastUsed = .now
        food.typicalHourOfDay = currentHour

        let entry = FoodLogEntry(
            food: food,
            grams: 100.0,
            servingLabel: "1 meal",
            mealTag: activeMealTag,
            timestamp: timestamp,
            dayKey: dayKey
        )
        modelContext.insert(entry)
        try? modelContext.save()

        Task { await healthService.syncFoodEntry(entry) }
        _ = CoachingCoordinator.evaluate(forDayKey: dayKey, context: modelContext)
        onLoggedDirectly?()
        dismiss()
    }
}
