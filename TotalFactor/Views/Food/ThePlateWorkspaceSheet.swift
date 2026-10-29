import SwiftUI
import SwiftData

/// Spec MacroFactor "The Plate" Workspace Sheet (v1.5.1 Kitchen Rehaul):
/// - Expanded staging tray with inline quantity steppers without opening sub-sheets
/// - Meal / Hour selector for the entire plate
/// - "Save Plate as Recipe" and "Save Plate as Saved Meal" actions
/// - 1-tap batch commit to SwiftData and Apple Health
struct ThePlateWorkspaceSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Binding var stagedItems: [StagedFoodItem]

    let dayKey: String
    var initialMealTag: MealTag = .none
    var onCommitAll: (MealTag, Date) -> Void

    @State private var activeMealTag: MealTag = .none
    @State private var targetTime: Date = .now
    @State private var showingSaveMealAlert: Bool = false
    @State private var saveMealName: String = ""
    @State private var showingRecipeBuilder: Bool = false

    private var totalCalories: Double {
        stagedItems.reduce(0.0) { $0 + $1.scaledNutrients.calories }
    }

    private var totalProtein: Double {
        stagedItems.reduce(0.0) { $0 + $1.scaledNutrients.protein }
    }

    private var totalCarbs: Double {
        stagedItems.reduce(0.0) { $0 + $1.scaledNutrients.carbs }
    }

    private var totalFat: Double {
        stagedItems.reduce(0.0) { $0 + $1.scaledNutrients.fat }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Top Macro Summary Card
                VStack(spacing: 8) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Plate Total")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                            Text("\(Int(totalCalories.rounded())) kcal")
                                .font(.system(size: 26, weight: .heavy, design: .rounded))
                                .foregroundStyle(.primary)
                        }
                        Spacer()
                        HStack(spacing: 12) {
                            macroPill(label: "P", value: totalProtein, color: .red)
                            macroPill(label: "C", value: totalCarbs, color: .blue)
                            macroPill(label: "F", value: totalFat, color: .yellow)
                        }
                    }

                    Divider()

                    // Meal Tag & Timestamp Pickers
                    HStack(spacing: 12) {
                        Picker("Meal", selection: $activeMealTag) {
                            ForEach(MealTag.allCases) { tag in
                                Text(tag.displayName).tag(tag)
                            }
                        }
                        .pickerStyle(.menu)

                        Spacer()

                        DatePicker(
                            "",
                            selection: $targetTime,
                            displayedComponents: [.hourAndMinute]
                        )
                        .labelsHidden()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(.secondarySystemGroupedBackground))

                // Staged Items List
                List {
                    Section {
                        ForEach($stagedItems) { $staged in
                            stagedItemRow(staged: $staged)
                        }
                        .onDelete { offsets in
                            stagedItems.remove(atOffsets: offsets)
                        }
                    } header: {
                        Text("\(stagedItems.count) Items on Plate")
                    }

                    Section("Plate Actions") {
                        Button {
                            showingSaveMealAlert = true
                        } label: {
                            Label("Save Plate as Saved Meal", systemImage: "tray.and.arrow.down.fill")
                        }

                        Button {
                            showingRecipeBuilder = true
                        } label: {
                            Label("Convert Plate to Recipe", systemImage: "frying.pan.fill")
                        }

                        Button(role: .destructive) {
                            stagedItems.removeAll()
                            dismiss()
                        } label: {
                            Label("Clear Plate", systemImage: "trash")
                        }
                    }
                }
                .listStyle(.insetGrouped)

                // Bottom Log Plate Button
                VStack(spacing: 6) {
                    Button {
                        onCommitAll(activeMealTag, targetTime)
                        dismiss()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                            Text("Log Plate (\(stagedItems.count) Items • \(Int(totalCalories.rounded())) kcal)")
                                .fontWeight(.bold)
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(stagedItems.isEmpty)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
            }
            .navigationTitle("The Plate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .onAppear {
                activeMealTag = initialMealTag
            }
            .alert("Save as Reusable Meal", isPresented: $showingSaveMealAlert) {
                TextField("Meal Name (e.g. Daily Post-Workout)", text: $saveMealName)
                Button("Save") {
                    savePlateAsSavedMeal()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Save this meal combination to your Kitchen to log it again with 1 tap.")
            }
            .sheet(isPresented: $showingRecipeBuilder) {
                RecipeBuilderSheet(prefilledStagedItems: stagedItems)
            }
        }
    }

    private func macroPill(label: String, value: Double, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(color)
            Text("\(Int(value.rounded()))g")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func stagedItemRow(staged: Binding<StagedFoodItem>) -> some View {
        let sc = staged.wrappedValue.scaledNutrients

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(staged.wrappedValue.item.name)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                    Text(staged.wrappedValue.item.brand ?? "USDA Whole Food")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(Int(sc.calories.rounded())) kcal")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
            }

            // Inline Stepper & Multiplier Controls
            HStack(spacing: 12) {
                // Stepper (- / +)
                HStack(spacing: 8) {
                    Button {
                        if staged.wrappedValue.quantity > 0.25 {
                            staged.wrappedValue.quantity = max(0.25, staged.wrappedValue.quantity - 0.25)
                        }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)

                    Text("\(InlineQuantityCalculator.formatClean(staged.wrappedValue.quantity)) ×")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .frame(minWidth: 44)

                    Button {
                        staged.wrappedValue.quantity += 0.25
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(Color(red: 0.18, green: 0.48, blue: 0.96))
                    }
                    .buttonStyle(.plain)
                }

                // Serving Selector Menu
                Menu {
                    ForEach(staged.wrappedValue.item.servingSizes) { sz in
                        Button(sz.label) {
                            staged.wrappedValue.selectedServing = sz
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(staged.wrappedValue.selectedServing.label)
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 9))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color(.tertiarySystemGroupedBackground), in: Capsule())
                }

                Spacer()

                Text("(\(Int(staged.wrappedValue.grams.rounded()))g)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func savePlateAsSavedMeal() {
        let title = saveMealName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !stagedItems.isEmpty else { return }

        let savedMeal = SavedMeal(name: title, defaultMealTag: activeMealTag)
        modelContext.insert(savedMeal)

        for item in stagedItems {
            let food: Food
            switch item.item {
            case .persisted(let f):
                food = f
            case .offlineUSDA(let entry):
                food = OfflineUSDACatalogService.shared.materialize(entry, in: modelContext)
            }
            let mealItem = SavedMealItem(
                food: food,
                grams: item.grams,
                servingLabel: item.selectedServing.label,
                quantity: item.quantity
            )
            mealItem.meal = savedMeal
            modelContext.insert(mealItem)
        }
        try? modelContext.save()
        saveMealName = ""
    }
}
