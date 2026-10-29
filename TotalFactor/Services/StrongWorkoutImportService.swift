import Foundation
import SwiftData

public struct StrongImportSummary: Equatable, Sendable {
    public var sessionsImported: Int
    public var setsImported: Int
    public var exercisesUpdated: Int

    public init(sessionsImported: Int, setsImported: Int, exercisesUpdated: Int) {
        self.sessionsImported = sessionsImported
        self.setsImported = setsImported
        self.exercisesUpdated = exercisesUpdated
    }
}

@MainActor
public enum StrongWorkoutImportService {
    private static let bundledMigrationKey = "totalfactor.migrated.bundledStrongWorkouts.v1"

    /// One-time idempotent import of bundled `BundledStrongWorkouts.csv` (the user's Strong history).
    public static func importBundledStrongHistoryIfNeeded(context: ModelContext) {
        guard !UserDefaults.standard.bool(forKey: bundledMigrationKey) else { return }
        guard let url = Bundle.main.url(forResource: "BundledStrongWorkouts", withExtension: "csv"),
              let content = try? String(contentsOf: url, encoding: .utf8) else {
            return
        }

        let gyms = (try? context.fetch(FetchDescriptor<GymProfile>())) ?? []
        let pfGym = gyms.first(where: { $0.name.localizedCaseInsensitiveContains("Planet Fitness") })
            ?? gyms.first(where: \.isDefault)
            ?? gyms.first

        let summary = importCSV(
            content: content,
            context: context,
            sourceUnitSystem: .imperial,
            defaultGym: pfGym,
            triggerCoachingEvaluation: false
        )

        if summary.sessionsImported > 0 || !content.isEmpty {
            UserDefaults.standard.set(true, forKey: bundledMigrationKey)
        }
    }

    /// Imports Strong / Hevy CSV workout history into SwiftData, deduplicating existing sessions,
    /// fitting personal rep-endurance curves (`personalRepCurveK`), and computing chronological PRs.
    @discardableResult
    public static func importCSV(
        content: String,
        context: ModelContext,
        sourceUnitSystem: UnitSystem = .imperial,
        defaultGym: GymProfile? = nil,
        triggerCoachingEvaluation: Bool = true
    ) -> StrongImportSummary {
        let parsedSessions = StrongCSVParser.parse(csvContent: content, sourceUnitSystem: sourceUnitSystem)
        guard !parsedSessions.isEmpty else {
            return StrongImportSummary(sessionsImported: 0, setsImported: 0, exercisesUpdated: 0)
        }

        // 1. Build deduplication set from existing finished WorkoutSessions (minute-level start + normalized title)
        let existingSessions = (try? context.fetch(FetchDescriptor<WorkoutSession>())) ?? []
        var existingFingerprints = Set<String>(
            existingSessions.map { sessionFingerprint(start: $0.start, title: $0.title) }
        )

        // 2. Resolve active GymProfile (Planet Fitness by default)
        let resolvedGym: GymProfile? = defaultGym ?? {
            let gyms = (try? context.fetch(FetchDescriptor<GymProfile>())) ?? []
            return gyms.first(where: \.isDefault) ?? gyms.first
        }()

        // 3. Map ProgramWorkouts (preferring active program) by lowercased workout title
        let programs = (try? context.fetch(FetchDescriptor<Program>())) ?? []
        let activeProgram = programs.first(where: \.isActive) ?? programs.first
        var workoutByLowerName: [String: ProgramWorkout] = [:]
        for p in programs {
            for w in p.workouts ?? [] {
                let key = w.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if workoutByLowerName[key] == nil || p.id == activeProgram?.id {
                    workoutByLowerName[key] = w
                }
            }
        }

        // 4. Map Exercises by lowercased name
        let allExercises = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
        var exerciseByLowerName: [String: Exercise] = [:]
        for ex in allExercises {
            exerciseByLowerName[ex.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()] = ex
        }

        var sessionsImported = 0
        var setsImported = 0
        var touchedExercises: [UUID: Exercise] = [:]

        for parsed in parsedSessions {
            let fp = sessionFingerprint(start: parsed.startDate, title: parsed.workoutName)
            guard !existingFingerprints.contains(fp) else { continue }
            existingFingerprints.insert(fp)

            let linkedWorkout = workoutByLowerName[parsed.workoutName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()]
            let session = WorkoutSession(
                title: parsed.workoutName,
                programWorkout: linkedWorkout,
                gymProfile: resolvedGym,
                start: parsed.startDate,
                notes: parsed.notes
            )
            session.end = parsed.endDate
            session.dayKey = parsed.dayKey
            context.insert(session)
            sessionsImported += 1

            for pSet in parsed.sets {
                let canonicalLower = pSet.canonicalExerciseName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let rawLower = pSet.rawExerciseName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

                let exercise: Exercise
                if let matched = exerciseByLowerName[canonicalLower] ?? exerciseByLowerName[rawLower] {
                    exercise = matched
                } else {
                    let created = makeCustomFallbackExercise(named: pSet.canonicalExerciseName)
                    context.insert(created)
                    exerciseByLowerName[canonicalLower] = created
                    exercise = created
                }

                let setTimestamp = parsed.startDate.addingTimeInterval(TimeInterval(pSet.setOrder * 90))
                let log = SetLog(
                    order: pSet.setOrder,
                    session: session,
                    exercise: exercise,
                    weightKg: pSet.weightKg,
                    reps: pSet.reps,
                    rir: pSet.rir,
                    type: pSet.setType,
                    isCompleted: true,
                    timestamp: setTimestamp
                )
                context.insert(log)
                setsImported += 1
                touchedExercises[exercise.id] = exercise
            }
        }

        // 5. Recompute fitted personalRepCurveK & chronological PersonalRecords for touched exercises
        if !touchedExercises.isEmpty {
            rebuildExerciseAnalytics(for: Array(touchedExercises.values), context: context)
        }

        try? context.save()

        if triggerCoachingEvaluation && sessionsImported > 0 {
            _ = CoachingCoordinator.evaluate(context: context)
        } else if sessionsImported > 0 {
            CoachingCoordinator.invalidateCache()
        }

        return StrongImportSummary(
            sessionsImported: sessionsImported,
            setsImported: setsImported,
            exercisesUpdated: touchedExercises.count
        )
    }

