import SwiftUI

/// MacroFactor Workouts In-Session Exercise Swap Sheet (§9)
/// Allows swapping a machine/exercise for a biomechanically equivalent substitute
/// when equipment is occupied or unavailable.
struct ExerciseSwapSheet: View {
    @Environment(\.dismiss) private var dismiss

    let currentExercise: Exercise
    let allExercises: [Exercise]
    let gymProfile: GymProfile?
    let onSelect: (Exercise) -> Void

    @State private var searchText: String = ""

    private var availableEquipmentSet: Set<Equipment>? {
        gymProfile.map { Set($0.availableEquipment) }
    }

    private var candidateSubstitutes: [Exercise] {
        let blueprintMap = Dictionary(allExercises.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let rankedBlueprints = ProgressionEngine.swapCandidates(
            for: currentExercise.asBlueprint,
            in: allExercises.map(\.asBlueprint),
            availableEquipment: availableEquipmentSet
        )
        let ranked = rankedBlueprints.compactMap { blueprintMap[$0.id] }
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return ranked }
        return ranked.filter {
            $0.name.lowercased().contains(q) ||
            $0.equipment.displayName.lowercased().contains(q) ||
            $0.primaryMuscles.contains { $0.displayName.lowercased().contains(q) }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Current Exercise")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)
                        HStack(spacing: 12) {
                            ExerciseThumbnailView(exercise: currentExercise, size: 44, cornerRadius: 10)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(currentExercise.name)
                                    .font(.subheadline.weight(.semibold))
                                Text("\(currentExercise.equipment.displayName) • \(currentExercise.movementPattern.displayName)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Recommended Substitutes") {
                    if candidateSubstitutes.isEmpty {
                        Text("No matching substitute exercises found.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(candidateSubstitutes) { candidate in
                            Button {
                                onSelect(candidate)
                                dismiss()
                            } label: {
                                HStack(spacing: 12) {
                                    ExerciseThumbnailView(exercise: candidate, size: 44, cornerRadius: 10)
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 6) {
                                            Text(candidate.name)
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundStyle(.primary)

                                            if candidate.movementPattern == currentExercise.movementPattern {
                                                Text("Direct Match")
                                                    .font(.system(size: 9, weight: .bold))
                                                    .padding(.horizontal, 5)
                                                    .padding(.vertical, 2)
                                                    .background(Color.green.opacity(0.15), in: Capsule())
                                                    .foregroundStyle(.green)
                                            }
                                        }
                                        Text("\(candidate.equipment.displayName) • \(candidate.primaryMuscles.map(\.displayName).joined(separator: ", "))")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "arrow.triangle.2.circlepath")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search substitutes")
            .navigationTitle("Swap Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
