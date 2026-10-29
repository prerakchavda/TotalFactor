import Foundation
import SwiftData

private struct BundledExerciseDTO: Codable {
    var name: String
    var primaryMuscles: [MuscleGroup]
    var secondaryMuscles: [MuscleGroup]
    var equipment: Equipment
    var movementPattern: MovementPattern
    var loadIncrementKg: Double
    var instructions: String
}

public enum SeedDataService {
    private static let planetFitnessActiveMigrationKey = "totalfactor.migrated.planetFitnessActive.v1"
    private static let planetFitnessProgramMigrationKey = "totalfactor.migrated.planetFitnessProgram.v1"
    private static let offlineUSDACatalogMigrationKey = "totalfactor.migrated.offlineUSDACatalog.v1"

    @MainActor
    public static func seedIfNeeded(context: ModelContext) {
        OfflineUSDACatalogService.shared.preloadInBackground()
        pruneUnusedLegacyBundledFoodsIfNeeded(context: context)
        seedBundledExercisesIfNeeded(context: context)
        seedDefaultGymProfilesIfNeeded(context: context)
        seedStarterProgramIfNeeded(context: context)
        try? context.save()

        // Import bundled Strong workouts after exercises, Planet Fitness gym, and Planet Fitness Split exist
        StrongWorkoutImportService.importBundledStrongHistoryIfNeeded(context: context)
    }

    public static func makePlanetFitnessGymProfile(isDefault: Bool = true) -> GymProfile {
        GymProfile(
            name: "Planet Fitness",
            isDefault: isDefault,
            availableEquipment: [
                .machine,
                .cable,
                .dumbbell,
                .smithMachine,
                .bodyweight,
                .ezBar,
                .kettlebell,
                .bands
            ],
            // 45, 35, 25, 10, 5, 2.5 lb plates in kg
            availablePlatesKg: [20.41, 15.88, 11.34, 4.54, 2.27, 1.13],
            // Planet Fitness counterbalanced Smith Machine starting carriage resistance (~20 lb)
            barWeightKg: 9.07,
            // 5 lb – 75 lb dumbbell rack in 5 lb jumps
            minDumbbellKg: 2.27,
            maxDumbbellKg: 34.02,
            dumbbellIncrementKg: 2.27,
            // 2.5 lb stack micro-weight increment
            cableIncrementKg: 1.13
        )
    }

