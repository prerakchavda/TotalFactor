import SwiftUI
import SwiftData

/// Phase 4 & Phase 8 Weekly Check-In Sheet (§8 & §12):
/// Displays expenditure update, trend weight vs goal rate, training summary (sessions, volume, PRs),
/// plain-English explanation, and Accept / Adjust / Skip controls.
struct WeeklyCheckInSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]

    @State private var generatedCheckIn: WeeklyCheckIn? = nil
    @State private var customCalorieAdjustment: Double = 0

    private var profile: UserProfile {
        profiles.first ?? CoachingCoordinator.fetchOrCreateProfile(context: modelContext)
    }

    var body: some View {
        NavigationStack {
            Group {
                if let checkIn = generatedCheckIn {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            // 1. Plain-English Reason Banner
                            VStack(alignment: .leading, spacing: 8) {
                                Label("Weekly Coaching Summary", systemImage: "sparkles")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.green)
                                Text(checkIn.explanation)
                                    .font(.headline)
                            }
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))

                            // 2. Expenditure & Weight Trend Cards
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Expenditure")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text("\(Int(checkIn.expenditure.rounded())) kcal")
                                        .font(.title3.weight(.bold).monospacedDigit())
                                    let expDiff = Int((checkIn.expenditure - checkIn.previousExpenditure).rounded())
                                    Text("\(expDiff >= 0 ? "+" : "")\(expDiff) kcal vs prior")
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                                .padding(14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("7-Day Trend Change")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(UnitsFormatter.formatSignedWeightDelta(checkIn.weightTrendChangeKg, system: profile.unitSystem))
                                        .font(.title3.weight(.bold).monospacedDigit())
                                    Text("EMA Smoothed")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                            }

                            // 3. Phase 8 (§12): Training Summary inside Check-In
                            VStack(alignment: .leading, spacing: 8) {
                                Label("Last 7 Days Training", systemImage: "dumbbell.fill")
                                    .font(.subheadline.weight(.semibold))
                                HStack {
                                    statPill(label: "Sessions", value: "\(checkIn.sessionsCompleted)")
                                    statPill(
                                        label: "Volume",
                                        value: UnitsFormatter.formatWeight(checkIn.weeklyVolumeKg, system: profile.unitSystem, decimals: 0)
                                    )
                                    statPill(label: "PRs Hit", value: "\(checkIn.prsHitCount)")
                                }
                            }
                            .padding(14)
                            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))

                            // 4. Proposed Targets + Optional Fine-Tune Slider
                            let adjustedCals = checkIn.targets.calories + customCalorieAdjustment
                            let extraCarbs = (customCalorieAdjustment / 4.0).rounded()

                            VStack(alignment: .leading, spacing: 12) {
                                Text("New Daily Targets")
                                    .font(.headline)

                                HStack {
                                    macroBox("Calories", "\(Int(adjustedCals))", "kcal", .orange)
                                    macroBox("Protein", "\(Int(checkIn.targets.protein))", "g", .red)
                                    macroBox("Carbs", "\(Int(max(20, checkIn.targets.carbs + extraCarbs)))", "g", .blue)
                                    macroBox("Fat", "\(Int(checkIn.targets.fat))", "g", .yellow)
                                }

                                if profile.enableTrainingDayCarbCycling {
                                    Divider()
                                    HStack {
                                        Text("Training Days:")
                                            .font(.caption.weight(.semibold))
                                        Spacer()
                                        Text("\(Int(checkIn.trainingDayTargets.calories + customCalorieAdjustment)) kcal • \(Int(checkIn.trainingDayTargets.carbs + extraCarbs))g C")
                                            .font(.caption.monospacedDigit())
                                    }
                                    HStack {
                                        Text("Rest Days:")
                                            .font(.caption.weight(.semibold))
                                        Spacer()
                                        Text("\(Int(checkIn.restDayTargets.calories + customCalorieAdjustment)) kcal • \(Int(checkIn.restDayTargets.carbs + extraCarbs))g C")
                                            .font(.caption.monospacedDigit())
                                    }
                                }

                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text("Manual Adjustment")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                        Text("\(customCalorieAdjustment >= 0 ? "+" : "")\(Int(customCalorieAdjustment)) kcal")
                                            .font(.caption.weight(.semibold).monospacedDigit())
                                    }
                                    Slider(value: $customCalorieAdjustment, in: -250...250, step: 25)
                                }
                            }
                            .padding(16)
                            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))

                            // 5. Accept / Skip Buttons (§8)
                            VStack(spacing: 10) {
                                Button {
                                    acceptCheckIn(checkIn)
                                } label: {
                                    Text("Accept Targets")
                                        .font(.headline)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                }
                                .buttonStyle(.borderedProminent)

                                Button("Skip This Week") {
                                    checkIn.skipped = true
                                    try? modelContext.save()
                                    dismiss()
                                }
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            }
                        }
                        .padding()
                    }
                } else {
                    ProgressView("Calculating Check-In...")
                }
            }
            .navigationTitle("Weekly Check-In")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .onAppear {
                if generatedCheckIn == nil {
                    generatedCheckIn = CoachingCoordinator.createWeeklyCheckIn(context: modelContext)
                }
            }
        }
    }

    private func statPill(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.subheadline.weight(.bold).monospacedDigit())
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
    }

    private func macroBox(_ label: String, _ value: String, _ unit: String, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.headline.monospacedDigit()).foregroundStyle(color)
            Text(unit).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
    }

    private func acceptCheckIn(_ checkIn: WeeklyCheckIn) {
        if abs(customCalorieAdjustment) >= 1 {
            var base = checkIn.targets
            base.calories += customCalorieAdjustment
            base.carbs = max(20, base.carbs + (customCalorieAdjustment / 4.0).rounded())
            checkIn.targets = base
        }
        checkIn.accepted = true
        try? modelContext.save()
        dismiss()
    }
}
