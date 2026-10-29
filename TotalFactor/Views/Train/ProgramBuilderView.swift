import SwiftUI
import SwiftData

struct ProgramBuilderView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Program.createdAt, order: .reverse) private var programs: [Program]
    @Query(sort: \Exercise.name) private var exercises: [Exercise]

    @State private var newProgramName: String = ""
    @State private var showingNewAlert: Bool = false
    @State private var showingFileImporter: Bool = false
    @State private var importAlertMessage: String? = nil

    var body: some View {
        NavigationStack {
            List {
                Section("Quick-Start Templates (§10)") {
                    ForEach(BuiltInProgramTemplate.allCases) { tmpl in
                        Button {
                            instantiateTemplate(tmpl)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(tmpl.rawValue)
                                        .font(.subheadline.weight(.semibold))
                                    Text("Creates & activates ready-to-run workouts")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "plus.circle.fill")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                Section("Your Programs") {
                    ForEach(programs) { prog in
                        NavigationLink {
                            ProgramDetailEditorView(program: prog)
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(prog.name)
                                            .font(.subheadline.weight(.semibold))
                                        Text("\(prog.sortedWorkouts.count) workouts • \(prog.daysPerWeek)d/wk")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if prog.isActive {
                                        Text("Active")
                                            .font(.caption2.weight(.bold))
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 3)
                                            .background(Color.green.opacity(0.16), in: Capsule())
                                            .foregroundStyle(.green)
                                    } else {
                                        Button("Activate") {
                                            activate(prog)
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.mini)
                                    }
                                }

                                WeekScheduleStripView(program: prog, interactive: false)
                            }
                            .padding(.vertical, 3)
                        }
                    }
                    .onDelete { offsets in
                        for idx in offsets { modelContext.delete(programs[idx]) }
                        try? modelContext.save()
                    }
                }
            }
            .navigationTitle("Programs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            newProgramName = "Custom Split"
                            showingNewAlert = true
                        } label: {
                            Label("New Blank Program", systemImage: "plus")
                        }

                        Divider()

                        Button {
                            showingFileImporter = true
                        } label: {
                            Label("Import Program File...", systemImage: "square.and.arrow.down")
                        }

                        Button {
                            importFromClipboard()
                        } label: {
                            Label("Import from Clipboard", systemImage: "doc.on.clipboard")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .fileImporter(
                isPresented: $showingFileImporter,
                allowedContentTypes: [.json, .data, .plainText],
                allowsMultipleSelection: false
            ) { result in
                handleFileImport(result)
            }
            .alert(
                "Program Import",
                isPresented: Binding(
                    get: { importAlertMessage != nil },
                    set: { if !$0 { importAlertMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) { importAlertMessage = nil }
            } message: {
                Text(importAlertMessage ?? "")
            }
            .alert("New Blank Program", isPresented: $showingNewAlert) {
                TextField("Program Name", text: $newProgramName)
                Button("Create") {
                    let p = Program(name: newProgramName.isEmpty ? "Custom Split" : newProgramName, daysPerWeek: 4, isActive: false)
                    modelContext.insert(p)
                    let w = ProgramWorkout(name: "Day 1", order: 0, scheduledWeekday: 2)
                    w.program = p
                    modelContext.insert(w)
                    activate(p)
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    private func activate(_ target: Program) {
        for p in programs { p.isActive = (p.id == target.id) }
        try? modelContext.save()
        _ = CoachingCoordinator.evaluate(context: modelContext)
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            do {
                let imported = try ProgramImportExportService.importProgram(from: url, into: modelContext)
                activate(imported)
                importAlertMessage = "Successfully imported \"\(imported.name)\" with \(imported.sortedWorkouts.count) workouts!"
            } catch {
                importAlertMessage = "Import failed: \(error.localizedDescription)"
            }
        case .failure(let err):
            importAlertMessage = "Could not open file: \(err.localizedDescription)"
        }
    }

    private func importFromClipboard() {
        #if canImport(UIKit)
        guard let text = UIPasteboard.general.string, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            importAlertMessage = "Clipboard is empty. Copy a program JSON first."
            return
        }
        do {
            let imported = try ProgramImportExportService.importProgram(from: text, into: modelContext)
            activate(imported)
            importAlertMessage = "Successfully imported \"\(imported.name)\" from clipboard!"
        } catch {
            importAlertMessage = "Could not parse program from clipboard: \(error.localizedDescription)"
        }
        #endif
    }

    private func instantiateTemplate(_ template: BuiltInProgramTemplate) {
        let exerciseByID = Dictionary(exercises.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let bp = ProgramGeneratorEngine.builtInTemplate(template, exercisePool: exercises.map(\.asBlueprint))

        let program = Program(name: bp.name, daysPerWeek: bp.daysPerWeek, isActive: true)
        for p in programs { p.isActive = false }
        modelContext.insert(program)

        for (wIdx, wb) in bp.workouts.enumerated() {
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
                    progressionRule: sb.progressionRule,
                    supersetGroup: sb.supersetGroup
                )
                slot.workout = workout
                modelContext.insert(slot)
            }
        }
        try? modelContext.save()
        _ = CoachingCoordinator.evaluate(context: modelContext)
    }
}

/// Visual Mon–Sun 7-day schedule strip (`§10 & §12`):
/// Displays scheduled training days vs rest days across Monday → Sunday, and when `interactive == true`,
/// lets the lifter tap any day pill to assign or clear a workout day (updating Training-Day Carb Cycling live).
struct WeekScheduleStripView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var program: Program
    let interactive: Bool

    private struct WeekdayColumn: Identifiable {
        let weekday: Int // Calendar weekday: 1=Sun, 2=Mon ... 7=Sat
        let shortTitle: String
        var id: Int { weekday }
    }

    private let columns: [WeekdayColumn] = [
        WeekdayColumn(weekday: 2, shortTitle: "Mon"),
        WeekdayColumn(weekday: 3, shortTitle: "Tue"),
        WeekdayColumn(weekday: 4, shortTitle: "Wed"),
        WeekdayColumn(weekday: 5, shortTitle: "Thu"),
        WeekdayColumn(weekday: 6, shortTitle: "Fri"),
        WeekdayColumn(weekday: 7, shortTitle: "Sat"),
        WeekdayColumn(weekday: 1, shortTitle: "Sun")
    ]

    var body: some View {
        let todayWeekday = DayKey.weekday(for: DayKey.today)
        let sortedWorkouts = program.sortedWorkouts

        HStack(spacing: 5) {
            ForEach(columns) { col in
                let assigned = sortedWorkouts.first { $0.scheduledWeekday == col.weekday }
                let isLiftDay = (assigned != nil) || (sortedWorkouts.allSatisfy { $0.scheduledWeekday == nil } && program.isTrainingWeekday(col.weekday))
                let isToday = (col.weekday == todayWeekday)

                if interactive {
                    Menu {
                        Section("\(col.shortTitle) Assignment") {
                            Button {
                                assign(workout: nil, toWeekday: col.weekday)
                            } label: {
                                if assigned == nil {
                                    Label("Rest Day", systemImage: "checkmark")
                                } else {
                                    Label("Rest Day", systemImage: "moon.zzz")
                                }
                            }

                            ForEach(sortedWorkouts) { w in
                                Button {
                                    assign(workout: w, toWeekday: col.weekday)
                                } label: {
                                    if assigned?.id == w.id {
                                        Label(w.name, systemImage: "checkmark")
                                    } else {
                                        Label(w.name, systemImage: "dumbbell")
                                    }
                                }
                            }
                        }
                    } label: {
                        dayCell(
                            dayTitle: col.shortTitle,
                            workoutBadge: assigned.map { compactCode(for: $0.name) } ?? (isLiftDay ? "Lift" : "Rest"),
                            isLiftDay: isLiftDay,
                            isToday: isToday
                        )
                    }
                    .buttonStyle(.plain)
                } else {
                    dayCell(
                        dayTitle: col.shortTitle,
                        workoutBadge: assigned.map { compactCode(for: $0.name) } ?? (isLiftDay ? "Lift" : "Rest"),
                        isLiftDay: isLiftDay,
                        isToday: isToday
                    )
                }
            }
        }
    }

    private func dayCell(dayTitle: String, workoutBadge: String, isLiftDay: Bool, isToday: Bool) -> some View {
        VStack(spacing: 3) {
            Text(dayTitle)
                .font(.system(size: 10, weight: isToday ? .heavy : .semibold))
                .foregroundStyle(isToday ? Color.accentColor : .secondary)

            Text(workoutBadge)
                .font(.system(size: 10, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .padding(.horizontal, 3)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity)
                .background(
                    isLiftDay ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.09),
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                )
                .foregroundStyle(isLiftDay ? Color.accentColor : .secondary)
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(isToday ? Color.accentColor.opacity(0.7) : Color.clear, lineWidth: 1.2)
                )
        }
        .frame(maxWidth: .infinity)
    }

    private func compactCode(for name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Lift" }
        let parts = trimmed.split(whereSeparator: \.isWhitespace).map(String.init)
        if parts.count == 1 {
            return String(parts[0].prefix(4))
        }
        let first = String(parts[0].prefix(2))
        let second = String(parts[1].prefix(2))
        return "\(first)\(second)"
    }

    private func assign(workout: ProgramWorkout?, toWeekday weekday: Int) {
        // Clear any existing workout already assigned to this weekday
        for existing in program.sortedWorkouts where existing.scheduledWeekday == weekday {
            existing.scheduledWeekday = nil
        }
        if let workout {
            workout.scheduledWeekday = weekday
        }
        let scheduledCount = Set(program.sortedWorkouts.compactMap(\.scheduledWeekday)).count
        if scheduledCount > 0 {
            program.daysPerWeek = scheduledCount
        }
        try? modelContext.save()
        _ = CoachingCoordinator.evaluate(context: modelContext)
    }
}

