import Foundation

/// MacroFactor Workouts Weekly Hypertrophy Volume Landmarks Engine:
/// Computes trailing 7-day hard sets per muscle group and maps against evidence-based
/// volume landmarks (Israetel / Schoenfeld / Helms / SBS):
/// - MV (Maintenance Volume): 4–6 sets
/// - MEV (Minimum Effective Volume): 8–10 sets
/// - MAV (Maximum Adaptive Volume): 12–20 sets
/// - MRV (Maximum Recoverable Volume): 22+ sets
public enum HypertrophyVolumeEngine {

    public struct VolumeSetEntry: Sendable {
        public var timestamp: Date
        public var primaryMuscles: [MuscleGroup]
        public var secondaryMuscles: [MuscleGroup]
        public var isCompleted: Bool
        public var setType: SetType

        public init(
            timestamp: Date,
            primaryMuscles: [MuscleGroup],
            secondaryMuscles: [MuscleGroup] = [],
            isCompleted: Bool = true,
            setType: SetType = .working
        ) {
            self.timestamp = timestamp
            self.primaryMuscles = primaryMuscles
            self.secondaryMuscles = secondaryMuscles
            self.isCompleted = isCompleted
            self.setType = setType
        }
    }

    public enum VolumeZone: String, Sendable, CaseIterable {
        case maintenance // < MEV (0 - 7 sets)
        case effective   // MEV - lower MAV (8 - 11 sets)
        case optimal     // Peak MAV (12 - 20 sets)
        case overreaching // >= MRV (21+ sets)

        public var displayName: String {
            switch self {
            case .maintenance: return "Maintenance (MV)"
            case .effective: return "Effective (MEV)"
            case .optimal: return "Optimal Growth (MAV)"
            case .overreaching: return "High Fatigue (MRV)"
            }
        }
    }

    public struct MuscleVolumeStatus: Identifiable, Sendable {
        public var id: String { muscle.id }
        public var muscle: MuscleGroup
        public var weeklyHardSets: Double
        public var directSets: Int
        public var indirectSets: Int
        public var mevThreshold: Double = 8.0
        public var mavHighThreshold: Double = 20.0
        public var zone: VolumeZone {
            if weeklyHardSets < 8.0 {
                return .maintenance
            } else if weeklyHardSets < 12.0 {
                return .effective
            } else if weeklyHardSets <= 20.0 {
                return .optimal
            } else {
                return .overreaching
            }
        }

        public var targetPercentage: Double {
            min(1.25, weeklyHardSets / mavHighThreshold)
        }

        public init(
            muscle: MuscleGroup,
            weeklyHardSets: Double,
            directSets: Int,
            indirectSets: Int,
            mevThreshold: Double = 8.0,
            mavHighThreshold: Double = 20.0
        ) {
            self.muscle = muscle
            self.weeklyHardSets = weeklyHardSets
            self.directSets = directSets
            self.indirectSets = indirectSets
            self.mevThreshold = mevThreshold
            self.mavHighThreshold = mavHighThreshold
        }
    }

    /// Evaluates weekly sets by muscle group from completed set entries in the trailing 7 days.
    public static func evaluateWeeklyVolume(
        entries: [VolumeSetEntry],
        referenceDate: Date = .now
    ) -> [MuscleVolumeStatus] {
        let sevenDaysAgo = referenceDate.addingTimeInterval(-7 * 86400)
        let recentEntries = entries.filter { $0.timestamp >= sevenDaysAgo && $0.isCompleted && $0.setType.countsTowardWorkingStats }

        var directCounts: [MuscleGroup: Int] = [:]
        var indirectCounts: [MuscleGroup: Int] = [:]

        for m in MuscleGroup.allCases {
            directCounts[m] = 0
            indirectCounts[m] = 0
        }

        for entry in recentEntries {
            for p in entry.primaryMuscles {
                directCounts[p, default: 0] += 1
            }
            for sec in entry.secondaryMuscles where !entry.primaryMuscles.contains(sec) {
                indirectCounts[sec, default: 0] += 1
            }
        }

        let majorMuscles: [MuscleGroup] = [
            .chest, .lats, .upperBack, .quads, .hamstrings, .glutes,
            .sideDelts, .rearDelts, .biceps, .triceps, .calves, .abs
        ]

        return majorMuscles.map { m in
            let direct = directCounts[m] ?? 0
            let indirect = indirectCounts[m] ?? 0
            let total = Double(direct) + (Double(indirect) * 0.5)
            return MuscleVolumeStatus(
                muscle: m,
                weeklyHardSets: total,
                directSets: direct,
                indirectSets: indirect
            )
        }
    }
}
