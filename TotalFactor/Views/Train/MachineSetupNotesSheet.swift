import SwiftUI

/// MacroFactor Workouts Persistent Machine Setup Notes Sheet (§9)
/// Pinned notes for seat height, cable pin, notch, or grip cues that persist across all workouts.
struct MachineSetupNotesSheet: View {
    @Environment(\.dismiss) private var dismiss

    let exercise: Exercise
    @State private var notesText: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        ExerciseThumbnailView(exercise: exercise, size: 44, cornerRadius: 10)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(exercise.name)
                                .font(.subheadline.weight(.semibold))
                            Text(exercise.equipment.displayName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    TextField(
                        "e.g. Seat #4, chest pad #2, cable notch #14, thumbs-around grip...",
                        text: $notesText,
                        axis: .vertical
                    )
                    .lineLimit(4...8)
                } header: {
                    Text("Machine & Setup Notes")
                } footer: {
                    Text("These notes automatically appear at the top of this exercise card in every current and future workout session.")
                }
            }
            .navigationTitle("Setup Notes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        exercise.machineSetupNotes = notesText.trimmingCharacters(in: .whitespacesAndNewlines)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                notesText = exercise.machineSetupNotes
            }
        }
    }
}