    // MARK: - Private Helpers

    private static func sessionFingerprint(start: Date, title: String) -> String {
        let minuteBucket = Int(start.timeIntervalSince1970 / 60.0)
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return "\(minuteBucket)|\(normalizedTitle)"
    }

    private static func rebuildExerciseAnalytics(for exercises: [Exercise], context: ModelContext) {
        for ex in exercises {
            let completedLogs = (ex.setLogs ?? []).filter { log in
                log.isCompleted && (log.session?.isFinished ?? true)
            }
            guard !completedLogs.isEmpty else { continue }

            let allSamples: [LoggedSetSample] = completedLogs.map { log in
                LoggedSetSample(
                    sessionDate: log.session?.start ?? log.timestamp,
                    weightKg: log.weightKg,
                    reps: log.reps,
                    rir: log.rir,
                    setType: log.type
                )
            }

            let fittedK = ProgressionEngine.fitPersonalRepCurveK(samples: allSamples)
            ex.personalRepCurveK = fittedK

            // Clear old PRs for this exercise and replay sessions chronologically for exact PR dates
            for oldPR in ex.personalRecords ?? [] {
                context.delete(oldPR)
            }

            let logsBySessionID = Dictionary(grouping: completedLogs) { $0.session?.id ?? $0.id }
            let sortedSessionGroups = logsBySessionID.values.sorted { lhs, rhs in
                let d0 = lhs[0].session?.start ?? lhs[0].timestamp
                let d1 = rhs[0].session?.start ?? rhs[0].timestamp
                return d0 < d1
            }

            var priorSamples: [LoggedSetSample] = []
            for sessionLogs in sortedSessionGroups {
                let sessionDate = sessionLogs[0].session?.start ?? sessionLogs[0].timestamp
                let ordered = sessionLogs.sorted { $0.order < $1.order }
                let sessionSamples = ordered.map {
                    LoggedSetSample(
                        sessionDate: sessionDate,
                        weightKg: $0.weightKg,
                        reps: $0.reps,
                        rir: $0.rir,
                        setType: $0.type
                    )
                }

                let detected = ProgressionEngine.detectSessionPRs(
                    priorSets: priorSamples,
                    sessionSets: sessionSamples,
                    k: fittedK
                )
                for pr in detected {
                    let record = PersonalRecord(
                        exercise: ex,
                        type: pr.type,
                        value: pr.value,
                        secondaryValue: pr.secondaryValue,
                        date: sessionDate
                    )
                    context.insert(record)
                }
                priorSamples.append(contentsOf: sessionSamples)
            }
        }
    }

    private static func makeCustomFallbackExercise(named name: String) -> Exercise {
        let lower = name.lowercased()
        let equipment: Equipment = {
            if lower.contains("cable") { return .cable }
            if lower.contains("dumbbell") || lower.contains("db") { return .dumbbell }
            if lower.contains("smith") { return .smithMachine }
            if lower.contains("band") { return .bands }
            if lower.contains("kettlebell") { return .kettlebell }
            if lower.contains("ez") { return .ezBar }
            if lower.contains("pull up") || lower.contains("push up") || lower.contains("dip") { return .bodyweight }
            return .machine
        }()

        let primary: [MuscleGroup] = {
            if lower.contains("chest") || lower.contains("pec") || lower.contains("bench") { return [.chest] }
            if lower.contains("lat") || lower.contains("pulldown") || lower.contains("pull up") { return [.lats] }
            if lower.contains("row") { return [.upperBack, .lats] }
            if lower.contains("shoulder") || lower.contains("overhead") || lower.contains("arnold") { return [.frontDelts, .sideDelts] }
            if lower.contains("lateral") { return [.sideDelts] }
            if lower.contains("rear delt") { return [.rearDelts] }
            if lower.contains("curl") { return [.biceps] }
            if lower.contains("tricep") || lower.contains("skull") || lower.contains("pushdown") { return [.triceps] }
            if lower.contains("leg curl") || lower.contains("hamstring") { return [.hamstrings] }
            if lower.contains("calf") { return [.calves] }
            if lower.contains("abduct") || lower.contains("adduct") || lower.contains("glute") || lower.contains("hip") { return [.glutes] }
            if lower.contains("squat") || lower.contains("leg press") || lower.contains("leg extension") { return [.quads] }
            if lower.contains("ab") || lower.contains("crunch") { return [.abs] }
            return [.chest]
        }()

        let pattern: MovementPattern = {
            if lower.contains("squat") || lower.contains("leg press") { return .squat }
            if lower.contains("row") { return .horizontalPull }
            if lower.contains("pulldown") || lower.contains("pull up") { return .verticalPull }
            if lower.contains("shoulder press") || lower.contains("overhead") { return .verticalPush }
            if lower.contains("press") { return .horizontalPush }
            return .isolation
        }()

        return Exercise(
            name: name,
            primaryMuscles: primary,
            secondaryMuscles: [],
            equipment: equipment,
            movementPattern: pattern,
            isCustom: true,
            instructions: "",
            loadIncrementKg: equipment == .cable ? 1.13 : 2.27
        )
    }
}
