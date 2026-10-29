import SwiftUI
import SwiftData

/// Spec MacroFactor 7-Day Adherence Calendar Strip (v1.5.1 Kitchen Rehaul):
/// - Horizontal scroll/swipe strip of days with day-of-week initials and calendar numbers
/// - Circular adherence rings for daily calories vs target zone
/// - 1-tap switching between days with haptic feedback
struct WeekAdherenceCalendarStrip: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState

    @Query private var allEntries: [FoodLogEntry]
    @Query private var dailyNotes: [DailyNote]

    @State private var weekOffset: Int = 0

    private var activeDayKey: String {
        appState.selectedDayKey
    }

    private var calendar: Calendar {
        Calendar.current
    }

    private var currentWeekDays: [Date] {
        let baseDate = calendar.date(byAdding: .weekOfYear, value: weekOffset, to: .now) ?? .now
        guard let weekInterval = calendar.dateInterval(of: .weekOfYear, for: baseDate) else {
            return []
        }
        var days: [Date] = []
        for i in 0..<7 {
            if let d = calendar.date(byAdding: .day, value: i, to: weekInterval.start) {
                days.append(d)
            }
        }
        return days
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        weekOffset -= 1
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .padding(6)
                }
                .buttonStyle(.plain)

                Spacer()

                Text(weekHeaderTitle)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                Spacer()

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        weekOffset += 1
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .padding(6)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)

            HStack(spacing: 6) {
                ForEach(currentWeekDays, id: \.self) { date in
                    let dayKey = DayKey.from(date)
                    let isSelected = (dayKey == activeDayKey)
                    let isToday = calendar.isDateInToday(date)
                    let entriesForDay = allEntries.filter { $0.dayKey == dayKey }
                    let eatenCals = entriesForDay.reduce(0.0) { $0 + $1.snapshotCaloriesPer100g * ($1.grams / 100.0) }
                    let digest = CoachingCoordinator.cachedOrComputeDigest(forDayKey: dayKey, context: modelContext)
                    let targetCals = max(800.0, digest.todayTargets.calories)
                    let progress = min(1.3, eatenCals / targetCals)
                    let isDone = dailyNotes.first(where: { $0.dayKey == dayKey })?.isComplete ?? false

                    dayBubble(
                        date: date,
                        dayKey: dayKey,
                        isSelected: isSelected,
                        isToday: isToday,
                        isDone: isDone,
                        progress: progress,
                        eatenCals: eatenCals,
                        targetCals: targetCals
                    )
                }
            }
            .padding(.horizontal, 6)
        }
        .padding(.vertical, 8)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var weekHeaderTitle: String {
        guard let first = currentWeekDays.first, let last = currentWeekDays.last else { return "This Week" }
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        let l = DateFormatter()
        l.dateFormat = "MMM d, yyyy"
        return "\(f.string(from: first)) – \(l.string(from: last))"
    }

    private func dayBubble(
        date: Date,
        dayKey: String,
        isSelected: Bool,
        isToday: Bool,
        isDone: Bool,
        progress: Double,
        eatenCals: Double,
        targetCals: Double
    ) -> some View {
        Button {
            #if canImport(UIKit)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            appState.selectedDayKey = dayKey
        } label: {
            VStack(spacing: 4) {
                // Day Initial (M, T, W, T, F, S, S)
                Text(dayOfWeekLetter(for: date))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)

                // Adherence Circular Ring with Day Number
                ZStack {
                    Circle()
                        .stroke(Color.secondary.opacity(0.18), lineWidth: 2.5)
                        .frame(width: 32, height: 32)

                    Circle()
                        .trim(from: 0, to: CGFloat(min(1.0, progress)))
                        .stroke(
                            ringColor(progress: progress, isDone: isDone),
                            style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .frame(width: 32, height: 32)

                    Text("\(calendar.component(.day, from: date))")
                        .font(.system(size: 12, weight: isSelected ? .heavy : (isToday ? .bold : .medium)))
                        .foregroundStyle(isSelected ? Color.primary : (isToday ? Color(red: 0.18, green: 0.48, blue: 0.96) : Color.primary))
                }

                // Mini Cals Subtitle or Target status
                if eatenCals > 0 {
                    Text("\(Int(eatenCals.rounded()))")
                        .font(.system(size: 8, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text("—")
                        .font(.system(size: 8, weight: .regular))
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(
                isSelected ? Color.primary.opacity(0.10) : (isToday ? Color(red: 0.18, green: 0.48, blue: 0.96).opacity(0.06) : Color.clear),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isSelected ? Color(red: 0.18, green: 0.48, blue: 0.96) : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }

    private func dayOfWeekLetter(for date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEEEE" // Single letter day (M, T, W, T, F, S, S)
        return f.string(from: date)
    }

    private func ringColor(progress: Double, isDone: Bool) -> Color {
        if isDone { return .green }
        if progress >= 0.90 && progress <= 1.05 {
            return .green
        } else if progress > 1.05 {
            return .orange
        } else if progress > 0.05 {
            return Color(red: 0.18, green: 0.48, blue: 0.96)
        } else {
            return .clear
        }
    }
}
