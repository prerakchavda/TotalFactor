import SwiftUI
import SwiftData

struct RootTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState

    @Query private var profiles: [UserProfile]
    @Query(filter: #Predicate<WorkoutSession> { $0.end == nil }) private var openSessions: [WorkoutSession]

    private var profile: UserProfile {
        profiles.first ?? CoachingCoordinator.fetchOrCreateProfile(context: modelContext)
    }

    @State private var keyboardVisible: Bool = false
    @State private var showingCardioLog: Bool = false
    @AppStorage(FoodTrackingPreference.key) private var foodTrackingEnabled: Bool = true

    var body: some View {
        @Bindable var state = appState

        VStack(spacing: 0) {
            // System tab bar is hidden (MFAppearance + .toolbar(.hidden)); MacroFactor chrome is drawn below.
            TabView(selection: $state.selectedTab) {
                TodayDashboardView()
                    .toolbar(.hidden, for: .tabBar)
                    .tag(AppTab.today)

                // Keep the same number of tab pages whether food tracking is on or off: inserting/removing a
                // TabView child while another tab is showing (e.g. flipping the switch in Settings) blanks the
                // current screen until relaunch. The custom tab bar below hides the Food tab when it's off.
                Group {
                    if foodTrackingEnabled {
                        FoodTimelineView()
                    } else {
                        Color.clear
                    }
                }
                .toolbar(.hidden, for: .tabBar)
                .tag(AppTab.food)

                TrainHubView()
                    .toolbar(.hidden, for: .tabBar)
                    .tag(AppTab.train)

                ProgressHubView()
                    .toolbar(.hidden, for: .tabBar)
                    .tag(AppTab.progress)

                SettingsView()
                    .toolbar(.hidden, for: .tabBar)
                    .tag(AppTab.settings)
            }

            if !keyboardVisible {
                bottomChrome
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            // Only collapse the bottom chrome for keyboards in the tabs themselves; a keyboard inside a
            // sheet would otherwise resize the root screen showing behind it.
            keyboardVisible = !Self.isPresentingModal
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardVisible = false
        }
        .sheet(isPresented: $state.showingQuickAddFood) {
            QuickAddFoodSheet(
                dayKey: state.selectedDayKey,
                initialTab: state.quickAddInitialTab,
                defaultMealTag: state.quickAddDefaultMealTag,
                autoStartDictation: state.quickAddAutoStartDictation
            )
        }
        .sheet(isPresented: $state.showingWeighInSheet) {
            QuickWeighInSheet()
                .presentationDetents([.height(320)])
        }
        .sheet(isPresented: $state.showingWeeklyCheckInSheet) {
            WeeklyCheckInSheet()
        }
        .sheet(isPresented: $showingCardioLog) {
            CardioLogSheet(unitSystem: profile.unitSystem)
        }
        .fullScreenCover(isPresented: $state.showingActiveWorkoutFullScreen) {
            if let session = openSessions.first(where: { $0.id == state.activeWorkoutSessionID }) ?? openSessions.first {
                ActiveWorkoutView(session: session)
            } else {
                NavigationStack {
                    ContentUnavailableView("No Active Session", systemImage: "dumbbell")
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Close") { state.showingActiveWorkoutFullScreen = false }
                            }
                        }
                }
            }
        }
        .fullScreenCover(
            isPresented: Binding(
                get: { !profile.onboardingCompleted },
                set: { _ in }
            )
        ) {
            OnboardingFlowView(profile: profile)
        }
        .onAppear {
            for arg in ProcessInfo.processInfo.arguments {
                if arg.starts(with: "--tab="), let tab = AppTab(rawValue: String(arg.dropFirst("--tab=".count))) {
                    state.selectedTab = tab
                }
            }
            if !foodTrackingEnabled && state.selectedTab == .food {
                state.selectedTab = .today
            }
        }
        .onChange(of: foodTrackingEnabled) { _, enabled in
            if !enabled && state.selectedTab == .food {
                state.selectedTab = .today
            }
        }
        .onOpenURL { url in
            guard url.scheme?.lowercased() == "totalfactor" else { return }
            if ShortcutsHealthBridge.isBridgeURL(url) {
                let defaultUnit = profiles.first?.unitSystem ?? .imperial
                if let payload = ShortcutsHealthBridge.parseURL(url, defaultUnitSystem: defaultUnit) {
                    let summary = ShortcutsHealthBridge.apply(payload, context: modelContext)
                    state.selectedTab = .today
                    state.shortcutSyncToastMessage = summary
                }
                return
            }
            let tabKey = url.host ?? url.pathComponents.dropFirst().first ?? ""
            if let tab = AppTab(rawValue: tabKey), tab != .food || foodTrackingEnabled {
                state.selectedTab = tab
            }
        }
        .alert(
            "Apple Health Shortcuts Sync",
            isPresented: Binding(
                get: { state.shortcutSyncToastMessage != nil },
                set: { if !$0 { state.shortcutSyncToastMessage = nil } }
            )
        ) {
            Button("Done", role: .cancel) { state.shortcutSyncToastMessage = nil }
        } message: {
            Text(state.shortcutSyncToastMessage ?? "")
        }
    }

    private static var isPresentingModal: Bool {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController?
            .presentedViewController != nil
    }

    // MARK: - MacroFactor Bottom Chrome (mini-bar, food search dock, tab bar)

    private var bottomChrome: some View {
        VStack(spacing: 10) {
            if let activeSession = openSessions.first, !appState.showingActiveWorkoutFullScreen {
                ActiveWorkoutMiniBar(session: activeSession) {
                    appState.activeWorkoutSessionID = activeSession.id
                    appState.showingActiveWorkoutFullScreen = true
                }
                .padding(.horizontal, 14)
            }

            if foodTrackingEnabled && (appState.selectedTab == .today || appState.selectedTab == .food) {
                MFFoodSearchDock(
                    onSearch: { appState.openQuickAdd(tab: 0) },
                    onScan: { appState.openQuickAdd(tab: 1) },
                    onDescribe: { appState.openQuickAdd(tab: 5) }
                )
                .padding(.horizontal, 14)
            }

            MFTabBar(
                selection: appState.selectedTab,
                hasOpenWorkout: !openSessions.isEmpty,
                foodTrackingEnabled: foodTrackingEnabled,
                onSelect: { appState.selectedTab = $0 },
                onLogFood: { appState.openQuickAdd(tab: 0) },
                onDescribeMeal: { appState.openQuickAdd(tab: 5) },
                onScanBarcode: { appState.openQuickAdd(tab: 1) },
                onQuickAdd: { appState.openQuickAdd(tab: 3) },
                onLogWeight: { appState.showingWeighInSheet = true },
                onCheckIn: { appState.showingWeeklyCheckInSheet = true },
                onWorkout: {
                    if let open = openSessions.first {
                        appState.activeWorkoutSessionID = open.id
                        appState.showingActiveWorkoutFullScreen = true
                    } else {
                        appState.selectedTab = .train
                    }
                },
                onLogCardio: { showingCardioLog = true }
            )
        }
        .padding(.top, 8)
        .background(AppleTheme.background.ignoresSafeArea(edges: .bottom))
    }
}

