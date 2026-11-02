import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// MacroFactor-inspired visual design system for Total Factor.
/// Monochrome surfaces (true black / white), flat borderless cards, wide all-caps display titles,
/// inverted pill buttons, and the MacroFactor nutrient palette (blue calories, coral protein,
/// amber fat, green carbs). The `AppleTheme` name is kept so existing call sites restyle automatically.
public enum AppleTheme {
    /// MacroFactor Calories Blue
    public static let calories = Color(mfHex: 0x5B8DEF)
    /// MacroFactor Protein Coral
    public static let protein = Color(mfHex: 0xF0785A)
    /// Expenditure / TDEE Violet
    public static let expenditure = Color(mfHex: 0xB28CF2)
    /// Interactive accent for links and secondary highlights
    public static let accent = Color(mfHex: 0x5B8DEF)

    #if canImport(UIKit)
    // Light-mode variants are darkened so labels stay readable on white / light-gray cards.
    /// MacroFactor Carbs Green
    public static let carbs = adaptive(light: 0x2E9E5B, dark: 0x5FBF84)
    /// MacroFactor Fat Amber
    public static let fat = adaptive(light: 0xC98A0B, dark: 0xF2C14E)
    /// Weight Trend Teal
    public static let trend = adaptive(light: 0x2A93A6, dark: 0x56B8C9)
    /// Workout / Training Lime
    public static let exercise = adaptive(light: 0x4F9E1F, dark: 0x8BD45A)

    /// Page background: pure white (light) / true black (dark)
    public static let background = adaptive(light: 0xFFFFFF, dark: 0x000000)
    /// Flat card surface: soft gray (light) / MacroFactor charcoal (dark)
    public static let cardSurface = adaptive(light: 0xF2F2F4, dark: 0x1C1C1E)
    /// Chips, input wells, bar tracks
    public static let tertiarySurface = adaptive(light: 0xE5E5EA, dark: 0x2C2C2E)
    public static let hairline = Color(uiColor: .separator).opacity(0.35)

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(mfHex: dark) : UIColor(mfHex: light)
        })
    }
    #else
    public static let carbs = Color(mfHex: 0x5FBF84)
    public static let fat = Color(mfHex: 0xF2C14E)
    public static let trend = Color(mfHex: 0x56B8C9)
    public static let exercise = Color(mfHex: 0x8BD45A)
    public static let background = Color.black
    public static let cardSurface = Color(white: 0.11)
    public static let tertiarySurface = Color(white: 0.17)
    public static let hairline = Color.white.opacity(0.10)
    #endif
}

fileprivate extension Color {
    init(mfHex hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0
        )
    }
}

#if canImport(UIKit)
fileprivate extension UIColor {
    convenience init(mfHex hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255.0,
            green: CGFloat((hex >> 8) & 0xFF) / 255.0,
            blue: CGFloat(hex & 0xFF) / 255.0,
            alpha: 1.0
        )
    }
}

/// Global UIKit chrome: MacroFactor wide black large titles, borderless nav bars, hidden system tab bar
/// (RootTabView draws its own MacroFactor tab bar).
public enum MFAppearance {
    public static func configure() {
        let largeTitleFont = UIFont.systemFont(ofSize: 28, weight: .black, width: .expanded)
        let inlineTitleFont = UIFont.systemFont(ofSize: 17, weight: .bold)

        let standard = UINavigationBarAppearance()
        standard.configureWithDefaultBackground()
        standard.shadowColor = .clear
        standard.largeTitleTextAttributes = [.font: largeTitleFont]
        standard.titleTextAttributes = [.font: inlineTitleFont]

        let scrollEdge = UINavigationBarAppearance()
        scrollEdge.configureWithTransparentBackground()
        scrollEdge.largeTitleTextAttributes = [.font: largeTitleFont]
        scrollEdge.titleTextAttributes = [.font: inlineTitleFont]

        let navBar = UINavigationBar.appearance()
        navBar.standardAppearance = standard
        navBar.compactAppearance = standard
        navBar.scrollEdgeAppearance = scrollEdge

        UITabBar.appearance().isHidden = true
    }
}
#endif

// MARK: - Cards

public struct AppleCardModifier: ViewModifier {
    var padding: CGFloat = 18
    var cornerRadius: CGFloat = 16

    public func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(AppleTheme.cardSurface)
            )
    }
}

public extension View {
    /// Flat, borderless MacroFactor card surface
    func appleHealthCard(padding: CGFloat = 18, cornerRadius: CGFloat = 16) -> some View {
        self.modifier(AppleCardModifier(padding: padding, cornerRadius: cornerRadius))
    }

    /// Alias for `appleHealthCard` used by MacroFactor-styled screens
    func mfCard(padding: CGFloat = 16, cornerRadius: CGFloat = 16) -> some View {
        self.modifier(AppleCardModifier(padding: padding, cornerRadius: cornerRadius))
    }
}

// MARK: - Typography

/// MacroFactor wide, all-caps display title ("DASHBOARD", "WORKOUTS")
public struct MFDisplayTitle: View {
    let text: String
    var size: CGFloat = 30

    public init(_ text: String, size: CGFloat = 30) {
        self.text = text
        self.size = size
    }

    public var body: some View {
        Text(text.uppercased())
            .font(.system(size: size, weight: .black))
            .fontWidth(.expanded)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .foregroundStyle(.primary)
            .accessibilityAddTraits(.isHeader)
    }
}

