import SwiftUI
import SwiftData

@main
struct TotalFactorApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var appState = AppState.shared
    @State private var healthService = HealthKitService.shared
    @State private var restTimer = RestTimerService.shared
    @State private var watchSync = PhoneWatchSyncService.shared

    let sharedModelContainer: ModelContainer = {
        let schema = Schema([
            UserProfile.self,
            Goal.self,
            NutrientTarget.self,
            Food.self,
            Recipe.self,
            RecipeIngredient.self,
            FoodLogEntry.self,
            DailyNote.self,
            WeighIn.self,
            BodyMetric.self,
            ProgressPhoto.self,
            ExpenditureEstimate.self,
            WeeklyCheckIn.self,
            Exercise.self,
            GymProfile.self,
            Program.self,
            ProgramWorkout.self,
            ExerciseSlot.self,
            WorkoutSession.self,
            SetLog.self,
            PersonalRecord.self,
            SavedMeal.self,
            SavedMealItem.self
        ])

        // Graceful provisioning fallback:
        // Free Apple Developer accounts block iCloud/CloudKit capabilities. We default to local persistent storage
        // and only attempt CloudKit automatic sync when explicitly enabled in Settings on a paid team.
        let wantsCloudSync = UserDefaults.standard.bool(forKey: "totalfactor.enableCloudKit")
        if wantsCloudSync {
            let cloudConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false, cloudKitDatabase: .automatic)
            if let cloudContainer = try? ModelContainer(for: schema, configurations: [cloudConfig]) {
                return cloudContainer
            }
        }

        let localConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false, cloudKitDatabase: .none)
        do {
            return try ModelContainer(for: schema, configurations: [localConfig])
        } catch {
            fatalError("Failed to initialize Total Factor SwiftData container: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(appState)
                .environment(healthService)
                .environment(restTimer)
                .environment(watchSync)
                .environment(NotificationService.shared)
                .onAppear {
                    let context = sharedModelContainer.mainContext
                    SeedDataService.seedIfNeeded(context: context)
                    CoachingCoordinator.processPendingWidgetActions(context: context)
                    watchSync.configure(container: sharedModelContainer)
                    _ = CoachingCoordinator.evaluate(context: context)
                    healthService.startObservingBodyMass(context: context)
                    NotificationService.shared.rescheduleAll()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        let context = sharedModelContainer.mainContext
                        CoachingCoordinator.processPendingWidgetActions(context: context)
                        restTimer.reconcileWithWallClock()
                        watchSync.pushCurrentState(context: context)
                        Task {
                            await healthService.importExternalBodyMetrics(context: context)
                            await healthService.refreshTodayDashboardTelemetry()
                            _ = CoachingCoordinator.evaluate(context: context)
                        }
                    }
                }
        }
        .modelContainer(sharedModelContainer)
    }
}
