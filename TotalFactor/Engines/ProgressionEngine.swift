import Foundation

public struct LoggedSetSample: Equatable, Sendable {
    public var sessionDate: Date
    public var weightKg: Double
    public var reps: Int
    public var rir: Int
    public var setType: SetType

    public init(sessionDate: Date, weightKg: Double, reps: Int, rir: Int, setType: SetType = .working) {
        self.sessionDate = sessionDate
        self.weightKg = weightKg
        self.reps = reps
        self.rir = rir
        self.setType = setType
    }

    public var effectiveReps: Int {
        max(1, reps + max(0, rir))
    }
}

public struct WarmupPrescription: Identifiable, Equatable, Sendable {
    public var id: Int { step }
    public var step: Int
    public var percentageLabel: String
    public var weightKg: Double
    public var reps: Int
}

public struct PlateBreakdown: Equatable, Sendable {
    public var targetWeightKg: Double
    public var achievedWeightKg: Double
    public var barWeightKg: Double
    public var platesPerSide: [Double]

    public var remainderKg: Double {
        targetWeightKg - achievedWeightKg
    }
}

public struct DetectedPR: Equatable, Sendable {
    public var type: PRType
    /// Primary metric: kg for `e1RM`, `heaviestWeight`, and `bestSessionVolume`; rep count for `mostRepsAtWeight`.
    public var value: Double
    /// Secondary context: `weightKg` at which `mostRepsAtWeight` was achieved (or `reps` for `heaviestWeight`).
    public var secondaryValue: Double

    public init(type: PRType, value: Double, secondaryValue: Double = 0) {
        self.type = type
        self.value = value
        self.secondaryValue = secondaryValue
    }
}

public struct NextSessionSuggestion: Equatable, Sendable {
    public enum Action: String, Codable, Sendable {
        case establishBaseline
        case addWeight
        case addReps
        case holdSteadyOnCut
        case holdDueToProteinGate
        case deload
        case targetFromE1RM
    }

    public var action: Action
    public var suggestedWeightKg: Double
    public var suggestedReps: Int
    public var targetRIR: Int
    public var estimated1RMKg: Double
    public var personalK: Double
    public var coachingNote: String
    public var isProteinGated: Bool
    public var isCutAdjusted: Bool
}

public typealias ProgressionWandDiagnostic = ProgressionEngine.ProgressionWandDiagnostic

public enum ProgressionEngine {
    public struct ProgressionWandDiagnostic: Identifiable, Equatable, Sendable {
        public enum Status: String, Codable, Sendable {
            case onTrack            // Blue (Target achieved, increment load)
            case consolidation      // Yellow (Consolidating reps, deload, or protein gate)
            case repRangeExpansion  // Orange (Equipment jump too large -> expand reps)
        }

        public var id: UUID = UUID()
        public var exerciseName: String
        public var status: Status
        public var suggestedWeightKg: Double
        public var repRangeLow: Int
        public var repRangeHigh: Int
        public var targetRIR: Int
        public var headline: String
        public var detailedRationale: String
        public var equipmentJumpPercentage: Double?
        public var isRepRangeExpanded: Bool
        public var rawIncrementKg: Double

        public init(
            id: UUID = UUID(),
            exerciseName: String,
            status: Status,
            suggestedWeightKg: Double,
            repRangeLow: Int,
            repRangeHigh: Int,
            targetRIR: Int,
            headline: String,
            detailedRationale: String,
            equipmentJumpPercentage: Double? = nil,
            isRepRangeExpanded: Bool = false,
            rawIncrementKg: Double = 2.5
        ) {
            self.id = id
            self.exerciseName = exerciseName
            self.status = status
            self.suggestedWeightKg = suggestedWeightKg
            self.repRangeLow = repRangeLow
            self.repRangeHigh = repRangeHigh
            self.targetRIR = targetRIR
            self.headline = headline
            self.detailedRationale = detailedRationale
            self.equipmentJumpPercentage = equipmentJumpPercentage
            self.isRepRangeExpanded = isRepRangeExpanded
            self.rawIncrementKg = rawIncrementKg
        }
    }

