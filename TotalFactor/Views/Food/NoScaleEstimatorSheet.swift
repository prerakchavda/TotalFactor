import SwiftUI
import SwiftData

/// Spec v1.5.2 "No-Scale & Container Estimator" Sheet:
/// For real-world dining where food scales are unavailable (family dinners, takeout, street food, social events).
/// Provides visual hand proportions, standardized takeout container volumes, and piece-count street food presets.
struct NoScaleEstimatorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(HealthKitService.self) private var healthService

    let dayKey: String
    var initialMealTag: MealTag = .none
    var onAddToPlate: (([StagedFoodItem]) -> Void)? = nil
    var onLoggedDirectly: (() -> Void)? = nil

    @State private var selectedTab: Int = 0 // 0: Hand Proportions, 1: Takeout Containers, 2: Street & Bites
    @State private var activeMealTag: MealTag = .none
    @State private var quantities: [UUID: Double] = [:] // entry.id -> quantity multiplier

    private var allEntries: [CompositeFoodEntry] {
        CompositeFoodLibrary.entries
    }

    private var handEntries: [CompositeFoodEntry] {
        allEntries.filter { $0.category == .handPortion && !$0.name.contains("Container") && !$0.name.contains("Takeout") }
    }

    private var containerEntries: [CompositeFoodEntry] {
        allEntries.filter { $0.category == .handPortion && ($0.name.contains("Container") || $0.name.contains("Takeout") || $0.name.contains("Pint") || $0.name.contains("Quart")) }
    }

    private var streetEntries: [CompositeFoodEntry] {
        allEntries.filter { $0.category == .streetFood || $0.category == .culturalStaple || $0.category == .takeout || $0.category == .snackAndTreat }
    }

    private var currentCategoryEntries: [CompositeFoodEntry] {
        switch selectedTab {
        case 0: return handEntries
        case 1: return containerEntries
        default: return streetEntries
        }
    }

    private var activeSelectedEntries: [(entry: CompositeFoodEntry, qty: Double)] {
        currentCategoryEntries.compactMap { entry in
            guard let q = quantities[entry.id], q > 0 else { return nil }
            return (entry, q)
        }
    }

    private var totalCalories: Double {
        activeSelectedEntries.reduce(0.0) { $0 + $1.entry.nutrients(forQuantity: $1.qty).calories }
    }

    private var totalProtein: Double {
        activeSelectedEntries.reduce(0.0) { $0 + $1.entry.nutrients(forQuantity: $1.qty).protein }
    }

    private var totalCarbs: Double {
        activeSelectedEntries.reduce(0.0) { $0 + $1.entry.nutrients(forQuantity: $1.qty).carbs }
    }

    private var totalFat: Double {
        activeSelectedEntries.reduce(0.0) { $0 + $1.entry.nutrients(forQuantity: $1.qty).fat }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Top Live Macro Summary Banner
                macroSummaryBanner
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color(.secondarySystemGroupedBackground))

                Divider()

                // Category Switcher
                Picker("Estimation Category", selection: $selectedTab) {
                    Text("Hand Proportions").tag(0)
                    Text("Takeout Containers").tag(1)
                    Text("Street & Bites").tag(2)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

                // Items List with Steppers
                List {
                    Section {
                        ForEach(currentCategoryEntries) { entry in
                            estimatorItemRow(entry: entry)
                        }
                    } header: {
                        Text(headerDescription)
                            .font(.caption2)
                            .textCase(nil)
                            .foregroundStyle(.secondary)
                    }
                }
                .listStyle(.insetGrouped)

                Divider()

                // Bottom Action Buttons
                bottomActionBar
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(.ultraThinMaterial)
            }
            .navigationTitle("No-Scale Estimator")
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

    private var macroSummaryBanner: some View {
        VStack(spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Selected Estimate")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                    Text("\(Int(totalCalories.rounded())) kcal")
                        .font(.system(size: 24, weight: .heavy, design: .rounded))
                        .foregroundStyle(.primary)
                }
                Spacer()
                HStack(spacing: 12) {
                    macroBadge("P", totalProtein, .red)
                    macroBadge("C", totalCarbs, .blue)
                    macroBadge("F", totalFat, .yellow)
                }
            }

            if activeSelectedEntries.isEmpty {
                Text("Tap + on any item to build your estimate without a food scale.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("\(activeSelectedEntries.count) item\(activeSelectedEntries.count == 1 ? "" : "s") ready to log or stage.")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Color.accentColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func macroBadge(_ label: String, _ value: Double, _ color: Color) -> some View {
        VStack(spacing: 1) {
            Text(label)
                .font(.caption2.weight(.bold))
                .foregroundStyle(color)
            Text("\(Int(value.rounded()))g")
                .font(.caption.weight(.semibold).monospacedDigit())
        }
    }

    private var headerDescription: String {
        switch selectedTab {
        case 0:
            return "Use your hand as a biological ruler: Palm = protein (30g P), Fist = carbs (1 cup), Cupped hand = snacks, Thumb = fats (1 tbsp)."
        case 1:
            return "Standardized restaurant & takeout containers: Pint = 2 cups (soup/curry), Quart = 4 cups, 3-Compartment = full meal."
        default:
            return "Verified composites for foods you can't put on a scale (Panipuri, Samosas, Street Tacos, Sushi, Roti, Biryani)."
        }
    }

    private func estimatorItemRow(entry: CompositeFoodEntry) -> some View {
        let currentQty = quantities[entry.id] ?? 0.0
        let step = defaultStep(for: entry)
        let isSelected = currentQty > 0
        let currentNutrients = entry.nutrients(forQuantity: max(step, currentQty))

        return HStack(spacing: 12) {
            // Icon / Avatar
            ZStack {
                Circle()
                    .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.10))
                    .frame(width: 42, height: 42)
                Image(systemName: iconName(for: entry))
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
            }

            // Text Description
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Text("\(entry.defaultServingLabel) • \(Int(entry.perServingNutrients.calories.rounded())) kcal")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if isSelected {
                    Text("\(formatQuantity(currentQty, unit: entry.pieceUnitName)) = \(Int(currentNutrients.calories.rounded())) kcal (\(Int(currentNutrients.protein.rounded()))P \(Int(currentNutrients.carbs.rounded()))C \(Int(currentNutrients.fat.rounded()))F)")
                        .font(.caption2.weight(.medium).monospacedDigit())
                        .foregroundStyle(Color.accentColor)
                }
            }

            Spacer()

            // Inline Stepper
            HStack(spacing: 6) {
                if isSelected {
                    Button {
                        adjustQuantity(for: entry, delta: -step)
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)

                    Text(formatQuantity(currentQty, unit: ""))
                        .font(.subheadline.weight(.bold).monospacedDigit())
                        .frame(minWidth: 26)

                    Button {
                        adjustQuantity(for: entry, delta: step)
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                } else {
                    Button {
                        quantities[entry.id] = entry.defaultQuantity
                    } label: {
                        Text("+ Add")
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.accentColor.opacity(0.15), in: Capsule())
                            .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func defaultStep(for entry: CompositeFoodEntry) -> Double {
        if entry.pieceUnitName == "piece" && entry.defaultQuantity >= 5.0 {
            return 1.0
        }
        if entry.pieceUnitName == "palm" || entry.pieceUnitName == "fist" || entry.pieceUnitName == "thumb" || entry.pieceUnitName == "handful" {
            return 0.5
        }
        return 1.0
    }

    private func adjustQuantity(for entry: CompositeFoodEntry, delta: Double) {
        let old = quantities[entry.id] ?? 0.0
        let newQty = max(0.0, old + delta)
        if newQty <= 0.05 {
            quantities.removeValue(forKey: entry.id)
        } else {
            quantities[entry.id] = newQty
        }
    }

    private func formatQuantity(_ qty: Double, unit: String) -> String {
        let numStr = qty.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(qty))" : String(format: "%.1f", qty)
        if unit.isEmpty { return numStr }
        return "\(numStr) \(unit)\(qty > 1 && !unit.hasSuffix("s") ? "s" : "")"
    }

    private func iconName(for entry: CompositeFoodEntry) -> String {
        switch entry.category {
        case .handPortion:
            if entry.name.contains("Palm") { return "hand.raised.fill" }
            if entry.name.contains("Fist") { return "circle.circle.fill" }
            if entry.name.contains("Thumb") { return "hand.thumbsup.fill" }
            if entry.name.contains("Cupped") { return "hands.clap.fill" }
            if entry.name.contains("Pint") || entry.name.contains("Quart") { return "takeoutbag.and.cup.and.straw.fill" }
            return "shippingbox.fill"
        case .streetFood:
            if entry.name.contains("Taco") { return "mouth.fill" }
            if entry.name.contains("Pizza") { return "chart.pie.fill" }
            if entry.name.contains("Wing") { return "flame.fill" }
            return "takeoutbag.and.cup.and.straw"
        case .culturalStaple:
            return "fork.knife"
        case .takeout:
            return "bag.fill"
        case .snackAndTreat:
            return "heart.fill"
        }
    }

    private var bottomActionBar: some View {
        HStack(spacing: 12) {
            // Stage on Plate Button
            if onAddToPlate != nil {
                Button {
                    stageSelectedOntoPlate()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "fork.knife")
                        Text("Add to Plate (\(activeSelectedEntries.count))")
                            .fontWeight(.semibold)
                    }
                    .font(.subheadline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(activeSelectedEntries.isEmpty)
            }

            // Direct Log Button
            Button {
                logSelectedDirectly()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Log \(Int(totalCalories.rounded())) kcal")
                        .fontWeight(.bold)
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(activeSelectedEntries.isEmpty)
        }
    }

    // MARK: - Actions

    private func stageSelectedOntoPlate() {
        guard let onAddToPlate else { return }
        let selected = activeSelectedEntries
        guard !selected.isEmpty else { return }

        var staged: [StagedFoodItem] = []
        for (entry, qty) in selected {
            let food = CompositeFoodLibrary.materialize(entry, in: modelContext)
            let serving = entry.defaultServing
            staged.append(
                StagedFoodItem(
                    item: .persisted(food),
                    quantity: qty,
                    selectedServing: serving,
                    mealTag: activeMealTag
                )
            )
        }
        onAddToPlate(staged)
        dismiss()
    }

    private func logSelectedDirectly() {
        let selected = activeSelectedEntries
        guard !selected.isEmpty else { return }

        let timestamp = (dayKey == DayKey.today) ? Date.now : (DayKey.date(from: dayKey) ?? .now)
        let currentHour = Calendar.current.component(.hour, from: .now)

        for (entry, qty) in selected {
            let food = CompositeFoodLibrary.materialize(entry, in: modelContext)
            let totalGrams = entry.servingGrams * qty
            let label = "\(formatQuantity(qty, unit: entry.pieceUnitName)) (\(Int(totalGrams.rounded()))g)"

            food.lastLoggedGrams = totalGrams
            food.lastLoggedServingLabel = label
            food.useCount += 1
            food.lastUsed = .now
            food.typicalHourOfDay = currentHour

            let logEntry = FoodLogEntry(
                food: food,
                grams: totalGrams,
                servingLabel: label,
                mealTag: activeMealTag,
                timestamp: timestamp,
                dayKey: dayKey
            )
            modelContext.insert(logEntry)
            Task { await healthService.syncFoodEntry(logEntry) }
        }

        try? modelContext.save()
        _ = CoachingCoordinator.evaluate(forDayKey: dayKey, context: modelContext)
        onLoggedDirectly?()
        dismiss()
    }
}
