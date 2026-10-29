import SwiftUI
import SwiftData

// MARK: - Standalone Sheet Wrapper for Any Exercise

struct ExerciseGuideSheet: View {
    @Environment(\.dismiss) private var dismiss
    let exercise: Exercise

    var body: some View {
        NavigationStack {
            ScrollView {
                ExerciseGuideContentView(exercise: exercise)
                    .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(exercise.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - Embeddable Visual + Step-by-Step Guide Content

struct ExerciseGuideContentView: View {
    let exercise: Exercise

    private enum MediaDisplayMode: String, CaseIterable, Identifiable {
        case animated = "Motion"
        case sideBySide = "Start vs Finish"
        var id: String { rawValue }
    }

    @State private var displayMode: MediaDisplayMode = .animated
    @State private var currentPhase: Int = 0
    @State private var isPlaying: Bool = true
    #if canImport(UIKit)
    @State private var startImage: UIImage? = nil
    @State private var finishImage: UIImage? = nil
    #endif

    var body: some View {
        let guide = ExerciseGuideCatalog.shared.guide(for: exercise)

        VStack(alignment: .leading, spacing: 16) {
            mediaCard(guide: guide)
            muscleAnatomyCard
            if !guide.setupTip.isEmpty {
                setupTipCard(tip: guide.setupTip)
            }
            stepsCard(steps: guide.steps)
            if !guide.formCues.isEmpty || !guide.commonMistakes.isEmpty {
                cuesAndMistakesCard(cues: guide.formCues, mistakes: guide.commonMistakes)
            }
        }
        #if canImport(UIKit)
        .task(id: guide.mediaKey) {
            guard !guide.mediaKey.isEmpty else { return }
            startImage = ExerciseImageCache.shared.cachedImage(mediaKey: guide.mediaKey, phase: 0, bucketSize: 560)
            finishImage = ExerciseImageCache.shared.cachedImage(mediaKey: guide.mediaKey, phase: 1, bucketSize: 560)
            if startImage == nil {
                startImage = await ExerciseImageCache.shared.loadImage(mediaKey: guide.mediaKey, phase: 0, bucketSize: 560)
            }
            if finishImage == nil {
                finishImage = await ExerciseImageCache.shared.loadImage(mediaKey: guide.mediaKey, phase: 1, bucketSize: 560)
            }
        }
        .task(id: "\(guide.mediaKey)_\(isPlaying)_\(displayMode.rawValue)") {
            guard isPlaying, displayMode == .animated, !guide.mediaKey.isEmpty else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(1450))
                guard !Task.isCancelled else { break }
                withAnimation(.easeInOut(duration: 0.22)) {
                    currentPhase = (currentPhase == 0) ? 1 : 0
                }
            }
        }
        #endif
    }

    @ViewBuilder
    private func mediaCard(guide: ExerciseGuideEntry) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 6) {
                    Label(exercise.equipment.displayName, systemImage: "dumbbell.fill")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Color.accentColor.opacity(0.12), in: Capsule())
                        .foregroundStyle(Color.accentColor)

                    Text(exercise.movementPattern.displayName)
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Color(.tertiarySystemFill), in: Capsule())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if guide.hasBundledPhotos {
                    Picker("View", selection: $displayMode) {
                        ForEach(MediaDisplayMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 185)
                }
            }

            #if canImport(UIKit)
            if guide.hasBundledPhotos, (startImage != nil || finishImage != nil) {
                if displayMode == .animated {
                    let activeImg = (currentPhase == 0 ? startImage : finishImage) ?? startImage ?? finishImage
                    ZStack(alignment: .bottom) {
                        if let activeImg {
                            Image(uiImage: activeImg)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: .infinity)
                                .frame(height: 240)
                                .background(Color.black.opacity(0.04))
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .onTapGesture {
                                    isPlaying = false
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        currentPhase = (currentPhase == 0) ? 1 : 0
                                    }
                                }
                        }

                        HStack {
                            Text(currentPhase == 0 ? "1/2 • Start / Stretch" : "2/2 • Peak / Finish")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(.black.opacity(0.68), in: Capsule())

                            Spacer()

                            Button {
                                isPlaying.toggle()
                            } label: {
                                Label(isPlaying ? "Pause" : "Loop", systemImage: isPlaying ? "pause.fill" : "play.fill")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(.black.opacity(0.68), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(10)
                    }
                } else {
                    HStack(spacing: 10) {
                        phaseFrame(image: startImage, badge: "1 • Start")
                        phaseFrame(image: finishImage, badge: "2 • Finish")
                    }
                }
            } else {
                fallbackIllustrationBanner
            }
            #else
            fallbackIllustrationBanner
            #endif
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    #if canImport(UIKit)
    private func phaseFrame(image: UIImage?, badge: String) -> some View {
        ZStack(alignment: .bottomLeading) {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .frame(height: 175)
                    .background(Color.black.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(.tertiarySystemFill))
                    .frame(height: 175)
            }
            Text(badge)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.black.opacity(0.68), in: Capsule())
                .padding(8)
        }
    }
    #endif