    public static let defaultEpleyK: Double = 30.0

    /// Exact spec §11 effort-adjusted e1RM:
    /// `weight * (1 + Double(reps + rir) / k)`
    public static func e1RM(weight: Double, reps: Int, rir: Int, k: Double = defaultEpleyK) -> Double {
        guard weight > 0, reps > 0 else { return 0 }
        let safeK = max(12.0, min(60.0, k))
        let totalReps = Double(reps + max(0, rir))
        if totalReps <= 1.0 {
            return weight
        }
        return weight * (1.0 + totalReps / safeK)
    }

    /// Inverse of `e1RM`: solves for weight that hits `reps` at `rir` for a given `estimated1RM`.
    public static func weightForTarget(
        estimated1RM: Double,
        reps: Int,
        rir: Int,
        k: Double = defaultEpleyK
    ) -> Double {
        guard estimated1RM > 0 else { return 0 }
        let safeK = max(12.0, min(60.0, k))
        let totalReps = Double(max(1, reps) + max(0, rir))
        if totalReps <= 1.0 {
            return estimated1RM
        }
        return estimated1RM / (1.0 + totalReps / safeK)
    }

    public static func roundToIncrement(_ weight: Double, increment: Double) -> Double {
        let step = max(0.25, increment)
        return (weight / step).rounded() * step
    }

    /// Fits a personalized rep-endurance parameter `k` in `[18, 50]` from logged working sets (§11).
    /// Higher `k` = more endurance-leaning (more reps at a given % of 1RM); lower `k` = more fast-twitch.
    /// Regularizes toward `priorK = 30` when data has narrow rep spread or few samples.
    public static func fitPersonalRepCurveK(
        samples: [LoggedSetSample],
        priorK: Double = defaultEpleyK
    ) -> Double {
        let valid = samples.filter {
            $0.setType.countsTowardWorkingStats &&
            $0.weightKg > 0 &&
            $0.reps >= 1 &&
            $0.effectiveReps <= 22 &&
            $0.rir <= 4
        }
        guard valid.count >= 4 else { return priorK }

        let repValues = valid.map(\.effectiveReps)
        guard let minR = repValues.min(), let maxR = repValues.max(), (maxR - minR) >= 4 else {
            return priorK
        }

        // Regularized relative dispersion objective:
        // True personal k makes implied 1RM = w_i * (1 + r_i / k) maximally consistent across low- and high-rep sets.
        let regularizationStrength = 0.006 / Double(valid.count)
        var bestK = priorK
        var bestLoss = Double.greatestFiniteMagnitude

        var candidateK = 18.0
        while candidateK <= 50.001 {
            let impliedMaxes = valid.map { $0.weightKg * (1.0 + Double($0.effectiveReps) / candidateK) }
            let meanMax = impliedMaxes.reduce(0.0, +) / Double(impliedMaxes.count)
            if meanMax > 0 {
                let relVariance = impliedMaxes.reduce(0.0) { acc, m in
                    let relErr = (m / meanMax) - 1.0
                    return acc + (relErr * relErr)
                }
                let priorPenalty = regularizationStrength * pow((candidateK - priorK) / priorK, 2)
                let loss = relVariance + priorPenalty
                if loss < bestLoss {
                    bestLoss = loss
                    bestK = candidateK
                }
            }
            candidateK += 0.25
        }

        return (bestK * 10.0).rounded() / 10.0
    }

    /// Groups logged sets by session day and returns per-session top e1RM in chronological order.
    public static func sessionTopE1RMs(
        samples: [LoggedSetSample],
        k: Double = defaultEpleyK,
        calendar: Calendar = .current
    ) -> [(dayKey: String, topE1RM: Double, sets: [LoggedSetSample])] {
        let working = samples.filter { $0.setType.countsTowardWorkingStats && $0.weightKg > 0 && $0.reps > 0 }
        let grouped = Dictionary(grouping: working) { DayKey.from($0.sessionDate, calendar: calendar) }
        return grouped.keys.sorted().compactMap { key in
            guard let daySets = grouped[key], !daySets.isEmpty else { return nil }
            let top = daySets.map { e1RM(weight: $0.weightKg, reps: $0.reps, rir: $0.rir, k: k) }.max() ?? 0
            return (key, top, daySets)
        }
    }

