import Foundation
import SwiftData
#if canImport(WatchConnectivity)
import WatchConnectivity
#endif

/// Coordinates bidirectional `WatchConnectivity` (`WCSession`) sync between iPhone and `TotalFactorWatch`
/// without requiring paid App Group entitlements (`8MF8V7WZJB` Free Personal Team compatible).
@MainActor
@Observable
public final class PhoneWatchSyncService: NSObject {
    public static let shared = PhoneWatchSyncService()

    public var isWatchPaired: Bool = false
    public var isWatchReachable: Bool = false
    /// Display-only live wrist heart rate streamed during an Apple Watch `HKWorkoutSession`.
    public var liveWatchHeartRateBPM: Double? = nil
    /// Ground Rule 3: Display-only active calories — never alters TDEE or macro targets.
    public var liveWatchActiveCaloriesDisplayOnly: Double = 0

    private var modelContainer: ModelContainer? = nil
    private var processedCommandIDs: Set<UUID> = []

    public override init() {
        super.init()
    }

    public func configure(container: ModelContainer) {
        self.modelContainer = container
        #if canImport(WatchConnectivity)
        if WCSession.isSupported() {
            let session = WCSession.default
            session.delegate = self
            if session.activationState != .activated {
                session.activate()
            } else {
                isWatchPaired = session.isPaired
                isWatchReachable = session.isReachable
                pushCurrentState(context: container.mainContext)
            }
        }
        #endif
    }

    public func pushCurrentState(context explicitContext: ModelContext? = nil) {
        #if canImport(WatchConnectivity)
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        guard let ctx = explicitContext ?? modelContainer?.mainContext else { return }

        let snapshot = buildSnapshot(context: ctx)
        guard let contextDict = snapshot.toApplicationContext(),
              let rawData = try? JSONEncoder().encode(snapshot) else { return }

        try? session.updateApplicationContext(contextDict)
        if session.isReachable {
            session.sendMessageData(rawData, replyHandler: nil, errorHandler: nil)
        }
        #endif
    }

