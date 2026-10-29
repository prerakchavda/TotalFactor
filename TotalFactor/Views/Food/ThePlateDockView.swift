import SwiftUI
import SwiftData

/// Spec MacroFactor "The Plate" Dock (v1.5.1 Kitchen Rehaul):
/// - Persistent floating bottom capsule dock across search, scan, and pantry modes
/// - Shows live count of staged items, total calories, and macro breakdown
/// - Tap expands into full `ThePlateWorkspaceSheet`
/// - Dedicated 1-tap "Log Plate" button
struct ThePlateDockView: View {
    @Binding var stagedItems: [StagedFoodItem]
    let onOpenWorkspace: () -> Void
    let onCommit: () -> Void

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
        HStack(spacing: 12) {
            // Expandable Tray Info
            Button {
                onOpenWorkspace()
            } label: {
                HStack(spacing: 10) {
                    // Badge Count
                    ZStack {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 28, height: 28)
                        Text("\(stagedItems.count)")
                            .font(.system(size: 13, weight: .heavy, design: .rounded))
                            .foregroundStyle(Color(red: 0.18, green: 0.48, blue: 0.96))
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text("The Plate")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white)
                            Image(systemName: "chevron.up")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white.opacity(0.8))
                        }

                        Text("\(Int(totalCalories.rounded())) kcal • \(Int(totalProtein.rounded()))P \(Int(totalCarbs.rounded()))C \(Int(totalFat.rounded()))F")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                }
            }
            .buttonStyle(.plain)

            Spacer()

            // 1-Tap Log Plate Primary Button
            Button {
                onCommit()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .heavy))
                    Text("Log Plate")
                        .font(.system(size: 13, weight: .bold))
                }
                .foregroundStyle(Color(red: 0.18, green: 0.48, blue: 0.96))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.white, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Color(red: 0.18, green: 0.48, blue: 0.96),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 4)
        .padding(.horizontal, 14)
        .padding(.bottom, 6)
    }
}