    /// Generates smart next-session load & rep suggestion incorporating:
    /// - §11 Rules (e1RM blend, top-of-range progression, bottom-of-range hold, 3-session decline deload)
    /// - §12 Cut-aware progression (during deficit > 0.5%/wk, flat or minor e1RM noise counts as success)
    /// - §12 Protein gate (if trailing 7-day average protein < floor, holds off aggressive load increases)
    public static func suggestNextSession(
        history: [LoggedSetSample],
        repRangeLow: Int,
        repRangeHigh: Int,
        targetRIR: Int,
        loadIncrementKg: Double,
        personalK: Double? = nil,
        weeklyWeightChangePercentBW: Double? = nil,
        avgProteinLast7d: Double? = nil,
        proteinFloor: Double? = nil
    ) -> NextSessionSuggestion {
        let fittedK = personalK ?? fitPersonalRepCurveK(samples: history)
        let sessions = sessionTopE1RMs(samples: history, k: fittedK)

        let isAggressiveCut = (weeklyWeightChangePercentBW ?? 0) < -0.50
        let isProteinUnderFloor: Bool = {
            guard let avgP = avgProteinLast7d, let floorP = proteinFloor, floorP > 0 else { return false }
            return avgP < floorP
        }()

        guard let lastSession = sessions.last else {
            return NextSessionSuggestion(
                action: .establishBaseline,
                suggestedWeightKg: roundToIncrement(20.0, increment: loadIncrementKg),
                suggestedReps: repRangeLow,
                targetRIR: targetRIR,
                estimated1RMKg: 0,
                personalK: fittedK,
                coachingNote: "First time logging — pick a comfortable load that leaves ~\(targetRIR) reps in reserve.",
                isProteinGated: isProteinUnderFloor,
                isCutAdjusted: isAggressiveCut
            )
        }

        // Exponentially weighted blend of up to last 4 sessions
        let recentSessions = Array(sessions.suffix(4))
        var blended1RM = recentSessions[0].topE1RM
        for s in recentSessions.dropFirst() {
            blended1RM = blended1RM + 0.45 * (s.topE1RM - blended1RM)
        }

        // Check 3 consecutive declines (requires at least 4 sessions: s0 > s1 > s2 > s3)
        let declinedThreeInARow: Bool = {
            guard sessions.count >= 4 else { return false }
            let tail = Array(sessions.suffix(4))
            return tail[1].topE1RM < tail[0].topE1RM * 0.992 &&
                   tail[2].topE1RM < tail[1].topE1RM * 0.992 &&
                   tail[3].topE1RM < tail[2].topE1RM * 0.992
        }()

        let lastSets = lastSession.sets
        let primaryLastSet = lastSets.max(by: { $0.weightKg < $1.weightKg }) ?? lastSets[0]
        let lastWeight = primaryLastSet.weightKg
        let lastAvgReps = Int((Double(lastSets.reduce(0) { $0 + $1.reps }) / Double(lastSets.count)).rounded())
        let lastBestReps = lastSets.map(\.reps).max() ?? primaryLastSet.reps
        let lastMinRIR = lastSets.map(\.rir).min() ?? primaryLastSet.rir

        // 1. Deload check (with §12 Cut-Aware override for minor fluctuations)
        if declinedThreeInARow {
            let totalDropFraction = (sessions[sessions.count - 4].topE1RM - lastSession.topE1RM) / max(1.0, sessions[sessions.count - 4].topE1RM)
            if isAggressiveCut && totalDropFraction < 0.05 {
                return NextSessionSuggestion(
                    action: .holdSteadyOnCut,
                    suggestedWeightKg: roundToIncrement(lastWeight, increment: loadIncrementKg),
                    suggestedReps: max(repRangeLow, min(repRangeHigh, lastAvgReps)),
                    targetRIR: targetRIR,
                    estimated1RMKg: blended1RM,
                    personalK: fittedK,
                    coachingNote: "Cut-aware mode: maintaining load & reps during a >0.5%/wk deficit preserves muscle.",
                    isProteinGated: isProteinUnderFloor,
                    isCutAdjusted: true
                )
            } else {
                let deloadWeight = max(loadIncrementKg, roundToIncrement(lastWeight * 0.90, increment: loadIncrementKg))
                return NextSessionSuggestion(
                    action: .deload,
                    suggestedWeightKg: deloadWeight,
                    suggestedReps: repRangeLow,
                    targetRIR: targetRIR + 1,
                    estimated1RMKg: blended1RM,
                    personalK: fittedK,
                    coachingNote: "e1RM dipped 3 sessions in a row — taking a 10% deload week to shed fatigue.",
                    isProteinGated: isProteinUnderFloor,
                    isCutAdjusted: isAggressiveCut
                )
            }
        }

        // 2. Last session missed bottom of rep range -> keep weight, aim for more reps (§11 step 5)
        if lastAvgReps < repRangeLow {
            return NextSessionSuggestion(
                action: .addReps,
                suggestedWeightKg: roundToIncrement(lastWeight, increment: loadIncrementKg),
                suggestedReps: repRangeLow,
                targetRIR: targetRIR,
                estimated1RMKg: blended1RM,
                personalK: fittedK,
                coachingNote: "Missed \(repRangeLow)-rep floor last time — hold weight and build back into range.",
                isProteinGated: isProteinUnderFloor,
                isCutAdjusted: isAggressiveCut
            )
        }

        // 3. Last session hit top of rep range at or under target RIR -> add weight (§11 step 4)
        let hitTopCleanly = (lastBestReps >= repRangeHigh && lastAvgReps >= repRangeHigh - 1 && lastMinRIR >= max(0, targetRIR - 1))
        if hitTopCleanly {
            if isProteinUnderFloor {
                return NextSessionSuggestion(
                    action: .holdDueToProteinGate,
                    suggestedWeightKg: roundToIncrement(lastWeight, increment: loadIncrementKg),
                    suggestedReps: repRangeHigh,
                    targetRIR: targetRIR,
                    estimated1RMKg: blended1RM,
                    personalK: fittedK,
                    coachingNote: "Protein gate: last week's protein averaged below floor — repeat load cleanly while refueling.",
                    isProteinGated: true,
                    isCutAdjusted: isAggressiveCut
                )
            }

            let progressedWeight = roundToIncrement(lastWeight + loadIncrementKg, increment: loadIncrementKg)
            // Solve expected reps at new weight from personal e1RM curve
            let solvedWeightTop = roundToIncrement(
                weightForTarget(estimated1RM: blended1RM, reps: repRangeHigh, rir: targetRIR, k: fittedK),
                increment: loadIncrementKg
            )
            let chosenWeight = max(progressedWeight, min(progressedWeight + loadIncrementKg, solvedWeightTop))
            return NextSessionSuggestion(
                action: .addWeight,
                suggestedWeightKg: chosenWeight,
                suggestedReps: repRangeLow,
                targetRIR: targetRIR,
                estimated1RMKg: blended1RM,
                personalK: fittedK,
                coachingNote: "Hit \(repRangeHigh) reps cleanly — adding load and resetting to \(repRangeLow)+ reps.",
                isProteinGated: false,
                isCutAdjusted: isAggressiveCut
            )
        }

        // 4. Inside rep range: during steep cut holding steady is success; otherwise push +1 rep toward top of range
        if isAggressiveCut && lastAvgReps >= repRangeLow {
            return NextSessionSuggestion(
                action: .holdSteadyOnCut,
                suggestedWeightKg: roundToIncrement(lastWeight, increment: loadIncrementKg),
                suggestedReps: min(repRangeHigh, lastAvgReps),
                targetRIR: targetRIR,
                estimated1RMKg: blended1RM,
                personalK: fittedK,
                coachingNote: "Cut-aware mode: matching \(lastAvgReps) reps at this load counts as a win in a deficit.",
                isProteinGated: isProteinUnderFloor,
                isCutAdjusted: true
            )
        }

        let solvedTopWeight = roundToIncrement(
            weightForTarget(estimated1RM: blended1RM, reps: repRangeHigh, rir: targetRIR, k: fittedK),
            increment: loadIncrementKg
        )
        let workingLoad = lastWeight > 0 ? roundToIncrement(lastWeight, increment: loadIncrementKg) : max(loadIncrementKg, solvedTopWeight)
        let targetReps = min(repRangeHigh, lastAvgReps + 1)

        return NextSessionSuggestion(
            action: .addReps,
            suggestedWeightKg: workingLoad,
            suggestedReps: targetReps,
            targetRIR: targetRIR,
            estimated1RMKg: blended1RM,
            personalK: fittedK,
            coachingNote: "Aim for \(targetReps) reps at \(targetRIR) RIR before adding weight.",
            isProteinGated: isProteinUnderFloor,
            isCutAdjusted: isAggressiveCut
        )
    }

