import SwiftUI

/// Spec MacroFactor Workouts Custom Gym Keypad:
/// - Horizontal colored RIR strip (`0` to `6+`)
/// - 10-Key numeric pad with first-digit overwrite and decimal support
/// - Side utilities: keyboard toggle, plate/notes, set type selector
/// - Prominent checkmark `✓` commit button for instant 1-tap logging
struct MacroFactorGymKeypad: View {
    enum ActiveField: Hashable {
        case weight
        case reps
        case weightLeft
        case repsLeft
        case weightRight
        case repsRight
    }

    let activeField: ActiveField
    let currentRIR: Int
    let setType: SetType
    let onDigit: (String) -> Void
    let onBackspace: () -> Void
    let onSetRIR: (Int) -> Void
    let onCycleSetType: () -> Void
    let onOpenPlatesOrNotes: () -> Void
    let onDismissKeypad: () -> Void
    let onCommitSet: () -> Void

    init(
        activeField: ActiveField,
        currentRIR: Int,
        setType: SetType,
        onDigit: @escaping (String) -> Void,
        onBackspace: @escaping () -> Void,
        onSetRIR: @escaping (Int) -> Void,
        onCycleSetType: @escaping () -> Void,
        onOpenPlatesOrNotes: @escaping () -> Void,
        onDismissKeypad: @escaping () -> Void,
        onCommitSet: @escaping () -> Void
    ) {
        self.activeField = activeField
        self.currentRIR = currentRIR
        self.setType = setType
        self.onDigit = onDigit
        self.onBackspace = onBackspace
        self.onSetRIR = onSetRIR
        self.onCycleSetType = onCycleSetType
        self.onOpenPlatesOrNotes = onOpenPlatesOrNotes
        self.onDismissKeypad = onDismissKeypad
        self.onCommitSet = onCommitSet
    }

    public var body: some View {
        VStack(spacing: 8) {
            // 1. Top Colored RIR Pill Strip
            rirPillStrip

            // 2. Main Keypad Grid (3 Columns Numeric + 1 Column Utility)
            HStack(spacing: 8) {
                // Numeric 3x4 Grid
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        keyButton("1")
                        keyButton("2")
                        keyButton("3")
                    }
                    HStack(spacing: 8) {
                        keyButton("4")
                        keyButton("5")
                        keyButton("6")
                    }
                    HStack(spacing: 8) {
                        keyButton("7")
                        keyButton("8")
                        keyButton("9")
                    }
                    HStack(spacing: 8) {
                        decimalOrBlankButton
                        keyButton("0")
                        backspaceButton
                    }
                }

                // Right Utility Column (4 Keys)
                VStack(spacing: 8) {
                    // 1. Dismiss Keypad
                    Button {
                        playClickHaptic()
                        onDismissKeypad()
                    } label: {
                        Image(systemName: "keyboard.chevron.compact.down")
                            .font(.system(size: 18, weight: .semibold))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)

                    // 2. Plates / Cues
                    Button {
                        playClickHaptic()
                        onOpenPlatesOrNotes()
                    } label: {
                        Image(systemName: "circle.grid.cross")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)

                    // 3. Set Type Toggle
                    Button {
                        playClickHaptic()
                        onCycleSetType()
                    } label: {
                        Text(setType.badge)
                            .font(.system(size: 15, weight: .heavy, design: .rounded))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(setTypeBackground(setType), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .foregroundStyle(setTypeForeground(setType))
                    }
                    .buttonStyle(.plain)

                    // 4. Commit Set Checkmark Button
                    Button {
                        playCommitHaptic()
                        onCommitSet()
                    } label: {
                        Image(systemName: "checkmark")
                            .font(.system(size: 20, weight: .bold))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color.primary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .foregroundStyle(Color(.systemBackground))
                    }
                    .buttonStyle(.plain)
                }
                .frame(width: 68)
            }
            .frame(height: 200)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(.systemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.8)
        )
        .shadow(color: Color.black.opacity(0.12), radius: 10, y: -2)
    }

    // MARK: - RIR Pill Strip

    private var rirPillStrip: some View {
        HStack(spacing: 8) {
            ForEach(0...6, id: \.self) { rir in
                Button {
                    playClickHaptic()
                    onSetRIR(rir)
                } label: {
                    ZStack {
                        Circle()
                            .fill(rirColor(rir))
                            .frame(width: 32, height: 32)
                        Text(rir == 6 ? "6+" : "\(rir)")
                            .font(.system(size: 13, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                    }
                    .overlay(
                        Circle()
                            .strokeBorder(Color.primary, lineWidth: currentRIR == rir ? 2.5 : 0)
                    )
                    .scaleEffect(currentRIR == rir ? 1.08 : 1.0)
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 4)

            // ? (Unrated RIR)
            Button {
                playClickHaptic()
                onSetRIR(2) // Default moderate RIR
            } label: {
                ZStack {
                    Circle()
                        .fill(Color(.systemGray4))
                        .frame(width: 32, height: 32)
                    Text("?")
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
    }

    // MARK: - Button Helpers

    private func keyButton(_ digit: String) -> some View {
        Button {
            playClickHaptic()
            onDigit(digit)
        } label: {
            Text(digit)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var decimalOrBlankButton: some View {
        if activeField == .weight || activeField == .weightLeft || activeField == .weightRight {
            Button {
                playClickHaptic()
                onDigit(".")
            } label: {
                Text(".")
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)
        } else {
            // Reps do not need decimals
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var backspaceButton: some View {
        Button {
            playClickHaptic()
            onBackspace()
        } label: {
            Image(systemName: "delete.left.fill")
                .font(.system(size: 18, weight: .semibold))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Colors & Haptics

    public static func rirColor(_ rir: Int) -> Color {
        switch rir {
        case 0: return Color(red: 0.95, green: 0.22, blue: 0.22) // Red (Failure)
        case 1: return Color(red: 0.98, green: 0.38, blue: 0.24) // Coral
        case 2: return Color(red: 1.00, green: 0.60, blue: 0.12) // Orange
        case 3: return Color(red: 0.98, green: 0.78, blue: 0.16) // Amber/Yellow
        case 4: return Color(red: 0.22, green: 0.78, blue: 0.44) // Mint
        case 5: return Color(red: 0.18, green: 0.82, blue: 0.35) // Green
        default: return Color(red: 0.08, green: 0.52, blue: 0.98) // Blue (6+)
        }
    }

    private func rirColor(_ rir: Int) -> Color {
        Self.rirColor(rir)
    }

    private func setTypeBackground(_ type: SetType) -> Color {
        switch type {
        case .working: return Color.primary.opacity(0.10)
        case .warmup: return Color.orange.opacity(0.18)
        case .drop: return Color.purple.opacity(0.18)
        case .failure: return Color.red.opacity(0.18)
        case .partial: return Color.teal.opacity(0.18)
        case .myorep: return Color.indigo.opacity(0.18)
        }
    }

    private func setTypeForeground(_ type: SetType) -> Color {
        switch type {
        case .working: return .primary
        case .warmup: return .orange
        case .drop: return .purple
        case .failure: return .red
        case .partial: return .teal
        case .myorep: return .indigo
        }
    }

    private func playClickHaptic() {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }

    private func playCommitHaptic() {
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }
}
