import SwiftUI
import SwiftData

/// Spec MacroFactor Hour-by-Hour Timeline Section (v1.5.1 Kitchen Rehaul):
/// - Chronological hourly grouping (e.g. 8:00 AM, 12:00 PM, 6:00 PM)
/// - Hourly macro subtotals: Calories kcal • Protein g • Carbs g • Fat g
/// - Inline `+` shortcut to log directly into that specific hour (with left/right handedness)
/// - Collapse/expand per hour, and setting to hide empty hours
/// - Explode Recipe action, swipe to delete, and swipe to add to Plate
struct HourByHourTimelineSection: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState

    let hour: Int
    let entries: [FoodLogEntry]
    let dayKey: String
    let isHandednessLeading: Bool
    var onAddFoodToHour: (Int) -> Void
    var onExplodeRecipe: (FoodLogEntry) -> Void
    var onEditEntry: (FoodLogEntry) -> Void
    var onStageToPlate: (FoodLogEntry) -> Void

    @State private var isCollapsed: Bool = false

    private var hourDate: Date {
        var comp = DateComponents()
        comp.hour = hour
        comp.minute = 0
        return Calendar.current.date(from: comp) ?? .now
    }

    private var formattedHourTitle: String {
        let f = DateFormatter()
        f.dateFormat = "h:00 a"
        return f.string(from: hourDate)
    }

    private var hourlyNutrients: NutrientsPer100g {
        var total = NutrientsPer100g()
        for e in entries {
            let sc = e.loggedNutrients.scaled(forGrams: e.grams)
            total.calories += sc.calories
            total.protein += sc.protein
            total.carbs += sc.carbs
            total.fat += sc.fat
            total.fiber += sc.fiber
        }
        return total
    }

    var body: some View {
        VStack(spacing: 8) {
            // Hour Subtotal Header Bar
            HStack(spacing: 8) {
                if isHandednessLeading {
                    addFoodButton
                }

                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        isCollapsed.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.secondary)

                        Text(formattedHourTitle)
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)

                        if !entries.isEmpty {
                            Text("• \(Int(hourlyNutrients.calories.rounded())) kcal")
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundStyle(Color(red: 0.18, green: 0.48, blue: 0.96))

                            Text("(\(Int(hourlyNutrients.protein.rounded()))P \(Int(hourlyNutrients.carbs.rounded()))C \(Int(hourlyNutrients.fat.rounded()))F)")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                if !isHandednessLeading {
                    addFoodButton
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)

            // Hour Food Tiles
            if !isCollapsed {
                if entries.isEmpty {
                    HStack {
                        Text("No food logged for this hour")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Spacer()
                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 4)
                } else {
                    VStack(spacing: 6) {
                        ForEach(entries) { entry in
                            foodTile(for: entry)
                        }
                    }
                    .padding(.horizontal, 12)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var addFoodButton: some View {
        Button {
            onAddFoodToHour(hour)
        } label: {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color(red: 0.18, green: 0.48, blue: 0.96))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add food at \(formattedHourTitle)")
    }

    private func foodTile(for entry: FoodLogEntry) -> some View {
        let sc = entry.loggedNutrients.scaled(forGrams: entry.grams)

        return HStack(spacing: 12) {
            // Leading Color Pill indicating major macro
            RoundedRectangle(cornerRadius: 3)
                .fill(majorMacroColor(sc))
                .frame(width: 4, height: 38)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(entry.foodName)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)

                    if entry.foodSource == .recipe || entry.recipeID != nil {
                        Text("RECIPE")
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundStyle(.purple)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Color.purple.opacity(0.15), in: Capsule())
                    } else {
                        FoodSourceBadge(source: entry.foodSource)
                    }
                }

                HStack(spacing: 6) {
                    Text(entry.servingLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("•")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text("\(Int(sc.calories.rounded())) kcal")
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("(\(Int(sc.protein.rounded()))P \(Int(sc.carbs.rounded()))C \(Int(sc.fat.rounded()))F)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Quick Stage to Plate (+)
            Button {
                onStageToPlate(entry)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.secondary)
                    .padding(6)
                    .background(Color(.tertiarySystemGroupedBackground), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add to Plate")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture {
            onEditEntry(entry)
        }
        .contextMenu {
            if entry.foodSource == .recipe || entry.recipeID != nil {
                Button {
                    onExplodeRecipe(entry)
                } label: {
                    Label("Explode Recipe", systemImage: "sparkles")
                }
            }

            Button {
                onStageToPlate(entry)
            } label: {
                Label("Add to The Plate", systemImage: "fork.knife")
            }

            Button {
                onEditEntry(entry)
            } label: {
                Label("Edit Portion", systemImage: "pencil")
            }

            Divider()

            Button(role: .destructive) {
                modelContext.delete(entry)
                try? modelContext.save()
            } label: {
                Label("Delete Entry", systemImage: "trash")
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                modelContext.delete(entry)
                try? modelContext.save()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading) {
            Button {
                onStageToPlate(entry)
            } label: {
                Label("Plate", systemImage: "plus")
            }
            .tint(Color(red: 0.18, green: 0.48, blue: 0.96))
        }
    }

    private func majorMacroColor(_ n: NutrientsPer100g) -> Color {
        let pCal = n.protein * 4
        let cCal = n.carbs * 4
        let fCal = n.fat * 9
        if pCal >= cCal && pCal >= fCal {
            return .red
        } else if cCal >= pCal && cCal >= fCal {
            return .blue
        } else {
            return .yellow
        }
    }
}