    /// Auto warm-up generator per spec §9: bar × 10, 50% × 5, 70% × 3, 85% × 1.
    public static func generateWarmupSets(
        workingWeightKg: Double,
        barWeightKg: Double = 20.0,
        loadIncrementKg: Double = 2.5
    ) -> [WarmupPrescription] {
        guard workingWeightKg > barWeightKg + loadIncrementKg else {
            return [WarmupPrescription(step: 1, percentageLabel: "Warmup", weightKg: max(loadIncrementKg, roundToIncrement(workingWeightKg * 0.6, increment: loadIncrementKg)), reps: 8)]
        }

        let candidates: [(String, Double, Int)] = [
            ("Bar", barWeightKg, 10),
            ("50%", roundToIncrement(workingWeightKg * 0.50, increment: loadIncrementKg), 5),
            ("70%", roundToIncrement(workingWeightKg * 0.70, increment: loadIncrementKg), 3),
            ("85%", roundToIncrement(workingWeightKg * 0.85, increment: loadIncrementKg), 1)
        ]

        var result: [WarmupPrescription] = []
        var lastAddedWeight = 0.0
        for (label, rawW, reps) in candidates {
            let w = max(barWeightKg, rawW)
            if w < workingWeightKg && (result.isEmpty || w > lastAddedWeight) {
                result.append(WarmupPrescription(step: result.count + 1, percentageLabel: label, weightKg: w, reps: reps))
                lastAddedWeight = w
            }
        }
        return result
    }

