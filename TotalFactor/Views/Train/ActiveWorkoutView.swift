import SwiftUI
import SwiftData
#if canImport(UIKit)
import UIKit
#endif

/// Spec MacroFactor Workouts Active Screen (v1.5 Revamp):
/// - Horizontal Exercise Switcher Carousel with thumbnails, progress counters, and `+` add exercise
/// - Clean MacroFactor Set Grid: `SET` | `PREVIOUS ↔` | `LB` | `REPS` (with mini colored RIR badges) | `▢` Checkbox
/// - Focused input boxes with crisp high-contrast active borders
/// - Docked Custom Gym Keypad with colored RIR pill strip (`0` to `6+`), 10-key numbers with first-digit overwrite, and black `✓` commit button
/// - MacroFactor Workout Complete Celebration sheet with front-and-back anatomical humanoid heatmap in royal blue (`#2F7CF6`), PR trophy cards, and "Update Workout Plan" switch
/// - Preserves ALL superior Total Factor features:
///   - Progression Wand (🪄) with diagnostic overload reasoning and dynamic rep range expansion
///   - Live Heart Rate Corner Badge (`❤️ 142 BPM`) streaming from Apple Watch
///   - Rest Timer Live Activity & Dynamic Island + Apple Watch haptics
///   - Pre-workout fasted fuel warning
///   - Bilateral & Unilateral (L/R) independent logging
///   - Biomechanical Equipment Swap with ranked movement substitutions
///   - Machine setup notes persistence
///   - Olympic barbell & Smith plate calculator
public struct ActiveWorkoutView: View {
    public enum WorkoutViewLayoutMode: String, CaseIterable, Identifiable {
        case carousel = "Carousel (Focused)"
        case list = "All Exercises (List)"
        public var id: String { rawValue }
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState
    @Environment(HealthKitService.self) private var healthService

    @Bindable var session: WorkoutSession

    @Query private var profiles: [UserProfile]
    @Query(sort: \Exercise.name) private var allExercises: [Exercise]

    @State private var layoutMode: WorkoutViewLayoutMode = .carousel
    @State private var selectedBlockIndex: Int = 0

    // Keypad & Focus State
    @State private var focusedSetID: UUID? = nil
    @State private var focusedField: MacroFactorGymKeypad.ActiveField = .weight
    @State private var isFirstDigit: Bool = true

    // Sheets & Overlays
    @State private var showingAddExercise: Bool = false
    @State private var showingNewCustomExercise: Bool = false
    @State private var exerciseSearch: String = ""
    @State private var plateCalcWeightKg: Double? = nil
    @State private var guideExercise: Exercise? = nil
    @State private var highlightedSetID: UUID? = nil
    @State private var livePRBannerText: String? = nil

    // MacroFactor Workouts interactive state
    @State private var activeWandDiagnostic: ProgressionEngine.ProgressionWandDiagnostic? = nil
    @State private var swappingBlock: ExerciseBlock? = nil
    @State private var setupNotesExercise: Exercise? = nil
    @State private var showingDiscardConfirmation: Bool = false

    // Celebration Sheet State
    @State private var showingCelebrationSheet: Bool = false
    @State private var sessionPRsForCelebration: [WorkoutCompleteCelebrationView.DetectedPRItem] = []
    @State private var routineDiffsForCelebration: [WorkoutChangeLogSheet.ChangeLogDiffItem] = []

    private var profile: UserProfile {
        profiles.first ?? CoachingCoordinator.fetchOrCreateProfile(context: modelContext)
    }

    public struct ExerciseBlock: Identifiable {
        public var id: UUID { exercise.id }
        public var exercise: Exercise
        public var sets: [SetLog]
        public var supersetGroup: Int?
    }

    private var groupedBlocks: [ExerciseBlock] {
        var blocks: [ExerciseBlock] = []
        for s in session.sortedSets {
            guard let ex = s.exercise else { continue }
            if let idx = blocks.firstIndex(where: { $0.exercise.id == ex.id }) {
                blocks[idx].sets.append(s)
            } else {
                blocks.append(ExerciseBlock(exercise: ex, sets: [s], supersetGroup: s.supersetGroup))
            }
        }
        return blocks
    }

    private var activeBlock: ExerciseBlock? {
        let blocks = groupedBlocks
        guard !blocks.isEmpty else { return nil }
        if selectedBlockIndex >= blocks.count {
            return blocks.last
        }
        return blocks[max(0, selectedBlockIndex)]
    }

    public var body: some View {
        let digest = CoachingCoordinator.cachedOrComputeDigest(context: modelContext)

        NavigationStack {
            VStack(spacing: 0) {
                // Top telemetry & alerts (Isolated subviews for 120Hz smooth UI)
                ActiveWatchHeartRateBanner()
                ActiveRestTimerBanner()

                if let prText = livePRBannerText {
                    livePRBanner(prText)
                }

                if let snackNudge = digest.preWorkoutSnackNudge {
                    fastedSnackBanner(snackNudge)
                }

                if digest.isProteinGateActive {
                    proteinGateBanner
                }

                // MacroFactor Top Horizontal Exercise Carousel
                exerciseCarouselStrip

                // Main Workout Content: Focused Exercise vs Full List
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 16) {
                            if layoutMode == .carousel {
                                if let block = activeBlock {
                                    exerciseCardContent(block: block, digest: digest, scrollProxy: proxy)
                                } else {
                                    emptyWorkoutPlaceholder
                                }
                            } else {
                                // Full vertical list of all exercises
                                ForEach(groupedBlocks) { block in
                                    exerciseCardContent(block: block, digest: digest, scrollProxy: proxy)
                                }
                                Button {
                                    showingAddExercise = true
                                } label: {
                                    Label("Add Exercise to Session", systemImage: "plus.circle.fill")
                                        .font(.subheadline.weight(.semibold))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                }
                                .buttonStyle(.bordered)
                            }

                            TextField("Session notes (grip, energy, cues...)", text: $session.notes, axis: .vertical)
                                .textFieldStyle(.roundedBorder)
                                .font(.caption)
                                .padding(.horizontal, 4)
                        }
                        .padding(.horizontal, 14)
                        .padding(.top, 10)
                        .padding(.bottom, focusedSetID != nil ? 240 : 50)
                    }
                }

