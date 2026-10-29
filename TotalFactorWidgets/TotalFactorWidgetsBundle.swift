import SwiftUI
import WidgetKit
import AppIntents

struct TotalFactorWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetDashboardSnapshot
}

struct TotalFactorTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> TotalFactorWidgetEntry {
        TotalFactorWidgetEntry(date: .now, snapshot: WidgetDashboardSnapshot())
    }

    func getSnapshot(in context: Context, completion: @escaping (TotalFactorWidgetEntry) -> Void) {
        completion(TotalFactorWidgetEntry(date: .now, snapshot: SharedSnapshotStore.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TotalFactorWidgetEntry>) -> Void) {
        let entry = TotalFactorWidgetEntry(date: .now, snapshot: SharedSnapshotStore.load())
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 30, to: .now) ?? .now.addingTimeInterval(1800)
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }
}

struct MacrosRemainingWidget: Widget {
    let kind = "TotalFactorMacrosWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TotalFactorTimelineProvider()) { entry in
            let s = entry.snapshot
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(Int(s.caloriesRemaining.rounded()))")
                            .font(.title2.weight(.heavy).monospacedDigit())
                            .foregroundStyle(.orange)
                        Text("kcal remaining")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(intent: WidgetQuickAddCaloriesIntent(calories: 200)) {
                        Text("+200")
                            .font(.caption2.weight(.bold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                }

                Spacer(minLength: 2)

                HStack(spacing: 8) {
                    miniStat("P", left: s.proteinTarget - s.proteinEaten, color: .red)
                    miniStat("C", left: s.carbsTarget - s.carbsEaten, color: .blue)
                    miniStat("F", left: s.fatTarget - s.fatEaten, color: .yellow)
                }
            }
            .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Macros Remaining")
        .description("Live calories and macros left today with interactive quick-add.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }

    private func miniStat(_ label: String, left: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.caption2.weight(.bold)).foregroundStyle(color)
            Text("\(Int(max(0, left).rounded()))g")
                .font(.caption.weight(.semibold).monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct TrendAndWorkoutWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let snapshot: WidgetDashboardSnapshot

    private var isImperial: Bool {
        snapshot.unitSystemRaw == "imperial"
    }

    private var unitLabel: String {
        isImperial ? "lb" : "kg"
    }

    private func formatKg(_ kg: Double) -> String {
        let val = isImperial ? (kg * 2.2046226218) : kg
        return String(format: "%.1f", val)
    }

    private var trendText: String {
        guard let kg = snapshot.trendWeightKg else { return "—" }
        return "\(formatKg(kg)) \(unitLabel)"
    }

    private var draftKg: Double {
        snapshot.draftWeighInKg ?? snapshot.latestScaleWeightKg ?? snapshot.trendWeightKg ?? 80.0
    }

    var body: some View {
        if family == .systemMedium {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Trend Weight", systemImage: "scalemass.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(trendText)
                        .font(.title3.weight(.bold).monospacedDigit())

                    Spacer(minLength: 2)

                    Label(snapshot.nextWorkoutName ?? "Rest Day", systemImage: "dumbbell.fill")
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    Text("TDEE \(Int(snapshot.expenditureKcal.rounded())) kcal")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Divider()

                VStack(alignment: .center, spacing: 6) {
                    Text(snapshot.draftWeighInKg != nil ? "Draft Scale" : "Quick Weigh-In")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(snapshot.draftWeighInKg != nil ? Color.accentColor : .secondary)

                    HStack(spacing: 6) {
                        Button(intent: WidgetNudgeWeighInIntent(direction: -1)) {
                            Image(systemName: "minus")
                                .font(.caption.weight(.bold))
                        }
                        .buttonStyle(.bordered)

                        Text("\(formatKg(draftKg)) \(unitLabel)")
                            .font(.subheadline.weight(.bold).monospacedDigit())
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)

                        Button(intent: WidgetNudgeWeighInIntent(direction: 1)) {
                            Image(systemName: "plus")
                                .font(.caption.weight(.bold))
                        }
                        .buttonStyle(.bordered)
                    }

                    Button(intent: WidgetLogWeighInIntent()) {
                        Label("Log Weight", systemImage: "checkmark.circle.fill")
                            .font(.caption2.weight(.bold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity)
            }
            .containerBackground(.fill.tertiary, for: .widget)
        } else {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Label("Trend", systemImage: "scalemass.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("TDEE \(Int(snapshot.expenditureKcal.rounded()))")
                        .font(.system(size: 9, weight: .medium).monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Text(trendText)
                    .font(.headline.weight(.bold).monospacedDigit())

                Label(snapshot.nextWorkoutName ?? "Rest Day", systemImage: "dumbbell.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer(minLength: 2)

                // Interactive Home Screen Weigh-In Control
                HStack(spacing: 4) {
                    Button(intent: WidgetNudgeWeighInIntent(direction: -1)) {
                        Text("−")
                            .font(.caption.weight(.heavy))
                    }
                    .buttonStyle(.bordered)

                    Button(intent: WidgetLogWeighInIntent()) {
                        Text("✓ \(formatKg(draftKg))")
                            .font(.caption2.weight(.bold).monospacedDigit())
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Button(intent: WidgetNudgeWeighInIntent(direction: 1)) {
                        Text("+")
                            .font(.caption.weight(.heavy))
                    }
                    .buttonStyle(.bordered)
                }
            }
            .containerBackground(.fill.tertiary, for: .widget)
        }
    }
}

struct TrendAndWorkoutWidget: Widget {
    let kind = "TotalFactorTrendWorkoutWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TotalFactorTimelineProvider()) { entry in
            TrendAndWorkoutWidgetView(snapshot: entry.snapshot)
        }
        .configurationDisplayName("Trend Weight & Weigh-In")
        .description("Smoothed EMA trend weight, interactive 1-tap weigh-in, TDEE, and today's lift.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct TotalFactorWidgetsBundle: WidgetBundle {
    var body: some Widget {
        MacrosRemainingWidget()
        TrendAndWorkoutWidget()
        #if canImport(ActivityKit)
        RestTimerLiveActivityWidget()
        #endif
    }
}