    /// Plate calculator per spec §9: computes plates per side for the active gym profile.
    public static func calculatePlatesPerSide(
        targetWeightKg: Double,
        barWeightKg: Double = 20.0,
        availablePlatesKg: [Double] = [25, 20, 15, 10, 5, 2.5, 1.25]
    ) -> PlateBreakdown {
        guard targetWeightKg > barWeightKg else {
            return PlateBreakdown(
                targetWeightKg: targetWeightKg,
                achievedWeightKg: barWeightKg,
                barWeightKg: barWeightKg,
                platesPerSide: []
            )
        }

        let sortedPlates = availablePlatesKg.filter { $0 > 0 }.sorted(by: >)
        var remainingPerSide = (targetWeightKg - barWeightKg) / 2.0
        var chosen: [Double] = []

        for plate in sortedPlates {
            while remainingPerSide + 0.001 >= plate {
                chosen.append(plate)
                remainingPerSide -= plate
            }
        }

        let achieved = barWeightKg + (chosen.reduce(0, +) * 2.0)
        return PlateBreakdown(
            targetWeightKg: targetWeightKg,
            achievedWeightKg: achieved,
            barWeightKg: barWeightKg,
            platesPerSide: chosen
        )
    }

    /// Weekly hard sets per muscle per spec §11: working sets at RIR ≤ 4 count 1.0 for primary, 0.5 for secondary.
    public static func weeklyHardSetsByMuscle(
        entries: [(setType: SetType, rir: Int, primary: [MuscleGroup], secondary: [MuscleGroup])]
    ) -> [MuscleGroup: Double] {
        var totals: [MuscleGroup: Double] = [:]
        for m in MuscleGroup.allCases { totals[m] = 0.0 }

        for entry in entries {
            guard entry.setType.countsTowardWorkingStats && entry.rir <= 4 else { continue }
            for p in entry.primary {
                totals[p, default: 0.0] += 1.0
            }
            for s in entry.secondary where !entry.primary.contains(s) {
                totals[s, default: 0.0] += 0.5
            }
        }
        return totals
    }

