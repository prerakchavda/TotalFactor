import SwiftUI
import SwiftData
import Charts

/// Workouts → Exercises: every lift you've logged with a strength trend line, so you can see at a glance
/// which exercises are going up or down. Tap one for the full charts (est. 1RM, heaviest, volume, reps) and history.
/// Must be shown inside a NavigationStack.
struct ExerciseProgressListView: View {
    let unitSystem: UnitSystem
    /// Show only the top N rows (e.g. on a summary screen); nil shows all with search and sorting.
    var limit: Int? = nil

    @Query(sort: \Exercise.name) private var exercises: [Exercise]
    @State private var search: String = ""
    @State private var sort: SortOrder = .recent

    enum SortOrder: String, CaseIterable, Identifiable {
        case recent = "Recent"
        case improved = "Most Improved"
        case mostTrained = "Most Trained"
        case name = "A–Z"
        var id: String { rawValue }
    }

    struct TrendPoint: Identifiable {
        let id = UUID()
        let date: Date
        let value: Double
    }

    struct Row: Identifiable {
        let exercise: Exercise
        var id: UUID { exercise.id }
        let points: [TrendPoint]
        let lastDate: Date
        let lastBestWeightKg: Double
        let lastBestReps: Int
        let latestE1RM: Double
        /// Est. 1RM change over the last 8 weeks (nil with fewer than 2 sessions in that window).
        let changeKg: Double?
    }

    private var rows: [Row] {
        var built = exercises.compactMap(Self.makeRow)
        let query = search.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty {
            built = built.filter { $0.exercise.name.localizedCaseInsensitiveContains(query) }
        }
        switch sort {
        case .recent:
            built.sort { $0.lastDate > $1.lastDate }
        case .improved:
            built.sort { ($0.changeKg ?? -.infinity) > ($1.changeKg ?? -.infinity) }
        case .mostTrained:
            built.sort { $0.points.count > $1.points.count }
        case .name:
            built.sort { $0.exercise.name.localizedCaseInsensitiveCompare($1.exercise.name) == .orderedAscending }
        }
        if let limit {
            return Array(built.prefix(limit))
        }
        return built
    }

    var body: some View {
        let current = rows
        VStack(alignment: .leading, spacing: 10) {
            if limit == nil {
                HStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("Search exercises", text: $search)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(AppleTheme.cardSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                    Menu {
                        Picker("Sort", selection: $sort) {
                            ForEach(SortOrder.allCases) { order in
                                Text(order.rawValue).tag(order)
                            }
                        }
                    } label: {
                        Label(sort.rawValue, systemImage: "arrow.up.arrow.down")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 9)
                            .background(AppleTheme.cardSurface, in: Capsule())
                    }
                }
            }

            if current.isEmpty {
                Text(search.isEmpty
                     ? "Finish a workout and your exercises will show up here with strength trend charts."
                     : "No logged exercises match \"\(search)\".")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(AppleTheme.cardSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                ForEach(current) { row in
                    NavigationLink {
                        ExerciseAnalyticsDetailView(exercise: row.exercise, unitSystem: unitSystem)
                    } label: {
                        rowView(row)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func rowView(_ row: Row) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(row.exercise.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text("\(UnitsFormatter.formatGymLoad(row.lastBestWeightKg, system: unitSystem)) × \(row.lastBestReps) · \(row.lastDate.formatted(.relative(presentation: .named)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            sparkline(row.points)
                .frame(width: 84, height: 34)

            VStack(alignment: .trailing, spacing: 2) {
                Text(UnitsFormatter.formatGymLoad(row.latestE1RM, system: unitSystem))
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .foregroundStyle(.primary)
                if let change = row.changeKg, abs(change) >= 0.05 {
                    Text(UnitsFormatter.formatSignedWeightDelta(change, system: unitSystem, decimals: 0))
                        .font(.caption2.weight(.semibold).monospacedDigit())
                        .foregroundStyle(change > 0 ? Color.green : Color.orange)
                } else {
                    Text("Est. 1RM")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(minWidth: 64, alignment: .trailing)

            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .background(AppleTheme.cardSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func sparkline(_ points: [TrendPoint]) -> some View {
        let recent = Array(points.suffix(12))
        if recent.count >= 2 {
            let values = recent.map(\.value)
            let low = values.min() ?? 0
            let high = values.max() ?? 1
            let pad = max(1, (high - low) * 0.15)
            Chart(recent) { point in
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Est. 1RM", point.value)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(AppleTheme.accent)
                PointMark(
                    x: .value("Date", point.date),
                    y: .value("Est. 1RM", point.value)
                )
                .symbolSize(10)
                .foregroundStyle(AppleTheme.accent)
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartYScale(domain: (low - pad)...(high + pad))
            .chartLegend(.hidden)
        } else {
            Text("1 session")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    /// Per-session best estimated 1RM for an exercise, from completed working sets.
    static func makeRow(_ exercise: Exercise) -> Row? {
        let logs = (exercise.setLogs ?? []).filter {
            $0.isCompleted && $0.type.countsTowardWorkingStats && $0.weightKg > 0 && $0.reps > 0
        }
        guard !logs.isEmpty else { return nil }
        let k = exercise.personalRepCurveK

        let bySession = Dictionary(grouping: logs) { log -> String in
            log.session?.id.uuidString ?? DayKey.from(log.timestamp)
        }

        struct SessionSummary {
            let date: Date
            let bestE1RM: Double
            let bestWeightKg: Double
            let bestReps: Int
        }

        let summaries: [SessionSummary] = bySession.values.compactMap { sets in
            guard let first = sets.first else { return nil }
            let date = first.session?.start ?? sets.map(\.timestamp).min() ?? first.timestamp
            guard let top = sets.max(by: {
                ProgressionEngine.e1RM(weight: $0.weightKg, reps: $0.reps, rir: $0.rir, k: k)
                    < ProgressionEngine.e1RM(weight: $1.weightKg, reps: $1.reps, rir: $1.rir, k: k)
            }) else { return nil }
            return SessionSummary(
                date: date,
                bestE1RM: ProgressionEngine.e1RM(weight: top.weightKg, reps: top.reps, rir: top.rir, k: k),
                bestWeightKg: top.weightKg,
                bestReps: top.reps
            )
        }
        .sorted { $0.date < $1.date }

        guard let latest = summaries.last else { return nil }

        let windowStart = Calendar.current.date(byAdding: .day, value: -56, to: latest.date) ?? latest.date
        let inWindow = summaries.filter { $0.date >= windowStart }
        let change: Double? = inWindow.count >= 2 ? latest.bestE1RM - (inWindow.first?.bestE1RM ?? latest.bestE1RM) : nil

        return Row(
            exercise: exercise,
            points: summaries.map { TrendPoint(date: $0.date, value: $0.bestE1RM) },
            lastDate: latest.date,
            lastBestWeightKg: latest.bestWeightKg,
            lastBestReps: latest.bestReps,
            latestE1RM: latest.bestE1RM,
            changeKg: change
        )
    }
}
