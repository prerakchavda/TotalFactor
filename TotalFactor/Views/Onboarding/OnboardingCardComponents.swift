import SwiftUI

// MARK: - Onboarding Card Components (MacroFactor-Style)

public struct OnboardingHeader: View {
    let currentStep: Int
    let totalSteps: Int
    let title: String
    let subtitle: String?

    public init(currentStep: Int, totalSteps: Int, title: String, subtitle: String? = nil) {
        self.currentStep = currentStep
        self.totalSteps = totalSteps
        self.title = title
        self.subtitle = subtitle
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Step \(currentStep) of \(totalSteps)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Spacer()
                Text("\(Int((Double(currentStep) / Double(totalSteps)) * 100))%")
                    .font(.caption2.weight(.bold).monospacedDigit())
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.accentColor.opacity(0.12), in: Capsule())
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.18))
                        .frame(height: 6)

                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: max(12, geo.size.width * CGFloat(Double(currentStep) / Double(totalSteps))), height: 6)
                        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: currentStep)
                }
            }
            .frame(height: 6)

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.primary)

                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.top, 4)
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }
}

public struct OnboardingBottomBar: View {
    let canGoBack: Bool
    let continueTitle: String
    let onBack: () -> Void
    let onContinue: () -> Void

    public init(
        canGoBack: Bool = true,
        continueTitle: String = "Continue",
        onBack: @escaping () -> Void,
        onContinue: @escaping () -> Void
    ) {
        self.canGoBack = canGoBack
        self.continueTitle = continueTitle
        self.onBack = onBack
        self.onContinue = onContinue
    }

    public var body: some View {
        HStack(spacing: 12) {
            if canGoBack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.headline)
                        .frame(width: 48, height: 48)
                        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")
            }

            Button(action: onContinue) {
                HStack {
                    Text(continueTitle)
                        .font(.headline.weight(.semibold))
                    Image(systemName: "arrow.right")
                        .font(.subheadline.weight(.bold))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(
            Color(uiColor: .systemBackground)
                .shadow(color: .black.opacity(0.06), radius: 6, y: -3)
        )
    }
}

public struct OnboardingSelectableCard: View {
    let title: String
    let subtitle: String?
    let systemImage: String
    let accentColor: Color
    let isSelected: Bool
    let badgeText: String?
    let action: () -> Void

    public init(
        title: String,
        subtitle: String? = nil,
        systemImage: String,
        accentColor: Color = .accentColor,
        isSelected: Bool,
        badgeText: String? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.accentColor = accentColor
        self.isSelected = isSelected
        self.badgeText = badgeText
        self.action = action
    }

    public var body: some View {
        Button(action: {
            #if canImport(UIKit)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            action()
        }) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundStyle(isSelected ? .white : accentColor)
                    .frame(width: 42, height: 42)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(isSelected ? accentColor : accentColor.opacity(0.12))
                    )

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)

                        if let badgeText {
                            Text(badgeText)
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(accentColor.opacity(0.14), in: Capsule())
                                .foregroundStyle(accentColor)
                        }
                    }

                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? accentColor : Color.secondary.opacity(0.35))
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected ? accentColor.opacity(0.08) : Color.secondary.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? accentColor : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

public struct MacroFactorGoalCard: View {
    let goal: GoalType
    let isSelected: Bool
    let action: () -> Void

    public var body: some View {
        let (icon, color, subtitle, tag): (String, Color, String, String) = {
            switch goal {
            case .cut:
                return (
                    "arrow.down.right.circle.fill",
                    .orange,
                    "Target sustainable fat loss while preserving lean muscle mass and metabolic rate.",
                    "Recommended"
                )
            case .maintain:
                return (
                    "equal.circle.fill",
                    .blue,
                    "Keep your weight stable while optimizing gym performance, recovery, and body recomposition.",
                    "Energy & Strength"
                )
            case .bulk:
                return (
                    "arrow.up.right.circle.fill",
                    .green,
                    "A calculated surplus to maximize muscle hypertrophy and strength gains while minimizing excess fat.",
                    "Hypertrophy"
                )
            }
        }()

        OnboardingSelectableCard(
            title: goal.displayName,
            subtitle: subtitle,
            systemImage: icon,
            accentColor: color,
            isSelected: isSelected,
            badgeText: tag,
            action: action
        )
    }
}

public struct MacroFactorRateSliderCard: View {
    let goalType: GoalType
    @Binding var ratePercent: Double
    let bodyWeightKg: Double
    let unitSystem: UnitSystem