    /// Evaluates all 4 Personal Record types (§2 & §11):
    /// `e1RM`, `heaviestWeight`, `mostRepsAtWeight`, and `bestSessionVolume`.
    public static func detectSessionPRs(
        priorSets: [LoggedSetSample],
        sessionSets: [LoggedSetSample],
        k: Double = defaultEpleyK,
        calendar: Calendar = .current
    ) -> [DetectedPR] {
        let validSession = sessionSets.filter { $0.setType.countsTowardWorkingStats && $0.weightKg > 0 && $0.reps > 0 }
        guard !validSession.isEmpty else { return [] }

        let validPrior = priorSets.filter { $0.setType.countsTowardWorkingStats && $0.weightKg > 0 && $0.reps > 0 }
        var awarded: [DetectedPR] = []

        // 1. Estimated 1RM PR
        let prevBest1RM = validPrior.map { e1RM(weight: $0.weightKg, reps: $0.reps, rir: $0.rir, k: k) }.max() ?? 0
        if let bestSet = validSession.max(by: {
            e1RM(weight: $0.weightKg, reps: $0.reps, rir: $0.rir, k: k) <
            e1RM(weight: $1.weightKg, reps: $1.reps, rir: $1.rir, k: k)
        }) {
            let session1RM = e1RM(weight: bestSet.weightKg, reps: bestSet.reps, rir: bestSet.rir, k: k)
            if session1RM > prevBest1RM + 0.1 {
                awarded.append(DetectedPR(type: .e1RM, value: session1RM, secondaryValue: bestSet.weightKg))
            }
        }

        // 2. Heaviest Weight PR
        let prevHeaviest = validPrior.map(\.weightKg).max() ?? 0
        if let heaviestSet = validSession.max(by: { $0.weightKg < $1.weightKg }),
           heaviestSet.weightKg > prevHeaviest + 0.1 {
            awarded.append(DetectedPR(type: .heaviestWeight, value: heaviestSet.weightKg, secondaryValue: Double(heaviestSet.reps)))
        }

        // 3. Most Reps at Weight PR (`mostRepsAtWeight`):
        // Requires prior history at the same or heavier load, and strictly more reps than ever hit at >= that load.
        if !validPrior.isEmpty {
            var bestRepPRCandidate: (weightKg: Double, reps: Int)? = nil
            for candidate in validSession {
                let priorAtOrAbove = validPrior.filter { $0.weightKg >= candidate.weightKg - 0.1 }
                guard !priorAtOrAbove.isEmpty else { continue }
                let priorMaxReps = priorAtOrAbove.map(\.reps).max() ?? 0
                if candidate.reps > priorMaxReps {
                    if let currentBest = bestRepPRCandidate {
                        if candidate.weightKg > currentBest.weightKg ||
                           (abs(candidate.weightKg - currentBest.weightKg) < 0.1 && candidate.reps > currentBest.reps) {
                            bestRepPRCandidate = (candidate.weightKg, candidate.reps)
                        }
                    } else {
                        bestRepPRCandidate = (candidate.weightKg, candidate.reps)
                    }
                }
            }
            if let repPR = bestRepPRCandidate {
                awarded.append(
                    DetectedPR(
                        type: .mostRepsAtWeight,
                        value: Double(repPR.reps),
                        secondaryValue: repPR.weightKg
                    )
                )
            }
        }

        // 4. Best Session Volume PR
        let sessionVolume = validSession.reduce(0.0) { $0 + ($1.weightKg * Double($1.reps)) }
        let priorVolumeByDay = Dictionary(grouping: validPrior) { DayKey.from($0.sessionDate, calendar: calendar) }
            .mapValues { sets in sets.reduce(0.0) { $0 + ($1.weightKg * Double($1.reps)) } }
        let prevBestVolume = priorVolumeByDay.values.max() ?? 0
        if sessionVolume > prevBestVolume + 1.0 {
            awarded.append(DetectedPR(type: .bestSessionVolume, value: sessionVolume, secondaryValue: Double(validSession.count)))
        }

        return awarded
    }