    private var fallbackIllustrationBanner: some View {
        HStack(spacing: 14) {
            ExerciseThumbnailView(exercise: exercise, size: 64, cornerRadius: 14)
            VStack(alignment: .leading, spacing: 4) {
                Text(exercise.name)
                    .font(.subheadline.bold())
                Text("Follow the step-by-step setup and execution guide below.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var muscleAnatomyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Target Muscles", systemImage: "figure.strengthtraining.traditional")
                    .font(.subheadline.bold())
                Spacer()
                HStack(spacing: 10) {
                    HStack(spacing: 4) {
                        Circle().fill(Color.red.opacity(0.85)).frame(width: 8, height: 8)
                        Text("Primary").font(.caption2).foregroundStyle(.secondary)
                    }
                    if !exercise.secondaryMuscles.isEmpty {
                        HStack(spacing: 4) {
                            Circle().fill(Color.orange.opacity(0.78)).frame(width: 8, height: 8)
                            Text("Secondary").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            HStack(alignment: .center, spacing: 14) {
                TargetMuscleDiagramView(
                    primary: Set(exercise.primaryMuscles),
                    secondary: Set(exercise.secondaryMuscles)
                )
                .frame(width: 148, height: 150)

                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("PRIMARY MOVER")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)
                        FlowMuscleChipsView(muscles: exercise.primaryMuscles, tint: .red)
                    }

                    if !exercise.secondaryMuscles.isEmpty {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("SYNERGISTS")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.secondary)
                            FlowMuscleChipsView(muscles: exercise.secondaryMuscles, tint: .orange)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func setupTipCard(tip: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "slider.horizontal.3")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.purple)
                .frame(width: 34, height: 34)
                .background(Color.purple.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text("Planet Fitness & Machine Setup")
                    .font(.subheadline.bold())
                    .foregroundStyle(.primary)
                Text(tip)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.purple.opacity(0.25), lineWidth: 1)
                )
        )
    }

    private func stepsCard(steps: [String]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("How to Perform", systemImage: "list.number")
                .font(.subheadline.bold())

            ForEach(Array(steps.enumerated()), id: \.offset) { idx, step in
                HStack(alignment: .top, spacing: 12) {
                    Text("\(idx + 1)")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background(Color.accentColor, in: Circle())

                    Text(step)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func cuesAndMistakesCard(cues: [String], mistakes: [String]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if !cues.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Coaching Cues", systemImage: "checkmark.seal.fill")
                        .font(.subheadline.bold())
                        .foregroundStyle(.green)

                    ForEach(cues, id: \.self) { cue in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.green)
                                .padding(.top, 3)
                            Text(cue)
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            if !cues.isEmpty && !mistakes.isEmpty {
                Divider()
            }

            if !mistakes.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Common Mistakes to Avoid", systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline.bold())
                        .foregroundStyle(.orange)

                    ForEach(mistakes, id: \.self) { mistake in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                                .padding(.top, 3)
                            Text(mistake)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// MARK: - Anatomical Front & Back Silhouette Diagram

private struct FlowMuscleChipsView: View {
    let muscles: [MuscleGroup]
    let tint: Color

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), alignment: .leading)], alignment: .leading, spacing: 6) {
            ForEach(muscles) { m in
                Text(m.displayName)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(tint.opacity(0.14), in: Capsule())
                    .foregroundStyle(tint)
            }
        }
    }
}

struct TargetMuscleDiagramView: View {
    let primary: Set<MuscleGroup>
    let secondary: Set<MuscleGroup>

    var body: some View {
        HStack(spacing: 8) {
            bodyFigure(isFront: true, label: "Front")
            bodyFigure(isFront: false, label: "Back")
        }
        .padding(8)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func fill(for muscles: [MuscleGroup]) -> Color {
        if muscles.contains(where: { primary.contains($0) }) {
            return Color.red.opacity(0.84)
        }
        if muscles.contains(where: { secondary.contains($0) }) {
            return Color.orange.opacity(0.75)
        }
        return Color.primary.opacity(0.11)
    }

    private func bodyFigure(isFront: Bool, label: String) -> some View {
        VStack(spacing: 4) {
            Canvas { ctx, size in
                let w = size.width
                let h = size.height
                let cx = w / 2.0
                let baseColor = Color.primary.opacity(0.11)

                func pill(_ x: CGFloat, _ y: CGFloat, _ rw: CGFloat, _ rh: CGFloat, color: Color) {
                    let rect = CGRect(x: x - rw / 2, y: y - rh / 2, width: rw, height: rh)
                    let path = Path(roundedRect: rect, cornerRadius: min(rw, rh) * 0.45)
                    ctx.fill(path, with: .color(color))
                }

                // Head
                pill(cx, h * 0.08, w * 0.22, h * 0.11, color: baseColor)

                // Traps / Neck
                pill(cx, h * 0.16, w * 0.34, h * 0.05, color: fill(for: [.traps]))

                // Shoulders (Delts)
                let deltMuscles: [MuscleGroup] = isFront ? [.frontDelts, .sideDelts] : [.rearDelts, .sideDelts]
                pill(cx - w * 0.24, h * 0.22, w * 0.15, h * 0.09, color: fill(for: deltMuscles))
                pill(cx + w * 0.24, h * 0.22, w * 0.15, h * 0.09, color: fill(for: deltMuscles))

                // Upper Torso (Chest vs Upper Back / Lats)
                if isFront {
                    pill(cx, h * 0.25, w * 0.36, h * 0.13, color: fill(for: [.chest]))
                    pill(cx, h * 0.39, w * 0.30, h * 0.15, color: fill(for: [.abs]))
                } else {
                    pill(cx, h * 0.24, w * 0.36, h * 0.11, color: fill(for: [.upperBack, .traps]))
                    pill(cx, h * 0.36, w * 0.33, h * 0.13, color: fill(for: [.lats]))
                    pill(cx, h * 0.49, w * 0.34, h * 0.11, color: fill(for: [.glutes]))
                }

                // Upper Arms (Biceps vs Triceps)
                let upperArm: [MuscleGroup] = isFront ? [.biceps] : [.triceps]
                pill(cx - w * 0.28, h * 0.33, w * 0.12, h * 0.13, color: fill(for: upperArm))
                pill(cx + w * 0.28, h * 0.33, w * 0.12, h * 0.13, color: fill(for: upperArm))

                // Forearms
                pill(cx - w * 0.31, h * 0.46, w * 0.10, h * 0.13, color: fill(for: [.forearms]))
                pill(cx + w * 0.31, h * 0.46, w * 0.10, h * 0.13, color: fill(for: [.forearms]))

                // Thighs (Quads vs Hamstrings)
                let thighMuscles: [MuscleGroup] = isFront ? [.quads] : [.hamstrings]
                let thighY: CGFloat = isFront ? 0.61 : 0.64
                pill(cx - w * 0.11, h * thighY, w * 0.15, h * 0.21, color: fill(for: thighMuscles))
                pill(cx + w * 0.11, h * thighY, w * 0.15, h * 0.21, color: fill(for: thighMuscles))

                // Calves
                pill(cx - w * 0.11, h * 0.84, w * 0.12, h * 0.17, color: fill(for: [.calves]))
                pill(cx + w * 0.11, h * 0.84, w * 0.12, h * 0.17, color: fill(for: [.calves]))
            }
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Complete Workout Visual Guide Sheet (e.g. Push / Back & Biceps / Lower / Upper)

struct WorkoutOverviewGuideSheet: View {
    @Environment(\.dismiss) private var dismiss
    let workout: ProgramWorkout
    let unitSystem: UnitSystem
    var onStartWorkout: (() -> Void)? = nil

    @State private var selectedExercise: Exercise? = nil

    var body: some View {
        let slots = workout.sortedSlots
        let totalSets = slots.reduce(0) { $0 + $1.sets }
        let estMinutes = max(20, Int((Double(totalSets) * 2.6).rounded()))
        let musclesWorked: [MuscleGroup] = {
            var seen = Set<MuscleGroup>()
            var ordered: [MuscleGroup] = []
            for slot in slots {
                for m in slot.exercise?.primaryMuscles ?? [] where seen.insert(m).inserted {
                    ordered.append(m)
                }
            }
            return ordered
        }()

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // Summary Card
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Label("\(slots.count) exercises", systemImage: "figure.strengthtraining.traditional")
                            Text("•")
                            Text("\(totalSets) working sets")
                            Text("•")
                            Text("~\(estMinutes) min")
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                        if !musclesWorked.isEmpty {
                            FlowMuscleChipsView(muscles: musclesWorked, tint: .accentColor)
                        }

                        Text("Tap any exercise below for full Start/Finish photos, Planet Fitness setup cues, and form steps.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                    // Ordered Exercise Guide Cards
                    ForEach(Array(slots.enumerated()), id: \.element.id) { idx, slot in
                        if let ex = slot.exercise {
                            let guide = ExerciseGuideCatalog.shared.guide(for: ex)
                            Button {
                                selectedExercise = ex
                            } label: {
                                HStack(alignment: .top, spacing: 12) {
                                    ExerciseThumbnailView(exercise: ex, size: 64, cornerRadius: 12)

                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack(spacing: 6) {
                                            Text("\(idx + 1). \(ex.name)")
                                                .font(.subheadline.bold())
                                                .foregroundStyle(.primary)
                                                .multilineTextAlignment(.leading)
                                            Spacer()
                                            Image(systemName: "chevron.right")
                                                .font(.caption.bold())
                                                .foregroundStyle(.tertiary)
                                        }

                                        Text("\(slot.sets) sets × \(slot.repRangeLow)–\(slot.repRangeHigh) reps • RIR \(slot.targetRIR) • Rest \(slot.restSeconds)s")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(Color.accentColor)

                                        if !guide.setupTip.isEmpty {
                                            Text(guide.setupTip)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(2)
                                                .multilineTextAlignment(.leading)
                                        } else if let firstStep = guide.steps.first {
                                            Text(firstStep)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(2)
                                                .multilineTextAlignment(.leading)
                                        }
                                    }
                                }
                                .padding(12)
                                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("\(workout.name) Guide")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let onStartWorkout {
                    Button {
                        dismiss()
                        onStartWorkout()
                    } label: {
                        Label("Start \(workout.name)", systemImage: "play.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial)
                }
            }
            .sheet(item: $selectedExercise) { ex in
                ExerciseGuideSheet(exercise: ex)
            }
        }
    }
}

// MARK: - Full Workout History Browser (Lazy List for Smooth 120Hz Scrolling)

struct WorkoutHistoryListView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \WorkoutSession.start, order: .reverse) private var sessions: [WorkoutSession]

    let unitSystem: UnitSystem

    @State private var searchText: String = ""
    @State private var selectedSession: WorkoutSession? = nil

    private var filteredSessions: [WorkoutSession] {
        let finished = sessions.filter(\.isFinished)
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return finished }
        return finished.filter { session in
            if session.title.localizedCaseInsensitiveContains(q) { return true }
            if session.dayKey.localizedCaseInsensitiveContains(q) { return true }
            return (session.sets ?? []).contains { $0.exercise?.name.localizedCaseInsensitiveContains(q) == true }
        }
    }

    var body: some View {
        NavigationStack {
            List(filteredSessions) { session in
                Button {
                    selectedSession = session
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(session.title)
                                .font(.subheadline.bold())
                                .foregroundStyle(.primary)
                            HStack(spacing: 6) {
                                Text(DayKey.displayTitle(for: session.dayKey))
                                if let end = session.end {
                                    let mins = max(1, Int(end.timeIntervalSince(session.start) / 60.0))
                                    Text("• \(mins)m")
                                }
                                if let gymName = session.gymProfile?.name {
                                    Text("• \(gymName)")
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 3) {
                            Text("\(session.completedSetCount) sets")
                                .font(.caption.bold())
                                .foregroundStyle(.primary)
                            Text("\(UnitsFormatter.formatWeight(session.totalWorkingVolumeKg, system: unitSystem, decimals: 0)) vol")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            .searchable(text: $searchText, prompt: "Search Push, Lower, exercise...")
            .navigationTitle("Workout History (\(filteredSessions.count))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $selectedSession) { session in
                WorkoutSessionDetailSheet(session: session, unitSystem: unitSystem)
            }
        }
    }
}

struct WorkoutSessionDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let session: WorkoutSession
    let unitSystem: UnitSystem

    @State private var guideExercise: Exercise? = nil

    private struct ExerciseSetGroup: Identifiable {
        var id: UUID
        var exercise: Exercise
        var sets: [SetLog]
    }

    private var groupedSets: [ExerciseSetGroup] {
        var orderIDs: [UUID] = []
        var byID: [UUID: (Exercise, [SetLog])] = [:]
        for log in session.sortedSets {
            guard let ex = log.exercise else { continue }
            if byID[ex.id] == nil {
                orderIDs.append(ex.id)
                byID[ex.id] = (ex, [])
            }
            byID[ex.id]?.1.append(log)
        }
        return orderIDs.compactMap { id in
            guard let pair = byID[id] else { return nil }
            return ExerciseSetGroup(id: id, exercise: pair.0, sets: pair.1)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(DayKey.displayTitle(for: session.dayKey))
                                .font(.subheadline.bold())
                            if let gym = session.gymProfile?.name {
                                Label(gym, systemImage: "building.2.fill")
                                    .font(.caption)
                                    .foregroundStyle(.purple)
                            }
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            if let end = session.end {
                                Text("\(max(1, Int(end.timeIntervalSince(session.start) / 60.0))) min")
                                    .font(.subheadline.bold())
                            }
                            Text("\(UnitsFormatter.formatWeight(session.totalWorkingVolumeKg, system: unitSystem, decimals: 0)) volume")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if !session.notes.isEmpty {
                        Text(session.notes)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                ForEach(groupedSets) { group in
                    Section {
                        Button {
                            guideExercise = group.exercise
                        } label: {
                            HStack(spacing: 10) {
                                ExerciseThumbnailView(exercise: group.exercise, size: 44, cornerRadius: 10)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(group.exercise.name)
                                        .font(.subheadline.bold())
                                        .foregroundStyle(.primary)
                                    Text("Tap for photo & form guide")
                                        .font(.caption2)
                                        .foregroundStyle(Color.accentColor)
                                }
                                Spacer()
                                Image(systemName: "info.circle")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }

                        ForEach(Array(group.sets.enumerated()), id: \.element.id) { idx, setLog in
                            HStack {
                                Text(setLog.type == .working ? "Set \(idx + 1)" : setLog.type.displayName)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 56, alignment: .leading)
                                Spacer()
                                Text("\(UnitsFormatter.formatGymLoad(setLog.weightKg, system: unitSystem)) × \(setLog.reps)")
                                    .font(.subheadline.monospacedDigit().weight(.medium))
                            }
                        }
                    }
                }
            }
            .navigationTitle(session.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $guideExercise) { ex in
                ExerciseGuideSheet(exercise: ex)
            }
        }
    }
}