private struct ProgramDetailEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var program: Program
    @Query(sort: \Exercise.name) private var exercises: [Exercise]

    @State private var addingSlotToWorkout: ProgramWorkout? = nil

    var body: some View {
        List {
            Section {
                WeekScheduleStripView(program: program, interactive: true)
                    .padding(.vertical, 4)
            } header: {
                Text("Mon–Sun Schedule Strip")
            } footer: {
                Text("Tap any day pill above to assign a workout or rest day. Active program training days automatically drive Training-Day Carb Cycling.")
            }

            Section("Program Settings") {
                TextField("Program Name", text: $program.name)
                Stepper("Days / Week: \(program.daysPerWeek)", value: $program.daysPerWeek, in: 1...7)
                    .onChange(of: program.daysPerWeek) { _, _ in
                        try? modelContext.save()
                        _ = CoachingCoordinator.evaluate(context: modelContext)
                    }

                Picker("Schedule Mode", selection: Binding(
                    get: { program.scheduleMode },
                    set: {
                        program.scheduleMode = $0
                        try? modelContext.save()
                        _ = CoachingCoordinator.evaluate(context: modelContext)
                    }
                )) {
                    ForEach(ProgramScheduleMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }

                if program.scheduleMode == .rollingSplit {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .foregroundStyle(Color.accentColor)
                        Text("Rolling Split: Work out whenever you want! Workouts cycle in sequence (1 → 2 → 3 → 4) whenever you hit the gym.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            ForEach(program.sortedWorkouts) { workout in
                Section {
                    HStack {
                        TextField("Workout Name", text: Binding(
                            get: { workout.name },
                            set: { workout.name = $0; try? modelContext.save() }
                        ))
                        .font(.headline)

                        Spacer()

                        Picker("Day", selection: Binding(
                            get: { workout.scheduledWeekday ?? 0 },
                            set: {
                                workout.scheduledWeekday = ($0 == 0 ? nil : $0)
                                try? modelContext.save()
                                _ = CoachingCoordinator.evaluate(context: modelContext)
                            }
                        )) {
                            Text("Flex").tag(0)
                            Text("Sun").tag(1)
                            Text("Mon").tag(2)
                            Text("Tue").tag(3)
                            Text("Wed").tag(4)
                            Text("Thu").tag(5)
                            Text("Fri").tag(6)
                            Text("Sat").tag(7)
                        }
                        .labelsHidden()
                    }

                    ForEach(workout.sortedSlots) { slot in
                        NavigationLink {
                            SlotEditorView(slot: slot)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(slot.exercise?.name ?? "Exercise")
                                        .font(.subheadline.weight(.medium))
                                    if let sg = slot.supersetGroup {
                                        Text("SS #\(sg)")
                                            .font(.caption2.weight(.bold))
                                            .foregroundStyle(.purple)
                                    }
                                }
                                Text("\(slot.sets) sets × \(slot.repRangeLow)–\(slot.repRangeHigh) reps @ \(slot.targetRIR) RIR • \(slot.restSeconds)s rest")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onMove { from, to in
                        var current = workout.sortedSlots
                        current.move(fromOffsets: from, toOffset: to)
                        for (i, s) in current.enumerated() { s.order = i }
                        try? modelContext.save()
                    }
                    .onDelete { offsets in
                        let current = workout.sortedSlots
                        for idx in offsets { modelContext.delete(current[idx]) }
                        try? modelContext.save()
                    }

                    Button {
                        addingSlotToWorkout = workout
                    } label: {
                        Label("Add Exercise Slot", systemImage: "plus.circle")
                            .font(.caption.weight(.semibold))
                    }
                }
            }

            Section {
                Button {
                    let nextOrder = program.sortedWorkouts.count
                    let w = ProgramWorkout(name: "Day \(nextOrder + 1)", order: nextOrder)
                    w.program = program
                    modelContext.insert(w)
                    try? modelContext.save()
                } label: {
                    Label("Add Workout Day", systemImage: "calendar.badge.plus")
                }
            }

            Section("Export & Share") {
                Button {
                    shareProgramFile()
                } label: {
                    Label("Export & Share Program (.totalfactorprogram)", systemImage: "square.and.arrow.up")
                }

                Button {
                    copyProgramJSON()
                } label: {
                    Label("Copy Program JSON to Clipboard", systemImage: "doc.on.doc")
                }
            }
        }
        .navigationTitle(program.name)
        .toolbar { EditButton() }
        .sheet(item: $addingSlotToWorkout) { targetWorkout in
            NavigationStack {
                List(exercises) { ex in
                    Button {
                        let nextOrder = targetWorkout.sortedSlots.count
                        let slot = ExerciseSlot(order: nextOrder, exercise: ex)
                        slot.workout = targetWorkout
                        modelContext.insert(slot)
                        try? modelContext.save()
                        addingSlotToWorkout = nil
                    } label: {
                        Text(ex.name)
                    }
                    .buttonStyle(.plain)
                }
                .navigationTitle("Add Exercise")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { addingSlotToWorkout = nil }
                    }
                }
            }
        }
    }

    private func shareProgramFile() {
        #if canImport(UIKit)
        do {
            let fileURL = try ProgramImportExportService.exportProgramToFile(program: program)
            let av = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let root = windowScene.windows.first?.rootViewController {
                root.present(av, animated: true)
            }
        } catch {}
        #endif
    }

    private func copyProgramJSON() {
        #if canImport(UIKit)
        if let json = try? ProgramImportExportService.exportProgramToJSON(program: program) {
            UIPasteboard.general.string = json
        }
        #endif
    }
}

private struct SlotEditorView: View {
    @Bindable var slot: ExerciseSlot

    var body: some View {
        Form {
            Section(slot.exercise?.name ?? "Slot") {
                Stepper("Working Sets: \(slot.sets)", value: $slot.sets, in: 1...10)
                Stepper("Rep Floor: \(slot.repRangeLow)", value: $slot.repRangeLow, in: 1...30)
                Stepper("Rep Ceiling: \(max(slot.repRangeLow, slot.repRangeHigh))", value: $slot.repRangeHigh, in: slot.repRangeLow...35)
                Stepper("Target RIR: \(slot.targetRIR)", value: $slot.targetRIR, in: 0...5)
                Stepper("Rest Timer: \(slot.restSeconds)s", value: $slot.restSeconds, in: 30...360, step: 15)
                Picker("Progression", selection: $slot.progressionRule) {
                    ForEach(ProgressionRule.allCases) { r in
                        Text(r.displayName).tag(r)
                    }
                }
                Stepper(
                    "Superset Group: \(slot.supersetGroup.map(String.init) ?? "None")",
                    value: Binding(
                        get: { slot.supersetGroup ?? 0 },
                        set: { slot.supersetGroup = ($0 <= 0 ? nil : $0) }
                    ),
                    in: 0...6
                )
            }
        }
        .navigationTitle("Slot Prescription")
    }
}