    public func buildSnapshot(context: ModelContext) -> WatchSyncStateSnapshot {
        let todayKey = DayKey.today
        let digest = CoachingCoordinator.cachedOrComputeDigest(forDayKey: todayKey, context: context)
        let profile = CoachingCoordinator.fetchOrCreateProfile(context: context)

        let allEntries = (try? context.fetch(FetchDescriptor<FoodLogEntry>())) ?? []
        let todayEntries = allEntries.filter { $0.dayKey == todayKey }
        let calsEaten = todayEntries.reduce(0.0) { $0 + $1.calories }
        let pEaten = todayEntries.reduce(0.0) { $0 + $1.protein }
        let cEaten = todayEntries.reduce(0.0) { $0 + $1.carbs }
        let fEaten = todayEntries.reduce(0.0) { $0 + $1.fat }

        let targets = digest.todayTargets

        let allPrograms = (try? context.fetch(FetchDescriptor<Program>())) ?? []
        let activeProgram = allPrograms.first(where: \.isActive) ?? allPrograms.first
        let weekday = DayKey.weekday(for: todayKey)
        let scheduledWorkout = activeProgram?.sortedWorkouts.first(where: { $0.scheduledWeekday == weekday }) ??
            (digest.isTodayTrainingDay ? activeProgram?.sortedWorkouts.first : nil)

        let templates: [WatchWorkoutTemplateDTO] = (activeProgram?.sortedWorkouts ?? []).map { w in
            let slots = w.sortedSlots
            return WatchWorkoutTemplateDTO(
                id: w.id,
                name: w.name,
                exerciseCount: slots.count,
                workingSetCount: slots.reduce(0) { $0 + $1.sets }
            )
        }

        let openSessions = (try? context.fetch(
            FetchDescriptor<WorkoutSession>(predicate: #Predicate { $0.end == nil })
        )) ?? []
        let activeSessionDTO: WatchActiveSessionDTO? = openSessions.first.map { ws in
            let ordered = ws.sortedSets
            let setsByExID = Dictionary(grouping: ordered) { $0.exercise?.id ?? UUID() }
            let slotByExID: [UUID: ExerciseSlot] = Dictionary(
                (ws.programWorkout?.sortedSlots ?? []).compactMap { slot in
                    guard let exID = slot.exercise?.id else { return nil }
                    return (exID, slot)
                },
                uniquingKeysWith: { first, _ in first }
            )

            var perExCounter: [UUID: Int] = [:]
            let setDTOs: [WatchSetItemDTO] = ordered.compactMap { s in
                guard let ex = s.exercise else { return nil }
                let idxInEx = (perExCounter[ex.id] ?? 0) + 1
                perExCounter[ex.id] = idxInEx
                let totalInEx = setsByExID[ex.id]?.count ?? 1
                let slot = slotByExID[ex.id]
                let restSec = s.type == .warmup ? min(60, slot?.restSeconds ?? 90) : (slot?.restSeconds ?? 120)
                let incKg = ws.gymProfile?.effectiveIncrementKg(for: ex) ?? ex.loadIncrementKg

                return WatchSetItemDTO(
                    id: s.id,
                    order: s.order,
                    exerciseID: ex.id,
                    exerciseName: ex.name,
                    setNumberInExercise: idxInEx,
                    totalSetsInExercise: totalInEx,
                    setTypeBadge: s.type.badge,
                    weightKg: s.weightKg,
                    reps: s.reps,
                    rir: s.rir,
                    restSeconds: restSec,
                    loadIncrementKg: incKg,
                    isCompleted: s.isCompleted
                )
            }

            return WatchActiveSessionDTO(
                id: ws.id,
                title: ws.title,
                startedAt: ws.start,
                sets: setDTOs
            )
        }

        let timer = RestTimerService.shared
        return WatchSyncStateSnapshot(
            updatedAt: .now,
            unitSystemRaw: profile.unitSystemRaw,
            caloriesRemaining: targets.calories - calsEaten,
            caloriesTarget: targets.calories,
            caloriesEaten: calsEaten,
            proteinRemaining: max(0, targets.protein - pEaten),
            proteinTarget: targets.protein,
            carbsRemaining: max(0, targets.carbs - cEaten),
            carbsTarget: targets.carbs,
            fatRemaining: max(0, targets.fat - fEaten),
            fatTarget: targets.fat,
            isTrainingDay: digest.isTodayTrainingDay,
            trendWeightKg: digest.weightSummary.latestTrendKg,
            latestScaleWeightKg: digest.weightSummary.latestScaleKg,
            scheduledWorkoutID: scheduledWorkout?.id,
            scheduledWorkoutName: scheduledWorkout?.name,
            availableWorkouts: templates,
            activeSession: activeSessionDTO,
            restEndDate: timer.isRunning ? timer.endDate : nil,
            restTotalSeconds: timer.isRunning ? timer.totalSeconds : 0,
            restExerciseName: timer.exerciseName,
            restNextSummary: timer.nextSetSummary
        )
    }

    // MARK: - Handle Incoming Watch Commands

    private func handleCommand(_ cmd: WatchCommandPayload) {
        if cmd.action != .liveHeartRate && cmd.action != .requestSync {
            guard !processedCommandIDs.contains(cmd.id) else { return }
            processedCommandIDs.insert(cmd.id)
            if processedCommandIDs.count > 250 {
                processedCommandIDs.removeAll()
                processedCommandIDs.insert(cmd.id)
            }
        }

        guard let ctx = modelContainer?.mainContext else { return }

        switch cmd.action {
        case .requestSync:
            pushCurrentState(context: ctx)

        case .liveHeartRate:
            if let bpm = cmd.heartRateBPM, bpm > 0 {
                liveWatchHeartRateBPM = bpm
            } else {
                liveWatchHeartRateBPM = nil
            }
            if let kcal = cmd.activeCaloriesDisplayOnly {
                liveWatchActiveCaloriesDisplayOnly = max(0, kcal)
            }

        case .adjustRestTimer:
            if let delta = cmd.deltaSeconds {
                RestTimerService.shared.adjust(bySeconds: delta)
            }

        case .skipRestTimer:
            RestTimerService.shared.skip()

        case .toggleSetComplete:
            guard let targetID = cmd.setID else { return }
            let allSets = (try? ctx.fetch(FetchDescriptor<SetLog>())) ?? []
            guard let setLog = allSets.first(where: { $0.id == targetID }) else { return }

            if let wKg = cmd.weightKg { setLog.weightKg = max(0, wKg) }
            if let r = cmd.reps { setLog.reps = max(1, r) }
            if let rir = cmd.rir { setLog.rir = max(0, min(6, rir)) }

            let timer = RestTimerService.shared
            setLog.isCompleted.toggle()
            setLog.timestamp = .now
            if setLog.isCompleted {
                setLog.restTakenSeconds = timer.consumeElapsedRestSeconds()
            } else {
                setLog.restTakenSeconds = 0
            }
            try? ctx.save()

            if setLog.isCompleted {
                let restSec = cmd.restSeconds ?? 120
                timer.start(
                    seconds: restSec,
                    workoutName: setLog.session?.title ?? "Strength",
                    exerciseName: setLog.exercise?.name ?? "Working Set",
                    setNumber: setLog.order + 1,
                    nextSetSummary: ""
                )
            } else {
                pushCurrentState(context: ctx)
            }

        case .updateSetValues:
            guard let targetID = cmd.setID else { return }
            let allSets = (try? ctx.fetch(FetchDescriptor<SetLog>())) ?? []
            guard let setLog = allSets.first(where: { $0.id == targetID }) else { return }
            if let wKg = cmd.weightKg { setLog.weightKg = max(0, wKg) }
            if let r = cmd.reps { setLog.reps = max(1, r) }
            if let rir = cmd.rir { setLog.rir = max(0, min(6, rir)) }
            try? ctx.save()
            pushCurrentState(context: ctx)

        case .addSet:
            let openSessions = (try? ctx.fetch(
                FetchDescriptor<WorkoutSession>(predicate: #Predicate { $0.end == nil })
            )) ?? []
            guard let session = openSessions.first, let exID = cmd.exerciseID else { return }
            let allExercises = (try? ctx.fetch(FetchDescriptor<Exercise>())) ?? []
            guard let ex = allExercises.first(where: { $0.id == exID }) else { return }

            let nextOrder = (session.sortedSets.map(\.order).max() ?? -1) + 1
            let newSet = SetLog(
                order: nextOrder,
                session: session,
                exercise: ex,
                weightKg: cmd.weightKg ?? 40.0,
                reps: cmd.reps ?? 8,
                rir: cmd.rir ?? 2,
                type: .working,
                isCompleted: false
            )
            ctx.insert(newSet)
            try? ctx.save()
            pushCurrentState(context: ctx)

        case .startWorkout:
            startWorkoutFromWatch(programWorkoutID: cmd.programWorkoutID, context: ctx)

        case .finishWorkout:
            finishActiveWorkoutFromWatch(context: ctx)

        case .logWeighIn:
            guard let kg = cmd.weightKg, kg >= 25.0, kg <= 350.0 else { return }
            let entry = WeighIn(date: cmd.createdAt, weightKg: kg, source: .manual)
            ctx.insert(entry)
            try? ctx.save()
            Task {
                await HealthKitService.shared.saveManualWeighIn(entry)
            }
            _ = CoachingCoordinator.evaluate(context: ctx)
            pushCurrentState(context: ctx)
        }
    }

    private func startWorkoutFromWatch(programWorkoutID: UUID?, context: ModelContext) {
        let openSessions = (try? context.fetch(
            FetchDescriptor<WorkoutSession>(predicate: #Predicate { $0.end == nil })
        )) ?? []
        if let alreadyOpen = openSessions.first {
            AppState.shared.activeWorkoutSessionID = alreadyOpen.id
            pushCurrentState(context: context)
            return
        }

        let gymProfiles = (try? context.fetch(FetchDescriptor<GymProfile>())) ?? []
        let activeGym = gymProfiles.first(where: \.isDefault) ?? gymProfiles.first
        let allWorkouts = (try? context.fetch(FetchDescriptor<ProgramWorkout>())) ?? []
        let chosenWorkout = programWorkoutID.flatMap { targetID in
            allWorkouts.first { $0.id == targetID }
        }

        let session = WorkoutSession(
            title: chosenWorkout?.name ?? "Freestyle Session",
            programWorkout: chosenWorkout,
            gymProfile: activeGym,
            start: .now
        )
        context.insert(session)

        let digest = CoachingCoordinator.evaluate(context: context)
        let allExercises = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
        let exerciseByID = Dictionary(allExercises.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let allowedEquip = Set(activeGym?.availableEquipment ?? Equipment.allCases)

        if let pw = chosenWorkout {
            var order = 0
            for slot in pw.sortedSlots {
                guard let baseEx = slot.exercise else { continue }
                let swapped = ProgramGeneratorEngine.autoSwapIfNeeded(
                    exercise: baseEx.asBlueprint,
                    availableEquipment: allowedEquip,
                    maxDumbbellKg: activeGym?.maxDumbbellKg ?? 50,
                    pool: allExercises.map(\.asBlueprint)
                )
                let resolvedEx = exerciseByID[swapped.id] ?? baseEx
                let history = (resolvedEx.setLogs ?? [])
                    .filter(\.isCompleted)
                    .map { LoggedSetSample(sessionDate: $0.session?.start ?? $0.timestamp, weightKg: $0.weightKg, reps: $0.reps, rir: $0.rir, setType: $0.type) }

                let inc = activeGym?.effectiveIncrementKg(for: resolvedEx) ?? resolvedEx.loadIncrementKg
                let suggestion = ProgressionEngine.suggestNextSession(
                    history: history,
                    repRangeLow: slot.repRangeLow,
                    repRangeHigh: slot.repRangeHigh,
                    targetRIR: slot.targetRIR,
                    loadIncrementKg: inc,
                    personalK: resolvedEx.personalRepCurveK,
                    weeklyWeightChangePercentBW: digest.weightSummary.weeklyRatePercentBW,
                    avgProteinLast7d: digest.avgProteinLast7d,
                    proteinFloor: digest.todayTargets.proteinFloor
                )

                for _ in 0..<slot.sets {
                    let setLog = SetLog(
                        order: order,
                        session: session,
                        exercise: resolvedEx,
                        weightKg: suggestion.suggestedWeightKg,
                        reps: suggestion.suggestedReps,
                        rir: slot.targetRIR,
                        type: .working,
                        supersetGroup: slot.supersetGroup,
                        isCompleted: false
                    )
                    context.insert(setLog)
                    order += 1
                }
            }
        } else {
            // Seed a quick freestyle compound trio so Watch immediately has sets ready to log
            let starterExercises = allExercises.filter(\.movementPattern.isCompound).prefix(3)
            var order = 0
            for ex in starterExercises {
                for _ in 0..<3 {
                    let setLog = SetLog(
                        order: order,
                        session: session,
                        exercise: ex,
                        weightKg: 40.0,
                        reps: 8,
                        rir: 2,
                        type: .working,
                        isCompleted: false
                    )
                    context.insert(setLog)
                    order += 1
                }
            }
        }

        try? context.save()
        AppState.shared.activeWorkoutSessionID = session.id
        pushCurrentState(context: context)
    }

    private func finishActiveWorkoutFromWatch(context: ModelContext) {
        let openSessions = (try? context.fetch(
            FetchDescriptor<WorkoutSession>(predicate: #Predicate { $0.end == nil })
        )) ?? []
        guard let session = openSessions.first else { return }

        for s in session.sortedSets where !s.isCompleted {
            context.delete(s)
        }
        session.end = .now
        liveWatchHeartRateBPM = nil
        liveWatchActiveCaloriesDisplayOnly = 0

        let timer = RestTimerService.shared
        timer.lastRestStartedAt = nil
        timer.skip()

        let exercisesInSession = Dictionary(
            grouping: session.sortedSets.compactMap(\.exercise),
            by: \.id
        ).compactMap(\.value.first)

        for ex in exercisesInSession {
            let allCompleted = (ex.setLogs ?? []).filter { $0.isCompleted && $0.type.countsTowardWorkingStats }
            let samples = allCompleted.map {
                LoggedSetSample(sessionDate: $0.session?.start ?? $0.timestamp, weightKg: $0.weightKg, reps: $0.reps, rir: $0.rir, setType: $0.type)
            }
            ex.personalRepCurveK = ProgressionEngine.fitPersonalRepCurveK(samples: samples, priorK: ex.personalRepCurveK)

            let priorSamples = allCompleted
                .filter { $0.session?.id != session.id }
                .map { LoggedSetSample(sessionDate: $0.session?.start ?? $0.timestamp, weightKg: $0.weightKg, reps: $0.reps, rir: $0.rir, setType: $0.type) }
            let sessionSamples = session.sortedSets
                .filter { $0.exercise?.id == ex.id && $0.isCompleted && $0.type.countsTowardWorkingStats }
                .map { LoggedSetSample(sessionDate: $0.timestamp, weightKg: $0.weightKg, reps: $0.reps, rir: $0.rir, setType: $0.type) }
            guard !sessionSamples.isEmpty else { continue }

            let detectedPRs = ProgressionEngine.detectSessionPRs(
                priorSets: priorSamples,
                sessionSets: sessionSamples,
                k: ex.personalRepCurveK
            )
            let existingPRs = ex.personalRecords ?? []
            for pr in detectedPRs {
                let alreadyRecorded: Bool
                if pr.type == .mostRepsAtWeight {
                    alreadyRecorded = existingPRs.contains {
                        $0.type == .mostRepsAtWeight &&
                        $0.secondaryValue >= pr.secondaryValue - 0.1 &&
                        $0.value >= pr.value
                    }
                } else {
                    let prevBest = existingPRs.filter { $0.type == pr.type }.map(\.value).max() ?? 0
                    alreadyRecorded = pr.value <= prevBest + 0.1
                }
                if !alreadyRecorded {
                    context.insert(
                        PersonalRecord(
                            exercise: ex,
                            type: pr.type,
                            value: pr.value,
                            secondaryValue: pr.secondaryValue,
                            date: .now
                        )
                    )
                }
            }
        }

        if let pw = session.programWorkout, let prog = pw.program {
            prog.lastCompletedWorkoutOrder = pw.order
        }

        try? context.save()
        AppState.shared.activeWorkoutSessionID = nil
        AppState.shared.showingActiveWorkoutFullScreen = false
        Task {
            await HealthKitService.shared.saveStrengthWorkout(session)
        }
        _ = CoachingCoordinator.evaluate(context: context)
        pushCurrentState(context: context)
    }
}

#if canImport(WatchConnectivity)
extension PhoneWatchSyncService: WCSessionDelegate {
    nonisolated public func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        let paired = session.isPaired
        let reachable = session.isReachable
        Task { @MainActor in
            self.isWatchPaired = paired
            self.isWatchReachable = reachable
            if activationState == .activated {
                self.pushCurrentState()
            }
        }
    }

    nonisolated public func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated public func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated public func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor in
            self.isWatchReachable = reachable
            if reachable {
                self.pushCurrentState()
            }
        }
    }

    nonisolated public func session(_ session: WCSession, didReceiveMessageData messageData: Data) {
        guard let cmd = WatchCommandPayload.fromData(messageData) else { return }
        Task { @MainActor in
            self.handleCommand(cmd)
        }
    }

    nonisolated public func session(
        _ session: WCSession,
        didReceiveMessageData messageData: Data,
        replyHandler: @escaping (Data) -> Void
    ) {
        guard let cmd = WatchCommandPayload.fromData(messageData) else {
            replyHandler(Data())
            return
        }
        Task { @MainActor in
            self.handleCommand(cmd)
            if let ctx = self.modelContainer?.mainContext,
               let replyData = try? JSONEncoder().encode(self.buildSnapshot(context: ctx)) {
                replyHandler(replyData)
            } else {
                replyHandler(Data())
            }
        }
    }

    nonisolated public func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let cmd = WatchCommandPayload.fromUserInfo(userInfo) else { return }
        Task { @MainActor in
            self.handleCommand(cmd)
        }
    }
}
#endif
