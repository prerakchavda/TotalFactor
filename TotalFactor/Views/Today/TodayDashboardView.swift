import SwiftUI
import SwiftData

struct TodayDashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState
    @Environment(HealthKitService.self) private var healthService

    @Query private var profiles: [UserProfile]
    @Query private var foodEntries: [FoodLogEntry]
    @Query private var dailyNotes: [DailyNote]
    @Query(sort: \WeeklyCheckIn.date, order: .reverse) private var checkIns: [WeeklyCheckIn]
    @Query private var programs: [Program]
    @Query private var gymProfiles: [GymProfile]
    @Query private var customNutrientTargets: [NutrientTarget]
    @Query private var goals: [Goal]

    @State private var showingMicronutrients: Bool = false
    @State private var previewGuideWorkout: ProgramWorkout? = nil

    private var profile: UserProfile {
        profiles.first ?? CoachingCoordinator.fetchOrCreateProfile(context: modelContext)
    }

    private var activeDayKey: String {
        appState.selectedDayKey
    }

    private var dayEntries: [FoodLogEntry] {
        foodEntries
            .filter { $0.dayKey == activeDayKey }
            .sorted { $0.timestamp < $1.timestamp }
    }

    private var dayNote: DailyNote? {
        dailyNotes.first { $0.dayKey == activeDayKey }
    }

    private var yesterdayUnmarkedWithFood: Bool {
        let yKey = DayKey.addingDays(-1, to: DayKey.today)
        let yCompleted = dailyNotes.first(where: { $0.dayKey == yKey })?.isComplete ?? false
        guard !yCompleted else { return false }
        let yCals = foodEntries.filter { $0.dayKey == yKey }.reduce(0.0) { $0 + $1.calories }
        return yCals >= 800
    }

    private var isCheckInDue: Bool {
        let todayWeekday = DayKey.weekday(for: DayKey.today)
        guard let latest = checkIns.first else {
            let activeGoal = goals.first(where: \.isActive)
            let start = activeGoal?.startDate ?? profile.createdAt
            let daysSinceStart = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: start), to: Calendar.current.startOfDay(for: .now)).day ?? 0
            return daysSinceStart >= 7 && todayWeekday == profile.checkInWeekday
        }
        let daysSince = DayKey.daysBetween(latest.dayKey, DayKey.today)
        return (daysSince >= 7 && todayWeekday == profile.checkInWeekday && latest.dayKey != DayKey.today) || daysSince >= 10
    }

    var body: some View {
        let digest = CoachingCoordinator.cachedOrComputeDigest(forDayKey: activeDayKey, context: modelContext)
        let targets = digest.todayTargets
        let eaten = totalNutrients(for: dayEntries)

        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    dayHeaderBar(isComplete: dayNote?.isComplete ?? false)

                    if yesterdayUnmarkedWithFood {
                        yesterdayCompleteBanner
                    }

                    if isCheckInDue {
                        checkInReadyBanner
                    }

                    macroZonesCard(eaten: eaten, targets: targets, isTrainingDay: digest.isTodayTrainingDay)

                    if let snackNudge = digest.preWorkoutSnackNudge {
                        nudgeCard(
                            icon: "bolt.badge.clock.fill",
                            color: AppleTheme.calories,
                            title: "Pre-Workout Fuel Nudge",
                            message: snackNudge,
                            actionTitle: "Log Snack"
                        ) {
                            appState.openQuickAdd(tab: 0)
                        }
                    }

                    if digest.isProteinGateActive {
                        nudgeCard(
                            icon: "shield.lefthalf.filled",
                            color: AppleTheme.protein,
                            title: "Protein Gate Active",
                            message: "Last 7 days averaged \(Int((digest.avgProteinLast7d ?? 0).rounded()))g protein vs. your \(Int(targets.proteinFloor))g floor. Aggressive load jumps are paused until protein rebounds.",
                            actionTitle: nil,
                            action: nil
                        )
                    }

                    coachingMetricsRow(digest: digest)

                    energyBalanceCard(digest: digest)

                    if profile.enableIntermittentFasting {
                        intermittentFastingCard
                    }

                    todayWorkoutCard(digest: digest)

                    externalWorkoutsSection

                    healthTelemetryCard
                }
                .padding(.horizontal)
                .padding(.bottom, 96)
            }
            .refreshable {
                await healthService.refreshTodayDashboardTelemetry()
            }
            .task {
                await healthService.refreshTodayDashboardTelemetry()
                healthService.startLiveHeartRateObserver()
            }
            .navigationTitle("Total Factor")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        appState.showingWeeklyCheckInSheet = true
                    } label: {
                        Label("Check-In", systemImage: "checkmark.seal")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        appState.showingWeighInSheet = true
                    } label: {
                        Label("Weigh In", systemImage: "scalemass")
                    }
                }
            }
            .sheet(isPresented: $showingMicronutrients) {
                MicronutrientDetailSheet(dayKey: activeDayKey, entries: dayEntries, targets: targets, sex: profile.biologicalSex)
            }
            .sheet(item: $previewGuideWorkout) { workout in
                WorkoutOverviewGuideSheet(workout: workout, unitSystem: profile.unitSystem) {
                    startWorkoutSession(from: workout)
                }
            }
        }
    }

    // MARK: - Subviews

    private func dayHeaderBar(isComplete: Bool) -> some View {
        HStack(spacing: 8) {
            Button {
                appState.selectedDayKey = DayKey.addingDays(-1, to: activeDayKey)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .background(Color.secondary.opacity(0.10), in: Circle())
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                appState.selectedDayKey = DayKey.today
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                    Text(DayKey.displayTitle(for: activeDayKey))
                        .font(.subheadline.weight(.bold))
                    if activeDayKey != DayKey.today {
                        Text("• Today")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(AppleTheme.hairline, lineWidth: 0.5))
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                toggleDayComplete()
            } label: {
                Image(systemName: isComplete ? "checkmark.circle.fill" : "circle.dashed")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(isComplete ? .green : .secondary)
                    .frame(width: 32, height: 32)
                    .background((isComplete ? Color.green : Color.secondary).opacity(0.12), in: Circle())
            }
            .buttonStyle(.plain)

            Button {
                appState.selectedDayKey = DayKey.addingDays(1, to: activeDayKey)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .background(Color.secondary.opacity(0.10), in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }

    private var yesterdayCompleteBanner: some View {
        HStack {
            Image(systemName: "sparkles")
                .foregroundStyle(.blue)
            Text("Yesterday has logged meals — mark complete so it feeds your expenditure?")
                .font(.caption)
            Spacer()
            Button("Complete") {
                let yKey = DayKey.addingDays(-1, to: DayKey.today)
                if let note = dailyNotes.first(where: { $0.dayKey == yKey }) {
                    note.isComplete = true
                } else {
                    modelContext.insert(DailyNote(dayKey: yKey, isComplete: true))
                }
                try? modelContext.save()
                _ = CoachingCoordinator.evaluate(forDayKey: activeDayKey, context: modelContext)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.mini)
        }
        .padding(12)
        .background(Color.blue.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
    }

    private var checkInReadyBanner: some View {
        Button {
            appState.showingWeeklyCheckInSheet = true
        } label: {
            HStack {
                Image(systemName: "chart.line.uptrend.xyaxis.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Weekly Check-In Ready")
                        .font(.subheadline.weight(.bold))
                    Text("Review expenditure, weight velocity, training volume & updated macro targets.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .background(Color.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    private func nudgeCard(
        icon: String,
        color: Color,
        title: String,
        message: String,
        actionTitle: String?,
        action: (() -> Void)?
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            AppleIconBadge(icon: icon, color: color, size: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(color)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .tint(color)
                    .controlSize(.small)
            }
        }
        .appleHealthCard(padding: 14)
    }

    private func macroZonesCard(eaten: NutrientsPer100g, targets: MacroTargets, isTrainingDay: Bool) -> some View {
        let caloriesRemaining = max(0, targets.calories - eaten.calories)
        let calorieRatio = targets.calories > 0 ? min(1.2, eaten.calories / targets.calories) : 0

        return VStack(alignment: .leading, spacing: 16) {
            // Header Row: Category Badge + Carb Cycling / Micronutrients Shortcut
            HStack {
                HStack(spacing: 8) {
                    AppleIconBadge(icon: "flame.fill", color: AppleTheme.calories, size: 28)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Energy & Macros")
                            .font(.headline.weight(.bold))
                        if profile.enableTrainingDayCarbCycling {
                            Text(isTrainingDay ? "Training-Day Target" : "Rest-Day Target")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(isTrainingDay ? AppleTheme.calories : AppleTheme.carbs)
                        }
                    }
                }
                Spacer()
                Button {
                    showingMicronutrients = true
                } label: {
                    Label("Micronutrients", systemImage: "pills.fill")
                        .font(.caption2.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            // Hero Metric Row: 38pt SF Rounded Numerals + Unit Label
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(Int(caloriesRemaining.rounded()))")
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(AppleTheme.calories)

                    Text("CAL REMAINING")
                        .font(.caption.weight(.heavy))
                        .foregroundStyle(.secondary)

                    Spacer()

                    VStack(alignment: .trailing, spacing: 1) {
                        Text("Goal \(Int(targets.calories.rounded()))")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                        Text("\(Int(eaten.calories.rounded())) eaten")
                            .font(.caption2.weight(.semibold).monospacedDigit())
                            .foregroundStyle(.primary)
                    }
                }

                // Apple Fitness Smooth Progress Track
                AppleFitnessBar(progress: calorieRatio, color: AppleTheme.calories, height: 9)
            }

            Divider()
                .padding(.vertical, 2)

            // Spacious 3-Column Macro Grid with SF Rounded Digits & Micro Progress Tracks
            HStack(spacing: 14) {
                AppleMacroColumnView(
                    title: "Protein",
                    eaten: eaten.protein,
                    target: targets.protein,
                    color: AppleTheme.protein
                )
                AppleMacroColumnView(
                    title: "Carbs",
                    eaten: eaten.carbs,
                    target: targets.carbs,
                    color: AppleTheme.carbs
                )
                AppleMacroColumnView(
                    title: "Fat",
                    eaten: eaten.fat,
                    target: targets.fat,
                    color: AppleTheme.fat
                )
            }
        }
        .appleHealthCard(padding: 20)
    }

    private func coachingMetricsRow(digest: CoachingDashboardDigest) -> some View {
        HStack(spacing: 12) {
            // Trend Weight Card (Apple Health Style)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    AppleIconBadge(icon: "scalemass.fill", color: AppleTheme.trend, size: 26)
                    Text("Weight Trend")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                    Spacer()
                }

                if let trendKg = digest.weightSummary.latestTrendKg {
                    Text(UnitsFormatter.formatWeight(trendKg, system: profile.unitSystem))
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.primary)

                    if let d7 = digest.weightSummary.change7dKg {
                        Label(
                            "\(UnitsFormatter.formatSignedWeightDelta(d7, system: profile.unitSystem)) this week",
                            systemImage: d7 <= 0 ? "arrow.down.right" : "arrow.up.right"
                        )
                        .font(.caption2.weight(.semibold).monospacedDigit())
                        .foregroundStyle(AppleTheme.trend)
                    } else {
                        Text("Log daily for velocity")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("No weigh-ins")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 2)

                Button {
                    appState.showingWeighInSheet = true
                } label: {
                    Label("Log Weight", systemImage: "plus")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .appleHealthCard(padding: 16)
            .frame(maxWidth: .infinity, alignment: .leading)

            // Adaptive Expenditure Card (Apple Health Style)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    AppleIconBadge(icon: "waveform.path.ecg", color: AppleTheme.expenditure, size: 26)
                    Text("Expenditure (TDEE)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                    Spacer()
                }

                Text("\(Int(digest.expenditure.expenditureKcal.rounded())) kcal")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.primary)

                ConfidencePill(confidence: digest.expenditure.confidence)

                Text(digest.expenditure.method == .adaptive ? "Adaptive Daily TDEE" : "Mifflin-St Jeor")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 2)
            }
            .appleHealthCard(padding: 16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func energyBalanceCard(digest: CoachingDashboardDigest) -> some View {
        let eatenKcal = dayEntries.reduce(0.0) { $0 + $1.calories }
        let tdeeKcal = digest.expenditure.expenditureKcal
        let deltaKcal = eatenKcal - tdeeKcal
        let isDeficit = deltaKcal < 0
        let absDelta = abs(Int(deltaKcal.rounded()))

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                AppleIconBadge(icon: "flame.fill", color: isDeficit ? .blue : .orange, size: 24)
                Text("Energy Balance (Intake vs. TDEE)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(isDeficit ? "In Deficit" : (absDelta < 25 ? "Balanced" : "In Surplus"))
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background((isDeficit ? Color.blue : Color.orange).opacity(0.15), in: Capsule())
                    .foregroundStyle(isDeficit ? Color.blue : Color.orange)
            }

            HStack(alignment: .firstTextBaseline) {
                Text("\(isDeficit ? "−" : "+")\(absDelta) kcal")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(isDeficit ? Color.blue : Color.orange)

                Text(isDeficit ? "net daily deficit" : "net daily surplus")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(Int(eatenKcal.rounded())) in • \(Int(tdeeKcal.rounded())) burn")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.primary)
                }
            }

            Text("MacroFactor-style dynamic energy balance: workouts and daily movement increase your metabolic burn, adapting your baseline expenditure automatically over time.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .appleHealthCard(padding: 16)
    }

    private var intermittentFastingCard: some View {
        let proto = profile.fastingProtocol
        let (isFasting, hoursFasted, progress, statusText) = evaluateFastingStatus(proto: proto)

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                AppleIconBadge(icon: "timer", color: .purple, size: 24)
                Text("Intermittent Fasting • \(proto.rawValue)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(isFasting ? "Fasting" : "Eating Window")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background((isFasting ? Color.purple : Color.green).opacity(0.15), in: Capsule())
                    .foregroundStyle(isFasting ? Color.purple : Color.green)
            }

            HStack(alignment: .firstTextBaseline) {
                Text(String(format: "%.1fh", hoursFasted))
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.purple)

                Text(isFasting ? "fasted of \(Int(proto.fastHours))h target" : "eating window open")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    toggleManualFast()
                } label: {
                    Text(isFasting ? "End Fast" : "Start Fast")
                        .font(.caption2.weight(.bold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            ProgressView(value: min(1.0, max(0.0, progress)))
                .tint(isFasting ? Color.purple : Color.green)

            Text(statusText)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .appleHealthCard(padding: 16)
    }

    private func evaluateFastingStatus(proto: FastingProtocol) -> (isFasting: Bool, hours: Double, progress: Double, statusText: String) {
        let todayFood = dayEntries
        if let firstMeal = todayFood.min(by: { $0.timestamp < $1.timestamp }), !profile.isManualFastActive {
            // First meal logged today -> Eating window is open
            let hoursSinceFirstMeal = Date.now.timeIntervalSince(firstMeal.timestamp) / 3600.0
            let windowRemaining = max(0.0, proto.eatingHours - hoursSinceFirstMeal)
            let progress = min(1.0, hoursSinceFirstMeal / max(1.0, proto.eatingHours))
            let status = windowRemaining > 0
                ? "Eating window closes in \(String(format: "%.1f", windowRemaining)) hours."
                : "Target eating window completed. Fasting begins after your last logged food."
            return (false, hoursSinceFirstMeal, progress, status)
        } else {
            // No meals logged today or manual fast forced -> Still fasting!
            let yesterdayKey = DayKey.addingDays(-1, to: activeDayKey)
            let yesterdayFood = foodEntries.filter { $0.dayKey == yesterdayKey }
            let lastMealTime = yesterdayFood.max(by: { $0.timestamp < $1.timestamp })?.timestamp ??
                Calendar.current.date(bySettingHour: 20, minute: 0, second: 0, of: Calendar.current.date(byAdding: .day, value: -1, to: .now)!)!
            let startTime = profile.isManualFastActive ? (profile.manualFastStartTime ?? lastMealTime) : lastMealTime
            let hoursFasted = max(0.0, Date.now.timeIntervalSince(startTime) / 3600.0)
            let progress = min(1.0, hoursFasted / max(1.0, proto.fastHours))
            let hoursRemaining = max(0.0, proto.fastHours - hoursFasted)
            let status = hoursRemaining > 0
                ? "\(String(format: "%.1f", hoursRemaining)) hours remaining until \(Int(proto.fastHours))h goal reached."
                : "Fasting goal reached! Eating window can open anytime."
            return (true, hoursFasted, progress, status)
        }
    }

    private func toggleManualFast() {
        if profile.isManualFastActive {
            profile.isManualFastActive = false
            profile.manualFastStartTime = nil
        } else {
            profile.isManualFastActive = true
            profile.manualFastStartTime = .now
        }
        try? modelContext.save()
    }

    private func todayWorkoutCard(digest: CoachingDashboardDigest) -> some View {
        let activeProgram = programs.first(where: \.isActive) ?? programs.first
        let targetWorkout: ProgramWorkout? = {
            if let prog = activeProgram, prog.scheduleMode == .rollingSplit {
                return prog.nextRollingWorkout
            }
            return activeProgram?.sortedWorkouts.first(where: { $0.name == digest.scheduledWorkoutName }) ?? activeProgram?.sortedWorkouts.first
        }()

        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                AppleSectionHeader(
                    title: activeProgram?.scheduleMode == .rollingSplit ? "Next Training" : "Today's Training",
                    icon: "dumbbell.fill",
                    color: AppleTheme.exercise,
                    subtitle: activeProgram?.name
                )
                Spacer()
                if let prog = activeProgram, prog.sortedWorkouts.count > 1 {
                    Menu {
                        ForEach(prog.sortedWorkouts) { w in
                            Button {
                                startWorkoutSession(from: w)
                            } label: {
                                HStack {
                                    Text(w.name)
                                    if w.id == targetWorkout?.id {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                        Divider()
                        Button("Freestyle Workout") {
                            startWorkoutSession(from: nil)
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text("Switch")
                                .font(.caption.weight(.semibold))
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption2)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.12), in: Capsule())
                    }
                }
            }

            if let workout = targetWorkout {
                HStack(spacing: 12) {
                    if let firstEx = workout.sortedSlots.first?.exercise {
                        ExerciseThumbnailView(exercise: firstEx, size: 48, cornerRadius: 12)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(activeProgram?.scheduleMode == .rollingSplit ? "Next Up: \(workout.name)" : (digest.isTodayTrainingDay ? workout.name : "Next: \(workout.name)"))
                            .font(.headline.weight(.semibold))
                        Text("\(workout.sortedSlots.count) exercises • \(workout.sortedSlots.reduce(0) { $0 + $1.sets }) working sets")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        previewGuideWorkout = workout
                    } label: {
                        Image(systemName: "photo")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Workout Guide")

                    Button {
                        startWorkoutSession(from: workout)
                    } label: {
                        Text("Start")
                            .font(.subheadline.weight(.bold))
                            .padding(.horizontal, 8)
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                HStack {
                    Text("Rest day or freestyle workout")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Freestyle") {
                        startWorkoutSession(from: nil)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .appleHealthCard(padding: 18)
    }

    @ViewBuilder
    private var externalWorkoutsSection: some View {
        let external = healthService.todayExternalWorkouts
        if !external.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Today's Apple Fitness Workouts", systemImage: "figure.run.circle.fill")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.orange)
                    Spacer()
                    Text("Display Only")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                ForEach(external) { wk in
                    HStack(spacing: 12) {
                        Text(wk.emoji)
                            .font(.title2)
                            .frame(width: 38, height: 38)
                            .background(Color.orange.opacity(0.12), in: Circle())

                        VStack(alignment: .leading, spacing: 2) {
                            Text(wk.title)
                                .font(.subheadline.weight(.semibold))
                            HStack(spacing: 6) {
                                Text("\(wk.durationMinutes) min")
                                Text("•")
                                Text("\(Int(wk.activeCalories)) kcal")
                                Text("•")
                                Text(wk.sourceAppName)
                            }
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Text(wk.startDate, format: .dateTime.hour().minute())
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .padding(10)
                    .background(AppleTheme.cardSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            .appleHealthCard(padding: 16)
        }
    }

    private var healthTelemetryCard: some View {
        let stats = healthService.todayStats
        return VStack(alignment: .leading, spacing: 14) {
            AppleSectionHeader(
                title: "Apple Health Context",
                icon: "heart.fill",
                color: .pink,
                subtitle: "Display Only • Never Alters Coaching Targets"
            )

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                telemetryTile(
                    title: "Live / Recent HR",
                    value: {
                        let bpm = healthService.currentLiveHeartRateBPM ?? stats.currentHeartRateBPM
                        return bpm.map { "\(Int($0.rounded())) bpm" } ?? "—"
                    }(),
                    icon: "heart.fill",
                    color: .red
                )
                telemetryTile(
                    title: "Resting HR / HRV",
                    value: {
                        let rhr = stats.restingHeartRateBPM.map { "\(Int($0.rounded()))bpm" } ?? "—"
                        let hrv = stats.hrvSDNNMilliseconds.map { "\(Int($0.rounded()))ms" } ?? "—"
                        return "\(rhr) • \(hrv)"
                    }(),
                    icon: "waveform.path.ecg",
                    color: .pink
                )
                telemetryTile(title: "Steps", value: "\(stats.stepsToday)", icon: "figure.walk", color: .green)
                telemetryTile(title: "Watch Active", value: "\(Int(stats.activeCaloriesDisplayOnly)) kcal", icon: "applewatch", color: .orange)
                telemetryTile(
                    title: "Sleep",
                    value: stats.sleepHoursLastNight.map { String(format: "%.1f hr", $0) } ?? "—",
                    icon: "bed.double.fill",
                    color: .indigo
                )
                if let minB = stats.minHeartRateBPM, let maxB = stats.maxHeartRateBPM {
                    telemetryTile(
                        title: "Daily HR Range",
                        value: "\(Int(minB.rounded())) – \(Int(maxB.rounded())) bpm",
                        icon: "heart.text.square.fill",
                        color: .purple
                    )
                }
            }
        }
        .appleHealthCard(padding: 18)
    }

    private func telemetryTile(title: String, value: String, icon: String, color: Color = .secondary) -> some View {
        HStack(spacing: 10) {
            AppleIconBadge(icon: icon, color: color, size: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption2).foregroundStyle(.secondary)
                Text(value).font(.system(size: 15, weight: .bold, design: .rounded)).monospacedDigit()
            }
            Spacer()
        }
        .padding(10)
        .background(AppleTheme.cardSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Actions

    private func toggleDayComplete() {
        if let existing = dayNote {
            existing.isComplete.toggle()
        } else {
            modelContext.insert(DailyNote(dayKey: activeDayKey, isComplete: true))
        }
        try? modelContext.save()
        _ = CoachingCoordinator.evaluate(forDayKey: activeDayKey, context: modelContext)
    }

    private func totalNutrients(for entries: [FoodLogEntry]) -> NutrientsPer100g {
        var total = NutrientsPer100g()
        for e in entries {
            total.calories += e.calories
            total.protein += e.protein
            total.carbs += e.carbs
            total.fat += e.fat
        }
        return total
    }

    private func startWorkoutSession(from programWorkout: ProgramWorkout?) {
        let defaultGym = gymProfiles.first(where: \.isDefault) ?? gymProfiles.first
        let session = WorkoutSession(
            title: programWorkout?.name ?? "Freestyle Strength",
            programWorkout: programWorkout,
            gymProfile: defaultGym,
            start: .now
        )
        modelContext.insert(session)

        if let pw = programWorkout {
            let digest = CoachingCoordinator.evaluate(context: modelContext)
            let allExercises = (try? modelContext.fetch(FetchDescriptor<Exercise>())) ?? []
            let exerciseByID = Dictionary(allExercises.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            let allowedEquip = Set(defaultGym?.availableEquipment ?? Equipment.allCases)

            var orderCounter = 0
            for slot in pw.sortedSlots {
                guard let baseEx = slot.exercise else { continue }
                let swappedBlueprint = ProgramGeneratorEngine.autoSwapIfNeeded(
                    exercise: baseEx.asBlueprint,
                    availableEquipment: allowedEquip,
                    maxDumbbellKg: defaultGym?.maxDumbbellKg ?? 50,
                    pool: allExercises.map(\.asBlueprint)
                )
                let targetEx = exerciseByID[swappedBlueprint.id] ?? baseEx
                let historySamples = (targetEx.setLogs ?? [])
                    .filter(\.isCompleted)
                    .map { LoggedSetSample(sessionDate: $0.session?.start ?? $0.timestamp, weightKg: $0.weightKg, reps: $0.reps, rir: $0.rir, setType: $0.type) }

                let inc = defaultGym?.effectiveIncrementKg(for: targetEx) ?? targetEx.loadIncrementKg
                let suggestion = ProgressionEngine.suggestNextSession(
                    history: historySamples,
                    repRangeLow: slot.repRangeLow,
                    repRangeHigh: slot.repRangeHigh,
                    targetRIR: slot.targetRIR,
                    loadIncrementKg: inc,
                    personalK: targetEx.personalRepCurveK,
                    weeklyWeightChangePercentBW: digest.weightSummary.weeklyRatePercentBW,
                    avgProteinLast7d: digest.avgProteinLast7d,
                    proteinFloor: digest.todayTargets.proteinFloor
                )

                for _ in 0..<slot.sets {
                    let setLog = SetLog(
                        order: orderCounter,
                        session: session,
                        exercise: targetEx,
                        weightKg: suggestion.suggestedWeightKg,
                        reps: suggestion.suggestedReps,
                        rir: slot.targetRIR,
                        type: .working,
                        supersetGroup: slot.supersetGroup,
                        isCompleted: false
                    )
                    modelContext.insert(setLog)
                    orderCounter += 1
                }
            }
        }

        try? modelContext.save()
        appState.activeWorkoutSessionID = session.id
        appState.showingActiveWorkoutFullScreen = true
        PhoneWatchSyncService.shared.pushCurrentState(context: modelContext)
    }
}
