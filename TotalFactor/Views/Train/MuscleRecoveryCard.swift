import SwiftUI

/// Weekly muscle map on the Workouts tab.
/// - Recovery: how fatigued each muscle is now (red → orange → yellow → green as it recovers), with a
///   +1/+2/+3 day preview to watch it fade.
/// - This Week: how much work each muscle got over the last 7 days.
struct MuscleRecoveryCard: View {
    let sessions: [WorkoutSession]

    private enum Mode: String, CaseIterable, Identifiable {
        case recovery = "Recovery"
        case week = "This Week"

        var id: String { rawValue }
    }

    @State private var mode: Mode = .recovery
    @State private var previewDays: Int = 0
    @State private var showAllMuscles: Bool = false

    /// Weekly sets that fill a muscle completely in This Week mode (top of the 12–20 growth range).
    private static let fullWeekSets: Double = 16

    var body: some View {
        let referenceDate = Date.now.addingTimeInterval(TimeInterval(previewDays) * 86_400)
        let samples = Self.samples(from: sessions, since: referenceDate.addingTimeInterval(-8 * 86_400))
        let statuses = MuscleRecoveryEngine.evaluate(samples: samples, now: referenceDate)
        let active = statuses.values
            .filter { $0.trainedThisWeek || !$0.isRecovered }
            .sorted { lhs, rhs in
                switch mode {
                case .recovery:
                    if lhs.fatigue != rhs.fatigue { return lhs.fatigue > rhs.fatigue }
                    return lhs.weeklySets > rhs.weeklySets
                case .week:
                    return lhs.weeklySets > rhs.weeklySets
                }
            }

        VStack(alignment: .leading, spacing: 14) {
            Picker("View", selection: $mode) {
                ForEach(Mode.allCases) { m in
                    Text(m.rawValue).tag(m)
                }
            }
            .pickerStyle(.segmented)

            AnatomicalHumanoidHeatmapView(
                muscleColors: colors(for: statuses),
                muscleWeights: weights(for: statuses),
                height: 220,
                showLabels: true
            )
            .frame(maxWidth: .infinity)

            legend
                .font(.caption2)
                .foregroundStyle(.secondary)

            if mode == .recovery {
                Picker("Preview", selection: $previewDays) {
                    Text("Now").tag(0)
                    Text("+1 day").tag(1)
                    Text("+2 days").tag(2)
                    Text("+3 days").tag(3)
                }
                .pickerStyle(.segmented)
            }

            if active.isEmpty {
                Text("Finish a workout to see which muscles you worked this week and how they recover day by day.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 8) {
                    ForEach(showAllMuscles ? active : Array(active.prefix(5))) { status in
                        muscleRow(status)
                    }
                }

                if active.count > 5 {
                    Button(showAllMuscles ? "Show Less" : "Show All \(active.count) Muscles") {
                        withAnimation { showAllMuscles.toggle() }
                    }
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity)
                }
            }

            Text("Estimated from your sets, how close to failure they were (RIR), and typical recovery times: about 3 days for big muscles, 1.5–2 for small ones. A guide, not a measurement.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .mfCard()
    }

    // MARK: - Rows & Legend

    private func muscleRow(_ status: MuscleRecoveryEngine.MuscleStatus) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(color(for: status) ?? AppleTheme.tertiarySurface)
                .frame(width: 12, height: 12)

            VStack(alignment: .leading, spacing: 1) {
                Text(status.muscle.displayName)
                    .font(.subheadline.weight(.semibold))
                Text(detailLine(status))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(trailingText(status))
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(mode == .recovery && !status.isRecovered ? Color.primary : Color.secondary)
        }
    }

    private func detailLine(_ status: MuscleRecoveryEngine.MuscleStatus) -> String {
        let sets = String(format: status.weeklySets == status.weeklySets.rounded() ? "%.0f" : "%.1f", status.weeklySets)
        guard let last = status.lastTrained else { return "\(sets) sets this week" }
        return "\(sets) sets this week • \(Self.relativeDay(last))"
    }

