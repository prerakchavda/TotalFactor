import SwiftUI
import SwiftData
import Charts

struct ExerciseLibraryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Exercise.name) private var exercises: [Exercise]
    @Query private var profiles: [UserProfile]

    @State private var search: String = ""
    @State private var selectedMuscle: MuscleGroup? = nil
    @State private var showingNewCustom: Bool = false

    private var profile: UserProfile {
        profiles.first ?? CoachingCoordinator.fetchOrCreateProfile(context: modelContext)
    }

    private var filtered: [Exercise] {
        exercises.filter { ex in
            let matchesText = search.isEmpty || ex.name.localizedCaseInsensitiveContains(search)
            let matchesMuscle = selectedMuscle == nil || ex.primaryMuscles.contains(selectedMuscle!)
            return matchesText && matchesMuscle
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        Button("All") { selectedMuscle = nil }
                            .buttonStyle(.bordered)
                            .tint(selectedMuscle == nil ? .accentColor : .secondary)
                        ForEach(MuscleGroup.allCases) { m in
                            Button(m.displayName) { selectedMuscle = m }
                                .buttonStyle(.bordered)
                                .tint(selectedMuscle == m ? .accentColor : .secondary)
                        }
                    }
                    .controlSize(.small)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }

                List(filtered) { ex in
                    let loggedSetCount = (ex.setLogs ?? []).filter(\.isCompleted).count
                    NavigationLink {
                        ExerciseAnalyticsDetailView(exercise: ex, unitSystem: profile.unitSystem)
                    } label: {
                        HStack(spacing: 12) {
                            ExerciseThumbnailView(exercise: ex, size: 48, cornerRadius: 10)

                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Text(ex.name).font(.subheadline.weight(.semibold))
                                    if ex.isCustom {
                                        Text("Custom")
                                            .font(.caption2)
                                            .padding(.horizontal, 5)
                                            .background(Color.blue.opacity(0.15), in: Capsule())
                                    }
                                    if loggedSetCount > 0 {
                                        Text("\(loggedSetCount) sets")
                                            .font(.caption2.weight(.semibold).monospacedDigit())
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 1)
                                            .background(Color.green.opacity(0.14), in: Capsule())
                                            .foregroundStyle(.green)
                                    }
                                }
                                Text("\(ex.equipment.displayName) • \(ex.primaryMuscles.map(\.displayName).joined(separator: ", "))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
                .listStyle(.plain)
            }
            .searchable(text: $search, prompt: "Search exercises")
            .navigationTitle("Exercise Guides & Library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingNewCustom = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingNewCustom) {
                NewCustomExerciseSheet()
            }
        }
    }
}

private struct ExerciseSessionHistoryGroup: Identifiable {
    let id: String
    let date: Date
    let dayKey: String
    let sessionTitle: String
    let sets: [SetLog]
    let workingVolumeKg: Double
    let topE1RMKg: Double
}

private struct ExerciseAnalyticsDetailView: View {
    let exercise: Exercise
    let unitSystem: UnitSystem

    @State private var showAllHistorySessions: Bool = false

    private var completedAllTypes: [SetLog] {
        (exercise.setLogs ?? []).filter(\.isCompleted)
    }

    private var sessionHistoryGroups: [ExerciseSessionHistoryGroup] {
        let grouped = Dictionary(grouping: completedAllTypes) { setLog -> String in
            if let sid = setLog.session?.id {
                return sid.uuidString
            }
            return DayKey.from(setLog.timestamp)
        }

        return grouped.map { key, logs in
            let orderedSets = logs.sorted { lhs, rhs in
                if lhs.order != rhs.order { return lhs.order < rhs.order }
                return lhs.timestamp < rhs.timestamp
            }
            let sessionRef = orderedSets.first?.session
            let sessionDate = sessionRef?.start ?? orderedSets.first?.timestamp ?? .now
            let dKey = sessionRef?.dayKey ?? DayKey.from(sessionDate)
            let title = sessionRef?.title ?? "Logged Session"

            var volKg = 0.0
            var bestE1RM = 0.0
            for s in orderedSets where s.type.countsTowardWorkingStats {
                volKg += max(0, s.weightKg) * Double(max(0, s.reps))
                let est = ProgressionEngine.e1RM(
                    weight: s.weightKg,
                    reps: s.reps,
                    rir: s.rir,
                    k: exercise.personalRepCurveK
                )
                if est > bestE1RM {
                    bestE1RM = est
                }
            }

            return ExerciseSessionHistoryGroup(
                id: key,
                date: sessionDate,
                dayKey: dKey,
                sessionTitle: title,
                sets: orderedSets,
                workingVolumeKg: volKg,
                topE1RMKg: bestE1RM
            )
        }
        .sorted { $0.date > $1.date }
    }

