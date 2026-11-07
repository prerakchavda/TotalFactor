import SwiftUI
import SwiftData

/// Today → Activity: strength workouts and cardio logged in Total Factor on the selected day,
/// plus whether the day is a scheduled training day.
struct TodayLoggedActivityCard: View {
    @Environment(AppState.self) private var appState

    @Query private var sessions: [WorkoutSession]
    @Query private var cardioSessions: [CardioSession]

    let unitSystem: UnitSystem
    let isTrainingDay: Bool
    let scheduledWorkoutName: String?

    init(dayKey: String, unitSystem: UnitSystem, isTrainingDay: Bool, scheduledWorkoutName: String?) {
        self.unitSystem = unitSystem
        self.isTrainingDay = isTrainingDay
        self.scheduledWorkoutName = scheduledWorkoutName
        _sessions = Query(
            filter: #Predicate<WorkoutSession> { $0.dayKey == dayKey },
            sort: \WorkoutSession.start
        )
        // Imported Apple Health cardio is already shown in the Apple Fitness section.
        _cardioSessions = Query(
            filter: #Predicate<CardioSession> { $0.dayKey == dayKey && $0.importedFromHealth == false },
            sort: \CardioSession.start
        )
    }

    private var dayTypeLine: String {
        if isTrainingDay {
            if let name = scheduledWorkoutName, !name.isEmpty {
                return "Training Day • \(name)"
            }
            return "Training Day"
        }
        return "Rest Day"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            AppleSectionHeader(
                title: "Logged Workouts",
                icon: "checklist",
                color: AppleTheme.exercise,
                subtitle: dayTypeLine
            )

            if sessions.isEmpty && cardioSessions.isEmpty {
                Text("Nothing logged yet for this day.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(sessions) { session in
                    sessionRow(session)
                }
                ForEach(cardioSessions) { cardio in
                    cardioRow(cardio)
                }
            }
        }
        .appleHealthCard(padding: 16)
    }

    private func sessionRow(_ session: WorkoutSession) -> some View {
        let minutes = session.effectiveElapsedSeconds(at: session.end ?? .now) / 60
        let volume = UnitsFormatter.formatWeight(session.totalWorkingVolumeKg, system: unitSystem, decimals: 0)
        let detail = "\(session.completedSetCount) sets • \(minutes) min • \(volume)"

        return Button {
            // Only an in-progress workout can be reopened from here; finished ones live in Workouts → History.
            guard !session.isFinished else { return }
            appState.activeWorkoutSessionID = session.id
            appState.showingActiveWorkoutFullScreen = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: session.isFinished ? "dumbbell.fill" : "play.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppleTheme.exercise)
                    .frame(width: 38, height: 38)
                    .background(AppleTheme.exercise.opacity(0.12), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(session.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if session.isFinished {
                    Text(session.start, format: .dateTime.hour().minute())
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                } else {
                    Text("Resume")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppleTheme.exercise)
                }
            }
            .padding(10)
            .background(AppleTheme.cardSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func cardioRow(_ cardio: CardioSession) -> some View {
        var parts: [String] = [cardio.formattedDuration]
        if let distance = cardio.formattedDistance(system: unitSystem) {
            parts.append(distance)
        }
        if let kcal = cardio.activeCalories, kcal > 0 {
            parts.append("\(Int(kcal.rounded())) kcal")
        }
        let detail = parts.joined(separator: " • ")

        return HStack(spacing: 12) {
            Image(systemName: cardio.kind.sfSymbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)
                .frame(width: 38, height: 38)
                .background(Color.orange.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(cardio.kind.displayName)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(cardio.start, format: .dateTime.hour().minute())
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(AppleTheme.cardSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
