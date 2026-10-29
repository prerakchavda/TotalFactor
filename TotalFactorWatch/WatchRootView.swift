import SwiftUI

struct WatchRootView: View {
    @Environment(WatchStore.self) private var store
    @State private var selectedTab: Int = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            WatchWorkoutTabView(onJumpToRest: { selectedTab = 1 })
                .tag(0)
                .tabItem {
                    Label("Lift", systemImage: "figure.strengthtraining.traditional")
                }

            WatchRestTimerTabView()
                .tag(1)
                .tabItem {
                    Label("Rest", systemImage: "timer")
                }

            WatchMacrosTabView()
                .tag(2)
                .tabItem {
                    Label("Macros", systemImage: "flame.fill")
                }

            WatchWeighInTabView()
                .tag(3)
                .tabItem {
                    Label("Weight", systemImage: "scalemass.fill")
                }
        }
        .overlay(alignment: .top) {
            if let banner = store.statusBanner {
                Text(banner)
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.top, 2)
            }
        }
    }
}

// MARK: - Tab 1: 1-Tap Set Logger + Digital Crown Load/Rep Dial

private struct WatchWorkoutTabView: View {
    @Environment(WatchStore.self) private var store
    let onJumpToRest: () -> Void

    private enum CrownField: Hashable {
        case weight
        case reps
    }

    @State private var activeField: CrownField = .weight
    @State private var crownValue: Double = 135.0
    @State private var syncedSetID: UUID? = nil
    @State private var showingFinishConfirm: Bool = false
    @FocusState private var isCrownFocused: Bool

    var body: some View {
        if let session = store.snapshot.activeSession, let current = store.currentSet {
            activeSetLogger(session: session, setItem: current)
        } else {
            idleStartWorkoutView
        }
    }