    var body: some View {
        let completedWorking = completedAllTypes
            .filter { $0.type.countsTowardWorkingStats }
            .sorted { ($0.session?.start ?? $0.timestamp) < ($1.session?.start ?? $1.timestamp) }
        let samples = completedWorking.map {
            LoggedSetSample(
                sessionDate: $0.session?.start ?? $0.timestamp,
                weightKg: $0.weightKg,
                reps: $0.reps,
                rir: $0.rir,
                setType: $0.type
            )
        }
        let sessionSeries = ProgressionEngine.sessionTopE1RMs(samples: samples, k: exercise.personalRepCurveK)
        let historyGroups = sessionHistoryGroups
        let visibleGroups = showAllHistorySessions ? historyGroups : Array(historyGroups.prefix(15))

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // Visual Demonstration Photos, Muscle Map, Planet Fitness Setup & Step-by-Step Guide
                ExerciseGuideContentView(exercise: exercise)

                // Swift Charts e1RM Trend (§9 & §11)
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Estimated 1RM Progression")
                            .font(.headline)
                        Spacer()
                        Text(String(format: "Curve k = %.1f", exercise.personalRepCurveK))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    if sessionSeries.isEmpty {
                        Text("Log working sets for \(exercise.name) to plot your effort-adjusted e1RM curve.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Chart {
                            ForEach(sessionSeries, id: \.dayKey) { item in
                                if let dt = DayKey.date(from: item.dayKey) {
                                    LineMark(
                                        x: .value("Date", dt),
                                        y: .value("e1RM", UnitsFormatter.displayWeight(item.topE1RM, system: unitSystem))
                                    )
                                    .interpolationMethod(.catmullRom)
                                    PointMark(
                                        x: .value("Date", dt),
                                        y: .value("e1RM", UnitsFormatter.displayWeight(item.topE1RM, system: unitSystem))
                                    )
                                }
                            }
                        }
                        .frame(height: 200)
                    }
                }
                .padding(14)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                // Personal Records
                VStack(alignment: .leading, spacing: 8) {
                    Text("Personal Records")
                        .font(.headline)
                    let prs = (exercise.personalRecords ?? []).sorted { $0.date > $1.date }
                    if prs.isEmpty {
                        Text("PRs appear automatically as you finish workouts.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(prs.prefix(10)) { pr in
                            HStack {
                                Text(pr.type.displayName)
                                    .font(.subheadline)
                                Spacer()
                                Text(formattedPRValue(pr))
                                    .font(.subheadline.weight(.bold).monospacedDigit())
                                Text(pr.dayKey)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding(14)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                // Chronological Per-Exercise Session & Set History (§9 & §11)
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Session & Set History")
                            .font(.headline)
                        Spacer()
                        if !historyGroups.isEmpty {
                            Text("\(historyGroups.count) \(historyGroups.count == 1 ? "session" : "sessions")")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }

                    if historyGroups.isEmpty {
                        Text("Completed sets for \(exercise.name) will appear here in chronological order with load, reps, RIR, and session e1RM.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(visibleGroups) { group in
                            sessionHistoryCard(group)
                        }

                        if historyGroups.count > 15 {
                            Button {
                                showAllHistorySessions.toggle()
                            } label: {
                                Text(showAllHistorySessions ? "Show Recent 15 Sessions" : "Show All \(historyGroups.count) Sessions")
                                    .font(.caption.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 6)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
                .padding(14)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(exercise.name)
    }

    private func sessionHistoryCard(_ group: ExerciseSessionHistoryGroup) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(group.sessionTitle)
                        .font(.subheadline.weight(.semibold))
                    Text(group.date.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    if group.topE1RMKg > 0 {
                        Text("Top e1RM \(UnitsFormatter.formatWeight(group.topE1RMKg, system: unitSystem))")
                            .font(.caption.weight(.bold).monospacedDigit())
                            .foregroundStyle(Color.accentColor)
                    }
                    if group.workingVolumeKg > 0 {
                        Text("Vol \(UnitsFormatter.formatWeight(group.workingVolumeKg, system: unitSystem, decimals: 0))")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Divider()

            ForEach(Array(group.sets.enumerated()), id: \.element.id) { idx, setLog in
                HStack(spacing: 8) {
                    Text("\(idx + 1)")
                        .font(.caption2.weight(.bold).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 18, alignment: .leading)

                    Text(setLog.type.badge)
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(setBadgeColor(setLog.type).opacity(0.15), in: Capsule())
                        .foregroundStyle(setBadgeColor(setLog.type))

                    Text("\(UnitsFormatter.formatGymLoad(setLog.weightKg, system: unitSystem)) × \(setLog.reps) reps")
                        .font(.caption.weight(.semibold).monospacedDigit())

                    if setLog.type != .warmup {
                        Text("@ \(setLog.rir) RIR")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if setLog.type.countsTowardWorkingStats {
                        let setE1RM = ProgressionEngine.e1RM(
                            weight: setLog.weightKg,
                            reps: setLog.reps,
                            rir: setLog.rir,
                            k: exercise.personalRepCurveK
                        )
                        if setE1RM > 0 {
                            Text("e1RM \(UnitsFormatter.formatGymLoad(setE1RM, system: unitSystem))")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func setBadgeColor(_ type: SetType) -> Color {
        switch type {
        case .warmup: return .orange
        case .working: return .blue
        case .drop: return .purple
        case .failure: return .red
        case .partial: return .teal
        case .myorep: return .indigo
        }
    }

    private func formattedPRValue(_ pr: PersonalRecord) -> String {
        switch pr.type {
        case .mostRepsAtWeight:
            let reps = Int(pr.value.rounded())
            let load = UnitsFormatter.formatGymLoad(pr.secondaryValue, system: unitSystem)
            return "\(reps) reps @ \(load)"
        case .bestSessionVolume:
            return UnitsFormatter.formatWeight(pr.value, system: unitSystem, decimals: 0)
        case .e1RM, .heaviestWeight:
            return UnitsFormatter.formatWeight(pr.value, system: unitSystem)
        }
    }
}

struct NewCustomExerciseSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var name: String = ""
    @State private var primaryMuscle: MuscleGroup = .chest
    @State private var equipment: Equipment = .dumbbell
    @State private var pattern: MovementPattern = .isolation
    @State private var incrementKg: Double = 2.5
    @State private var cues: String = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Exercise Name", text: $name)
                Picker("Primary Muscle", selection: $primaryMuscle) {
                    ForEach(MuscleGroup.allCases) { m in Text(m.displayName).tag(m) }
                }
                Picker("Equipment", selection: $equipment) {
                    ForEach(Equipment.allCases) { e in Text(e.displayName).tag(e) }
                }
                Picker("Movement Pattern", selection: $pattern) {
                    ForEach(MovementPattern.allCases) { p in Text(p.displayName).tag(p) }
                }
                HStack {
                    Text("Load Increment (kg)")
                    Spacer()
                    TextField("2.5", value: $incrementKg, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
                TextField("Coaching Cues (optional)", text: $cues, axis: .vertical)
            }
            .navigationTitle("New Custom Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let ex = Exercise(
                            name: name,
                            primaryMuscles: [primaryMuscle],
                            equipment: equipment,
                            movementPattern: pattern,
                            isCustom: true,
                            instructions: cues,
                            loadIncrementKg: max(0.5, incrementKg)
                        )
                        modelContext.insert(ex)
                        try? modelContext.save()
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