    private func trailingText(_ status: MuscleRecoveryEngine.MuscleStatus) -> String {
        switch mode {
        case .week:
            return "\(Int((min(1, status.weeklySets / Self.fullWeekSets) * 100).rounded()))%"
        case .recovery:
            guard let ready = status.recoveredAt else { return "Fresh" }
            let hours = ready.timeIntervalSinceNow / 3600
            if hours <= 0 { return "Fresh" }
            if hours < 20 { return "Fresh in \(Int(hours.rounded(.up)))h" }
            return "Fresh " + ready.formatted(.dateTime.weekday(.abbreviated).hour())
        }
    }

    @ViewBuilder
    private var legend: some View {
        switch mode {
        case .recovery:
            HStack(spacing: 12) {
                legendDot(Self.fatiguedColor, "Fatigued")
                legendDot(Self.recoveringColor, "Recovering")
                legendDot(Self.nearlyColor, "Nearly")
                legendDot(Self.freshColor, "Fresh")
            }
        case .week:
            HStack(spacing: 8) {
                Text("Light")
                LinearGradient(
                    colors: [AppleTheme.accent.opacity(0.3), AppleTheme.accent],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(height: 6)
                .clipShape(Capsule())
                Text("\(Int(Self.fullWeekSets))+ sets")
            }
        }
    }

    private func legendDot(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label)
        }
    }

    // MARK: - Colors

    private static let fatiguedColor = Color.red
    private static let recoveringColor = Color.orange
    private static let nearlyColor = Color.yellow
    private static let freshColor = Color.green

    /// nil means "draw the neutral body color" (not trained recently).
    private func color(for status: MuscleRecoveryEngine.MuscleStatus) -> Color? {
        switch mode {
        case .recovery:
            if status.fatigue >= 0.66 { return Self.fatiguedColor }
            if status.fatigue >= 0.4 { return Self.recoveringColor }
            if status.fatigue >= MuscleRecoveryEngine.recoveredThreshold { return Self.nearlyColor }
            return status.trainedThisWeek ? Self.freshColor.opacity(0.75) : nil
        case .week:
            guard status.weeklySets > 0 else { return nil }
            let intensity = min(1, status.weeklySets / Self.fullWeekSets)
            return AppleTheme.accent.opacity(0.3 + 0.7 * intensity)
        }
    }

    private func colors(for statuses: [MuscleGroup: MuscleRecoveryEngine.MuscleStatus]) -> [MuscleGroup: Color] {
        var result: [MuscleGroup: Color] = [:]
        for (muscle, status) in statuses {
            if let c = color(for: status) {
                result[muscle] = c
            }
        }
        return result
    }

    private func weights(for statuses: [MuscleGroup: MuscleRecoveryEngine.MuscleStatus]) -> [MuscleGroup: Double] {
        statuses.mapValues { status in
            mode == .recovery ? status.fatigue + min(status.weeklySets, 50) / 1000 : status.weeklySets
        }
    }

    // MARK: - Data

    /// Completed sets from recent sessions. Uses each set's own completion time when it falls inside the
    /// session (imports and edits can leave odd timestamps), otherwise the session start.
    static func samples(from sessions: [WorkoutSession], since: Date) -> [MuscleRecoveryEngine.SetSample] {
        var result: [MuscleRecoveryEngine.SetSample] = []
        for session in sessions where session.start >= since {
            let windowStart = session.start.addingTimeInterval(-3600)
            let windowEnd = (session.end ?? .now).addingTimeInterval(3600)
            for set in session.sets ?? [] where set.isCompleted {
                guard let ex = set.exercise else { continue }
                let inSession = set.timestamp >= windowStart && set.timestamp <= windowEnd
                result.append(
                    MuscleRecoveryEngine.SetSample(
                        timestamp: inSession ? set.timestamp : session.start,
                        primaryMuscles: ex.primaryMuscles,
                        secondaryMuscles: ex.secondaryMuscles,
                        rir: set.rir,
                        setType: set.type
                    )
                )
            }
        }
        return result
    }

    private static func relativeDay(_ date: Date) -> String {
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: .now)).day ?? 0
        switch days {
        case ..<1: return "today"
        case 1: return "yesterday"
        default: return "\(days)d ago"
        }
    }
}