    private var idleStartWorkoutView: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if let schedID = store.snapshot.scheduledWorkoutID,
                       let schedName = store.snapshot.scheduledWorkoutName {
                        Button {
                            store.startWorkout(programWorkoutID: schedID)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("TODAY'S LIFT")
                                    .font(.system(size: 10, weight: .heavy))
                                    .foregroundStyle(.green)
                                Text(schedName)
                                    .font(.footnote.weight(.bold))
                                    .lineLimit(2)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .tint(.green)
                    }

                    ForEach(store.snapshot.availableWorkouts) { w in
                        if w.id != store.snapshot.scheduledWorkoutID {
                            Button {
                                store.startWorkout(programWorkoutID: w.id)
                            } label: {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(w.name)
                                        .font(.caption.weight(.semibold))
                                        .lineLimit(1)
                                    Text("\(w.exerciseCount) ex • \(w.workingSetCount) sets")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }

                    Button {
                        store.startWorkout(programWorkoutID: nil)
                    } label: {
                        Label("Freestyle Lift", systemImage: "plus.circle.fill")
                            .font(.caption.weight(.semibold))
                    }

                    if !store.isPhoneReachable {
                        Text("Using cached program • syncs automatically when iPhone is nearby.")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .padding(.top, 2)
                    }
                }
            }
            .navigationTitle("Lift")
        }
    }

    private func activeSetLogger(session: WatchActiveSessionDTO, setItem: WatchSetItemDTO) -> some View {
        let stepDisplay = crownStep(for: setItem, field: activeField)
        let minDisplay = activeField == .weight ? 0.0 : 1.0
        let maxDisplay = activeField == .weight ? 1200.0 : 60.0

        return ScrollView {
            VStack(spacing: 6) {
                // Header: Exercise + Set X/Y + Live Heart Rate
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(setItem.exerciseName)
                        .font(.caption.weight(.bold))
                        .lineLimit(1)
                    Spacer()
                    if let bpm = store.workoutManager.liveHeartRateBPM {
                        HStack(spacing: 2) {
                            Image(systemName: "heart.fill")
                                .foregroundStyle(.red)
                            Text("\(Int(bpm.rounded()))")
                                .monospacedDigit()
                        }
                        .font(.system(size: 11, weight: .bold))
                    }
                }

                HStack {
                    Text("Set \(setItem.setNumberInExercise)/\(setItem.totalSetsInExercise) • \(setItem.setTypeBadge)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if store.restRemainingSeconds > 0 {
                        Button {
                            onJumpToRest()
                        } label: {
                            Text("⏱ \(store.restRemainingSeconds)s")
                                .font(.system(size: 11, weight: .bold).monospacedDigit())
                                .foregroundStyle(.orange)
                        }
                        .buttonStyle(.plain)
                    }
                }

                // Side-by-side Weight & Reps Crown Selector Tiles
                HStack(spacing: 6) {
                    Button {
                        switchCrownField(to: .weight, setItem: setItem)
                    } label: {
                        VStack(spacing: 1) {
                            Text(store.snapshot.weightUnitSymbol.uppercased())
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(activeField == .weight ? .green : .secondary)
                            Text(formattedDisplayWeight(currentWeightDisplay(for: setItem)))
                                .font(.system(size: 17, weight: .heavy).monospacedDigit())
                                .minimumScaleFactor(0.7)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(activeField == .weight ? Color.green.opacity(0.22) : Color.white.opacity(0.08))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(activeField == .weight ? Color.green : Color.clear, lineWidth: 1.5)
                        )
                    }
                    .buttonStyle(.plain)

                    Button {
                        switchCrownField(to: .reps, setItem: setItem)
                    } label: {
                        VStack(spacing: 1) {
                            Text("REPS")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(activeField == .reps ? .cyan : .secondary)
                            Text("\(currentReps(for: setItem))")
                                .font(.system(size: 17, weight: .heavy).monospacedDigit())
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(activeField == .reps ? Color.cyan.opacity(0.22) : Color.white.opacity(0.08))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(activeField == .reps ? Color.cyan : Color.clear, lineWidth: 1.5)
                        )
                    }
                    .buttonStyle(.plain)
                }

                // Quick +/- Nudge Row alongside Digital Crown
                HStack(spacing: 8) {
                    Button {
                        nudgeActiveField(by: -1, setItem: setItem)
                    } label: {
                        Image(systemName: "minus")
                            .font(.caption.weight(.bold))
                            .frame(maxWidth: .infinity)
                    }
                    .controlSize(.mini)

                    Text("Turn Crown")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)

                    Button {
                        nudgeActiveField(by: 1, setItem: setItem)
                    } label: {
                        Image(systemName: "plus")
                            .font(.caption.weight(.bold))
                            .frame(maxWidth: .infinity)
                    }
                    .controlSize(.mini)
                }

                // Primary 1-Tap Log Set CTA
                Button {
                    let kg = store.snapshot.internalKg(fromDisplay: currentWeightDisplay(for: setItem))
                    let reps = currentReps(for: setItem)
                    store.logOrToggleSet(setItem, overrideWeightKg: kg, overrideReps: reps)
                } label: {
                    Label(
                        setItem.isCompleted ? "Completed (Undo)" : "Log Set",
                        systemImage: setItem.isCompleted ? "checkmark.circle.fill" : "checkmark"
                    )
                    .font(.footnote.weight(.bold))
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(setItem.isCompleted ? .gray : .green)

                // Secondary Controls: Prev / +Set / Next / Finish
                HStack(spacing: 6) {
                    Button {
                        store.selectPreviousSet()
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .controlSize(.mini)

                    Button("+ Set") {
                        store.addSet(from: setItem)
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .controlSize(.mini)

                    Button {
                        store.selectNextSet()
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                    .controlSize(.mini)
                }

                Button(role: .destructive) {
                    showingFinishConfirm = true
                } label: {
                    Text("Finish (\(session.completedCount)/\(session.sets.count))")
                        .font(.caption2.weight(.semibold))
                }
                .padding(.top, 2)
            }
            .padding(.horizontal, 2)
        }
        .focusable(true)
        .focused($isCrownFocused)
        .digitalCrownRotation(
            $crownValue,
            from: minDisplay,
            through: maxDisplay,
            by: stepDisplay,
            sensitivity: .medium,
            isContinuous: false,
            isHapticFeedbackEnabled: true
        )
        .onAppear {
            syncCrown(with: setItem)
            isCrownFocused = true
        }
        .onChange(of: setItem.id) { _, _ in
            syncCrown(with: setItem)
            isCrownFocused = true
        }
        .onChange(of: crownValue) { _, newValue in
            applyCrownValue(newValue, to: setItem)
        }
        .confirmationDialog("Finish Workout?", isPresented: $showingFinishConfirm) {
            Button("Finish & Save", role: .destructive) {
                store.finishWorkout()
            }
            Button("Keep Lifting", role: .cancel) {}
        }
    }

    private func crownStep(for setItem: WatchSetItemDTO, field: CrownField) -> Double {
        switch field {
        case .reps:
            return 1.0
        case .weight:
            if store.snapshot.isImperial {
                let dispInc = store.snapshot.displayWeight(setItem.loadIncrementKg)
                return dispInc >= 4.5 ? 5.0 : 2.5
            } else {
                return max(0.5, (setItem.loadIncrementKg * 2.0).rounded() / 2.0)
            }
        }
    }

    private func syncCrown(with setItem: WatchSetItemDTO) {
        syncedSetID = setItem.id
        if activeField == .weight {
            crownValue = roundedHalf(store.snapshot.displayWeight(setItem.weightKg))
        } else {
            crownValue = Double(setItem.reps)
        }
    }

    private func switchCrownField(to field: CrownField, setItem: WatchSetItemDTO) {
        activeField = field
        syncCrown(with: setItem)
        isCrownFocused = true
    }

    private func nudgeActiveField(by steps: Int, setItem: WatchSetItemDTO) {
        let step = crownStep(for: setItem, field: activeField)
        let next = crownValue + Double(steps) * step
        crownValue = activeField == .weight ? max(0, next) : max(1, min(60, next))
        applyCrownValue(crownValue, to: setItem)
    }

    private func applyCrownValue(_ val: Double, to setItem: WatchSetItemDTO) {
        guard syncedSetID == setItem.id else { return }
        if activeField == .weight {
            let kg = store.snapshot.internalKg(fromDisplay: max(0, val))
            store.updateDraftSetValues(setID: setItem.id, weightKg: kg, reps: setItem.reps)
        } else {
            let reps = max(1, min(60, Int(val.rounded())))
            store.updateDraftSetValues(setID: setItem.id, weightKg: setItem.weightKg, reps: reps)
        }
    }

    private func currentWeightDisplay(for setItem: WatchSetItemDTO) -> Double {
        if activeField == .weight && syncedSetID == setItem.id {
            return crownValue
        }
        return roundedHalf(store.snapshot.displayWeight(setItem.weightKg))
    }

    private func currentReps(for setItem: WatchSetItemDTO) -> Int {
        if activeField == .reps && syncedSetID == setItem.id {
            return max(1, Int(crownValue.rounded()))
        }
        return setItem.reps
    }

    private func roundedHalf(_ value: Double) -> Double {
        (value * 2.0).rounded() / 2.0
    }

    private func formattedDisplayWeight(_ value: Double) -> String {
        let half = roundedHalf(value)
        if abs(half.rounded() - half) < 0.05 {
            return "\(Int(half.rounded()))"
        }
        return String(format: "%.1f", half)
    }
}

// MARK: - Tab 2: Wrist Haptic Rest Timer

private struct WatchRestTimerTabView: View {
    @Environment(WatchStore.self) private var store

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                if store.restRemainingSeconds > 0 {
                    let total = Double(max(1, store.snapshot.restTotalSeconds))
                    let progress = min(1.0, max(0.0, Double(store.restRemainingSeconds) / total))

                    Gauge(value: progress) {
                        Text("REST")
                    } currentValueLabel: {
                        Text(formatClock(store.restRemainingSeconds))
                            .font(.system(size: 16, weight: .heavy).monospacedDigit())
                    }
                    .gaugeStyle(.accessoryCircularCapacity)
                    .tint(.orange)
                    .scaleEffect(1.2)
                    .padding(.vertical, 6)

                    if !store.snapshot.restExerciseName.isEmpty {
                        Text(store.snapshot.restExerciseName)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    HStack(spacing: 6) {
                        Button("-15s") {
                            store.adjustRest(deltaSeconds: -15)
                        }
                        .font(.caption2.weight(.bold))

                        Button("+30s") {
                            store.adjustRest(deltaSeconds: 30)
                        }
                        .font(.caption2.weight(.bold))
                    }

                    Button("Skip Rest") {
                        store.skipRest()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .font(.caption.weight(.bold))
                } else {
                    Text("Rest Timer")
                        .font(.footnote.weight(.bold))

                    Text("Auto-starts with wrist haptics (3-2-1-Go) when you log a set.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                        ForEach([60, 90, 120, 180], id: \.self) { sec in
                            Button("\(sec)s") {
                                store.startLocalPresetRest(seconds: sec)
                            }
                            .font(.caption.weight(.bold).monospacedDigit())
                        }
                    }
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private func formatClock(_ totalSeconds: Int) -> String {
        let mins = totalSeconds / 60
        let secs = totalSeconds % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// MARK: - Tab 3: Remaining Macros Glance

private struct WatchMacrosTabView: View {
    @Environment(WatchStore.self) private var store

    var body: some View {
        let snap = store.snapshot
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(snap.isTrainingDay ? "TRAINING DAY" : "REST DAY")
                        .font(.system(size: 9, weight: .heavy))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background((snap.isTrainingDay ? Color.green : Color.blue).opacity(0.22), in: Capsule())
                        .foregroundStyle(snap.isTrainingDay ? .green : .cyan)
                    Spacer()
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text("\(Int(snap.caloriesRemaining.rounded())) kcal")
                        .font(.title3.weight(.heavy).monospacedDigit())
                        .foregroundStyle(snap.caloriesRemaining >= 0 ? Color.primary : Color.orange)
                    Text("Remaining of \(Int(snap.caloriesTarget.rounded()))")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }

                macroRow(
                    label: "Protein",
                    remaining: snap.proteinRemaining,
                    target: snap.proteinTarget,
                    color: .pink
                )
                macroRow(
                    label: "Carbs",
                    remaining: snap.carbsRemaining,
                    target: snap.carbsTarget,
                    color: .orange
                )
                macroRow(
                    label: "Fat",
                    remaining: snap.fatRemaining,
                    target: snap.fatTarget,
                    color: .yellow
                )
            }
            .padding(.horizontal, 4)
        }
    }

    private func macroRow(label: String, remaining: Double, target: Double, color: Color) -> some View {
        let eaten = max(0, target - remaining)
        let ratio = target > 0 ? min(1.0, eaten / target) : 0
        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label)
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                Text("\(Int(remaining.rounded()))g left")
                    .font(.system(size: 11, weight: .bold).monospacedDigit())
                    .foregroundStyle(color)
            }
            ProgressView(value: ratio)
                .tint(color)
        }
    }
}

