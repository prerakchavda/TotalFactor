import SwiftUI

struct MacroZoneBar: View {
    let title: String
    let current: Double
    let unit: String
    let floor: Double?
    let target: Double?
    let ceiling: Double?
    let tint: Color

    private var scaleMax: Double {
        let candidates = [current, floor ?? 0, target ?? 0, ceiling ?? 0].filter { $0 > 0 }
        let highest = candidates.max() ?? 100
        return max(10, highest * 1.18)
    }

    private var statusColor: Color {
        if let ceiling, current > ceiling {
            return .red
        }
        if let floor, current < floor {
            return tint.opacity(0.75)
        }
        return tint
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                HStack(spacing: 4) {
                    Text("\(Int(current.rounded()))")
                        .font(.subheadline.weight(.bold).monospacedDigit())
                        .foregroundStyle(
                            (ceiling != nil && current > ceiling!) ? Color.red : Color.primary
                        )
                    if let target {
                        Text("/ \(Int(target.rounded())) \(unit)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    } else if let ceiling {
                        Text("/ ≤\(Int(ceiling.rounded())) \(unit)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    } else if let floor {
                        Text("/ ≥\(Int(floor.rounded())) \(unit)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }

            GeometryReader { geo in
                let width = max(1, geo.size.width)
                let fillWidth = min(width, max(0, CGFloat(current / scaleMax) * width))

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.16))
                        .frame(height: 10)

                    // Optimal zone highlight between floor and ceiling/target
                    if let floor {
                        let startX = min(width, CGFloat(floor / scaleMax) * width)
                        let endVal = ceiling ?? (target.map { $0 * 1.1 } ?? scaleMax)
                        let endX = min(width, CGFloat(endVal / scaleMax) * width)
                        if endX > startX {
                            Rectangle()
                                .fill(tint.opacity(0.18))
                                .frame(width: endX - startX, height: 10)
                                .offset(x: startX)
                        }
                    }

                    Capsule()
                        .fill(statusColor)
                        .frame(width: fillWidth, height: 10)

                    // Floor tick
                    if let floor {
                        let x = min(width - 2, CGFloat(floor / scaleMax) * width)
                        Rectangle()
                            .fill(Color.primary.opacity(0.55))
                            .frame(width: 2, height: 14)
                            .offset(x: x)
                    }

                    // Target tick
                    if let target {
                        let x = min(width - 2, CGFloat(target / scaleMax) * width)
                        Circle()
                            .fill(Color.primary)
                            .frame(width: 6, height: 6)
                            .offset(x: x - 3)
                    }

                    // Ceiling tick
                    if let ceiling {
                        let x = min(width - 2, CGFloat(ceiling / scaleMax) * width)
                        Rectangle()
                            .fill(Color.red.opacity(0.85))
                            .frame(width: 2, height: 14)
                            .offset(x: x)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .frame(height: 14)

            HStack(spacing: 10) {
                if let floor {
                    Text("Floor \(Int(floor.rounded()))\(unit)")
                }
                if let target {
                    let diff = Int((target - current).rounded())
                    Text(diff >= 0 ? "\(diff)\(unit) left" : "\(abs(diff))\(unit) over")
                }
                if let ceiling {
                    Text("Max \(Int(ceiling.rounded()))\(unit)")
                }
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
        }
    }
}

struct FoodSourceBadge: View {
    let source: FoodSource

    private var color: Color {
        switch source {
        case .usda: return .green
        case .off: return .orange
        case .custom: return .blue
        case .recipe: return .purple
        case .healthKit: return .pink
        }
    }

    var body: some View {
        Text(source.shortBadge)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }
}

struct ConfidencePill: View {
    let confidence: ConfidenceLevel

    private var color: Color {
        switch confidence {
        case .low: return .orange
        case .medium: return .blue
        case .high: return .green
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text("\(confidence.displayName) Confidence")
                .font(.caption2.weight(.semibold))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(color.opacity(0.14), in: Capsule())
        .foregroundStyle(color)
    }
}
