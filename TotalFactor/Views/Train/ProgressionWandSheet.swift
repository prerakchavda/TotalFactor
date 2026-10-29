import SwiftUI

/// MacroFactor Workouts Progression Wand Diagnostic Popover/Sheet (§9 & Smart Overload)
struct ProgressionWandSheet: View {
    @Environment(\.dismiss) private var dismiss

    let diagnostic: ProgressionEngine.ProgressionWandDiagnostic
    let unitSystem: UnitSystem

    private var statusColor: Color {
        switch diagnostic.status {
        case .onTrack: return .blue
        case .consolidation: return .yellow
        case .repRangeExpansion: return .orange
        }
    }

    private var statusIcon: String {
        switch diagnostic.status {
        case .onTrack: return "arrow.up.circle.fill"
        case .consolidation: return "shield.lefthalf.filled"
        case .repRangeExpansion: return "arrow.left.and.right.circle.fill"
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // Hero Status Card
                    HStack(spacing: 14) {
                        Image(systemName: statusIcon)
                            .font(.system(size: 32, weight: .semibold))
                            .foregroundStyle(statusColor)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(diagnostic.exerciseName)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(diagnostic.headline)
                                .font(.title3.weight(.bold))
                                .foregroundStyle(.primary)
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(statusColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))

                    // Targets Grid
                    HStack(spacing: 12) {
                        targetMetricPill(
                            title: "TARGET LOAD",
                            value: UnitsFormatter.formatGymLoad(diagnostic.suggestedWeightKg, system: unitSystem),
                            subtitle: "\(unitSystem.weightSymbol)"
                        )

                        targetMetricPill(
                            title: "TARGET REPS",
                            value: "\(diagnostic.repRangeLow)–\(diagnostic.repRangeHigh)",
                            subtitle: diagnostic.isRepRangeExpanded ? "Expanded (+3)" : "Ceiling"
                        )

                        targetMetricPill(
                            title: "TARGET RIR",
                            value: "\(diagnostic.targetRIR)",
                            subtitle: "In Reserve"
                        )
                    }

                    // Detailed Rationale Box
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Smart Progression Rationale", systemImage: "sparkles")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)

                        Text(diagnostic.detailedRationale)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .lineSpacing(3)

                        if let jumpPct = diagnostic.equipmentJumpPercentage, jumpPct > 0 {
                            Divider().padding(.vertical, 4)
                            HStack {
                                Text("Equipment Increment Jump")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(String(format: "+%.1f%% (+%@)", jumpPct, UnitsFormatter.formatGymLoad(diagnostic.rawIncrementKg, system: unitSystem)))
                                    .font(.caption.weight(.bold).monospacedDigit())
                                    .foregroundStyle(diagnostic.isRepRangeExpanded ? .orange : .secondary)
                            }
                        }
                    }
                    .padding(16)
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))

                    Spacer(minLength: 20)
                }
                .padding()
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Progression Wand")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private func targetMetricPill(title: String, value: String, subtitle: String) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.bold).monospacedDigit())
                .foregroundStyle(.primary)
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }
}
