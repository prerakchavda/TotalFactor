import SwiftUI

/// MacroFactor Workouts Routine Change Log & Commit Sheet (§9 & §10)
/// When finishing a workout with modifications (added sets, swapped exercises, etc.),
/// prompts the user to either update their saved program template or keep changes for today only.
struct WorkoutChangeLogSheet: View {
    @Environment(\.dismiss) private var dismiss

    let workoutTitle: String
    let programName: String
    let diffItems: [ChangeLogDiffItem]
    let onCommitToRoutine: () -> Void
    let onSaveTodayOnly: () -> Void

    public struct ChangeLogDiffItem: Identifiable, Sendable {
        public enum Kind: Sendable {
            case addedExercise
            case swappedExercise
            case setStructureChanged
        }

        public var id: UUID = UUID()
        public var kind: Kind
        public var title: String
        public var detail: String

        public init(kind: Kind, title: String, detail: String) {
            self.kind = kind
            self.title = title
            self.detail = detail
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        // Header Banner
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Workout Finished")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                            Text("Routine Changes Detected")
                                .font(.title2.weight(.bold))
                                .foregroundStyle(.primary)
                            Text("You made modifications to '\(workoutTitle)' in '\(programName)'. Would you like to commit these adjustments to your routine for future sessions?")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 8)

                        // Diff Items Card
                        VStack(alignment: .leading, spacing: 14) {
                            Text("MODIFICATIONS MADE TODAY")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.secondary)

                            ForEach(diffItems) { item in
                                HStack(alignment: .top, spacing: 12) {
                                    iconForKind(item.kind)
                                        .frame(width: 24, height: 24)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.title)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(.primary)
                                        Text(item.detail)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                if item.id != diffItems.last?.id {
                                    Divider()
                                }
                            }
                        }
                        .padding(16)
                        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                    }
                    .padding()
                }

                // Action Buttons
                VStack(spacing: 10) {
                    Button {
                        onCommitToRoutine()
                        dismiss()
                    } label: {
                        Text("Update '\(programName)' Routine")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        onSaveTodayOnly()
                        dismiss()
                    } label: {
                        Text("Save for Today Only")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal)
                .padding(.bottom, 20)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Commit Routine Changes")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func iconForKind(_ kind: ChangeLogDiffItem.Kind) -> some View {
        switch kind {
        case .addedExercise:
            return Image(systemName: "plus.circle.fill")
                .foregroundStyle(.green)
        case .swappedExercise:
            return Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                .foregroundStyle(.blue)
        case .setStructureChanged:
            return Image(systemName: "slider.horizontal.3")
                .foregroundStyle(.orange)
        }
    }
}