                // Docked MacroFactor Custom Gym Keypad
                if let targetID = focusedSetID, let targetSet = session.sortedSets.first(where: { $0.id == targetID }) {
                    dockedKeypad(for: targetSet)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.22), value: focusedSetID != nil)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 8) {
                        Menu {
                            Picker("View Mode", selection: $layoutMode) {
                                ForEach(WorkoutViewLayoutMode.allCases) { mode in
                                    Text(mode.rawValue).tag(mode)
                                }
                            }
                            Divider()
                            Button("Add Exercise") { showingAddExercise = true }
                            Button {
                                togglePauseWorkout()
                            } label: {
                                Label(session.isPaused ? "Resume Workout" : "Pause Workout", systemImage: session.isPaused ? "play.fill" : "pause.fill")
                            }
                            Divider()
                            Button(role: .destructive) {
                                showingDiscardConfirmation = true
                            } label: {
                                Label("Discard Workout", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "line.3.horizontal")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(.primary)
                        }

                        // Elapsed Workout Duration Clock / Paused Badge
                        Button {
                            if session.isPaused {
                                togglePauseWorkout()
                            }
                        } label: {
                            ActiveElapsedTimerView(session: session)
                        }
                        .buttonStyle(.plain)
                    }
                }

                ToolbarItem(placement: .principal) {
                    ActiveRestTimerPill()
                }

                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 8) {
                        ActiveCornerHeartRateBadge()
                        Button("Finish") {
                            finishWorkout()
                        }
                        .font(.subheadline.weight(.heavy))
                        .foregroundStyle(Color(red: 0.18, green: 0.48, blue: 0.96))
                    }
                }
            }
            .sheet(isPresented: $showingAddExercise) {
                addExerciseSheet(digest: digest)
            }
            .sheet(item: $guideExercise) { targetExercise in
                ExerciseGuideSheet(exercise: targetExercise)
            }
            .sheet(
                isPresented: Binding(
                    get: { plateCalcWeightKg != nil },
                    set: { if !$0 { plateCalcWeightKg = nil } }
                )
            ) {
                PlateCalculatorSheet(
                    targetWeightKg: plateCalcWeightKg ?? 60.0,
                    gymProfile: session.gymProfile,
                    unitSystem: profile.unitSystem
                )
                .presentationDetents([.medium])
            }
            .sheet(item: $activeWandDiagnostic) { diag in
                ProgressionWandSheet(diagnostic: diag, unitSystem: profile.unitSystem)
                    .presentationDetents([.medium, .large])
            }
            .sheet(item: $swappingBlock) { block in
                ExerciseSwapSheet(
                    currentExercise: block.exercise,
                    allExercises: allExercises,
                    gymProfile: session.gymProfile,
                    onSelect: { substitute in
                        swapExercise(in: block, with: substitute, digest: digest)
                    }
                )
            }
            .sheet(item: $setupNotesExercise) { ex in
                MachineSetupNotesSheet(exercise: ex)
            }
            .sheet(isPresented: $showingCelebrationSheet) {
                WorkoutCompleteCelebrationView(
                    session: session,
                    unitSystem: profile.unitSystem,
                    prList: sessionPRsForCelebration,
                    diffItems: routineDiffsForCelebration,
                    onCommitToRoutine: {
                        if let pw = session.programWorkout {
                            commitChangesToRoutine(pw: pw)
                        }
                    },
                    onFinishSession: {
                        performFinishWorkout()
                    }
                )
            }
            .onAppear {
                healthService.startLiveHeartRateObserver()
                autoFocusFirstIncompleteSet()
            }
            .onDisappear {
                healthService.stopLiveHeartRateObserver()
            }
            .alert("Discard Workout?", isPresented: $showingDiscardConfirmation) {
                Button("Discard Workout", role: .destructive) {
                    discardWorkout()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Are you sure you want to discard this workout? All logged sets and progress will be permanently deleted.")
            }
        }
    }

    // MARK: - MacroFactor Horizontal Exercise Switcher Carousel

    private var exerciseCarouselStrip: some View {
        ScrollViewReader { carouselProxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(groupedBlocks.enumerated()), id: \.element.id) { index, block in
                        let isSelected = (layoutMode == .carousel && selectedBlockIndex == index)
                        let completedCount = block.sets.filter(\.isCompleted).count
                        let totalCount = block.sets.count
                        let isAllDone = totalCount > 0 && completedCount == totalCount

                        Button {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                selectedBlockIndex = index
                                layoutMode = .carousel
                            }
                            autoFocusFirstIncompleteSet(in: block)
                        } label: {
                            VStack(spacing: 4) {
                                ZStack(alignment: .topTrailing) {
                                    ExerciseThumbnailView(exercise: block.exercise, size: 44, cornerRadius: 10)

                                    if isAllDone {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 14, weight: .bold))
                                            .foregroundStyle(.green)
                                            .background(Circle().fill(Color(.systemBackground)))
                                            .offset(x: 4, y: -4)
                                    }
                                }

                                Text(block.exercise.name)
                                    .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                                    .foregroundStyle(isSelected ? .primary : .secondary)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.center)
                                    .frame(width: 72, height: 26)

                                Text("\(completedCount)/\(totalCount)")
                                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                                    .foregroundStyle(isAllDone ? .green : .secondary)
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 6)
                            .background(
                                isSelected ? Color.primary.opacity(0.12) : Color.clear,
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(isSelected ? Color.primary : Color.clear, lineWidth: 1.5)
                            )
                        }
                        .buttonStyle(.plain)
                        .id(block.id)
                    }

                    // Trailing '+' Tile to Add Exercise
                    Button {
                        showingAddExercise = true
                    } label: {
                        VStack(spacing: 4) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color(.secondarySystemGroupedBackground))
                                    .frame(width: 44, height: 44)
                                Image(systemName: "plus")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundStyle(Color(red: 0.18, green: 0.48, blue: 0.96))
                            }
                            Text("Add")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                            Text("+")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.clear)
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 6)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }
            .background(Color(.systemGroupedBackground))
            .onChange(of: selectedBlockIndex) { _, newIndex in
                let blocks = groupedBlocks
                if newIndex < blocks.count {
                    withAnimation {
                        carouselProxy.scrollTo(blocks[newIndex].id, anchor: .center)
                    }
                }
            }
        }
    }

    // MARK: - Exercise Card & Set Grid

    private func exerciseCardContent(
        block: ExerciseBlock,
        digest: CoachingDashboardDigest,
        scrollProxy: ScrollViewProxy
    ) -> some View {
        let ex = block.exercise

        return VStack(alignment: .leading, spacing: 12) {
            // Header with Exercise Title, Round info, and MacroFactor Action Pills
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ex.name)
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)

                        if let sg = block.supersetGroup {
                            Text("Superset \(sg) • Round 1 of \(block.sets.count)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.purple)
                        } else {
                            Text("Set \(block.sets.filter(\.isCompleted).count + 1) of \(block.sets.count)")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    // Quick Guide Thumbnail
                    Button {
                        guideExercise = ex
                    } label: {
                        ExerciseThumbnailView(exercise: ex, size: 36, cornerRadius: 8)
                    }
                    .buttonStyle(.plain)
                }

                // Persistent Machine Setup Notes Chip
                if !ex.machineSetupNotes.isEmpty {
                    Button {
                        setupNotesExercise = ex
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "wrench.and.screwdriver.fill")
                                .font(.system(size: 9))
                            Text(ex.machineSetupNotes)
                                .font(.system(size: 11, weight: .medium))
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.12), in: Capsule())
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                // MacroFactor Action Pills Bar (Horizontal Scroll preventing text wrapping)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        // 🪄 Progression Wand
                        Button {
                            computeAndOpenWand(for: block, digest: digest)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "wand.and.stars")
                                    .font(.system(size: 11, weight: .bold))
                                Text("Wand")
                                    .font(.system(size: 11, weight: .bold))
                            }
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.blue.opacity(0.15), in: Capsule())
                            .foregroundStyle(Color(red: 0.18, green: 0.48, blue: 0.96))
                        }
                        .buttonStyle(.plain)

                        // ⏱ Warm Up
                        Button {
                            insertAutoWarmups(for: block)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "flame.fill")
                                    .font(.system(size: 10))
                                Text("Warm Up")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .background(Color(.tertiarySystemGroupedBackground), in: Capsule())
                            .foregroundStyle(.primary)
                        }
                        .buttonStyle(.plain)

                        // 🔀 Swap
                        Button {
                            swappingBlock = block
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.system(size: 10))
                                Text("Swap")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .background(Color(.tertiarySystemGroupedBackground), in: Capsule())
                            .foregroundStyle(.primary)
                        }
                        .buttonStyle(.plain)

                        // 📊 Info
                        Button {
                            guideExercise = ex
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "chart.bar.doc.horizontal")
                                    .font(.system(size: 10))
                                Text("Info")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .background(Color(.tertiarySystemGroupedBackground), in: Capsule())
                            .foregroundStyle(.primary)
                        }
                        .buttonStyle(.plain)

                        // 📝 Note
                        Button {
                            setupNotesExercise = ex
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "plus")
                                    .font(.system(size: 10))
                                Text("Note")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .background(Color(.tertiarySystemGroupedBackground), in: Capsule())
                            .foregroundStyle(.primary)
                        }
                        .buttonStyle(.plain)

                        // Menu for Unilateral / Plates / Delete
                        Menu {
                            Button {
                                toggleUnilateral(for: block)
                            } label: {
                                Label(block.sets.first?.isUnilateral == true ? "Switch to Bilateral" : "Switch to Unilateral (L / R)", systemImage: "arrow.left.and.right")
                            }
                            if ex.equipment.usesBarbellPlates {
                                Button {
                                    plateCalcWeightKg = block.sets.first(where: { $0.type == .working })?.weightKg ?? 60.0
                                } label: {
                                    Label("Plate Calculator", systemImage: "circle.grid.cross")
                                }
                            }
                            Divider()
                            Button(role: .destructive) {
                                for s in block.sets { modelContext.delete(s) }
                                try? modelContext.save()
                                PhoneWatchSyncService.shared.pushCurrentState(context: modelContext)
                            } label: {
                                Label("Delete Exercise", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(Color(.tertiarySystemGroupedBackground), in: Capsule())
                        }
                    }
                }
            }

            // MacroFactor Set Grid Table
            VStack(spacing: 6) {
                // Table Headers
                HStack(spacing: 8) {
                    Text("Set").frame(width: 34, alignment: .center)
                    Text("Previous ↔").frame(maxWidth: .infinity, alignment: .leading)
                    Text(profile.unitSystem.weightSymbol.uppercased()).frame(width: 74, alignment: .center)
                    Text("Reps").frame(width: 74, alignment: .center)
                    Text("").frame(width: 32, alignment: .center)
                }
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

                // Set Rows
                ForEach(Array(block.sets.enumerated()), id: \.element.id) { idx, setLog in
                    let isFocused = focusedSetID == setLog.id

                    macroFactorSetRow(
                        setLog: setLog,
                        index: idx,
                        isFocused: isFocused,
                        bodyweightMode: ex.bodyweightMode,
                        onSelectField: { field in
                            focusedSetID = setLog.id
                            focusedField = field
                            isFirstDigit = true
                        },
                        onToggleCompleted: {
                            let restSec = effectiveRestSeconds(for: setLog, exercise: ex)
                            toggleSetCompleted(setLog, in: block, restSeconds: restSec, scrollProxy: scrollProxy)
                        }
                    )
                }

                // Add Set Button
                HStack {
                    Button {
                        addSet(to: block)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                                .font(.system(size: 12, weight: .bold))
                            Text("Set")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundStyle(Color(red: 0.18, green: 0.48, blue: 0.96))
                        .padding(.vertical, 6)
                        .padding(.horizontal, 8)
                    }
                    Spacer()
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // MARK: - MacroFactor Set Row

    private func macroFactorSetRow(
        setLog: SetLog,
        index: Int,
        isFocused: Bool,
        bodyweightMode: BodyweightMode,
        onSelectField: @escaping (MacroFactorGymKeypad.ActiveField) -> Void,
        onToggleCompleted: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 8) {
            // 1. Set Badge Menu (1, 2, 3, W, D, F, P, M)
            Menu {
                ForEach(SetType.allCases) { st in
                    Button(st.displayName) {
                        setLog.type = st
                        try? modelContext.save()
                        PhoneWatchSyncService.shared.pushCurrentState(context: modelContext)
                    }
                }
                Divider()
                Button(role: .destructive) {
                    modelContext.delete(setLog)
                    try? modelContext.save()
                    PhoneWatchSyncService.shared.pushCurrentState(context: modelContext)
                } label: {
                    Label("Delete Set", systemImage: "trash")
                }
            } label: {
                Text(setLog.type == .working ? "\(index + 1)" : setLog.type.badge)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .frame(width: 34, height: 34)
                    .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .foregroundStyle(.primary)
            }

            // 2. Previous performance
            Text(previousPerformanceText(for: setLog, index: index))
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)

            // 3. Weight Input Box (with Active Focus Outline)
            if setLog.isUnilateral {
                unilateralBoxes(setLog: setLog, onSelectField: onSelectField)
            } else {
                Button {
                    onSelectField(.weight)
                } label: {
                    Text(formatLoadDisplay(setLog.weightKg, bodyweightMode: bodyweightMode))
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .frame(width: 74, height: 38)
                        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(isFocused && focusedField == .weight ? Color.primary : Color.clear, lineWidth: 2)
                        )
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)

                // 4. Reps Input Box with Mini Colored RIR Badge (MacroFactor Signature!)
                Button {
                    onSelectField(.reps)
                } label: {
                    ZStack(alignment: .bottomTrailing) {
                        Text("\(setLog.reps)")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .frame(width: 74, height: 38)
                            .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(isFocused && focusedField == .reps ? Color.primary : Color.clear, lineWidth: 2)
                            )
                            .foregroundStyle(.primary)

                        // Mini Colored RIR Circle Badge
                        ZStack {
                            Circle()
                                .fill(MacroFactorGymKeypad.rirColor(setLog.rir))
                                .frame(width: 15, height: 15)
                            Text(setLog.rir == 6 ? "6+" : "\(setLog.rir)")
                                .font(.system(size: 8, weight: .heavy, design: .rounded))
                                .foregroundStyle(.white)
                        }
                        .offset(x: -3, y: -3)
                    }
                }
                .buttonStyle(.plain)
            }

            // 5. Completion Checkbox (MacroFactor Square Style)
            Button {
                onToggleCompleted()
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(setLog.isCompleted ? Color.primary : Color(.tertiarySystemGroupedBackground))
                        .frame(width: 28, height: 28)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(setLog.isCompleted ? Color.clear : Color.secondary.opacity(0.4), lineWidth: 1.5)
                        )

                    if setLog.isCompleted {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color(.systemBackground))
                    }
                }
                .frame(width: 32, height: 38)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func unilateralBoxes(
        setLog: SetLog,
        onSelectField: @escaping (MacroFactorGymKeypad.ActiveField) -> Void
    ) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Button { onSelectField(.weightLeft) } label: {
                    Text("L:\(Int(UnitsFormatter.displayWeight(setLog.weightKgLeft ?? setLog.weightKg, system: profile.unitSystem)))")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .frame(width: 74, height: 26)
                        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 6))
                }
                Button { onSelectField(.repsLeft) } label: {
                    Text("\(setLog.repsLeft ?? setLog.reps)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .frame(width: 74, height: 26)
                        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 6))
                }
            }
            HStack(spacing: 4) {
                Button { onSelectField(.weightRight) } label: {
                    Text("R:\(Int(UnitsFormatter.displayWeight(setLog.weightKgRight ?? setLog.weightKg, system: profile.unitSystem)))")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .frame(width: 74, height: 26)
                        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 6))
                }
                Button { onSelectField(.repsRight) } label: {
                    Text("\(setLog.repsRight ?? setLog.reps)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .frame(width: 74, height: 26)
                        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 6))
                }
            }
        }
    }

    // MARK: - Docked Custom Gym Keypad Integration

    private func dockedKeypad(for targetSet: SetLog) -> some View {
        MacroFactorGymKeypad(
            activeField: focusedField,
            currentRIR: targetSet.rir,
            setType: targetSet.type,
            onDigit: { digit in
                handleKeypadDigit(digit, on: targetSet)
            },
            onBackspace: {
                handleKeypadBackspace(on: targetSet)
            },
            onSetRIR: { newRIR in
                targetSet.rir = newRIR
                try? modelContext.save()
                PhoneWatchSyncService.shared.pushCurrentState(context: modelContext)
            },
            onCycleSetType: {
                targetSet.type = nextSetType(targetSet.type)
                try? modelContext.save()
                PhoneWatchSyncService.shared.pushCurrentState(context: modelContext)
            },
            onOpenPlatesOrNotes: {
                if let ex = targetSet.exercise, ex.equipment.usesBarbellPlates {
                    plateCalcWeightKg = targetSet.weightKg
                } else if let ex = targetSet.exercise {
                    setupNotesExercise = ex
                }
            },
            onDismissKeypad: {
                withAnimation { focusedSetID = nil }
            },
            onCommitSet: {
                commitFocusedSet(targetSet)
            }
        )
    }

    private func handleKeypadDigit(_ digit: String, on targetSet: SetLog) {
        if focusedField == .weight || focusedField == .weightLeft || focusedField == .weightRight {
            let currentKg = (focusedField == .weightLeft ? targetSet.weightKgLeft : (focusedField == .weightRight ? targetSet.weightKgRight : targetSet.weightKg)) ?? targetSet.weightKg
            let currentDisplay = UnitsFormatter.displayWeight(currentKg, system: profile.unitSystem)

            var str = isFirstDigit ? "" : (currentDisplay > 0 ? "\(currentDisplay)".replacingOccurrences(of: ".0", with: "") : "")
            if digit == "." && str.contains(".") { return }
            str += digit
            if str == "." { str = "0." }

            if let val = Double(str) {
                let internalKg = UnitsFormatter.internalKg(fromDisplay: val, system: profile.unitSystem)
                if focusedField == .weightLeft {
                    targetSet.weightKgLeft = internalKg
                } else if focusedField == .weightRight {
                    targetSet.weightKgRight = internalKg
                } else {
                    targetSet.weightKg = internalKg
                }
                isFirstDigit = false
                try? modelContext.save()
            }
        } else {
            // Reps
            let currentReps = (focusedField == .repsLeft ? targetSet.repsLeft : (focusedField == .repsRight ? targetSet.repsRight : targetSet.reps)) ?? targetSet.reps
            var str = isFirstDigit ? "" : "\(currentReps)"
            str += digit
            if let val = Int(str), val <= 99 {
                if focusedField == .repsLeft {
                    targetSet.repsLeft = val
                } else if focusedField == .repsRight {
                    targetSet.repsRight = val
                } else {
                    targetSet.reps = val
                }
                isFirstDigit = false
                try? modelContext.save()
            }
        }
    }

    private func handleKeypadBackspace(on targetSet: SetLog) {
        if focusedField == .weight || focusedField == .weightLeft || focusedField == .weightRight {
            let currentKg = (focusedField == .weightLeft ? targetSet.weightKgLeft : (focusedField == .weightRight ? targetSet.weightKgRight : targetSet.weightKg)) ?? targetSet.weightKg
            let currentDisplay = "\(UnitsFormatter.displayWeight(currentKg, system: profile.unitSystem))".replacingOccurrences(of: ".0", with: "")
            let newStr = String(currentDisplay.dropLast())
            let val = Double(newStr) ?? 0.0
            let internalKg = UnitsFormatter.internalKg(fromDisplay: val, system: profile.unitSystem)
            if focusedField == .weightLeft { targetSet.weightKgLeft = internalKg }
            else if focusedField == .weightRight { targetSet.weightKgRight = internalKg }
            else { targetSet.weightKg = internalKg }
        } else {
            let currentReps = (focusedField == .repsLeft ? targetSet.repsLeft : (focusedField == .repsRight ? targetSet.repsRight : targetSet.reps)) ?? targetSet.reps
            let newStr = String("\(currentReps)".dropLast())
            let val = Int(newStr) ?? 0
            if focusedField == .repsLeft { targetSet.repsLeft = val }
            else if focusedField == .repsRight { targetSet.repsRight = val }
            else { targetSet.reps = val }
        }
        try? modelContext.save()
    }

    private func effectiveRestSeconds(for setLog: SetLog, exercise: Exercise) -> Int {
        let slot = session.programWorkout?.sortedSlots.first { $0.exercise?.id == exercise.id }
        let configured = slot?.restSeconds ?? 120
        return setLog.type == .warmup ? min(60, configured) : configured
    }

    private func commitFocusedSet(_ targetSet: SetLog) {
        guard let currentBlock = groupedBlocks.first(where: { $0.sets.contains(where: { $0.id == targetSet.id }) }) else { return }

        // 1. Mark completed
        targetSet.isCompleted = true
        targetSet.timestamp = .now
        targetSet.restTakenSeconds = RestTimerService.shared.consumeElapsedRestSeconds()
        try? modelContext.save()
        checkLiveSetPR(for: targetSet, exercise: currentBlock.exercise)

        // 2. Start Rest Timer
        let restSec = effectiveRestSeconds(for: targetSet, exercise: currentBlock.exercise)
        RestTimerService.shared.start(
            seconds: restSec,
            workoutName: session.title,
            exerciseName: currentBlock.exercise.name,
            setNumber: targetSet.order + 1,
            nextSetSummary: ""
        )

        // 3. Advance to next uncompleted set in current block
        if let nextSet = currentBlock.sets.first(where: { !$0.isCompleted }) {
            focusedSetID = nextSet.id
            focusedField = .weight
            isFirstDigit = true
        } else {
            // All sets in this exercise complete! Advance carousel to next exercise block
            let blocks = groupedBlocks
            if let curIdx = blocks.firstIndex(where: { $0.id == currentBlock.id }), curIdx + 1 < blocks.count {
                selectedBlockIndex = curIdx + 1
                let nextBlock = blocks[curIdx + 1]
                if let nextSet = nextBlock.sets.first(where: { !$0.isCompleted }) {
                    focusedSetID = nextSet.id
                    focusedField = .weight
                    isFirstDigit = true
                }
            } else {
                // Entire workout completed!
                withAnimation { focusedSetID = nil }
            }
        }
    }

    private func autoFocusFirstIncompleteSet(in block: ExerciseBlock? = nil) {
        let targetBlock = block ?? activeBlock
        if let set = targetBlock?.sets.first(where: { !$0.isCompleted }) {
            focusedSetID = set.id
            focusedField = .weight
            isFirstDigit = true
        }
    }

    // MARK: - Workout Lifecycle & Controls

    private func togglePauseWorkout() {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
        if session.isPaused {
            session.resumeSession()
        } else {
            session.pauseSession()
        }
        try? modelContext.save()
    }

    private func discardWorkout() {
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        #endif
        let timer = RestTimerService.shared
        timer.lastRestStartedAt = nil
        timer.skip()
        PhoneWatchSyncService.shared.liveWatchHeartRateBPM = nil
        PhoneWatchSyncService.shared.liveWatchActiveCaloriesDisplayOnly = 0
        HealthKitService.shared.stopLiveHeartRateObserver()

        for s in session.sortedSets {
            modelContext.delete(s)
        }
        modelContext.delete(session)
        try? modelContext.save()

        appState.activeWorkoutSessionID = nil
        appState.showingActiveWorkoutFullScreen = false
        dismiss()
    }

    private func finishWorkout() {
        let diffs = evaluateRoutineDiff()
        let prs = collectSessionPRs()
        sessionPRsForCelebration = prs
        routineDiffsForCelebration = diffs
        showingCelebrationSheet = true
    }

    private func performFinishWorkout() {
        for s in session.sortedSets where !s.isCompleted {
            modelContext.delete(s)
        }
        session.end = .now
        PhoneWatchSyncService.shared.liveWatchHeartRateBPM = nil
        PhoneWatchSyncService.shared.liveWatchActiveCaloriesDisplayOnly = 0
        HealthKitService.shared.stopLiveHeartRateObserver()
        let timer = RestTimerService.shared
        timer.lastRestStartedAt = nil
        timer.skip()

        let exercisesInSession = Dictionary(
            grouping: session.sortedSets.compactMap(\.exercise),
            by: \.id
        ).compactMap(\.value.first)
        for ex in exercisesInSession {
            updatePersonalCurveAndPRs(for: ex)
        }

        if let pw = session.programWorkout, let prog = pw.program {
            prog.lastCompletedWorkoutOrder = pw.order
        }

        try? modelContext.save()
        _ = CoachingCoordinator.evaluate(context: modelContext)
        Task {
            await healthService.saveStrengthWorkout(session)
        }
        appState.activeWorkoutSessionID = nil
        appState.showingActiveWorkoutFullScreen = false
        dismiss()
    }

    private func collectSessionPRs() -> [WorkoutCompleteCelebrationView.DetectedPRItem] {
        var items: [WorkoutCompleteCelebrationView.DetectedPRItem] = []
        let exercisesInSession = Dictionary(
            grouping: session.sortedSets.compactMap(\.exercise),
            by: \.id
        ).compactMap(\.value.first)

        for ex in exercisesInSession {
            let allCompleted = (ex.setLogs ?? []).filter { $0.isCompleted && $0.type.countsTowardWorkingStats }
            let priorSamples = allCompleted
                .filter { $0.session?.id != session.id }
                .map { LoggedSetSample(sessionDate: $0.session?.start ?? $0.timestamp, weightKg: $0.weightKg, reps: $0.reps, rir: $0.rir, setType: $0.type) }
            let sessionSamples = session.sortedSets
                .filter { $0.exercise?.id == ex.id && $0.isCompleted && $0.type.countsTowardWorkingStats }
                .map { LoggedSetSample(sessionDate: $0.timestamp, weightKg: $0.weightKg, reps: $0.reps, rir: $0.rir, setType: $0.type) }
            guard !sessionSamples.isEmpty else { continue }

            let detected = ProgressionEngine.detectSessionPRs(
                priorSets: priorSamples,
                sessionSets: sessionSamples,
                k: ex.personalRepCurveK
            )
            for pr in detected {
                items.append(
                    .init(
                        exerciseName: ex.name,
                        type: pr.type,
                        value: pr.value,
                        secondaryValue: pr.secondaryValue
                    )
                )
            }
        }
        return items
    }

    private func checkLiveSetPR(for setLog: SetLog, exercise: Exercise) {
        guard setLog.type.countsTowardWorkingStats else { return }
        let priorLogs = (exercise.setLogs ?? []).filter {
            $0.isCompleted && $0.type.countsTowardWorkingStats && $0.id != setLog.id
        }
        guard priorLogs.contains(where: { $0.session?.id != session.id }) else { return }

        let priorSamples = priorLogs.map {
            LoggedSetSample(sessionDate: $0.session?.start ?? $0.timestamp, weightKg: $0.weightKg, reps: $0.reps, rir: $0.rir, setType: $0.type)
        }
        let currentSample = LoggedSetSample(
            sessionDate: setLog.timestamp,
            weightKg: setLog.weightKg,
            reps: setLog.reps,
            rir: setLog.rir,
            setType: setLog.type
        )
        let livePRs = ProgressionEngine.detectSessionPRs(
            priorSets: priorSamples,
            sessionSets: [currentSample],
            k: exercise.personalRepCurveK
        )
        guard !livePRs.isEmpty else { return }

        if livePRs.contains(where: { $0.type == .heaviestWeight }) {
            livePRBannerText = "New Load PR: \(UnitsFormatter.formatGymLoad(setLog.weightKg, system: profile.unitSystem)) × \(setLog.reps) on \(exercise.name)!"
        } else if livePRs.contains(where: { $0.type == .mostRepsAtWeight }) {
            livePRBannerText = "New Rep PR: \(setLog.reps) reps @ \(UnitsFormatter.formatGymLoad(setLog.weightKg, system: profile.unitSystem)) on \(exercise.name)!"
        } else if let e1rmPR = livePRs.first(where: { $0.type == .e1RM }) {
            livePRBannerText = "New Est. 1RM PR: \(UnitsFormatter.formatGymLoad(e1rmPR.value, system: profile.unitSystem)) on \(exercise.name)!"
        }
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }

    private func updatePersonalCurveAndPRs(for ex: Exercise) {
        let allCompleted = (ex.setLogs ?? []).filter { $0.isCompleted && $0.type.countsTowardWorkingStats }
        let samples = allCompleted.map {
            LoggedSetSample(sessionDate: $0.session?.start ?? $0.timestamp, weightKg: $0.weightKg, reps: $0.reps, rir: $0.rir, setType: $0.type)
        }
        ex.personalRepCurveK = ProgressionEngine.fitPersonalRepCurveK(samples: samples, priorK: ex.personalRepCurveK)

        let priorSamples = allCompleted
            .filter { $0.session?.id != session.id }
            .map { LoggedSetSample(sessionDate: $0.session?.start ?? $0.timestamp, weightKg: $0.weightKg, reps: $0.reps, rir: $0.rir, setType: $0.type) }

        let sessionSamples = session.sortedSets
            .filter { $0.exercise?.id == ex.id && $0.isCompleted && $0.type.countsTowardWorkingStats }
            .map { LoggedSetSample(sessionDate: $0.timestamp, weightKg: $0.weightKg, reps: $0.reps, rir: $0.rir, setType: $0.type) }
        guard !sessionSamples.isEmpty else { return }

        let detectedPRs = ProgressionEngine.detectSessionPRs(
            priorSets: priorSamples,
            sessionSets: sessionSamples,
            k: ex.personalRepCurveK
        )
        let existingPRs = ex.personalRecords ?? []

        for pr in detectedPRs {
            let alreadyRecorded = existingPRs.contains {
                $0.type == pr.type && $0.value >= pr.value
            }
            if !alreadyRecorded {
                modelContext.insert(
                    PersonalRecord(
                        exercise: ex,
                        type: pr.type,
                        value: pr.value,
                        secondaryValue: pr.secondaryValue,
                        date: .now
                    )
                )
            }
        }
    }

    // MARK: - Actions & Helpers

    private func toggleSetCompleted(
        _ setLog: SetLog,
        in block: ExerciseBlock,
        restSeconds: Int,
        scrollProxy: ScrollViewProxy
    ) {
        let timer = RestTimerService.shared
        setLog.isCompleted.toggle()
        setLog.timestamp = .now
        if setLog.isCompleted {
            setLog.restTakenSeconds = timer.consumeElapsedRestSeconds()
        } else {
            setLog.restTakenSeconds = 0
        }
        try? modelContext.save()

        guard setLog.isCompleted else {
            PhoneWatchSyncService.shared.pushCurrentState(context: modelContext)
            return
        }

        checkLiveSetPR(for: setLog, exercise: block.exercise)

        // Superset auto-alternation
        var nextSummary = ""
        if let sg = block.supersetGroup {
            let partnerNext = session.sortedSets.first {
                !$0.isCompleted && $0.supersetGroup == sg && $0.exercise?.id != block.exercise.id
            }
            if let partner = partnerNext {
                highlightedSetID = partner.id
                nextSummary = "Superset next: \(partner.exercise?.name ?? "Next Exercise")"
                withAnimation { scrollProxy.scrollTo(partner.id, anchor: .center) }
            }
        }

        let effectiveRest = setLog.type == .warmup ? min(60, restSeconds) : restSeconds
        timer.start(
            seconds: effectiveRest,
            workoutName: session.title,
            exerciseName: block.exercise.name,
            setNumber: setLog.order + 1,
            nextSetSummary: nextSummary
        )
    }

    private func insertAutoWarmups(for block: ExerciseBlock) {
        let workingWeight = block.sets.first(where: { $0.type == .working })?.weightKg ?? 60.0
        let barKg = session.gymProfile?.barWeightKg ?? 20.0
        let inc = session.gymProfile?.effectiveIncrementKg(for: block.exercise) ?? block.exercise.loadIncrementKg
        let warmups = ProgressionEngine.generateWarmupSets(workingWeightKg: workingWeight, barWeightKg: barKg, loadIncrementKg: inc)

        let insertOrder = block.sets.first?.order ?? 0
        for s in session.sortedSets where s.order >= insertOrder {
            s.order += warmups.count
        }
        for (offset, wu) in warmups.enumerated() {
            let ws = SetLog(
                order: insertOrder + offset,
                session: session,
                exercise: block.exercise,
                weightKg: wu.weightKg,
                reps: wu.reps,
                rir: 4,
                type: .warmup,
                isCompleted: false
            )
            modelContext.insert(ws)
        }
        try? modelContext.save()
        PhoneWatchSyncService.shared.pushCurrentState(context: modelContext)
    }

    private func addSet(to block: ExerciseBlock) {
        let last = block.sets.last
        let nextOrder = (session.sortedSets.map(\.order).max() ?? -1) + 1
        let newSet = SetLog(
            order: nextOrder,
            session: session,
            exercise: block.exercise,
            weightKg: last?.weightKg ?? 40.0,
            reps: last?.reps ?? 8,
            rir: last?.rir ?? 2,
            type: .working,
            supersetGroup: block.supersetGroup,
            isCompleted: false
        )
        modelContext.insert(newSet)
        try? modelContext.save()
        PhoneWatchSyncService.shared.pushCurrentState(context: modelContext)
    }

    private func appendExerciseToSession(_ ex: Exercise, digest: CoachingDashboardDigest) {
        let nextOrder = (session.sortedSets.map(\.order).max() ?? -1) + 1
        for i in 0..<3 {
            let s = SetLog(
                order: nextOrder + i,
                session: session,
                exercise: ex,
                weightKg: 40.0,
                reps: 8,
                rir: 2,
                type: .working,
                isCompleted: false
            )
            modelContext.insert(s)
        }
        try? modelContext.save()
        PhoneWatchSyncService.shared.pushCurrentState(context: modelContext)
        selectedBlockIndex = max(0, groupedBlocks.count - 1)
    }

    private func swapExercise(in block: ExerciseBlock, with newExercise: Exercise, digest: CoachingDashboardDigest) {
        for s in block.sets {
            s.exercise = newExercise
        }
        try? modelContext.save()
        PhoneWatchSyncService.shared.pushCurrentState(context: modelContext)
    }

    private func toggleUnilateral(for block: ExerciseBlock) {
        let isUnilateral = block.sets.first?.isUnilateral == true
        let target = !isUnilateral
        for s in block.sets {
            s.isUnilateral = target
            if target {
                s.weightKgLeft = s.weightKg
                s.repsLeft = s.reps
                s.weightKgRight = s.weightKg
                s.repsRight = s.reps
            }
        }
        try? modelContext.save()
    }

    private func computeAndOpenWand(for block: ExerciseBlock, digest: CoachingDashboardDigest) {
        let ex = block.exercise
        let pastLogs = (ex.setLogs ?? []).filter { $0.isCompleted && $0.session?.id != session.id }
        let samples = pastLogs.map {
            LoggedSetSample(sessionDate: $0.session?.start ?? $0.timestamp, weightKg: $0.weightKg, reps: $0.reps, rir: $0.rir, setType: $0.type)
        }
        let inc = session.gymProfile?.effectiveIncrementKg(for: ex) ?? ex.loadIncrementKg
        let suggestion = ProgressionEngine.suggestNextSession(
            history: samples,
            repRangeLow: 6,
            repRangeHigh: 10,
            targetRIR: 2,
            loadIncrementKg: inc,
            personalK: ex.personalRepCurveK,
            weeklyWeightChangePercentBW: digest.weightSummary.weeklyRatePercentBW,
            avgProteinLast7d: digest.avgProteinLast7d,
            proteinFloor: digest.todayTargets.proteinFloor
        )
        let diag = ProgressionEngine.evaluateProgressionWand(
            exerciseName: ex.name,
            suggestion: suggestion,
            repRangeLow: 6,
            repRangeHigh: 10,
            loadIncrementKg: inc,
            lastWorkingWeightKg: block.sets.first(where: { $0.type == .working })?.weightKg
        )
        activeWandDiagnostic = diag
    }

    private func evaluateRoutineDiff() -> [WorkoutChangeLogSheet.ChangeLogDiffItem] {
        guard let pw = session.programWorkout else { return [] }
        var diffs: [WorkoutChangeLogSheet.ChangeLogDiffItem] = []
        let routineSlots = pw.sortedSlots
        let sessionBlocks = groupedBlocks
        let routineExerciseIDs = Set(routineSlots.compactMap { $0.exercise?.id })

        for block in sessionBlocks where !routineExerciseIDs.contains(block.exercise.id) {
            diffs.append(.init(kind: .addedExercise, title: "Added \(block.exercise.name)", detail: "\(block.sets.count) sets logged"))
        }

        for slot in routineSlots {
            guard let ex = slot.exercise else { continue }
            if let block = sessionBlocks.first(where: { $0.exercise.id == ex.id }) {
                let workingCount = block.sets.filter { $0.type.countsTowardWorkingStats }.count
                if workingCount != slot.sets && workingCount > 0 {
                    diffs.append(.init(kind: .setStructureChanged, title: "\(ex.name) Set Target", detail: "Adjusted from \(slot.sets) to \(workingCount) sets"))
                }
            }
        }
        return diffs
    }

    private func commitChangesToRoutine(pw: ProgramWorkout) {
        for slot in (pw.slots ?? []) { modelContext.delete(slot) }
        pw.slots = []
        for (order, block) in groupedBlocks.enumerated() {
            let workingSets = block.sets.filter { $0.type.countsTowardWorkingStats }
            let setCount = max(1, workingSets.count)
            let avgReps = workingSets.isEmpty ? 8 : (workingSets.map(\.reps).reduce(0, +) / workingSets.count)
            let slot = ExerciseSlot(
                order: order,
                exercise: block.exercise,
                sets: setCount,
                repRangeLow: max(4, avgReps - 2),
                repRangeHigh: min(20, avgReps + 2),
                targetRIR: 2,
                restSeconds: 120,
                progressionRule: .doubleProgression,
                supersetGroup: block.supersetGroup
            )
            slot.workout = pw
            modelContext.insert(slot)
        }
        try? modelContext.save()
    }

    private func previousPerformanceText(for setLog: SetLog, index: Int) -> String {
        guard let ex = setLog.exercise else { return "—" }
        let pastSets = (ex.setLogs ?? [])
            .filter { $0.isCompleted && $0.session?.id != session.id && $0.type.countsTowardWorkingStats }
            .sorted { ($0.session?.start ?? $0.timestamp) < ($1.session?.start ?? $1.timestamp) }

        if let lastSession = pastSets.last?.session {
            let lastSessionSets = pastSets.filter { $0.session?.id == lastSession.id }
            if index < lastSessionSets.count {
                let p = lastSessionSets[index]
                return "\(UnitsFormatter.formatGymLoad(p.weightKg, system: profile.unitSystem)) × \(p.reps)"
            }
        }
        return "—"
    }

    private func formatLoadDisplay(_ weightKg: Double, bodyweightMode: BodyweightMode) -> String {
        let loadStr = "\(Int(UnitsFormatter.displayWeight(weightKg, system: profile.unitSystem)))"
        switch bodyweightMode {
        case .standardLoad: return loadStr
        case .bodyweightOnly: return "BW"
        case .weightedBodyweight: return "+ \(loadStr)"
        case .assistedBodyweight: return "- \(loadStr)"
        }
    }

    private func nextSetType(_ current: SetType) -> SetType {
        switch current {
        case .working: return .warmup
        case .warmup: return .drop
        case .drop: return .failure
        case .failure: return .partial
        case .partial: return .myorep
        case .myorep: return .working
        }
    }

    // MARK: - Subviews & Banners

    private func livePRBanner(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "trophy.fill")
                .font(.subheadline)
                .foregroundStyle(.yellow)
            Text(text)
                .font(.caption.weight(.bold))
                .foregroundStyle(.primary)
            Spacer()
            Button {
                withAnimation { livePRBannerText = nil }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.yellow.opacity(0.18))
    }

    private func fastedSnackBanner(_ snackNudge: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "bolt.badge.clock.fill")
                .font(.title3)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Energy & Fuel Notice")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.orange)
                Text(snackNudge)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.12))
    }

    private var proteinGateBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "shield.lefthalf.filled")
                .foregroundStyle(.indigo)
            Text("Protein Gate: Last week's protein was under floor — holding aggressive load jumps.")
                .font(.caption2)
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(Color.indigo.opacity(0.12))
    }

    private var emptyWorkoutPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "dumbbell.fill")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("No Exercises Added")
                .font(.headline)
            Button("Add Exercise") {
                showingAddExercise = true
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }

    private func addExerciseSheet(digest: CoachingDashboardDigest) -> some View {
        NavigationStack {
            List(filteredExercises) { ex in
                Button {
                    appendExerciseToSession(ex, digest: digest)
                    showingAddExercise = false
                } label: {
                    HStack(spacing: 12) {
                        ExerciseThumbnailView(exercise: ex, size: 44, cornerRadius: 10)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ex.name).font(.subheadline.weight(.semibold))
                            Text("\(ex.equipment.displayName) • \(ex.primaryMuscles.map(\.displayName).joined(separator: ", "))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .searchable(text: $exerciseSearch, prompt: "Search exercises")
            .navigationTitle("Add Exercise")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { showingAddExercise = false }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingNewCustomExercise = true
                    } label: {
                        Label("Custom", systemImage: "plus")
                            .font(.subheadline.weight(.semibold))
                    }
                }
            }
            .sheet(isPresented: $showingNewCustomExercise) {
                NewCustomExerciseSheet()
            }
        }
    }

    private var filteredExercises: [Exercise] {
        let q = exerciseSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return allExercises }
        return allExercises.filter { $0.name.lowercased().contains(q) }
    }
}

