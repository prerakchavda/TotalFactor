import Foundation

/// Muscle Recovery Map engine: estimates how fatigued each muscle is right now from recent working sets,
/// plus how much work it got over the trailing 7 days.
///
/// Deterministic, inspectable rules (estimates, not measurements):
/// - Each working set adds load = role (primary 1.0, secondary 0.5) × effort from RIR
///   (0 → 1.0, 1 → 0.9, 2 → 0.8, 3 → 0.65, 4 → 0.5, 5+ → 0.3). Warm-ups and partials add nothing.
/// - A set's load fades linearly to zero over the muscle's recovery window:
///   72 h for big muscles (chest, back, quads, hamstrings, glutes), 48 h for traps, front delts and triceps,
///   36 h for small muscles (side/rear delts, biceps, forearms, calves, abs).
/// - Fatigue = remaining load ÷ 6 (≈ one hard session for a muscle), capped at 1.
/// - A muscle counts as recovered once fatigue drops below 0.1.
public enum MuscleRecoveryEngine {

    public static let fullFatigueLoad: Double = 6.0
    public static let recoveredThreshold: Double = 0.1

    public struct SetSample: Sendable {
        public var timestamp: Date
        public var primaryMuscles: [MuscleGroup]
        public var secondaryMuscles: [MuscleGroup]
        public var rir: Int
        public var setType: SetType

        public init(
            timestamp: Date,
            primaryMuscles: [MuscleGroup],
            secondaryMuscles: [MuscleGroup] = [],
            rir: Int = 2,
            setType: SetType = .working
        ) {
            self.timestamp = timestamp
            self.primaryMuscles = primaryMuscles
            self.secondaryMuscles = secondaryMuscles
            self.rir = rir
            self.setType = setType
        }
    }

    public struct MuscleStatus: Identifiable, Sendable {
        public var id: String { muscle.id }
        public var muscle: MuscleGroup
        /// 0 (fresh) … 1 (just hammered).
        public var fatigue: Double
        /// Trailing 7-day sets, secondary muscles counted as 0.5.
        public var weeklySets: Double
        public var lastTrained: Date?
        /// When fatigue is expected to fall below `recoveredThreshold`; nil if already recovered.
        public var recoveredAt: Date?

        public var isRecovered: Bool { fatigue < MuscleRecoveryEngine.recoveredThreshold }
        public var trainedThisWeek: Bool { weeklySets > 0 }
    }

    public static func recoveryHours(for muscle: MuscleGroup) -> Double {
        switch muscle {
        case .chest, .lats, .upperBack, .quads, .hamstrings, .glutes:
            return 72
        case .traps, .frontDelts, .triceps:
            return 48
        case .sideDelts, .rearDelts, .biceps, .forearms, .calves, .abs:
            return 36
        }
    }

    public static func effort(rir: Int) -> Double {
        switch rir {
        case ..<1: return 1.0
        case 1: return 0.9
        case 2: return 0.8
        case 3: return 0.65
        case 4: return 0.5
        default: return 0.3
        }
    }

    /// Status for every muscle group at `now`. Samples after `now` are ignored, so passing a past
    /// or future `now` replays or previews the map.
    public static func evaluate(samples: [SetSample], now: Date = .now) -> [MuscleGroup: MuscleStatus] {
        let weekAgo = now.addingTimeInterval(-7 * 86_400)

        // Per muscle: (timestamp, load) for each contributing set, and weighted weekly set count.
        var contributions: [MuscleGroup: [(Date, Double)]] = [:]
        var weeklySets: [MuscleGroup: Double] = [:]
        var lastTrained: [MuscleGroup: Date] = [:]

        for sample in samples where sample.setType.countsTowardWorkingStats && sample.timestamp <= now {
            let effortFactor = effort(rir: sample.rir)
            let roles: [(MuscleGroup, Double)] =
                sample.primaryMuscles.map { ($0, 1.0) } +
                sample.secondaryMuscles.filter { !sample.primaryMuscles.contains($0) }.map { ($0, 0.5) }

            for (muscle, role) in roles {
                let window = recoveryHours(for: muscle) * 3600
                if now.timeIntervalSince(sample.timestamp) < window {
                    contributions[muscle, default: []].append((sample.timestamp, role * effortFactor))
                }
                if sample.timestamp >= weekAgo {
                    weeklySets[muscle, default: 0] += role
                    if (lastTrained[muscle] ?? .distantPast) < sample.timestamp {
                        lastTrained[muscle] = sample.timestamp
                    }
                }
            }
        }

        var result: [MuscleGroup: MuscleStatus] = [:]
        for muscle in MuscleGroup.allCases {
            let sets = contributions[muscle] ?? []
            let window = recoveryHours(for: muscle) * 3600
            let fatigue = fatigueLevel(sets, at: now, window: window)

            var recoveredAt: Date? = nil
            if fatigue >= recoveredThreshold {
                // Step forward hourly until fatigue clears; bounded by the recovery window.
                var probe = now
                let limit = now.addingTimeInterval(window)
                while probe < limit {
                    probe = probe.addingTimeInterval(3600)
                    if fatigueLevel(sets, at: probe, window: window) < recoveredThreshold { break }
                }
                recoveredAt = probe
            }

            result[muscle] = MuscleStatus(
                muscle: muscle,
                fatigue: fatigue,
                weeklySets: weeklySets[muscle] ?? 0,
                lastTrained: lastTrained[muscle],
                recoveredAt: recoveredAt
            )
        }
        return result
    }

    private static func fatigueLevel(_ sets: [(Date, Double)], at time: Date, window: TimeInterval) -> Double {
        var load = 0.0
        for (timestamp, setLoad) in sets {
            let elapsed = time.timeIntervalSince(timestamp)
            guard elapsed >= 0, elapsed < window else { continue }
            load += setLoad * (1 - elapsed / window)
        }
        return min(1, load / fullFatigueLoad)
    }
}