    private var weeklyWeightKg: Double {
        bodyWeightKg * (ratePercent / 100.0)
    }

    private var weeklyWeightDisplay: String {
        let val = unitSystem == .imperial ? UnitsFormatter.kgToLb(weeklyWeightKg) : weeklyWeightKg
        return String(format: "%.2f %@", val, unitSystem.weightSymbol)
    }

    private var zoneInfo: (name: String, color: Color, note: String) {
        switch goalType {
        case .cut:
            if ratePercent < 0.40 {
                return ("Conservative", .mint, "Gentle pace: maximum energy, highest muscle retention, easiest social adherence.")
            } else if ratePercent <= 0.75 {
                return ("Standard (Recommended)", .orange, "Optimal balance of fat loss speed, training performance, and satiety.")
            } else {
                return ("Aggressive", .red, "Fast fat loss: requires strict dietary discipline and higher fatigue management.")
            }
        case .bulk:
            if ratePercent < 0.20 {
                return ("Conservative", .mint, "Minimal fat gain; slow and steady lean mass accrual.")
            } else if ratePercent <= 0.35 {
                return ("Standard (Recommended)", .green, "Optimal rate for muscle hypertrophy while controlling fat accumulation.")
            } else {
                return ("Aggressive", .orange, "Maximum surplus: faster weight gain; recommended primarily for beginners.")
            }
        case .maintain:
            return ("Maintenance", .blue, "Maintains weight within a natural ±1.5% bodyweight fluid buffer.")
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Target Rate of Change")
                        .font(.headline)
                    Text("\(String(format: "%.2f", ratePercent))% body weight / week")
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Color.accentColor)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("~\(weeklyWeightDisplay) / wk")
                        .font(.headline.weight(.bold).monospacedDigit())
                    Text(zoneInfo.name)
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(zoneInfo.color.opacity(0.15), in: Capsule())
                        .foregroundStyle(zoneInfo.color)
                }
            }

            Slider(
                value: $ratePercent,
                in: goalType.suggestedRateRangePercent,
                step: 0.05
            )
            .tint(zoneInfo.color)

            HStack {
                Text(String(format: "Min: %.2f%%", goalType.suggestedRateRangePercent.lowerBound))
                Spacer()
                Text(String(format: "Max: %.2f%%", goalType.suggestedRateRangePercent.upperBound))
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)

            Text(zoneInfo.note)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .padding(16)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

public struct MacroFactorSplitPreviewBar: View {
    let calories: Double
    let targets: MacroTargets

    private var proteinKcal: Double { targets.protein * 4 }
    private var carbsKcal: Double { targets.carbs * 4 }
    private var fatKcal: Double { targets.fat * 9 }
    private var totalSumKcal: Double { max(1, proteinKcal + carbsKcal + fatKcal) }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Day-1 Energy Target")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(Int(calories.rounded()))")
                            .font(.system(size: 32, weight: .bold, design: .rounded).monospacedDigit())
                        Text("kcal / day")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }

            // Stacked colored bar
            GeometryReader { geo in
                HStack(spacing: 2) {
                    Rectangle()
                        .fill(Color.blue)
                        .frame(width: max(4, geo.size.width * CGFloat(proteinKcal / totalSumKcal)))

                    Rectangle()
                        .fill(Color.orange)
                        .frame(width: max(4, geo.size.width * CGFloat(carbsKcal / totalSumKcal)))

                    Rectangle()
                        .fill(Color.yellow)
                        .frame(width: max(4, geo.size.width * CGFloat(fatKcal / totalSumKcal)))
                }
                .clipShape(Capsule())
            }
            .frame(height: 12)

            // 3 macro stat chips
            HStack(spacing: 8) {
                macroChip(
                    title: "Protein",
                    grams: Int(targets.protein.rounded()),
                    color: .blue,
                    percent: Int((proteinKcal / totalSumKcal * 100).rounded())
                )
                macroChip(
                    title: "Carbs",
                    grams: Int(targets.carbs.rounded()),
                    color: .orange,
                    percent: Int((carbsKcal / totalSumKcal * 100).rounded())
                )
                macroChip(
                    title: "Fat",
                    grams: Int(targets.fat.rounded()),
                    color: .yellow,
                    percent: Int((fatKcal / totalSumKcal * 100).rounded())
                )
            }
        }
        .padding(16)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func macroChip(title: String, grams: Int, color: Color, percent: Int) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(grams)")
                    .font(.headline.weight(.bold).monospacedDigit())
                Text("g")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text("\(percent)% kcal")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.09), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