// MARK: - Tab 4: Digital Crown Wrist Weigh-In

private struct WatchWeighInTabView: View {
    @Environment(WatchStore.self) private var store
    @FocusState private var crownFocused: Bool

    var body: some View {
        @Bindable var bindableStore = store
        ScrollView {
            VStack(spacing: 6) {
                if let trendKg = store.snapshot.trendWeightKg {
                    Text("EMA Trend: \(store.snapshot.formatBodyWeight(trendKg))")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.cyan)
                } else {
                    Text("Wrist Weigh-In")
                        .font(.caption.weight(.bold))
                }

                Text(String(format: "%.1f %@", store.weighInDraftDisplay, store.snapshot.weightUnitSymbol))
                    .font(.title3.weight(.heavy).monospacedDigit())
                    .padding(.vertical, 4)

                HStack(spacing: 8) {
                    Button {
                        store.weighInDraftDisplay = max(60, (store.weighInDraftDisplay - 0.2).rounded(toPlaces: 1))
                    } label: {
                        Image(systemName: "minus")
                    }
                    .controlSize(.mini)

                    Text("Crown")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)

                    Button {
                        store.weighInDraftDisplay = min(700, (store.weighInDraftDisplay + 0.2).rounded(toPlaces: 1))
                    } label: {
                        Image(systemName: "plus")
                    }
                    .controlSize(.mini)
                }

                Button {
                    store.logWeighInFromWrist()
                } label: {
                    Label("Save Weigh-In", systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.bold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.cyan)
            }
            .padding(.horizontal, 2)
        }
        .focusable(true)
        .focused($crownFocused)
        .digitalCrownRotation(
            $bindableStore.weighInDraftDisplay,
            from: 60.0,
            through: 700.0,
            by: 0.1,
            sensitivity: .medium,
            isContinuous: false,
            isHapticFeedbackEnabled: true
        )
        .onAppear {
            crownFocused = true
        }
    }
}

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let divisor = pow(10.0, Double(places))
        return (self * divisor).rounded() / divisor
    }
}
