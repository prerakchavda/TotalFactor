import SwiftUI

/// Spec §11 Weekly Muscle Volume Map:
/// Counts hard sets (RIR ≤ 4; primary = 1.0, secondary = 0.5) over the last 7 days and colors each muscle zone.
struct MuscleVolumeMapView: View {
    let sessions: [WorkoutSession]

    private var weeklyVolume: [MuscleGroup: Double] {
        let cutoffKey = DayKey.addingDays(-6, to: DayKey.today)
        let recentSets = sessions
            .filter { $0.isFinished && $0.dayKey >= cutoffKey }
            .flatMap { $0.sets ?? [] }
            .filter(\.isCompleted)

        let tuples: [(setType: SetType, rir: Int, primary: [MuscleGroup], secondary: [MuscleGroup])] = recentSets.compactMap { s in
            guard let ex = s.exercise else { return nil }
            return (s.type, s.rir, ex.primaryMuscles, ex.secondaryMuscles)
        }
        return ProgressionEngine.weeklyHardSetsByMuscle(entries: tuples)
    }

    var body: some View {
        let vol = weeklyVolume
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Weekly Muscle Volume Map")
                        .font(.headline)
                    Text("Hard sets last 7d (RIR ≤ 4 • Secondary = 0.5×)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("Target 10–16")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.green)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(MuscleGroup.allCases) { muscle in
                    let sets = vol[muscle] ?? 0
                    VStack(alignment: .leading, spacing: 3) {
                        Text(muscle.displayName)
                            .font(.caption2.weight(.semibold))
                            .lineLimit(1)
                        Text(String(format: "%.1f sets", sets))
                            .font(.caption.weight(.bold).monospacedDigit())
                            .foregroundStyle(zoneColor(for: sets))
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(zoneColor(for: sets).opacity(0.13), in: RoundedRectangle(cornerRadius: 10))
                }
            }
        }
        .padding(16)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
    }

    private func zoneColor(for sets: Double) -> Color {
        if sets < 4 { return .secondary }
        if sets < 10 { return .blue }
        if sets <= 17 { return .green }
        return .orange
    }
}
