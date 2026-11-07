import SwiftUI
import SwiftData

/// Edit a finished workout: title, date/time, duration, notes, and every set's type, load and reps.
/// Edits are held as drafts until Save, so Cancel leaves the workout untouched.
struct WorkoutSessionEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let session: WorkoutSession
    let unitSystem: UnitSystem

    private struct SetDraft {
        var weightText: String
        var repsText: String
        var type: SetType
        var isNew: Bool
    }

    private struct ExerciseDraft: Identifiable {
        var id: UUID { exercise.id }
        let exercise: Exercise
        var setIDs: [UUID]
    }

    @State private var title: String
    @State private var start: Date
    @State private var durationMinutes: Int
    @State private var notes: String
    @State private var exerciseDrafts: [ExerciseDraft]
    @State private var setDrafts: [UUID: SetDraft]

    init(session: WorkoutSession, unitSystem: UnitSystem) {
        self.session = session
        self.unitSystem = unitSystem

        var drafts: [UUID: SetDraft] = [:]
        var groups: [ExerciseDraft] = []
        for log in session.sortedSets {
            guard let ex = log.exercise else { continue }
            drafts[log.id] = SetDraft(
                weightText: Self.weightText(log.weightKg, system: unitSystem),
                repsText: "\(log.reps)",
                type: log.type,
                isNew: false
            )
            if let idx = groups.firstIndex(where: { $0.exercise.id == ex.id }) {
                groups[idx].setIDs.append(log.id)
            } else {
                groups.append(ExerciseDraft(exercise: ex, setIDs: [log.id]))
            }
        }

        let end = session.end ?? session.start
        _title = State(initialValue: session.title)
        _start = State(initialValue: session.start)
        _durationMinutes = State(initialValue: max(1, Int(end.timeIntervalSince(session.start) / 60.0)))
        _notes = State(initialValue: session.notes)
        _exerciseDrafts = State(initialValue: groups)
        _setDrafts = State(initialValue: drafts)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Workout") {
                    TextField("Title", text: $title)
                    DatePicker("Started", selection: $start, in: ...Date.now)
                    Stepper(value: $durationMinutes, in: 1...600, step: 5) {
                        HStack {
                            Text("Duration")
                            Spacer()
                            Text("\(durationMinutes) min")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(1...4)
                }

                ForEach(exerciseDrafts) { group in
                    Section {
                        ForEach(Array(group.setIDs.enumerated()), id: \.element) { idx, setID in
                            setRow(setID: setID, index: idx)
                        }
                        .onDelete { offsets in
                            removeSets(at: offsets, from: group.id)
                        }

                        Button {
                            addSet(to: group.id)
                        } label: {
                            Label("Add Set", systemImage: "plus")
                                .font(.subheadline.weight(.semibold))
                        }
                    } header: {
                        HStack {
                            Text(group.exercise.name)
                            Spacer()
                            Button(role: .destructive) {
                                exerciseDrafts.removeAll { $0.id == group.id }
                            } label: {
                                Image(systemName: "trash")
                            }
                            .accessibilityLabel("Remove \(group.exercise.name)")
                        }
                    } footer: {
                        if group.exercise.bodyweightMode != .standardLoad {
                            Text("Weight is the added or assisted load for this bodyweight exercise.")
                        }
                    }
                }
            }
            .navigationTitle("Edit Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                        dismiss()
                    }
                    .fontWeight(.bold)
                }
            }
        }
    }

    // MARK: - Set Row

    private func setRow(setID: UUID, index: Int) -> some View {
        let draft = setDrafts[setID]
        let type = draft?.type ?? .working
        return HStack(spacing: 10) {
            Menu {
                ForEach(SetType.allCases) { option in
                    Button(option.displayName) {
                        setDrafts[setID]?.type = option
                    }
                }
            } label: {
                Text(type == .working ? "\(index + 1)" : type.badge)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(type == .working ? Color.primary : Color.orange)
                    .frame(width: 34, height: 28)
                    .background(AppleTheme.tertiarySurface, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            }

            Spacer(minLength: 4)

            TextField("0", text: binding(for: setID, \.weightText))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(width: 72)
            Text(unitSystem.weightSymbol)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("×")
                .foregroundStyle(.secondary)

            TextField("0", text: binding(for: setID, \.repsText))
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(width: 44)
            Text("reps")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// Looks drafts up by set ID (not index) so deleting rows never leaves a stale binding behind.
    private func binding(for setID: UUID, _ keyPath: WritableKeyPath<SetDraft, String>) -> Binding<String> {
        Binding(
            get: { setDrafts[setID]?[keyPath: keyPath] ?? "" },
            set: { setDrafts[setID]?[keyPath: keyPath] = $0 }
        )
    }

    // MARK: - Draft Editing

    private func removeSets(at offsets: IndexSet, from exerciseID: UUID) {
        guard let idx = exerciseDrafts.firstIndex(where: { $0.id == exerciseID }) else { return }
        exerciseDrafts[idx].setIDs.remove(atOffsets: offsets)
        if exerciseDrafts[idx].setIDs.isEmpty {
            exerciseDrafts.remove(at: idx)
        }
    }

    private func addSet(to exerciseID: UUID) {
        guard let idx = exerciseDrafts.firstIndex(where: { $0.id == exerciseID }) else { return }
        let last = exerciseDrafts[idx].setIDs.last.flatMap { setDrafts[$0] }
        let newID = UUID()
        setDrafts[newID] = SetDraft(
            weightText: last?.weightText ?? "0",
            repsText: last?.repsText ?? "8",
            type: .working,
            isNew: true
        )
        exerciseDrafts[idx].setIDs.append(newID)
    }

    // MARK: - Save

    private func save() {
        let originalStart = session.start
        let originalEnd = session.end
        let existingByID = Dictionary((session.sets ?? []).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        var touched: [UUID: Exercise] = [:]
        for ex in WorkoutHistoryService.uniqueExercises(in: session) {
            touched[ex.id] = ex
        }

        let keptIDs = Set(exerciseDrafts.flatMap(\.setIDs))
        for log in session.sets ?? [] where !keptIDs.contains(log.id) {
            modelContext.delete(log)
        }

        let shift = start.timeIntervalSince(originalStart)
        var order = 0
        for group in exerciseDrafts {
            var lastTimestamp = start
            for setID in group.setIDs {
                guard let draft = setDrafts[setID] else { continue }
                let weightKg = parsedWeightKg(draft.weightText)
                let reps = parsedReps(draft.repsText)

                if let log = existingByID[setID], !draft.isNew {
                    if log.isUnilateral && (abs(log.weightKg - weightKg) > 0.001 || log.reps != reps) {
                        log.weightKgLeft = weightKg
                        log.weightKgRight = weightKg
                        log.repsLeft = reps
                        log.repsRight = reps
                    }
                    log.weightKg = weightKg
                    log.reps = reps
                    log.type = draft.type
                    log.order = order
                    log.timestamp = log.timestamp.addingTimeInterval(shift)
                    lastTimestamp = log.timestamp
                } else {
                    let log = SetLog(
                        order: order,
                        session: session,
                        exercise: group.exercise,
                        weightKg: weightKg,
                        reps: reps,
                        type: draft.type,
                        isCompleted: true,
                        timestamp: lastTimestamp
                    )
                    modelContext.insert(log)
                }
                order += 1
            }
        }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        session.title = trimmedTitle.isEmpty ? session.title : trimmedTitle
        session.start = start
        session.dayKey = DayKey.from(start)
        session.end = start.addingTimeInterval(TimeInterval(durationMinutes * 60))
        session.notes = notes
        try? modelContext.save()

        StrongWorkoutImportService.rebuildExerciseAnalytics(for: Array(touched.values), context: modelContext)
        try? modelContext.save()
        _ = CoachingCoordinator.evaluate(context: modelContext)

        // Re-write the Apple Health workout when its time window moved.
        if session.start != originalStart || session.end != originalEnd, let oldUUID = session.healthKitWorkoutUUID {
            let context = modelContext
            let edited = session
            Task {
                await HealthKitService.shared.deleteStrengthWorkout(uuid: oldUUID)
                edited.healthKitWorkoutUUID = nil
                await HealthKitService.shared.saveStrengthWorkout(edited)
                try? context.save()
            }
        }
    }

    private func parsedWeightKg(_ text: String) -> Double {
        let normalized = text.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)
        guard let display = Double(normalized), display.isFinite else { return 0 }
        let clamped = min(max(display, 0), 2000)
        return UnitsFormatter.internalKg(fromDisplay: clamped, system: unitSystem)
    }

    private func parsedReps(_ text: String) -> Int {
        guard let reps = Int(text.trimmingCharacters(in: .whitespaces)) else { return 0 }
        return min(max(reps, 0), 999)
    }

    private static func weightText(_ kg: Double, system: UnitSystem) -> String {
        let display = (UnitsFormatter.displayWeight(kg, system: system) * 100).rounded() / 100
        if display == display.rounded() {
            return String(format: "%.0f", display)
        }
        return String(format: "%g", display)
    }
}