    /// Keeps SwiftData `@Query var foods: [Food]` ultra-lean:
    /// All ~8,156 USDA Foundation + SR Legacy whole foods now live in `OfflineUSDACatalogService` and materialize
    /// into SwiftData only on first log, favorite, or recipe use. On upgraded installs, any unlogged, unfavorited
    /// legacy generic seed rows are pruned once while 100% preserving every food ever used, favorited, or in a recipe.
    @MainActor
    private static func pruneUnusedLegacyBundledFoodsIfNeeded(context: ModelContext) {
        guard !UserDefaults.standard.bool(forKey: offlineUSDACatalogMigrationKey) else { return }
        let descriptor = FetchDescriptor<Food>(predicate: #Predicate { $0.isBundledGeneric == true })
        let genericRows = (try? context.fetch(descriptor)) ?? []
        for food in genericRows {
            let usedInRecipe = !(food.recipeUsages ?? []).isEmpty
            if food.useCount == 0 && !food.isFavorite && !usedInRecipe {
                context.delete(food)
            }
        }
        UserDefaults.standard.set(true, forKey: offlineUSDACatalogMigrationKey)
    }

    @MainActor
    private static func seedBundledExercisesIfNeeded(context: ModelContext) {
        guard let url = Bundle.main.url(forResource: "BundledExercises", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let items = try? JSONDecoder().decode([BundledExerciseDTO].self, from: data) else {
            return
        }

        let existing = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
        var existingByLowerName: [String: Exercise] = [:]
        for ex in existing {
            existingByLowerName[ex.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()] = ex
        }

        // Sync any missing exercises from BundledExercises.json (safe on both fresh & upgraded installs)
        for dto in items {
            let key = dto.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if let found = existingByLowerName[key] {
                if !found.isCustom && found.instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    found.instructions = dto.instructions
                }
            } else {
                let ex = Exercise(
                    name: dto.name,
                    primaryMuscles: dto.primaryMuscles,
                    secondaryMuscles: dto.secondaryMuscles,
                    equipment: dto.equipment,
                    movementPattern: dto.movementPattern,
                    isCustom: false,
                    instructions: dto.instructions,
                    loadIncrementKg: dto.loadIncrementKg
                )
                context.insert(ex)
                existingByLowerName[key] = ex
            }
        }
    }

    @MainActor
    private static func seedDefaultGymProfilesIfNeeded(context: ModelContext) {
        var existingGyms = (try? context.fetch(FetchDescriptor<GymProfile>())) ?? []

        if existingGyms.isEmpty {
            let planetFitness = makePlanetFitnessGymProfile(isDefault: true)

            let commercial = GymProfile(
                name: "Commercial Gym",
                isDefault: false,
                availableEquipment: Equipment.allCases,
                availablePlatesKg: [25, 20, 15, 10, 5, 2.5, 1.25],
                barWeightKg: 20.0,
                minDumbbellKg: 2.5,
                maxDumbbellKg: 55.0,
                dumbbellIncrementKg: 2.5,
                cableIncrementKg: 2.5
            )

            let homeGym = GymProfile(
                name: "Home Dumbbell + Bench",
                isDefault: false,
                availableEquipment: [.dumbbell, .bodyweight, .bands, .kettlebell],
                availablePlatesKg: [20, 10, 5, 2.5, 1.25],
                barWeightKg: 20.0,
                minDumbbellKg: 2.5,
                maxDumbbellKg: 32.5,
                dumbbellIncrementKg: 2.5,
                cableIncrementKg: 2.5
            )

            context.insert(planetFitness)
            context.insert(commercial)
            context.insert(homeGym)
            UserDefaults.standard.set(true, forKey: planetFitnessActiveMigrationKey)
            return
        }

        // Existing install upgrade: ensure Planet Fitness exists and activate it once
        let pfGym: GymProfile
        if let found = existingGyms.first(where: { $0.name.localizedCaseInsensitiveContains("Planet Fitness") }) {
            pfGym = found
        } else {
            let created = makePlanetFitnessGymProfile(isDefault: false)
            context.insert(created)
            existingGyms.append(created)
            pfGym = created
        }

        if !UserDefaults.standard.bool(forKey: planetFitnessActiveMigrationKey) {
            for gym in existingGyms {
                gym.isDefault = (gym.id == pfGym.id)
            }
            UserDefaults.standard.set(true, forKey: planetFitnessActiveMigrationKey)
        }
    }

    @MainActor
    private static func seedStarterProgramIfNeeded(context: ModelContext) {
        let existingPrograms = (try? context.fetch(FetchDescriptor<Program>())) ?? []
        let allExercises = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
        guard !allExercises.isEmpty else { return }

        if existingPrograms.isEmpty {
            insertProgram(
                from: ProgramGeneratorEngine.planetFitnessProgramBlueprint(exercisePool: allExercises.map(\.asBlueprint)),
                isActive: true,
                allExercises: allExercises,
                context: context
            )
            UserDefaults.standard.set(true, forKey: planetFitnessProgramMigrationKey)
            return
        }

        // One-time upgrade for existing installs: install & activate the user's real Planet Fitness Split
        if !UserDefaults.standard.bool(forKey: planetFitnessProgramMigrationKey) {
            if let existingPF = existingPrograms.first(where: { $0.name.localizedCaseInsensitiveContains("Planet Fitness Split") }) {
                for p in existingPrograms {
                    p.isActive = (p.id == existingPF.id)
                }
            } else {
                for p in existingPrograms {
                    p.isActive = false
                }
                insertProgram(
                    from: ProgramGeneratorEngine.planetFitnessProgramBlueprint(exercisePool: allExercises.map(\.asBlueprint)),
                    isActive: true,
                    allExercises: allExercises,
                    context: context
                )
            }
            UserDefaults.standard.set(true, forKey: planetFitnessProgramMigrationKey)
        }
    }

    @MainActor
    private static func insertProgram(
        from blueprint: GeneratedProgramBlueprint,
        isActive: Bool,
        allExercises: [Exercise],
        context: ModelContext
    ) {
        let exerciseByID = Dictionary(allExercises.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let program = Program(name: blueprint.name, daysPerWeek: blueprint.daysPerWeek, isActive: isActive)
        context.insert(program)

        for (wIdx, wb) in blueprint.workouts.enumerated() {
            let workout = ProgramWorkout(name: wb.name, order: wIdx, scheduledWeekday: wb.scheduledWeekday)
            workout.program = program
            context.insert(workout)

            for (sIdx, sb) in wb.slots.enumerated() {
                let slot = ExerciseSlot(
                    order: sIdx,
                    exercise: exerciseByID[sb.exercise.id],
                    sets: sb.sets,
                    repRangeLow: sb.repRangeLow,
                    repRangeHigh: sb.repRangeHigh,
                    targetRIR: sb.targetRIR,
                    restSeconds: sb.restSeconds,
                    progressionRule: sb.progressionRule,
                    supersetGroup: sb.supersetGroup
                )
                slot.workout = workout
                context.insert(slot)
            }
        }
    }
}
