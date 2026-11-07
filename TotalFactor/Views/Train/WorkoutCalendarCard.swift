import SwiftUI
import Charts

/// Strong-style training calendar: month grid with workout days filled in, week/month/streak stats,
/// and a workouts-per-week bar chart for the last 12 weeks. Tapping a workout day opens that session.
struct WorkoutCalendarCard: View {
    let sessions: [WorkoutSession]
    let onSelect: (WorkoutSession) -> Void

    @State private var monthOffset: Int = 0

    private let calendar = Calendar.current

    private struct WeekCount: Identifiable {
        var id: Date { weekStart }
        let weekStart: Date
        let count: Int
    }

    var body: some View {
        let finished = sessions.filter(\.isFinished)
        let sessionsByDay = Dictionary(grouping: finished, by: \.dayKey)
        let month = displayedMonthStart

        VStack(alignment: .leading, spacing: 14) {
            monthHeader(month: month)

            statsRow(finished: finished, month: month)

            weekdayHeader

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 6) {
                let cells = monthCells(for: month)
                ForEach(cells.indices, id: \.self) { idx in
                    if let day = cells[idx] {
                        dayCell(day, sessions: sessionsByDay[DayKey.from(day)] ?? [])
                    } else {
                        Color.clear.frame(height: 34)
                    }
                }
            }

            Rectangle()
                .fill(AppleTheme.hairline)
                .frame(height: 0.5)

            weeklyChart(finished: finished)
        }
        .mfCard()
    }

    // MARK: - Header & Stats

    private var displayedMonthStart: Date {
        let currentMonth = calendar.dateInterval(of: .month, for: .now)?.start ?? .now
        return calendar.date(byAdding: .month, value: monthOffset, to: currentMonth) ?? currentMonth
    }

    private func monthHeader(month: Date) -> some View {
        HStack {
            Text(month.formatted(.dateTime.month(.wide).year()))
                .font(.headline)
            Spacer()
            Button {
                monthOffset -= 1
            } label: {
                MFCircleIcon("chevron.left", size: 30)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Previous Month")

            Button {
                monthOffset += 1
            } label: {
                MFCircleIcon("chevron.right", size: 30)
            }
            .buttonStyle(.plain)
            .disabled(monthOffset >= 0)
            .opacity(monthOffset >= 0 ? 0.35 : 1)
            .accessibilityLabel("Next Month")
        }
    }

    private func statsRow(finished: [WorkoutSession], month: Date) -> some View {
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: .now)?.start ?? .now
        let thisWeek = finished.filter { $0.start >= weekStart }.count
        let monthEnd = calendar.date(byAdding: .month, value: 1, to: month) ?? month
        let inMonth = finished.filter { $0.start >= month && $0.start < monthEnd }.count

        return HStack(spacing: 8) {
            statTile(value: "\(thisWeek)", label: "This Week")
            statTile(value: "\(inMonth)", label: monthOffset == 0 ? "This Month" : month.formatted(.dateTime.month(.abbreviated)))
            statTile(value: "\(weekStreak(finished: finished))", label: "Week Streak")
            statTile(value: "\(finished.count)", label: "All Time")
        }
    }

    private func statTile(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.headline.monospacedDigit())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(AppleTheme.tertiarySurface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    /// Consecutive weeks with at least one workout, counting back from this week
    /// (an empty current week doesn't break the streak until it's over).
    private func weekStreak(finished: [WorkoutSession]) -> Int {
        let trainedWeeks = Set(finished.compactMap { calendar.dateInterval(of: .weekOfYear, for: $0.start)?.start })
        guard var cursor = calendar.dateInterval(of: .weekOfYear, for: .now)?.start else { return 0 }
        if !trainedWeeks.contains(cursor) {
            guard let lastWeek = calendar.date(byAdding: .weekOfYear, value: -1, to: cursor) else { return 0 }
            cursor = lastWeek
        }
        var streak = 0
        while trainedWeeks.contains(cursor) {
            streak += 1
            guard let previous = calendar.date(byAdding: .weekOfYear, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return streak
    }

    // MARK: - Month Grid

    private var weekdayHeader: some View {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = max(0, min(symbols.count - 1, calendar.firstWeekday - 1))
        let ordered = Array(symbols[first...]) + Array(symbols[..<first])
        return HStack(spacing: 2) {
            ForEach(Array(ordered.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    /// Leading `nil`s pad the first row so day 1 lands under its weekday.
    private func monthCells(for month: Date) -> [Date?] {
        let dayCount = calendar.range(of: .day, in: .month, for: month)?.count ?? 30
        let firstWeekday = calendar.component(.weekday, from: month)
        let leading = (firstWeekday - calendar.firstWeekday + 7) % 7
        var cells: [Date?] = Array(repeating: nil, count: leading)
        for offset in 0..<dayCount {
            cells.append(calendar.date(byAdding: .day, value: offset, to: month))
        }
        return cells
    }

    private func dayCell(_ day: Date, sessions daySessions: [WorkoutSession]) -> some View {
        let trained = !daySessions.isEmpty
        let isToday = calendar.isDateInToday(day)
        let isFuture = day > Date.now

        return Button {
            if let first = daySessions.min(by: { $0.start < $1.start }) {
                onSelect(first)
            }
        } label: {
            Text("\(calendar.component(.day, from: day))")
                .font(.footnote.weight(trained ? .bold : .regular))
                .monospacedDigit()
                .foregroundStyle(trained ? Color.black : (isFuture ? Color.secondary : Color.primary))
                .frame(width: 32, height: 32)
                .background(Circle().fill(trained ? AppleTheme.exercise : Color.clear))
                .overlay(Circle().stroke(isToday ? Color.primary : Color.clear, lineWidth: 1.5))
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(day.formatted(date: .complete, time: .omitted) + (trained ? ", \(daySessions.count) workout" : ""))
    }

    // MARK: - Weekly Chart

    private func weeklyChart(finished: [WorkoutSession]) -> some View {
        let counts = weeklyCounts(finished: finished, weeks: 12)
        let average = counts.isEmpty ? 0 : Double(counts.map(\.count).reduce(0, +)) / Double(counts.count)

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Workouts per Week")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(String(format: "%.1f avg • 12 wks", average))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Chart(counts) { week in
                BarMark(
                    x: .value("Week", week.weekStart, unit: .weekOfYear),
                    y: .value("Workouts", week.count)
                )
                .foregroundStyle(AppleTheme.exercise)
                .cornerRadius(3)
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3))
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .month)) { _ in
                    AxisValueLabel(format: .dateTime.month(.abbreviated))
                }
            }
            .frame(height: 110)
        }
    }

    private func weeklyCounts(finished: [WorkoutSession], weeks: Int) -> [WeekCount] {
        guard let currentWeek = calendar.dateInterval(of: .weekOfYear, for: .now)?.start else { return [] }
        let byWeek = Dictionary(grouping: finished) { calendar.dateInterval(of: .weekOfYear, for: $0.start)?.start ?? $0.start }
        return (0..<weeks).reversed().compactMap { back in
            guard let weekStart = calendar.date(byAdding: .weekOfYear, value: -back, to: currentWeek) else { return nil }
            return WeekCount(weekStart: weekStart, count: byWeek[weekStart]?.count ?? 0)
        }
    }
}
