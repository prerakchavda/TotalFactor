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
    @Query(sort: \CardioSession.start, order: .reverse) private var cardioSessions: [CardioSession]

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
    @State private var showingCardioLog: Bool = false
    @State private var selectedCardioSession: CardioSession? = nil
    @State private var isSyncingCardio: Bool = false
    @AppStorage("totalfactor.workoutsSubTab") private var subTabRaw: String = "train"

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
            VStack(spacing: 0) {
                SubTabBar(tabs: WorkoutsSubTab.allCases, selection: subTab) { $0.title }

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        switch subTab.wrappedValue {
                        case .train:
                            trainSection
                        case .recovery:
                            recoverySection
                        case .history:
                            historySection
                        case .exercises:
                            ExerciseProgressListView(unitSystem: profile.unitSystem)
                        }
                    }
                    .padding()
                    .padding(.bottom, 16)
                }
            }
            .background(AppleTheme.background)
            .navigationTitle("WORKOUTS")
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
            .sheet(isPresented: $showingCardioLog) {
                CardioLogSheet(unitSystem: profile.unitSystem)
            }
            .sheet(item: $selectedCardioSession) { cardio in
                CardioLogSheet(session: cardio, unitSystem: profile.unitSystem)
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

    // MARK: - Sub-tabs

    private enum WorkoutsSubTab: String, CaseIterable, Identifiable {
        case train
        case recovery
        case history
        case exercises

        var id: String { rawValue }

        var title: String {
            switch self {
            case .train: return "Train"
            case .recovery: return "Recovery"
            case .history: return "History"
            case .exercises: return "Exercises"
            }
        }
    }

    private var subTab: Binding<WorkoutsSubTab> {
        Binding(
            get: { WorkoutsSubTab(rawValue: subTabRaw) ?? .train },
            set: { subTabRaw = $0.rawValue }
        )
    }

    /// Train: gym, resume/start, active program and tools.
    @ViewBuilder
    private var trainSection: some View {
        gymSelectorStrip

        if let openSession = sessions.first(where: { !$0.isFinished }) {
            Button {
                appState.activeWorkoutSessionID = openSession.id
                appState.showingActiveWorkoutFullScreen = true
            } label: {
                HStack {
                    Image(systemName: "play.fill")
                        .font(.title3.weight(.bold))
                    VStack(alignment: .leading) {
                        Text("Resume \(openSession.title)")
                            .font(.headline.weight(.bold))
                        Text("Started \(openSession.start, style: .relative) ago")
                            .font(.caption)
                            .opacity(0.7)
                    }
                    Spacer()
                    Image(systemName: "arrow.up.right")
                }
                .foregroundStyle(AppleTheme.background)
                .padding(16)
                .background(Color.primary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
        }

        MFSectionTitle("Program")

        activeProgramCard

        MFSectionTitle("Tools")

        quickToolsGrid
    }

    /// Recovery: muscle recovery map and weekly set volume.
    @ViewBuilder
    private var recoverySection: some View {
        MFSectionTitle("Muscle Recovery")

        MuscleRecoveryCard(sessions: sessions)

        MFSectionTitle("Weekly Volume")

        HypertrophyVolumeCardView(statuses: weeklyVolumeStatuses)
    }

    private var weeklyVolumeStatuses: [HypertrophyVolumeEngine.MuscleVolumeStatus] {
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
        return HypertrophyVolumeEngine.evaluateWeeklyVolume(entries: volumeEntries)
    }

    /// History: calendar, recent workouts and cardio.
    @ViewBuilder
    private var historySection: some View {
        WorkoutCalendarCard(
            sessions: sessions,
            cardioSessions: cardioSessions,
            onSelect: { session in
                selectedHistorySession = session
            },
            onSelectCardio: { cardio in
                selectedCardioSession = cardio
            }
        )

        recentSessionsCard

        MFSectionTitle("Cardio")

        CardioHistoryCard(
            sessions: cardioSessions,
            unitSystem: profile.unitSystem,
            onLog: { showingCardioLog = true },
            onSelect: { cardio in
                selectedCardioSession = cardio
            },
            onSyncHealth: { syncCardioFromHealth() },
            isSyncing: isSyncingCardio
        )
    }

    private var gymSelectorStrip: some View {
        let isPlanetFitness = activeGym?.name.localizedCaseInsensitiveContains("Planet Fitness") == true
        return HStack(spacing: 10) {
            MFCircleIcon("building.2.fill", size: 34)

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
                .background(AppleTheme.tertiarySurface, in: Capsule())
                .foregroundStyle(.secondary)
        }
        .appleHealthCard(padding: 14)
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
                .buttonStyle(.mfChip)
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
                                                .background(Color.primary, in: Capsule())
                                                .foregroundStyle(AppleTheme.background)
                                        } else if let wd = workout.scheduledWeekday {
                                            Text(shortWeekdayName(wd))
                                                .font(.caption2.weight(.bold))
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(AppleTheme.tertiarySurface, in: Capsule())
                                                .foregroundStyle(.primary)
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
                            .buttonStyle(.mfChip)
                            .controlSize(.small)

                            Button {
                                startWorkout(from: workout)
                            } label: {
                                Text("Start")
                                    .font(.caption.weight(.bold))
                            }
                            .buttonStyle(.mfPrimaryCompact)
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
                    .background(AppleTheme.tertiarySurface.opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
                    .foregroundStyle(.primary)
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

    /// Cardio card → Sync: asks for any missing Health read access (distance), then imports the last 90 days.
    private func syncCardioFromHealth() {
        guard !isSyncingCardio else { return }
        isSyncingCardio = true
        Task { @MainActor in
            let health = HealthKitService.shared
            let granted = await health.requestPermissions()
            if !granted, let err = health.lastAuthError, err.localizedCaseInsensitiveContains("entitlement") {
                isSyncingCardio = false
                importResultMessage = "Direct Apple Health access is blocked on Free Apple ID / SideStore installs.\n\nUse Settings → Apple Health & Cloud → Apple Shortcuts Bridge (or the \"Total Factor Log Cardio Workout\" shortcut) to sync workouts for free."
                return
            }
            let added = await health.importExternalCardioWorkouts(context: modelContext, daysBack: 90)
            isSyncingCardio = false
            importResultMessage = added > 0
                ? "Added \(added) cardio workout\(added == 1 ? "" : "s") from Apple Health."
                : "You're up to date. No new cardio workouts in Apple Health from the last 90 days."
        }
    }

    private func startWorkout(from programWorkout: ProgramWorkout?) {
        // Only one workout can be open: resume it instead of starting a second, orphaned session.
        if let open = WorkoutHistoryService.openSession(context: modelContext) {
            appState.activeWorkoutSessionID = open.id
            appState.showingActiveWorkoutFullScreen = true
            return
        }
        let gym = activeGym
        let session = WorkoutSession(
            title: programWorkout?.name ?? "Freestyle Session",
            programWorkout: programWorkout,
            gymProfile: gym,
            start: .now
        )
        modelContext.insert(session)

        if let pw = programWorkout {
            WorkoutPlannerService.populate(session: session, from: pw, gym: gym, context: modelContext)
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
            ShareSheetHelper.present(activityItems: [fileURL])
        } catch {}
        #endif
    }
}
