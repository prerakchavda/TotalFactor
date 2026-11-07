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
    @AppStorage(FoodTrackingPreference.key) private var foodTrackingEnabled: Bool = true

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
                VStack(alignment: .leading, spacing: 14) {
                    dashboardHeader

                    dayHeaderBar(isComplete: dayNote?.isComplete ?? false)

                    if foodTrackingEnabled {
                        if yesterdayUnmarkedWithFood {
                            yesterdayCompleteBanner
                        }

                        if isCheckInDue {
                            checkInReadyBanner
                        }

                        MFSectionTitle("Nutrition", actionTitle: "Micros") {
                            showingMicronutrients = true
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

                        MFSectionTitle("Insights & Analytics")

                        coachingMetricsRow(digest: digest)

                        energyBalanceCard(digest: digest)
                    }

                    if profile.enableIntermittentFasting {
                        intermittentFastingCard
                    }

                    MFSectionTitle("Training")

                    todayWorkoutCard(digest: digest)

                    externalWorkoutsSection

                    MFSectionTitle("Health")

                    healthTelemetryCard
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .background(AppleTheme.background)
            .refreshable {
                await healthService.refreshTodayDashboardTelemetry()
            }
            .task {
                await healthService.refreshTodayDashboardTelemetry()
                healthService.startLiveHeartRateObserver()
            }
            .toolbar(.hidden, for: .navigationBar)
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

    /// MacroFactor-style wide all-caps page title with round quick-action buttons
    private var dashboardHeader: some View {
        HStack(alignment: .center, spacing: 10) {
            MFDisplayTitle("Dashboard")
            Spacer()
            if foodTrackingEnabled {
                Button {
                    appState.showingWeeklyCheckInSheet = true
                } label: {
                    MFCircleIcon("checkmark.seal")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Weekly Check-In")
            }

            Button {
                appState.showingWeighInSheet = true
            } label: {
                MFCircleIcon("scalemass")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Log Weight")
        }
        .padding(.top, 8)
    }

    private func dayHeaderBar(isComplete: Bool) -> some View {
        HStack(spacing: 8) {
            Button {
                appState.selectedDayKey = DayKey.addingDays(-1, to: activeDayKey)
            } label: {
                MFCircleIcon("chevron.left", size: 32)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Previous Day")

            Button {
                appState.selectedDayKey = DayKey.today
            } label: {
                HStack(spacing: 6) {
                    Text(DayKey.displayTitle(for: activeDayKey))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)
                    if activeDayKey != DayKey.today {
                        Text("Jump to Today")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 32)
                .background(Capsule().fill(AppleTheme.cardSurface))
            }
            .buttonStyle(.plain)

            if foodTrackingEnabled {
                Button {
                    toggleDayComplete()
                } label: {
                    Image(systemName: isComplete ? "checkmark" : "circle.dashed")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(isComplete ? AppleTheme.background : Color.secondary)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(isComplete ? Color.primary : AppleTheme.tertiarySurface))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isComplete ? "Day Complete" : "Mark Day Complete")
            }

            Button {
                appState.selectedDayKey = DayKey.addingDays(1, to: activeDayKey)
            } label: {
                MFCircleIcon("chevron.right", size: 32)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Next Day")
        }
    }

    private var yesterdayCompleteBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .foregroundStyle(AppleTheme.accent)
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
            .buttonStyle(.mfPrimaryCompact)
        }
        .mfCard(padding: 12, cornerRadius: 14)
    }

    /// MacroFactor "Check In — it's time" hero: inverted circle on a flat card
    private var checkInReadyBanner: some View {
        Button {
            appState.showingWeeklyCheckInSheet = true
        } label: {
            HStack(spacing: 16) {
                VStack(spacing: 0) {
                    Text("Check In")
                        .font(.system(size: 15, weight: .heavy))
                    Text("it's time")
                        .font(.system(size: 10, weight: .medium))
                        .opacity(0.7)
                }
                .foregroundStyle(AppleTheme.background)
                .frame(width: 84, height: 84)
                .background(Circle().fill(Color.primary))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Weekly Check-In Ready")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.primary)
                    Text("Review expenditure, weight velocity, training volume & updated macro targets.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }
            .mfCard(padding: 16)
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
                    .buttonStyle(.mfPrimaryCompact)
            }
        }
        .appleHealthCard(padding: 14)
    }

    private func macroZonesCard(eaten: NutrientsPer100g, targets: MacroTargets, isTrainingDay: Bool) -> some View {
        let caloriesRemaining = max(0, targets.calories - eaten.calories)

        // MacroFactor Nutrition widget: calories, protein, fat, carbs as tall bars
        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(Int(caloriesRemaining.rounded()))")
                    .font(.system(size: 34, weight: .heavy))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                Text("Cal remaining")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if profile.enableTrainingDayCarbCycling {
                    Text(isTrainingDay ? "Training Day" : "Rest Day")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(AppleTheme.tertiarySurface))
                }
            }

            HStack(alignment: .bottom, spacing: 8) {
                MFNutrientBarColumn(
                    title: "Calories",
                    value: eaten.calories,
                    target: targets.calories,
                    unit: "",
                    color: AppleTheme.calories
                )
                MFNutrientBarColumn(
                    title: "Protein",
                    value: eaten.protein,
                    target: targets.protein,
                    unit: "g",
                    color: AppleTheme.protein
                )
                MFNutrientBarColumn(
                    title: "Fat",
                    value: eaten.fat,
                    target: targets.fat,
                    unit: "g",
                    color: AppleTheme.fat
                )
                MFNutrientBarColumn(
                    title: "Carbs",
                    value: eaten.carbs,
                    target: targets.carbs,
                    unit: "g",
                    color: AppleTheme.carbs
                )
            }
        }
        .mfCard(padding: 18)
    }

    private func coachingMetricsRow(digest: CoachingDashboardDigest) -> some View {
        HStack(spacing: 12) {
            // Trend Weight Card (Apple Health Style - Clickable to Weight Detail & History)
            NavigationLink(destination: WeightDetailView()) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Weight Trend")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.tertiary)
                    }

                    if let trendKg = digest.weightSummary.latestTrendKg {
                        Text(UnitsFormatter.formatWeight(trendKg, system: profile.unitSystem))
                            .font(.system(size: 24, weight: .bold))
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

                    HStack {
                        Text("View History")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(AppleTheme.trend)
                        Spacer()
                        Button {
                            appState.showingWeighInSheet = true
                        } label: {
                            Label("Log", systemImage: "plus")
                                .font(.caption2.weight(.semibold))
                        }
                        .buttonStyle(.mfChip)
                        .controlSize(.mini)
                    }
                }
                .appleHealthCard(padding: 16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            // Adaptive Expenditure Card (Apple Health Style)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Expenditure")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)
                    Spacer()
                }

                Text("\(Int(digest.expenditure.expenditureKcal.rounded())) kcal")
                    .font(.system(size: 24, weight: .bold))
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
                AppleIconBadge(icon: "flame.fill", color: isDeficit ? AppleTheme.calories : AppleTheme.protein, size: 24)
                Text("Energy Balance (Intake vs. TDEE)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(isDeficit ? "In Deficit" : (absDelta < 25 ? "Balanced" : "In Surplus"))
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background((isDeficit ? AppleTheme.calories : AppleTheme.protein).opacity(0.15), in: Capsule())
                    .foregroundStyle(isDeficit ? AppleTheme.calories : AppleTheme.protein)
            }

            HStack(alignment: .firstTextBaseline) {
                Text("\(isDeficit ? "−" : "+")\(absDelta) kcal")
                    .font(.system(size: 26, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(isDeficit ? AppleTheme.calories : AppleTheme.protein)

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
                    .font(.system(size: 26, weight: .bold))
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
                .buttonStyle(.mfChip)
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
                    .buttonStyle(.mfChip)
                    .accessibilityLabel("Workout Guide")

                    Button {
                        startWorkoutSession(from: workout)
                    } label: {
                        Text("Start")
                            .font(.subheadline.weight(.bold))
                            .padding(.horizontal, 8)
                    }
                    .buttonStyle(.mfPrimaryCompact)
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
                    .buttonStyle(.mfChip)
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
                Text(value).font(.system(size: 15, weight: .bold)).monospacedDigit()
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
        if let open = WorkoutHistoryService.openSession(context: modelContext) {
            appState.activeWorkoutSessionID = open.id
            appState.showingActiveWorkoutFullScreen = true
            return
        }
        let defaultGym = gymProfiles.first(where: \.isDefault) ?? gymProfiles.first
        let session = WorkoutSession(
            title: programWorkout?.name ?? "Freestyle Strength",
            programWorkout: programWorkout,
            gymProfile: defaultGym,
            start: .now
        )
        modelContext.insert(session)

        if let pw = programWorkout {
            WorkoutPlannerService.populate(session: session, from: pw, gym: defaultGym, context: modelContext)
        }

        try? modelContext.save()
        appState.activeWorkoutSessionID = session.id
        appState.showingActiveWorkoutFullScreen = true
        PhoneWatchSyncService.shared.pushCurrentState(context: modelContext)
    }
}
