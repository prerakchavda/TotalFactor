import SwiftUI
import WidgetKit
#if canImport(ActivityKit)
import ActivityKit
import AppIntents

struct RestTimerLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RestTimerAttributes.self) { context in
            // Lock Screen / Notification Banner Live Activity UI
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(context.attributes.exerciseName) • Set \(context.attributes.setNumber)")
                        .font(.subheadline.weight(.bold))
                        .lineLimit(1)
                    if !context.state.nextSetSummary.isEmpty {
                        Text(context.state.nextSetSummary)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(context.attributes.workoutName)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Text(timerInterval: Date.now...max(Date.now, context.state.endDate), countsDown: true)
                    .font(.title2.weight(.heavy).monospacedDigit())
                    .foregroundStyle(.orange)
                    .frame(width: 72, alignment: .trailing)

                Button(intent: AdjustRestTimerIntent(seconds: 30)) {
                    Text("+30s")
                        .font(.caption.weight(.bold))
                }
                .buttonStyle(.bordered)

                Button(intent: SkipRestTimerIntent()) {
                    Text("Skip")
                        .font(.caption.weight(.bold))
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }
            .padding(14)
            .activityBackgroundTint(Color.black.opacity(0.85))
            .activitySystemActionForegroundColor(.white)

        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.attributes.exerciseName)
                            .font(.caption.weight(.bold))
                            .lineLimit(1)
                        Text("Set \(context.attributes.setNumber)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(timerInterval: Date.now...max(Date.now, context.state.endDate), countsDown: true)
                        .font(.title3.weight(.bold).monospacedDigit())
                        .foregroundStyle(.orange)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 12) {
                        Button(intent: AdjustRestTimerIntent(seconds: 30)) {
                            Label("+30s", systemImage: "plus.circle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)

                        Button(intent: SkipRestTimerIntent()) {
                            Label("Skip Rest", systemImage: "forward.end.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                    }
                }
            } compactLeading: {
                Image(systemName: "timer")
                    .foregroundStyle(.orange)
            } compactTrailing: {
                Text(timerInterval: Date.now...max(Date.now, context.state.endDate), countsDown: true)
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(.orange)
                    .frame(width: 44)
            } minimal: {
                Image(systemName: "timer")
                    .foregroundStyle(.orange)
            }
        }
    }
}
#endif
