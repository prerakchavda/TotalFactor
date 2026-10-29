import SwiftUI
import SwiftData
#if canImport(UIKit)
import UIKit
#endif

/// Spec §4 & §6 Zero-Lag Inline Food Logger:
/// - Docked custom calculator keypad (no iOS system keyboard slide-up lag)
/// - Pre-selects your remembered amount for 1-tap repeat OR 1st-digit overwrite
/// - Supports inline `+` and `×` kitchen-scale math (`140+65`, `1.5×2`) + `00` (`1` + `00` = `100 g`)
/// - Horizontal 1-tap serving-unit pills + quick `0.5× / 1× / 1.5× / 2×` multipliers
/// - Supports unmaterialized `OfflineUSDAFoodEntry` rows (~8,156 offline USDA foods) without inserting SwiftData rows until logged or favorited
/// - Live macro preview, source trust badge, Atwater >15% discrepancy warning & "Copy to Custom"
struct FoodDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(HealthKitService.self) private var healthService

    let target: CatalogSearchItem
    let dayKey: String
    let initialMealTag: MealTag
    var onLogged: () -> Void

    @State private var materializedFood: Food? = nil
    @State private var selectedServing: ServingSize = ServingSize(label: "1 g", grams: 1.0)
    @State private var calculator = InlineQuantityCalculator(initialText: "100", isPreselected: true)
    @State private var mealTag: MealTag = .none
    @State private var customCopyToEdit: Food? = nil

    init(
        target: CatalogSearchItem,
        dayKey: String,
        initialMealTag: MealTag = .none,
        onLogged: @escaping () -> Void
    ) {
        self.target = target
        self.dayKey = dayKey
        self.initialMealTag = initialMealTag
        self.onLogged = onLogged
    }

    init(
        food: Food,
        dayKey: String,
        initialMealTag: MealTag = .none,
        onLogged: @escaping () -> Void
    ) {
        self.target = .persisted(food)
        self.dayKey = dayKey
        self.initialMealTag = initialMealTag
        self.onLogged = onLogged
    }

    private var activePersistedFood: Food? {
        if let materializedFood { return materializedFood }
        if case .persisted(let food) = target { return food }
        return nil
    }

    private var displayName: String {
        activePersistedFood?.name ?? target.name
    }

    private var displayBrand: String? {
        activePersistedFood?.brand ?? target.brand
    }

    private var displaySource: FoodSource {
        activePersistedFood?.source ?? target.source
    }

    private var isFavorite: Bool {
        activePersistedFood?.isFavorite ?? false
    }

    private var baseNutrientsPer100g: NutrientsPer100g {
        if let food = activePersistedFood {
            return food.nutrientsPer100g
        }
        switch target {
        case .persisted(let food): return food.nutrientsPer100g
        case .offlineUSDA(let entry): return entry.nutrientsPer100g
        }
    }

    private var baseServingSizes: [ServingSize] {
        if let food = activePersistedFood {
            return food.servingSizes
        }
        switch target {
        case .persisted(let food): return food.servingSizes
        case .offlineUSDA(let entry): return entry.servingSizes
        }
    }

    private var rememberedGrams: Double {
        if let food = activePersistedFood {
            return food.lastLoggedGrams
        }
        switch target {
        case .persisted(let food): return food.lastLoggedGrams
        case .offlineUSDA(let entry): return entry.defaultServing.grams
        }
    }

    private var rememberedServingLabel: String {
        if let food = activePersistedFood {
            return food.lastLoggedServingLabel
        }
        switch target {
        case .persisted(let food): return food.lastLoggedServingLabel
        case .offlineUSDA(let entry): return entry.defaultServing.label
        }
    }

    private var parsedQuantity: Double {
        calculator.evaluatedValue
    }

    private var computedGrams: Double {
        if selectedServing.label == "1 g" {
            return parsedQuantity
        }
        return parsedQuantity * selectedServing.grams
    }

    private var previewNutrients: NutrientsPer100g {
        baseNutrientsPer100g.scaled(forGrams: computedGrams)
    }

    private var qualityCheck: FoodQualityCheckResult {
        FoodSearchRanker.validateMacroCalorieConsistency(nutrients: baseNutrientsPer100g)
    }

    var body: some View {
        let allServings = buildServingOptions()

        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        headerSection

                        if qualityCheck.isFlagged, let msg = qualityCheck.warningMessage {
                            discrepancyBanner(message: msg)
                        }

                        liveMacroCard

                        amountReadoutCard

                        servingPillsRow(options: allServings)

                        quickMultipliersAndMealRow
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }

                Divider()

                // Docked zero-lag custom calculator pad + 1-tap Log CTA
                VStack(spacing: 10) {
                    InlineFoodKeypadView(calculator: $calculator)

                    Button {
                        logFoodNow()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                            Text("Log Food (\(Int(previewNutrients.calories.rounded())) kcal)")
                                .fontWeight(.bold)
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(computedGrams <= 0.05)
                }
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 10)
                .background(.ultraThinMaterial)
            }
            .navigationTitle("Log Food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 14) {
                        Button {
                            duplicateToCustomAndEdit()
                        } label: {
                            Image(systemName: "doc.badge.gearshape")
                        }
                        .accessibilityLabel("Copy to Custom Food")

                        Button {
                            toggleFavorite()
                        } label: {
                            Image(systemName: isFavorite ? "star.fill" : "star")
                                .foregroundStyle(isFavorite ? .yellow : .secondary)
                        }
                        .accessibilityLabel(isFavorite ? "Remove Favorite" : "Favorite Food")
                    }
                }
            }
            .onAppear {
                if case .persisted(let food) = target {
                    materializedFood = food
                }
                mealTag = initialMealTag
                restoreRememberedServing(from: allServings)
            }
            .sheet(item: $customCopyToEdit) { copy in
                CustomFoodEditorSheet(existingFood: copy, prefilledBarcode: copy.barcode, parsedLabel: nil) { _ in }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Subviews

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(displayName)
                .font(.headline)
                .lineLimit(2)

            HStack(spacing: 8) {
                if let brand = displayBrand, !brand.isEmpty {
                    Text(brand)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text(displaySource.badgeTitle)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.14), in: Capsule())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func discrepancyBanner(message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.subheadline)
            VStack(alignment: .leading, spacing: 4) {
                Text("Macro-Calorie Discrepancy")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.orange)
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Fix Copy") {
                duplicateToCustomAndEdit()
            }
            .font(.caption2.weight(.bold))
            .buttonStyle(.bordered)
            .controlSize(.mini)
        }
        .padding(10)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }

    private var liveMacroCard: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                macroPreviewTile("Calories", "\(Int(previewNutrients.calories.rounded()))", "kcal", .orange)
                macroPreviewTile("Protein", String(format: "%.1f", previewNutrients.protein), "g", .red)
                macroPreviewTile("Carbs", String(format: "%.1f", previewNutrients.carbs), "g", .blue)
                macroPreviewTile("Fat", String(format: "%.1f", previewNutrients.fat), "g", .yellow)
            }
            HStack(spacing: 16) {
                Text("Fiber \(String(format: "%.1f", previewNutrients.fiber))g")
                Text("Sugar \(String(format: "%.1f", previewNutrients.sugar))g")
                Text("Sodium \(Int(previewNutrients.sodiumMg.rounded()))mg")
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 10)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
    }

    private var amountReadoutCard: some View {
        Button {
            // Tapping the readout re-selects the whole number so the next digit overwrites in 1 tap
            calculator.reset(to: InlineQuantityCalculator.formatClean(parsedQuantity), preselected: true)
            InlineFoodKeypadHaptics.lightTap()
        } label: {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(selectedServing.label == "1 g" ? "Weight (grams)" : selectedServing.label)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text("= \(Int(computedGrams.rounded())) g total")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(calculator.expression)
                        .font(.system(size: 28, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.primary)
                        .padding(.horizontal, calculator.isPreselected ? 10 : 4)
                        .padding(.vertical, 2)
                        .background(
                            calculator.isPreselected
                                ? Color.accentColor.opacity(0.22)
                                : Color.clear,
                            in: RoundedRectangle(cornerRadius: 8)
                        )

                    if calculator.hasOperator {
                        Text("= \(InlineQuantityCalculator.formatClean(parsedQuantity))")
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.secondary.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(Color.accentColor.opacity(0.45), lineWidth: 1.5)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func servingPillsRow(options: [ServingSize]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(options) { option in
                    let isSelected = option.label == selectedServing.label
                    Button {
                        selectServing(option)
                    } label: {
                        Text(option.label == "1 g" ? "Grams (g)" : option.label)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(
                                isSelected ? Color.accentColor : Color.secondary.opacity(0.14),
                                in: Capsule()
                            )
                            .foregroundStyle(isSelected ? Color.white : Color.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var quickMultipliersAndMealRow: some View {
        HStack(spacing: 6) {
            ForEach(["0.5", "1", "1.5", "2"], id: \.self) { preset in
                Button("\(preset)×") {
                    applyQuickMultiplier(preset)
                }
                .font(.caption.weight(.semibold).monospacedDigit())
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                .buttonStyle(.plain)
            }

            Spacer()

            Menu {
                ForEach(MealTag.allCases) { tag in
                    Button {
                        mealTag = tag
                    } label: {
                        if mealTag == tag {
                            Label(tag.displayName, systemImage: "checkmark")
                        } else {
                            Text(tag.displayName)
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "fork.knife")
                    Text(mealTag == .none ? "Meal" : mealTag.displayName)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9, weight: .bold))
                }
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.secondary.opacity(0.12), in: Capsule())
            }
        }
    }

    // MARK: - Helpers & Actions

    private func buildServingOptions() -> [ServingSize] {
        var list = baseServingSizes
        let oneGram = ServingSize(label: "1 g", grams: 1.0)
        if !list.contains(where: { $0.label == "1 g" }) {
            list.insert(oneGram, at: 0)
        }
        return list
    }

    private func restoreRememberedServing(from options: [ServingSize]) {
        if let matched = options.first(where: { $0.label == rememberedServingLabel }) {
            selectedServing = matched
            let mult = rememberedGrams / max(0.1, matched.grams)
            calculator.reset(to: InlineQuantityCalculator.formatClean(mult), preselected: true)
        } else {
            selectedServing = ServingSize(label: "1 g", grams: 1.0)
            calculator.reset(to: InlineQuantityCalculator.formatClean(max(1, rememberedGrams)), preselected: true)
        }
    }

    private func selectServing(_ option: ServingSize) {
        let previousGrams = max(1.0, computedGrams)
        selectedServing = option
        if option.label == "1 g" {
            calculator.reset(to: InlineQuantityCalculator.formatClean(previousGrams.rounded()), preselected: true)
        } else if option.label == rememberedServingLabel {
            let rememberedMult = rememberedGrams / max(0.1, option.grams)
            calculator.reset(to: InlineQuantityCalculator.formatClean(rememberedMult), preselected: true)
        } else {
            calculator.reset(to: "1", preselected: true)
        }
        InlineFoodKeypadHaptics.lightTap()
    }

    private func applyQuickMultiplier(_ preset: String) {
        let factor = Double(preset) ?? 1.0
        if selectedServing.label == "1 g" {
            calculator.reset(to: String(Int((factor * 100.0).rounded())), preselected: true)
        } else {
            calculator.reset(to: preset, preselected: true)
        }
        InlineFoodKeypadHaptics.lightTap()
    }

    private func toggleFavorite() {
        if let food = activePersistedFood {
            food.isFavorite.toggle()
            try? modelContext.save()
        } else if case .offlineUSDA(let entry) = target {
            let created = OfflineUSDACatalogService.shared.materialize(entry, in: modelContext, markFavorite: true)
            materializedFood = created
        }
        InlineFoodKeypadHaptics.lightTap()
    }

    private func duplicateToCustomAndEdit() {
        let copy: Food
        if let food = activePersistedFood {
            copy = food.duplicateAsCustom()
        } else {
            copy = Food(
                name: displayName,
                brand: displayBrand,
                barcode: nil,
                source: .custom,
                sourceID: nil,
                isBundledGeneric: false,
                servingSizes: baseServingSizes,
                nutrientsPer100g: baseNutrientsPer100g,
                isFavorite: false
            )
        }
        modelContext.insert(copy)
        try? modelContext.save()
        customCopyToEdit = copy
    }

    private func resolveOrMaterializeFoodForLogging() -> Food {
        if let food = activePersistedFood {
            return food
        }
        switch target {
        case .persisted(let food):
            materializedFood = food
            return food
        case .offlineUSDA(let entry):
            let food = OfflineUSDACatalogService.shared.materialize(entry, in: modelContext)
            materializedFood = food
            return food
        }
    }

    private func macroPreviewTile(_ label: String, _ value: String, _ unit: String, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.subheadline.weight(.bold).monospacedDigit()).foregroundStyle(color)
            Text(unit).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func logFoodNow() {
        let food = resolveOrMaterializeFoodForLogging()
        let grams = max(0.5, computedGrams)
        let displayLabel: String
        if selectedServing.label == "1 g" {
            displayLabel = "\(Int(grams.rounded())) g"
        } else {
            displayLabel = "\(InlineQuantityCalculator.formatClean(parsedQuantity)) × \(selectedServing.label)"
        }

        food.lastLoggedGrams = grams
        food.lastLoggedServingLabel = selectedServing.label
        food.useCount += 1
        food.lastUsed = .now
        food.typicalHourOfDay = Calendar.current.component(.hour, from: .now)

        let timestamp = (dayKey == DayKey.today) ? Date.now : (DayKey.date(from: dayKey) ?? .now)
        let entry = FoodLogEntry(
            food: food,
            grams: grams,
            servingLabel: displayLabel,
            mealTag: mealTag,
            timestamp: timestamp,
            dayKey: dayKey
        )
        modelContext.insert(entry)
        try? modelContext.save()
        Task { await healthService.syncFoodEntry(entry) }
        _ = CoachingCoordinator.evaluate(forDayKey: dayKey, context: modelContext)
        InlineFoodKeypadHaptics.lightTap()
        dismiss()
        onLogged()
    }
}

/// Reusable docked 4×4 custom calculator keypad for fast food weight & serving entry without system keyboard lag.
struct InlineFoodKeypadView: View {
    @Binding var calculator: InlineQuantityCalculator

    private let rows: [[InlineQuantityCalculator.Key]] = [
        [.one, .two, .three, .backspace],
        [.four, .five, .six, .plus],
        [.seven, .eight, .nine, .multiply],
        [.decimal, .zero, .doubleZero, .equals]
    ]

    var body: some View {
        VStack(spacing: 6) {
            ForEach(0..<rows.count, id: \.self) { rowIndex in
                HStack(spacing: 6) {
                    ForEach(rows[rowIndex], id: \.rawValue) { key in
                        keypadButton(for: key)
                    }
                }
            }
        }
    }

    private func keypadButton(for key: InlineQuantityCalculator.Key) -> some View {
        let isUtility = (key == .backspace || key == .plus || key == .multiply || key == .equals)
        return Button {
            calculator.tap(key)
            InlineFoodKeypadHaptics.lightTap()
        } label: {
            Group {
                if key == .backspace {
                    Image(systemName: "delete.left.fill")
                        .font(.system(size: 18, weight: .semibold))
                } else {
                    Text(key.rawValue)
                        .font(.system(size: 20, weight: isUtility ? .bold : .semibold, design: .rounded).monospacedDigit())
                }
            }
            .foregroundStyle(foregroundColor(for: key))
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(backgroundColor(for: key), in: RoundedRectangle(cornerRadius: 11))
        }
        .buttonStyle(.plain)
    }

    private func backgroundColor(for key: InlineQuantityCalculator.Key) -> Color {
        switch key {
        case .plus, .multiply, .equals:
            return Color.accentColor.opacity(0.16)
        case .backspace:
            return Color.secondary.opacity(0.18)
        default:
            return Color.secondary.opacity(0.11)
        }
    }

    private func foregroundColor(for key: InlineQuantityCalculator.Key) -> Color {
        switch key {
        case .plus, .multiply, .equals:
            return Color.accentColor
        default:
            return Color.primary
        }
    }
}

enum InlineFoodKeypadHaptics {
    static func lightTap() {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }
}
