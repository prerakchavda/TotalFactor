import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct TrainHubView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState

    @Query private var profiles: [UserProfile]
    @Query private var programs: [Program]
    @Query private var gymProfiles: [GymProfile]
    @Query(sort: \WorkoutSession.start, order: .reverse) private var sessions: [WorkoutSession]

    @State private var showingPlanGenerator: Bool = false
    @State private var showingProgramBuilder: Bool = false
    @State private var showingGymProfiles: Bool = false
    @State private var showingExerciseLibrary: Bool = false
    @State private var showingFullHistory: Bool = false
    @State private var showingCSVImporter: Bool = false
    @State private var showingProgramImporter: Bool = false
    @State private var importResultMessage: String? = nil

    @State private var previewGuideWorkout: ProgramWorkout? = nil
    @State private var selectedHistorySession: WorkoutSession? = nil

    private var profile: UserProfile {
        profiles.first ?? CoachingCoordinator.fetchOrCreateProfile(context: modelContext)
    }

    private var activeProgram: Program? {
        programs.first(where: \.isActive) ?? programs.first
    }

    private var activeGym: GymProfile? {
        gymProfiles.first(where: \.isDefault) ?? gymProfiles.first
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    gymSelectorStrip

                    if let openSession = sessions.first(where: { !$0.isFinished }) {
                        Button {
                            appState.activeWorkoutSessionID = openSession.id
                            appState.showingActiveWorkoutFullScreen = true
                        } label: {
                            HStack {
                                Image(systemName: "play.circle.fill")
                                    .font(.title2)
                                VStack(alignment: .leading) {
                                    Text("Resume \(openSession.title)")
                                        .font(.headline)
                                    Text("Started \(openSession.start, style: .relative) ago")
                                        .font(.caption)
                                }
                                Spacer()
                                Image(systemName: "arrow.up.right")
                            }
                            .foregroundStyle(.white)
                            .padding(16)
                            .background(Color.green, in: RoundedRectangle(cornerRadius: 16))
                        }
                        .buttonStyle(.plain)
                    }

                    activeProgramCard

                    let volumeEntries: [HypertrophyVolumeEngine.VolumeSetEntry] = sessions.flatMap { s in
                        (s.sets ?? []).compactMap { set in
                            guard let ex = set.exercise else { return nil }
                            return HypertrophyVolumeEngine.VolumeSetEntry(
                                timestamp: s.start,
                                primaryMuscles: ex.primaryMuscles,
                                secondaryMuscles: ex.secondaryMuscles,
                                isCompleted: set.isCompleted,
                                setType: set.type
                            )
                        }
                    }
                    let volumeStatuses = HypertrophyVolumeEngine.evaluateWeeklyVolume(entries: volumeEntries)
                    HypertrophyVolumeCardView(statuses: volumeStatuses)

                    quickToolsGrid

                    recentSessionsCard
                }
                .padding()
                .padding(.bottom, 70)
            }
            .navigationTitle("Train")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button {
                            showingProgramImporter = true
                        } label: {
                            Label("Import Program File...", systemImage: "arrow.down.doc")
                        }
                        if let prog = activeProgram {
                            Button {
                                shareActiveProgram(prog)
                            } label: {
                                Label("Export \(prog.name)", systemImage: "square.and.arrow.up")
                            }
                        }
                        Divider()
                        Button {
                            showingCSVImporter = true
                        } label: {
                            Label("Import Strong Workouts CSV", systemImage: "tablecells.badge.ellipsis")
                        }
                    } label: {
                        Image(systemName: "square.and.arrow.down.on.square")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        startWorkout(from: nil)
                    } label: {
                        Label("Freestyle", systemImage: "plus.circle.fill")
                    }
                }
            }
            .sheet(isPresented: $showingPlanGenerator) {
                PlanGeneratorSheet()
            }
            .sheet(isPresented: $showingProgramBuilder) {
                ProgramBuilderView()
            }
            .sheet(isPresented: $showingGymProfiles) {
                GymProfileEditorView()
            }
            .sheet(isPresented: $showingExerciseLibrary) {
                ExerciseLibraryView()
            }
            .sheet(isPresented: $showingFullHistory) {
                WorkoutHistoryListView(unitSystem: profile.unitSystem)
            }
            .sheet(item: $previewGuideWorkout) { workout in
                WorkoutOverviewGuideSheet(workout: workout, unitSystem: profile.unitSystem) {
                    startWorkout(from: workout)
                }
            }
            .sheet(item: $selectedHistorySession) { session in
                WorkoutSessionDetailSheet(session: session, unitSystem: profile.unitSystem)
            }
            .fileImporter(
                isPresented: $showingCSVImporter,
                allowedContentTypes: [.commaSeparatedText, .plainText],
                allowsMultipleSelection: false
            ) { result in
                handleCSVImport(result)
            }
            .fileImporter(
                isPresented: $showingProgramImporter,
                allowedContentTypes: [.json, .data, .plainText],
                allowsMultipleSelection: false
            ) { result in
                handleProgramImport(result)
            }
            .alert(
                "Workout Import",
                isPresented: Binding(
                    get: { importResultMessage != nil },
                    set: { if !$0 { importResultMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) { importResultMessage = nil }
            } message: {
                Text(importResultMessage ?? "")
            }
            .onChange(of: appState.pendingShortcutWorkoutName) { _, newValue in
                guard let name = newValue else { return }
                appState.pendingShortcutWorkoutName = nil
                let match = activeProgram?.sortedWorkouts.first {
                    $0.name.localizedCaseInsensitiveContains(name)
                } ?? activeProgram?.sortedWorkouts.first
                startWorkout(from: match)
            }
        }
    }

    private var gymSelectorStrip: some View {
        let isPlanetFitness = activeGym?.name.localizedCaseInsensitiveContains("Planet Fitness") == true
        return HStack(spacing: 10) {
            Image(systemName: "building.2.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isPlanetFitness ? .purple : .accentColor)
                .frame(width: 32, height: 32)
                .background((isPlanetFitness ? Color.purple : Color.accentColor).opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Menu {
                    ForEach(gymProfiles) { gym in
                        Button {
                            for g in gymProfiles { g.isDefault = (g.id == gym.id) }
                            try? modelContext.save()
                        } label: {
                            HStack {
                                Text(gym.name)
                                if gym.isDefault { Image(systemName: "checkmark") }
                            }
                        }
                    }
                    Divider()
                    Button("Manage Gym Profiles...") {
                        showingGymProfiles = true
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(activeGym?.name ?? "Planet Fitness")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.primary)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }

                if let gym = activeGym {
                    let maxDB = UnitsFormatter.formatGymLoad(gym.maxDumbbellKg, system: profile.unitSystem)
                    Text(isPlanetFitness ? "Machines • Cables • Smith • DBs to \(maxDB)" : "\(gym.availableEquipment.count) equipment types • DBs to \(maxDB)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text("Active Gym")
                .font(.caption2.weight(.bold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background((isPlanetFitness ? Color.purple : Color.green).opacity(0.15), in: Capsule())
                .foregroundStyle(isPlanetFitness ? .purple : .green)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .appleHealthCard(padding: 12)
    }

    private var activeProgramCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(activeProgram?.name ?? "No Active Program")
                        .font(.headline)
                    if let prog = activeProgram {
                        let subtitle = (prog.scheduleMode == .rollingSplit)
                            ? "Rolling Split (Any Day) • Next: \(prog.nextRollingWorkout?.name ?? "Workout 1")"
                            : "\(prog.daysPerWeek) days / week • Tap any routine for photos & guide"
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button("Edit") {
                    showingProgramBuilder = true
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if let prog = activeProgram {
                WeekScheduleStripView(program: prog, interactive: false)

                ForEach(prog.sortedWorkouts) { workout in
                    let slots = workout.sortedSlots
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Button {
                                previewGuideWorkout = workout
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 6) {
                                        Text(workout.name)
                                            .font(.subheadline.weight(.bold))
                                            .foregroundStyle(.primary)
                                        if prog.scheduleMode == .rollingSplit && workout.id == prog.nextRollingWorkout?.id {
                                            Text("NEXT UP")
                                                .font(.system(size: 9, weight: .heavy))
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Color.green.opacity(0.18), in: Capsule())
                                                .foregroundStyle(.green)
                                        } else if let wd = workout.scheduledWeekday {
                                            Text(shortWeekdayName(wd))
                                                .font(.caption2.weight(.bold))
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Color.accentColor.opacity(0.14), in: Capsule())
                                                .foregroundStyle(Color.accentColor)
                                        }
                                    }
                                    let names = slots.compactMap { $0.exercise?.name }.prefix(3).joined(separator: " • ")
                                    Text(names.isEmpty ? "No exercises yet" : names)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            .buttonStyle(.plain)

                            Spacer()

                            Button {
                                previewGuideWorkout = workout
                            } label: {
                                Label("Guide", systemImage: "photo")
                                    .font(.caption.weight(.semibold))
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)

                            Button {
                                startWorkout(from: workout)
                            } label: {
                                Text("Start")
                                    .font(.caption.weight(.bold))
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }

                        if !slots.isEmpty {
                            Button {
                                previewGuideWorkout = workout
                            } label: {
                                HStack(spacing: 6) {
                                    ForEach(slots.prefix(6)) { slot in
                                        if let ex = slot.exercise {
                                            ExerciseThumbnailView(exercise: ex, size: 38, cornerRadius: 8)
                                        }
                                    }
                                    if slots.count > 6 {
                                        Text("+\(slots.count - 6)")
                                            .font(.caption2.weight(.bold))
                                            .foregroundStyle(.secondary)
                                            .padding(.leading, 2)
                                    }
                                    Spacer()
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(12)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .appleHealthCard(padding: 18)
    }

    private var quickToolsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            toolTile(title: "Exercise Guides", subtitle: "Photos, muscles & cues", icon: "books.vertical.fill", color: .orange) {
                showingExerciseLibrary = true
            }
            toolTile(title: "Programs & Splits", subtitle: "PF Split, U/L, PPL", icon: "calendar.badge.plus", color: .blue) {
                showingProgramBuilder = true
            }
            toolTile(title: "Gym Profiles", subtitle: "Planet Fitness & travel", icon: "dumbbell.fill", color: .purple) {
                showingGymProfiles = true
            }
            toolTile(title: "Plan Generator", subtitle: "Rule-based custom split", icon: "wand.and.stars", color: .teal) {
                showingPlanGenerator = true
            }
        }
    }

    private func toolTile(title: String, subtitle: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(color)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .appleHealthCard(padding: 14)
        }
        .buttonStyle(.plain)
    }

    private var recentSessionsCard: some View {
        let allFinished = sessions.filter(\.isFinished)
        let recent = allFinished.prefix(8)

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Workout History")
                    .font(.headline)
                Spacer()
                if allFinished.count > 0 {
                    Button("See All (\(allFinished.count))") {
                        showingFullHistory = true
                    }
                    .font(.caption.weight(.semibold))
                }
            }

            if recent.isEmpty {
                Text("Complete your first session to unlock personalized rep curves and volume tracking.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(recent)) { s in
                    Button {
                        selectedHistorySession = s
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(s.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Text("\(DayKey.displayTitle(for: s.dayKey)) • \(s.completedSetCount) sets")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            HStack(spacing: 6) {
                                Text(UnitsFormatter.formatWeight(s.totalWorkingVolumeKg, system: profile.unitSystem, decimals: 0))
                                    .font(.subheadline.weight(.bold).monospacedDigit())
                                    .foregroundStyle(.primary)
                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .appleHealthCard(padding: 18)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func shortWeekdayName(_ wd: Int) -> String {
        let names = ["", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        return (1...7).contains(wd) ? names[wd] : ""
    }

    private func handleCSVImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            importResultMessage = "Could not open CSV file: \(error.localizedDescription)"
        case .success(let urls):
            guard let url = urls.first else { return }
            let didAccess = url.startAccessingSecurityScopedResource()
            defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
            guard let content = try? String(contentsOf: url, encoding: .utf8) else {
                importResultMessage = "Unable to read UTF-8 text from \(url.lastPathComponent)."
                return
            }
            let summary = StrongWorkoutImportService.importCSV(
                content: content,
                context: modelContext,
                sourceUnitSystem: profile.unitSystem,
                defaultGym: activeGym
            )
            if summary.sessionsImported > 0 {
                importResultMessage = "Imported \(summary.sessionsImported) new workout sessions (\(summary.setsImported) sets across \(summary.exercisesUpdated) exercises)."
            } else {
                importResultMessage = "All workouts in this CSV are already in your history (0 new sessions added)."
            }
        }
    }

    private func startWorkout(from programWorkout: ProgramWorkout?) {
        let gym = activeGym
        let session = WorkoutSession(
            title: programWorkout?.name ?? "Freestyle Session",
            programWorkout: programWorkout,
            gymProfile: gym,
            start: .now
        )
        modelContext.insert(session)

        if let pw = programWorkout {
            let digest = CoachingCoordinator.evaluate(context: modelContext)
            let allExercises = (try? modelContext.fetch(FetchDescriptor<Exercise>())) ?? []
            let exerciseByID = Dictionary(allExercises.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            let allowedEquip = Set(gym?.availableEquipment ?? Equipment.allCases)

            var order = 0
            for slot in pw.sortedSlots {
                guard let baseEx = slot.exercise else { continue }
                let swapped = ProgramGeneratorEngine.autoSwapIfNeeded(
                    exercise: baseEx.asBlueprint,
                    availableEquipment: allowedEquip,
                    maxDumbbellKg: gym?.maxDumbbellKg ?? 50,
                    pool: allExercises.map(\.asBlueprint)
                )
                let resolvedEx = exerciseByID[swapped.id] ?? baseEx
                let history = (resolvedEx.setLogs ?? [])
                    .filter(\.isCompleted)
                    .map { LoggedSetSample(sessionDate: $0.session?.start ?? $0.timestamp, weightKg: $0.weightKg, reps: $0.reps, rir: $0.rir, setType: $0.type) }

                let inc = gym?.effectiveIncrementKg(for: resolvedEx) ?? resolvedEx.loadIncrementKg
                let suggestion = ProgressionEngine.suggestNextSession(
                    history: history,
                    repRangeLow: slot.repRangeLow,
                    repRangeHigh: slot.repRangeHigh,
                    targetRIR: slot.targetRIR,
                    loadIncrementKg: inc,
                    personalK: resolvedEx.personalRepCurveK,
                    weeklyWeightChangePercentBW: digest.weightSummary.weeklyRatePercentBW,
                    avgProteinLast7d: digest.avgProteinLast7d,
                    proteinFloor: digest.todayTargets.proteinFloor
                )

                for _ in 0..<slot.sets {
                    let setLog = SetLog(
                        order: order,
                        session: session,
                        exercise: resolvedEx,
                        weightKg: suggestion.suggestedWeightKg,
                        reps: suggestion.suggestedReps,
                        rir: slot.targetRIR,
                        type: .working,
                        supersetGroup: slot.supersetGroup,
                        isCompleted: false
                    )
                    modelContext.insert(setLog)
                    order += 1
                }
            }
        }

        try? modelContext.save()
        appState.activeWorkoutSessionID = session.id
        appState.showingActiveWorkoutFullScreen = true
        PhoneWatchSyncService.shared.pushCurrentState(context: modelContext)
    }

    private func handleProgramImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            do {
                let prog = try ProgramImportExportService.importProgram(from: url, into: modelContext)
                for p in programs { p.isActive = (p.id == prog.id) }
                try? modelContext.save()
                _ = CoachingCoordinator.evaluate(context: modelContext)
                importResultMessage = "Successfully imported \"\(prog.name)\" (\(prog.sortedWorkouts.count) workouts) and set it as your active program!"
            } catch {
                importResultMessage = "Failed to import program: \(error.localizedDescription)"
            }
        case .failure(let error):
            importResultMessage = "Could not open file: \(error.localizedDescription)"
        }
    }

    private func shareActiveProgram(_ prog: Program) {
        #if canImport(UIKit)
        do {
            let fileURL = try ProgramImportExportService.exportProgramToFile(program: prog)
            let av = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let root = windowScene.windows.first?.rootViewController {
                root.present(av, animated: true)
            }
        } catch {}
        #endif
    }
}
