import Foundation
import SwiftData

/// Past-workout actions shared by the history, detail and active-workout screens:
/// delete, repeat, and "what did I do last time" lookups for freestyle sessions.
@MainActor
public enum WorkoutHistoryService {

    /// The workout currently in progress, if any (only one should be open at a time).
    public static func openSession(context: ModelContext) -> WorkoutSession? {
        let descriptor = FetchDescriptor<WorkoutSession>(predicate: #Predicate<WorkoutSession> { $0.end == nil })
        return (try? context.fetch(descriptor))?.first
    }

    public static func uniqueExercises(in session: WorkoutSession) -> [Exercise] {
        var seen = Set<UUID>()
        var result: [Exercise] = []
        for log in session.sortedSets {
            guard let ex = log.exercise, !seen.contains(ex.id) else { continue }
            seen.insert(ex.id)
            result.append(ex)
        }
        return result
    }

    /// Deletes a finished workout and its sets, removes its Apple Health copy, and rebuilds the PRs it contributed to.
    public static func delete(_ session: WorkoutSession, context: ModelContext) {
        let exercises = uniqueExercises(in: session)
        let healthKitUUID = session.healthKitWorkoutUUID

        for log in session.sortedSets {
            context.delete(log)
        }
        context.delete(session)
        try? context.save()

        StrongWorkoutImportService.rebuildExerciseAnalytics(for: exercises, context: context)
        try? context.save()
        _ = CoachingCoordinator.evaluate(context: context)

        if let healthKitUUID {
            Task { await HealthKitService.shared.deleteStrengthWorkout(uuid: healthKitUUID) }
        }
    }

    /// Starts a new workout pre-filled with a past session's exercises, set counts, loads and reps (Strong-style "Repeat").
    public static func startRepeat(of source: WorkoutSession, gym: GymProfile?, context: ModelContext) -> WorkoutSession {
        let session = WorkoutSession(
            title: source.title,
            programWorkout: source.programWorkout,
            gymProfile: gym ?? source.gymProfile,
            start: .now
        )
        context.insert(session)

        let completed = source.sortedSets.filter(\.isCompleted)
        let template = completed.isEmpty ? source.sortedSets : completed
        for (order, log) in template.enumerated() {
            guard let ex = log.exercise else { continue }
            let copy = SetLog(
                order: order,
                session: session,
                exercise: ex,
                weightKg: log.weightKg,
                reps: log.reps,
                rir: log.rir,
                type: log.type,
                supersetGroup: log.supersetGroup,
                isCompleted: false,
                isUnilateral: log.isUnilateral,
                weightKgLeft: log.weightKgLeft,
                repsLeft: log.repsLeft,
                weightKgRight: log.weightKgRight,
                repsRight: log.repsRight
            )
            context.insert(copy)
        }

        try? context.save()
        PhoneWatchSyncService.shared.pushCurrentState(context: context)
        return session
    }

    /// Completed sets from the most recent finished workout that included `exercise`, in logged order.
    public static func lastPerformedSets(of exercise: Exercise, excludingSessionID: UUID? = nil) -> [SetLog] {
        let logs = (exercise.setLogs ?? []).filter { log in
            log.isCompleted && log.session?.isFinished == true && log.session?.id != excludingSessionID
        }
        let latest = logs.max { lhs, rhs in
            (lhs.session?.start ?? lhs.timestamp) < (rhs.session?.start ?? rhs.timestamp)
        }
        guard let latestSessionID = latest?.session?.id else { return [] }
        return logs
            .filter { $0.session?.id == latestSessionID }
            .sorted { $0.order < $1.order }
    }
}