// MARK: - Isolated Header Telemetry Tickers

private struct ActiveElapsedTimerView: View {
    let session: WorkoutSession

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0)) { context in
            let elapsed = session.effectiveElapsedSeconds(at: context.date)
            let s = elapsed % 60
            let m = (elapsed / 60) % 60
            let h = elapsed / 3600

            HStack(spacing: 5) {
                if session.isPaused {
                    Image(systemName: "pause.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.yellow)
                }

                if h > 0 {
                    Text(String(format: "%d:%02d:%02d", h, m, s))
                } else {
                    Text(String(format: "%02d:%02d", m, s))
                }
            }
            .font(.system(size: 14, weight: .bold, design: .monospaced))
            .foregroundStyle(session.isPaused ? Color.yellow : Color.primary)
            .padding(.horizontal, session.isPaused ? 7 : 0)
            .padding(.vertical, session.isPaused ? 3 : 0)
            .background(
                session.isPaused ? Color.yellow.opacity(0.18) : Color.clear,
                in: Capsule()
            )
        }
    }
}

private struct ActiveRestTimerPill: View {
    @Environment(RestTimerService.self) private var restTimer

    var body: some View {
        if restTimer.isRunning {
            HStack(spacing: 5) {
                Image(systemName: "timer")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.orange)
                Text("\(restTimer.remainingSeconds)s")
                    .font(.system(size: 12, weight: .heavy, design: .monospaced))
                    .foregroundStyle(.orange)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.orange.opacity(0.16), in: Capsule())
        }
    }
}