/// MacroFactor floating "Search for a food" pill with inline barcode button and AI describe button
private struct MFFoodSearchDock: View {
    let onSearch: () -> Void
    let onScan: () -> Void
    let onDescribe: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onSearch) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Search for a food")
                        .font(.subheadline)
                    Spacer(minLength: 4)
                }
                .foregroundStyle(.secondary)
                .padding(.leading, 16)
                .padding(.trailing, 52)
                .frame(height: 46)
                .background(Capsule().fill(AppleTheme.cardSurface))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Search for a food")
            .overlay(alignment: .trailing) {
                Button(action: onScan) {
                    Image(systemName: "barcode.viewfinder")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 4)
                .accessibilityLabel("Scan Barcode")
            }

            Button(action: onDescribe) {
                Image(systemName: "sparkles")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 46, height: 46)
                    .background(Circle().fill(AppleTheme.cardSurface))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Describe a Meal")
        }
    }
}

/// MacroFactor bottom navigation: icon + label tabs with a center inverted "+" quick-action button
private struct MFTabBar: View {
    let selection: AppTab
    let hasOpenWorkout: Bool
    let foodTrackingEnabled: Bool
    let onSelect: (AppTab) -> Void
    let onLogFood: () -> Void
    let onDescribeMeal: () -> Void
    let onScanBarcode: () -> Void
    let onQuickAdd: () -> Void
    let onLogWeight: () -> Void
    let onCheckIn: () -> Void
    let onWorkout: () -> Void
    let onLogCardio: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            tabButton(.today, title: "Dashboard", icon: "square.grid.2x2", selectedIcon: "square.grid.2x2.fill")
            if foodTrackingEnabled {
                tabButton(.food, title: "Food Log", icon: "fork.knife", selectedIcon: "fork.knife")
            }
            addMenu
            tabButton(.train, title: "Workouts", icon: "dumbbell", selectedIcon: "dumbbell.fill")
            tabButton(.progress, title: "Progress", icon: "chart.xyaxis.line", selectedIcon: "chart.xyaxis.line")
            tabButton(.settings, title: "More", icon: "ellipsis.circle", selectedIcon: "ellipsis.circle.fill")
        }
        .padding(.top, 8)
        .padding(.bottom, 2)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(AppleTheme.hairline)
                .frame(height: 0.5)
        }
        .sensoryFeedback(.selection, trigger: selection)
    }

    private func tabButton(_ tab: AppTab, title: String, icon: String, selectedIcon: String) -> some View {
        let isSelected = selection == tab
        return Button {
            onSelect(tab)
        } label: {
            VStack(spacing: 4) {
                Image(systemName: isSelected ? selectedIcon : icon)
                    .font(.system(size: 19, weight: isSelected ? .semibold : .regular))
                    .frame(height: 24)
                Text(title)
                    .font(.system(size: 10, weight: isSelected ? .bold : .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(isSelected ? Color.primary : Color.secondary)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var addMenu: some View {
        Menu {
            if foodTrackingEnabled {
                Button(action: onLogFood) {
                    Label("Log Food", systemImage: "magnifyingglass")
                }
                Button(action: onDescribeMeal) {
                    Label("Describe a Meal", systemImage: "sparkles")
                }
                Button(action: onScanBarcode) {
                    Label("Scan Barcode", systemImage: "barcode.viewfinder")
                }
                Button(action: onQuickAdd) {
                    Label("Quick Add Macros", systemImage: "bolt.fill")
                }
                Divider()
            }
            Button(action: onLogWeight) {
                Label("Log Weight", systemImage: "scalemass")
            }
            Button(action: onWorkout) {
                Label(hasOpenWorkout ? "Resume Workout" : "Start a Workout", systemImage: "dumbbell")
            }
            Button(action: onLogCardio) {
                Label("Log Cardio", systemImage: "figure.run")
            }
            if foodTrackingEnabled {
                Button(action: onCheckIn) {
                    Label("Weekly Check-In", systemImage: "checkmark.seal")
                }
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(AppleTheme.background)
                .frame(width: 46, height: 46)
                .background(Circle().fill(Color.primary))
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
        }
        .menuOrder(.fixed)
        .accessibilityLabel("Add")
    }
}

private struct ActiveWorkoutMiniBar: View {
    @Environment(RestTimerService.self) private var restTimer
    let session: WorkoutSession
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.headline)
                    .foregroundStyle(.black)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(AppleTheme.exercise))

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(session.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        if session.isPaused {
                            Text("PAUSED")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.yellow)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1.5)
                                .background(Color.yellow.opacity(0.18), in: Capsule())
                        }
                    }
                    if restTimer.isRunning {
                        Text("Rest: \(restTimer.remainingSeconds)s • \(restTimer.exerciseName)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.orange)
                    } else if session.isPaused {
                        Text("Workout paused • Tap to resume")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                    } else {
                        Text("\(session.completedSetCount) sets logged • Tap to open")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if restTimer.isRunning {
                    Button("+30s") {
                        restTimer.adjust(bySeconds: 30)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
                Image(systemName: "chevron.up.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(AppleTheme.cardSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
