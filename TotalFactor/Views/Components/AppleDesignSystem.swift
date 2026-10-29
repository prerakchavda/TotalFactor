import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Authentic Apple Health & Apple Fitness visual design system for Total Factor.
/// Implements Apple's signature SF Rounded metric typography, un-cramped card hierarchy,
/// native grouped surfaces, floating ultra-thin glass, and vibrant health metric palette.
public enum AppleTheme {
    /// Apple Fitness / Health Active Energy Flame Orange
    public static let calories = Color(red: 1.0, green: 0.369, blue: 0.102)
    /// Apple Health Heart / Nutrition Coral Pink
    public static let protein = Color(red: 1.0, green: 0.176, blue: 0.333)
    /// Apple Health Electric Cyan / Aqua
    public static let carbs = Color(red: 0.0, green: 0.780, blue: 0.745)
    /// Apple Fitness Luminous Gold
    public static let fat = Color(red: 1.0, green: 0.839, blue: 0.0)
    /// Apple Health Trends Royal Violet
    public static let expenditure = Color(red: 0.686, green: 0.322, blue: 0.871)
    /// Apple Health Body Metrics Ocean Teal
    public static let trend = Color(red: 0.188, green: 0.690, blue: 0.780)
    /// Apple Fitness Workout Neon Lime
    public static let exercise = Color(red: 0.631, green: 1.0, blue: 0.0)

    #if canImport(UIKit)
    public static let background = Color(uiColor: .systemGroupedBackground)
    public static let cardSurface = Color(uiColor: .secondarySystemGroupedBackground)
    public static let tertiarySurface = Color(uiColor: .tertiarySystemGroupedBackground)
    public static let hairline = Color(uiColor: .separator).opacity(0.14)
    #else
    public static let background = Color(white: 0.05)
    public static let cardSurface = Color(white: 0.12)
    public static let tertiarySurface = Color(white: 0.18)
    public static let hairline = Color.white.opacity(0.10)
    #endif
}

public struct AppleCardModifier: ViewModifier {
    var padding: CGFloat = 18
    var cornerRadius: CGFloat = 18

    public func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(AppleTheme.cardSurface)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(AppleTheme.hairline, lineWidth: 0.75)
                    )
            )
    }
}

public extension View {
    func appleHealthCard(padding: CGFloat = 18, cornerRadius: CGFloat = 18) -> some View {
        self.modifier(AppleCardModifier(padding: padding, cornerRadius: cornerRadius))
    }
}

/// Small tinted squircle icon badge matching Apple Health category headers
public struct AppleIconBadge: View {
    let icon: String
    let color: Color
    var size: CGFloat = 28

    public init(icon: String, color: Color, size: CGFloat = 28) {
        self.icon = icon
        self.color = color
        self.size = size
    }

    public var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(color.opacity(0.15))
                .frame(width: size, height: size)
            Image(systemName: icon)
                .font(.system(size: size * 0.52, weight: .semibold))
                .foregroundStyle(color)
        }
    }
}

/// Apple Health clean section header with optional icon badge and subtitle
public struct AppleSectionHeader: View {
    let title: String
    var icon: String? = nil
    var color: Color = .primary
    var subtitle: String? = nil

    public init(title: String, icon: String? = nil, color: Color = .primary, subtitle: String? = nil) {
        self.title = title
        self.icon = icon
        self.color = color
        self.subtitle = subtitle
    }

    public var body: some View {
        HStack(spacing: 8) {
            if let icon {
                AppleIconBadge(icon: icon, color: color, size: 26)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.primary)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }
}

/// Apple Fitness style smooth horizontal progress bar with rounded ends and tinted background track
public struct AppleFitnessBar: View {
    let progress: Double
    let color: Color
    var height: CGFloat = 8

    public init(progress: Double, color: Color, height: CGFloat = 8) {
        self.progress = max(0.0, min(1.5, progress))
        self.color = color
        self.height = height
    }

    public var body: some View {
        GeometryReader { geo in
            let fillWidth = geo.size.width * min(1.0, progress)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(color.opacity(0.18))
                    .frame(height: height)

                Capsule()
                    .fill(color)
                    .frame(width: max(fillWidth > 0 ? height : 0, fillWidth), height: height)
            }
        }
        .frame(height: height)
    }
}

/// Un-cramped Apple Health macro column with rounded digits and micro progress bar
public struct AppleMacroColumnView: View {
    let title: String
    let eaten: Double
    let target: Double
    let color: Color

    public init(title: String, eaten: Double, target: Double, color: Color) {
        self.title = title
        self.eaten = eaten
        self.target = target
        self.color = color
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)
                Text(title)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(Int(eaten.rounded()))")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text("/\(Int(target.rounded()))g")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            let ratio = target > 0 ? (eaten / target) : 0
            AppleFitnessBar(progress: ratio, color: color, height: 4)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