public struct ActiveCornerHeartRateBadge: View {
    @Environment(PhoneWatchSyncService.self) private var watchSync
    @Environment(HealthKitService.self) private var healthService

    public init() {}

    public var body: some View {
        let bpm = watchSync.liveWatchHeartRateBPM ?? healthService.currentLiveHeartRateBPM
        HStack(spacing: 4) {
            Image(systemName: "heart.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(bpm != nil ? .red : .secondary)
            if let bpm, bpm > 0 {
                Text("\(Int(bpm.rounded()))")
                    .font(.system(size: 11, weight: .bold, design: .rounded).monospacedDigit())
            } else {
                Text("--")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(Color.red.opacity(0.12), in: Capsule())
    }
}

private struct ActiveWatchHeartRateBanner: View {
    @Environment(PhoneWatchSyncService.self) private var watchSync
    @Environment(HealthKitService.self) private var healthService

    var body: some View {
        let bpm = watchSync.liveWatchHeartRateBPM ?? healthService.currentLiveHeartRateBPM
        if let bpm, bpm > 0 {
            HStack(spacing: 10) {
                Image(systemName: "heart.fill")
                    .foregroundStyle(.red)
                Text("\(Int(bpm.rounded())) BPM")
                    .font(.subheadline.weight(.bold).monospacedDigit())
                if watchSync.liveWatchActiveCaloriesDisplayOnly > 0 {
                    Text("• \(Int(watchSync.liveWatchActiveCaloriesDisplayOnly.rounded())) active kcal (Display Only)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
            .background(Color.red.opacity(0.10))
        }
    }
}

private struct ActiveRestTimerBanner: View {
    @Environment(RestTimerService.self) private var restTimer

    var body: some View {
        if restTimer.isRunning {
            HStack(spacing: 12) {
                Image(systemName: "timer")
                    .font(.title3)
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Rest • \(restTimer.remainingSeconds)s")
                        .font(.headline.monospacedDigit())
                    if !restTimer.nextSetSummary.isEmpty {
                        Text(restTimer.nextSetSummary)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button("-15s") { restTimer.adjust(bySeconds: -15) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Button("+30s") { restTimer.adjust(bySeconds: 30) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Button("Skip") { restTimer.skip() }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .controlSize(.small)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color.orange.opacity(0.14))
        }
    }
}