    /// MacroFactor Workouts Progression Wand Diagnostic (§9 & Smart Overload):
    /// Analyzes performance against target rep ceilings, protein gates, cut adjustments,
    /// and detects coarse equipment increments to dynamically expand rep ranges.
    public static func evaluateProgressionWand(
        exerciseName: String,
        suggestion: NextSessionSuggestion,
        repRangeLow: Int,
        repRangeHigh: Int,
        loadIncrementKg: Double,
        lastWorkingWeightKg: Double?
    ) -> ProgressionWandDiagnostic {
        let baseWeight = lastWorkingWeightKg ?? suggestion.suggestedWeightKg
        let jumpFraction: Double? = (baseWeight > 0) ? (loadIncrementKg / baseWeight) : nil
        let jumpPct: Double? = jumpFraction.map { $0 * 100.0 }

        // Equipment Gap / Rep Range Expansion Check:
        // When the smallest available jump in load is >= 12.5% of working weight
        // (typical with dumbbell jumps, e.g. 20kg -> 22.5kg = +12.5%), jumping load directly
        // risks premature plateauing or form breakdown. Smart Progression dynamically expands the
        // rep range by +3 reps (e.g., 8–12 becomes 8–15) to build work capacity before adding load.
        let isLargeEquipmentJump = (jumpFraction ?? 0.0) >= 0.125
        if isLargeEquipmentJump && suggestion.action == .addWeight {
            let expandedHigh = repRangeHigh + 3
            return ProgressionWandDiagnostic(
                exerciseName: exerciseName,
                status: .repRangeExpansion,
                suggestedWeightKg: baseWeight,
                repRangeLow: repRangeLow,
                repRangeHigh: expandedHigh,
                targetRIR: suggestion.targetRIR,
                headline: "Rep Range Expanded (\(repRangeLow)–\(expandedHigh))",
                detailedRationale: String(
                    format: "The smallest available equipment jump (+%.1f kg, ~%.0f%%) is too large for an optimal strength progression. We expanded your rep ceiling to %d reps to build capacity safely before adding load.",
                    loadIncrementKg,
                    jumpPct ?? 0,
                    expandedHigh
                ),
                equipmentJumpPercentage: jumpPct,
                isRepRangeExpanded: true,
                rawIncrementKg: loadIncrementKg
            )
        }

        switch suggestion.action {
        case .addWeight:
            return ProgressionWandDiagnostic(
                exerciseName: exerciseName,
                status: .onTrack,
                suggestedWeightKg: suggestion.suggestedWeightKg,
                repRangeLow: repRangeLow,
                repRangeHigh: repRangeHigh,
                targetRIR: suggestion.targetRIR,
                headline: "Target Reached • Added Load",
                detailedRationale: "All working sets completed at or above the \(repRangeHigh)-rep ceiling with clean execution. Progressive overload bumped load to \(suggestion.suggestedWeightKg) kg.",
                equipmentJumpPercentage: jumpPct,
                isRepRangeExpanded: false,
                rawIncrementKg: loadIncrementKg
            )
        case .addReps:
            return ProgressionWandDiagnostic(
                exerciseName: exerciseName,
                status: .consolidation,
                suggestedWeightKg: suggestion.suggestedWeightKg,
                repRangeLow: repRangeLow,
                repRangeHigh: repRangeHigh,
                targetRIR: suggestion.targetRIR,
                headline: "Consolidating Rep Volume",
                detailedRationale: "Building toward the \(repRangeHigh)-rep ceiling at \(suggestion.suggestedWeightKg) kg with controlled cadence. Target \(suggestion.suggestedReps) reps at \(suggestion.targetRIR) RIR.",
                equipmentJumpPercentage: jumpPct,
                isRepRangeExpanded: false,
                rawIncrementKg: loadIncrementKg
            )
        case .deload:
            return ProgressionWandDiagnostic(
                exerciseName: exerciseName,
                status: .consolidation,
                suggestedWeightKg: suggestion.suggestedWeightKg,
                repRangeLow: repRangeLow,
                repRangeHigh: repRangeHigh,
                targetRIR: suggestion.targetRIR,
                headline: "Deload Session Active",
                detailedRationale: "Accumulated fatigue detected across consecutive sessions. Load reduced by 10% to reset neuromuscular recovery while maintaining movement patterns.",
                equipmentJumpPercentage: jumpPct,
                isRepRangeExpanded: false,
                rawIncrementKg: loadIncrementKg
            )
        case .holdDueToProteinGate:
            return ProgressionWandDiagnostic(
                exerciseName: exerciseName,
                status: .consolidation,
                suggestedWeightKg: suggestion.suggestedWeightKg,
                repRangeLow: repRangeLow,
                repRangeHigh: repRangeHigh,
                targetRIR: suggestion.targetRIR,
                headline: "Protein Gate Active",
                detailedRationale: "Last week's average daily protein fell below your recovery floor. Holding load steady to protect muscle tissue until nutrition targets recover.",
                equipmentJumpPercentage: jumpPct,
                isRepRangeExpanded: false,
                rawIncrementKg: loadIncrementKg
            )
        case .holdSteadyOnCut:
            return ProgressionWandDiagnostic(
                exerciseName: exerciseName,
                status: .consolidation,
                suggestedWeightKg: suggestion.suggestedWeightKg,
                repRangeLow: repRangeLow,
                repRangeHigh: repRangeHigh,
                targetRIR: suggestion.targetRIR,
                headline: "Deficit Preservation",
                detailedRationale: "In an active calorie deficit. Maintaining load and rep capacity preserves lean mass without inducing excessive systemic fatigue.",
                equipmentJumpPercentage: jumpPct,
                isRepRangeExpanded: false,
                rawIncrementKg: loadIncrementKg
            )
        case .establishBaseline, .targetFromE1RM:
            return ProgressionWandDiagnostic(
                exerciseName: exerciseName,
                status: .consolidation,
                suggestedWeightKg: suggestion.suggestedWeightKg,
                repRangeLow: repRangeLow,
                repRangeHigh: repRangeHigh,
                targetRIR: suggestion.targetRIR,
                headline: "Calibration Session",
                detailedRationale: "Initial calibration set. Select a load that allows \(repRangeLow)–\(repRangeHigh) reps with ~\(suggestion.targetRIR) reps in reserve.",
                equipmentJumpPercentage: jumpPct,
                isRepRangeExpanded: false,
                rawIncrementKg: loadIncrementKg
            )
        }
    }

