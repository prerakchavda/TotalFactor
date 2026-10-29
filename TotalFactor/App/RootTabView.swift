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

    var body: some View {
        @Bindable var state = appState

        ZStack(alignment: .bottom) {
            TabView(selection: $state.selectedTab) {
                TodayDashboardView()
                    .tabItem {
                        Label("Today", systemImage: "bolt.heart.fill")
                    }
                    .tag(AppTab.today)

                FoodTimelineView()
                    .tabItem {
                        Label("Food", systemImage: "fork.knife")
                    }
                    .tag(AppTab.food)

                TrainHubView()
                    .tabItem {
                        Label("Train", systemImage: "dumbbell.fill")
                    }
                    .tag(AppTab.train)

                ProgressHubView()
                    .tabItem {
                        Label("Progress", systemImage: "chart.xyaxis.line")
                    }
                    .tag(AppTab.progress)

                SettingsView()
                    .tabItem {
                        Label("Settings", systemImage: "gearshape.fill")
                    }
                    .tag(AppTab.settings)
            }

            // Persistent mini-bar when an active workout or rest timer is running, plus thumb-reachable + food button
            VStack(spacing: 8) {
                if let activeSession = openSessions.first, !state.showingActiveWorkoutFullScreen {
                    ActiveWorkoutMiniBar(session: activeSession) {
                        state.activeWorkoutSessionID = activeSession.id
                        state.showingActiveWorkoutFullScreen = true
                    }
                    .padding(.horizontal, 14)
                }

                if state.selectedTab == .today || state.selectedTab == .food {
                    HStack {
                        Spacer()
                        Button {
                            state.openQuickAdd(tab: 0)
                        } label: {
                            Image(systemName: "plus")
                                .font(.title2.weight(.bold))
                                .foregroundStyle(.white)
                                .frame(width: 58, height: 58)
                                .background(Circle().fill(Color.accentColor).shadow(color: .black.opacity(0.25), radius: 8, y: 4))
                        }
                        .accessibilityLabel("Quick Add Food")
                        .padding(.trailing, 18)
                    }
                }
            }
            .padding(.bottom, 58)
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
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(.green))

                VStack(alignment: .leading, spacing: 2) {
                    Text(session.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    if restTimer.isRunning {
                        Text("Rest: \(restTimer.remainingSeconds)s • \(restTimer.exerciseName)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.orange)
                    } else {
                        Text("\(session.completedSetCount) sets logged • Tap to resume")
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
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
