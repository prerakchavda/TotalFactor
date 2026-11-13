import SwiftUI
import SwiftData

struct TodayDashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
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
    @Query(filter: #Predicate<WorkoutSession> { $0.end == nil }) private var openWorkoutSessions: [WorkoutSession]

    @State private var showingMicronutrients: Bool = false
    @State private var previewGuideWorkout: ProgramWorkout? = nil
    @AppStorage(FoodTrackingPreference.key) private var foodTrackingEnabled: Bool = true
    @AppStorage("totalfactor.todaySubTab") private var storedSubTabRaw: String = TodaySubTab.overview.rawValue

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

    // MARK: - Sub-tabs (Overview · Nutrition · Activity)

    /// Sub-tabs shown at the top of the dashboard. Nutrition is hidden when food tracking is off.
    private var visibleSubTabs: [TodaySubTab] {
        foodTrackingEnabled ? [.overview, .nutrition, .activity] : [.overview, .activity]
    }

    /// The remembered sub-tab, falling back to Overview when it isn't currently available
    /// (e.g. Nutrition was last selected but food tracking has since been turned off).
    private var effectiveSubTab: TodaySubTab {
        let stored = TodaySubTab(rawValue: storedSubTabRaw) ?? .overview
        return visibleSubTabs.contains(stored) ? stored : .overview
    }

    private var subTabSelection: Binding<TodaySubTab> {
        Binding(
            get: { effectiveSubTab },
            set: { storedSubTabRaw = $0.rawValue }
        )
    }

    private func selectSubTab(_ tab: TodaySubTab) {
        withAnimation(.easeInOut(duration: 0.2)) {
            storedSubTabRaw = tab.rawValue
        }
    }

    var body: some View {
        let digest = CoachingCoordinator.cachedOrComputeDigest(forDayKey: activeDayKey, context: modelContext)
        let targets = digest.todayTargets
        let eaten = totalNutrients(for: dayEntries)
        let currentTab = effectiveSubTab

        NavigationStack {
            VStack(spacing: 0) {
                // Pinned header: title, day switcher and sub-tab picker stay visible while content scrolls.
                VStack(alignment: .leading, spacing: 14) {
                    dashboardHeader

                    dayHeaderBar(isComplete: dayNote?.isComplete ?? false)
                }
                .padding(.horizontal)
                .padding(.bottom, 10)

                SubTabBar(tabs: visibleSubTabs, selection: subTabSelection) { tab in
                    tab.title
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        switch currentTab {
                        case .overview:
                            overviewTab(digest: digest, targets: targets, eaten: eaten)
                        case .nutrition:
                            nutritionTab(digest: digest, targets: targets, eaten: eaten)
                        case .activity:
                            activityTab(digest: digest)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 4)
                    .padding(.bottom, 24)
                }
                .id(currentTab)
                .refreshable {
                    await healthService.refreshTodayDashboardTelemetry()
                }
            }
            .background(AppleTheme.background)
            .task {
                await healthService.refreshTodayDashboardTelemetry()
                healthService.startLiveHeartRateObserver()
            }
            .onAppear {
                normalizeStoredSubTab()
            }
            .onChange(of: foodTrackingEnabled) { _, _ in
                normalizeStoredSubTab()
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

    // MARK: - Sub-tab Content

    /// Overview: banners, at-a-glance nutrition & weight, and today's planned workout.
    @ViewBuilder
    private func overviewTab(digest: CoachingDashboardDigest, targets: MacroTargets, eaten: NutrientsPer100g) -> some View {
        if let openSession = openWorkoutSessions.first {
            activeWorkoutBanner(openSession)
        }

        if foodTrackingEnabled {
            if yesterdayUnmarkedWithFood {
                yesterdayCompleteBanner
            }

            if isCheckInDue {
                checkInReadyBanner
            }

            MFSectionTitle("Today", actionTitle: "Nutrition") {
                selectSubTab(.nutrition)
            }

            nutritionSnapshotCard(eaten: eaten, targets: targets)

            coachingMetricsRow(digest: digest)
        } else {
            MFSectionTitle("Today")

            weightTrendCard(digest: digest)
        }

        if profile.enableIntermittentFasting {
            intermittentFastingCard
        }

        MFSectionTitle("Training", actionTitle: "Activity") {
            selectSubTab(.activity)
        }

        todayWorkoutCard(digest: digest)
    }

    /// Nutrition: full macro detail, coaching nudges, meal breakdown and energy balance.
    @ViewBuilder
    private func nutritionTab(digest: CoachingDashboardDigest, targets: MacroTargets, eaten: NutrientsPer100g) -> some View {
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

        MFSectionTitle("Meals")

        mealBreakdownCard

        MFSectionTitle("Insights & Analytics")

        energyBalanceCard(digest: digest)
    }

    /// Activity: what was trained/logged today, Apple Fitness workouts and Apple Health telemetry.
    @ViewBuilder
    private func activityTab(digest: CoachingDashboardDigest) -> some View {
        MFSectionTitle("Training")

        TodayLoggedActivityCard(
            dayKey: activeDayKey,
            unitSystem: profile.unitSystem,
            isTrainingDay: digest.isTodayTrainingDay,
            scheduledWorkoutName: digest.scheduledWorkoutName
        )

        externalWorkoutsSection

        MFSectionTitle("Health")

        healthTelemetryCard
    }

    /// Falls back to Overview when the remembered sub-tab isn't available (Nutrition with food tracking off).
    private func normalizeStoredSubTab() {
        let stored = TodaySubTab(rawValue: storedSubTabRaw) ?? .overview
        if !visibleSubTabs.contains(stored) {
            storedSubTabRaw = TodaySubTab.overview.rawValue
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

    /// Compact calories + macros summary for Overview; tapping opens the Nutrition sub-tab.
    private func nutritionSnapshotCard(eaten: NutrientsPer100g, targets: MacroTargets) -> some View {
        let caloriesRemaining = max(0, targets.calories - eaten.calories)

        return Button {
            selectSubTab(.nutrition)
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(Int(caloriesRemaining.rounded()))")
                        .font(.system(size: 28, weight: .heavy))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                    Text("Cal remaining")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(eaten.calories.rounded())) / \(Int(targets.calories.rounded()))")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.tertiary)
                }

                HStack(spacing: 12) {
                    macroSnapshotColumn(title: "Protein", value: eaten.protein, target: targets.protein, color: AppleTheme.protein)
                    macroSnapshotColumn(title: "Fat", value: eaten.fat, target: targets.fat, color: AppleTheme.fat)
                    macroSnapshotColumn(title: "Carbs", value: eaten.carbs, target: targets.carbs, color: AppleTheme.carbs)
                }
            }
            .mfCard(padding: 16)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Nutrition summary, \(Int(caloriesRemaining.rounded())) calories remaining")
    }

    private func macroSnapshotColumn(title: String, value: Double, target: Double, color: Color) -> some View {
        let fraction: Double = target > 0 ? min(1.0, max(0.0, value / target)) : 0.0

        return VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("\(Int(value.rounded())) / \(Int(target.rounded()))g")
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(.primary)
            ProgressView(value: fraction)
                .tint(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Per-meal totals for the selected day (Nutrition sub-tab).
    private var mealBreakdownCard: some View {
        let entries = dayEntries
        let tagsInUse: [MealTag] = MealTag.allCases.filter { tag in
            entries.contains { $0.mealTag == tag }
        }

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("\(entries.count) \(entries.count == 1 ? "food" : "foods") logged")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)
                Spacer()
                Button {
                    appState.openQuickAdd(tab: 0)
                } label: {
                    Label("Log Food", systemImage: "plus")
                        .font(.caption2.weight(.semibold))
                }
                .buttonStyle(.mfChip)
                .controlSize(.mini)
            }

            if tagsInUse.isEmpty {
                Text("Nothing logged yet for this day.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(tagsInUse) { tag in
                    let mealEntries = entries.filter { $0.mealTag == tag }
                    let mealCalories = mealEntries.reduce(0.0) { $0 + $1.calories }
                    let mealProtein = mealEntries.reduce(0.0) { $0 + $1.protein }
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tag.displayName)
                                .font(.subheadline.weight(.semibold))
                            Text(mealEntries.map(\.foodName).joined(separator: ", "))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(Int(mealCalories.rounded())) kcal")
                                .font(.caption.weight(.bold).monospacedDigit())
                            Text("\(Int(mealProtein.rounded()))g protein")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(AppleTheme.protein)
                        }
                    }
                    .padding(10)
                    .background(AppleTheme.cardSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
        .appleHealthCard(padding: 16)
    }

    /// Shown on Overview while a workout is still open, so it can be resumed in one tap.
    private func activeWorkoutBanner(_ session: WorkoutSession) -> some View {
        Button {
            appState.activeWorkoutSessionID = session.id
            appState.showingActiveWorkoutFullScreen = true
        } label: {
            HStack(spacing: 12) {
                AppleIconBadge(icon: "figure.strengthtraining.traditional", color: AppleTheme.exercise, size: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Workout in Progress")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)
                    Text("\(session.title) • \(session.completedSetCount) sets done")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Text("Resume")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppleTheme.background)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.primary))
            }
            .appleHealthCard(padding: 14)
        }
        .buttonStyle(.plain)
    }

    private func coachingMetricsRow(digest: CoachingDashboardDigest) -> some View {
        HStack(spacing: 12) {
            weightTrendCard(digest: digest)

            expenditureCard(digest: digest)
        }
    }

    /// Trend Weight Card (Apple Health Style - Clickable to Weight Detail & History)
    private func weightTrendCard(digest: CoachingDashboardDigest) -> some View {
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
    }

    /// Adaptive Expenditure Card (Apple Health Style)
    private func expenditureCard(digest: CoachingDashboardDigest) -> some View {
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
            HStack(alignment: .top) {
                AppleSectionHeader(
                    title: "Apple Health Context",
                    icon: "heart.fill",
                    color: .pink,
                    subtitle: healthService.lastShortcutsSyncDate.map {
                        "Shortcuts Synced \($0.formatted(date: .omitted, time: .shortened)) • Display Only"
                    } ?? "Display Only • Never Alters Coaching Targets"
                )
                Spacer()
                Button {
                    if let url = ShortcutsHealthBridge.syncShortcutURL {
                        openURL(url)
                    }
                } label: {
                    Label("Sync", systemImage: "bolt.heart.fill")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.mfChip)
                .controlSize(.small)
            }

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

/// Sub-tabs inside the Today dashboard so each focused section fits without a long scroll.
private enum TodaySubTab: String, CaseIterable, Identifiable {
    case overview
    case nutrition
    case activity

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return "Overview"
        case .nutrition: return "Nutrition"
        case .activity: return "Activity"
        }
    }
}