    /// MacroFactor Workouts Exercise Substitution Engine (§9):
    /// Ranks available library exercises for in-session swapping based on:
    /// 1. Exact movement pattern match (horizontal push, hinge, squat, etc.)
    /// 2. Primary muscle overlap
    /// 3. Equipment availability in the user's active GymProfile.
    public static func swapCandidates(
        for currentExercise: ExerciseBlueprint,
        in library: [ExerciseBlueprint],
        availableEquipment: Set<Equipment>? = nil
    ) -> [ExerciseBlueprint] {
        let currentID = currentExercise.id
        let currentPattern = currentExercise.movementPattern
        let currentPrimaries = Set(currentExercise.primaryMuscles)

        let candidates = library.filter { ex in
            guard ex.id != currentID else { return false }
            if let available = availableEquipment, !available.contains(ex.equipment) {
                return false
            }
            return true
        }

        return candidates.sorted { a, b in
            let aPatternMatch = (a.movementPattern == currentPattern)
            let bPatternMatch = (b.movementPattern == currentPattern)

            let aMuscleOverlap = Set(a.primaryMuscles).intersection(currentPrimaries).count
            let bMuscleOverlap = Set(b.primaryMuscles).intersection(currentPrimaries).count

            if aPatternMatch != bPatternMatch {
                return aPatternMatch && !bPatternMatch
            }
            if aMuscleOverlap != bMuscleOverlap {
                return aMuscleOverlap > bMuscleOverlap
            }
            return a.name < b.name
        }
    }
}
