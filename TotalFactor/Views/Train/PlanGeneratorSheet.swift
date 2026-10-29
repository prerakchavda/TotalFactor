import SwiftUI
import SwiftData

/// Spec §10 Rule-Based Plan Generator Sheet:
/// Inputs: goal (strength / size / both), experience, days per week, minutes per session, gym profile.
struct PlanGeneratorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query private var exercises: [Exercise]
    @Query private var gymProfiles: [GymProfile]
    @Query private var programs: [Program]

    @State private var goalFocus: TrainingGoalFocus = .both
    @State private var experience: ExperienceLevel = .intermediate
    @State private var daysPerWeek: Int = 4
    @State private var minutesPerSession: Int = 60
    @State private var selectedGymID: UUID? = nil

    private var chosenGym: GymProfile? {
        if let id = selectedGymID, let match = gymProfiles.first(where: { $0.id == id }) {
            return match
        }
        return gymProfiles.first(where: \.isDefault) ?? gymProfiles.first
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Training Parameters") {
                    Picker("Primary Focus", selection: $goalFocus) {
                        ForEach(TrainingGoalFocus.allCases) { g in
                            Text(g.displayName).tag(g)
                        }
                    }

                    Picker("Experience", selection: $experience) {
                        ForEach(ExperienceLevel.allCases) { e in
                            Text("\(e.displayName) (~\(e.targetWeeklyHardSetsPerMuscle) sets/muscle/wk)").tag(e)
                        }
                    }

                    Stepper("Days Per Week: \(daysPerWeek)", value: $daysPerWeek, in: 2...6)
                    Stepper("Session Cap: \(minutesPerSession) min", value: $minutesPerSession, in: 30...105, step: 5)

                    Picker("Gym Equipment Profile", selection: $selectedGymID) {
                        ForEach(gymProfiles) { gym in
                            Text(gym.name).tag(Optional(gym.id))
                        }
                    }
                }

                Section {
                    Button {
                        generateAndSave()
                    } label: {
                        Label("Generate & Activate Program", systemImage: "wand.and.stars")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                } footer: {
                    Text("Uses ~2.75 min/set pacing, movement-pattern balance, available gym equipment, and exercises with your personal lift history.")
                }
            }
            .navigationTitle("Plan Generator")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                selectedGymID = chosenGym?.id
            }
        }
    }

    private func generateAndSave() {
        let equip = Set(chosenGym?.availableEquipment ?? Equipment.allCases)
        let historyIDs = Set(exercises.filter { !($0.setLogs ?? []).isEmpty }.map(\.id))
        let exerciseByID = Dictionary(exercises.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        let blueprint = ProgramGeneratorEngine.generateProgram(
            goalFocus: goalFocus,
            experience: experience,
            daysPerWeek: daysPerWeek,
            minutesPerSession: minutesPerSession,
            availableEquipment: equip,
            exercisePool: exercises.map(\.asBlueprint),
            historicalExerciseIDs: historyIDs
        )

        for p in programs { p.isActive = false }
        let program = Program(name: blueprint.name, daysPerWeek: blueprint.daysPerWeek, isActive: true)
        modelContext.insert(program)

        for (wIdx, wb) in blueprint.workouts.enumerated() {
            let workout = ProgramWorkout(name: wb.name, order: wIdx, scheduledWeekday: wb.scheduledWeekday)
            workout.program = program
            modelContext.insert(workout)
            for (sIdx, sb) in wb.slots.enumerated() {
                let slot = ExerciseSlot(
                    order: sIdx,
                    exercise: exerciseByID[sb.exercise.id],
                    sets: sb.sets,
                    repRangeLow: sb.repRangeLow,
                    repRangeHigh: sb.repRangeHigh,
                    targetRIR: sb.targetRIR,
                    restSeconds: sb.restSeconds,
                    progressionRule: sb.progressionRule
                )
                slot.workout = workout
                modelContext.insert(slot)
            }
        }

        try? modelContext.save()
        _ = CoachingCoordinator.evaluate(context: modelContext)
        dismiss()
    }
}