/// MacroFactor section heading ("Insights & Analytics") with optional trailing text action
public struct MFSectionTitle: View {
    let title: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    public init(_ title: String, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.title = title
        self.actionTitle = actionTitle
        self.action = action
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.title3.weight(.bold))
                .foregroundStyle(.primary)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 6)
    }
}

// MARK: - Buttons

/// MacroFactor pill buttons: primary is an inverted (white-on-black / black-on-white) capsule,
/// secondary is a neutral gray chip.
public struct MFPillButtonStyle: ButtonStyle {
    public enum Kind { case primary, secondary }

    var kind: Kind = .primary
    var compact: Bool = false

    public init(_ kind: Kind = .primary, compact: Bool = false) {
        self.kind = kind
        self.compact = compact
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(compact ? .footnote.weight(.semibold) : .subheadline.weight(.bold))
            .lineLimit(1)
            .padding(.horizontal, compact ? 12 : 18)
            .padding(.vertical, compact ? 7 : 11)
            .foregroundStyle(kind == .primary ? AppleTheme.background : Color.primary)
            .background(
                Capsule().fill(kind == .primary ? Color.primary : AppleTheme.tertiarySurface)
            )
            .opacity(configuration.isPressed ? 0.75 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

public extension ButtonStyle where Self == MFPillButtonStyle {
    static var mfPrimary: MFPillButtonStyle { MFPillButtonStyle(.primary) }
    static var mfSecondary: MFPillButtonStyle { MFPillButtonStyle(.secondary) }
    static var mfChip: MFPillButtonStyle { MFPillButtonStyle(.secondary, compact: true) }
    static var mfPrimaryCompact: MFPillButtonStyle { MFPillButtonStyle(.primary, compact: true) }
}

/// Round neutral icon button label used in MacroFactor headers
public struct MFCircleIcon: View {
    let systemName: String
    var size: CGFloat = 36

    public init(_ systemName: String, size: CGFloat = 36) {
        self.systemName = systemName
        self.size = size
    }

    public var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(.primary)
            .frame(width: size, height: size)
            .background(Circle().fill(AppleTheme.tertiarySurface))
    }
}

// MARK: - Badges & Headers

/// Small squircle icon badge: colored glyph on a neutral MacroFactor well
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
                .fill(AppleTheme.tertiarySurface)
                .frame(width: size, height: size)
            Image(systemName: icon)
                .font(.system(size: size * 0.5, weight: .semibold))
                .foregroundStyle(color)
        }
    }
}

/// Card header with optional icon badge and subtitle
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
        HStack(spacing: 10) {
            if let icon {
                AppleIconBadge(icon: icon, color: color, size: 28)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.primary)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }
}

// MARK: - Progress Bars

/// Flat horizontal progress bar on a neutral track
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
                    .fill(AppleTheme.tertiarySurface)
                    .frame(height: height)

                Capsule()
                    .fill(color)
                    .frame(width: max(fillWidth > 0 ? height : 0, fillWidth), height: height)
            }
        }
        .frame(height: height)
    }
}

/// Compact macro column: label, eaten / target, and a thin progress bar
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
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(Int(eaten.rounded()))")
                    .font(.system(size: 19, weight: .bold))
                    .monospacedDigit()
                Text("/ \(Int(target.rounded()))g")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            let ratio = target > 0 ? (eaten / target) : 0
            AppleFitnessBar(progress: ratio, color: color, height: 5)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// MacroFactor dashboard nutrient column: tall rounded bar filling from the bottom,
/// value, "/ target", and the nutrient name in its signature color.
public struct MFNutrientBarColumn: View {
    let title: String
    let value: Double
    let target: Double
    let unit: String
    let color: Color
    var showRemaining: Bool = false
    var barHeight: CGFloat = 96

    public init(title: String, value: Double, target: Double, unit: String, color: Color, showRemaining: Bool = false, barHeight: CGFloat = 96) {
        self.title = title
        self.value = value
        self.target = target
        self.unit = unit
        self.color = color
        self.showRemaining = showRemaining
        self.barHeight = barHeight
    }

    public var body: some View {
        let ratio = target > 0 ? min(1.0, max(0.0, value / target)) : 0
        let displayed = showRemaining ? max(0, target - value) : value

        VStack(spacing: 8) {
            ZStack(alignment: .bottom) {
                Rectangle()
                    .fill(AppleTheme.tertiarySurface)
                Rectangle()
                    .fill(color)
                    .frame(height: barHeight * ratio)
            }
            .frame(height: barHeight)
            .frame(maxWidth: 46)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(spacing: 1) {
                Text("\(Int(displayed.rounded()))")
                    .font(.system(size: 17, weight: .bold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text("/ \(Int(target.rounded()))\(unit)")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                HStack(spacing: 4) {
                    Circle()
                        .fill(color)
                        .frame(width: 6, height: 6)
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                }
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): \(Int(value.rounded())) of \(Int(target.rounded()))\(unit)")
    }
}

/// MacroFactor food-row macro summary: "504 Cal • 33P • 7F • 0C"
public struct MFMacroSummaryLine: View {
    let calories: Double
    let protein: Double
    let fat: Double
    let carbs: Double

    public init(calories: Double, protein: Double, fat: Double, carbs: Double) {
        self.calories = calories
        self.protein = protein
        self.fat = fat
        self.carbs = carbs
    }

    public var body: some View {
        Text("\(Int(calories.rounded())) Cal  •  \(Int(protein.rounded()))P  •  \(Int(fat.rounded()))F  •  \(Int(carbs.rounded()))C")
            .font(.caption.weight(.medium))
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }
}
