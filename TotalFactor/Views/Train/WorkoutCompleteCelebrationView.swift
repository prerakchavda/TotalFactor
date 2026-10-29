import SwiftUI
import SwiftData

/// Spec MacroFactor Workouts Celebration Screen:
/// - Front & Back Anatomical Humanoid Heatmap in vibrant royal blue
/// - PR Trophy Cards for Volume, Reps, and 1RM records
/// - Workout Details Summary (Volume, Sets, Time, Calories)
/// - "Update Workout Plan" default switch
/// - 1-tap "Done" commit button
struct WorkoutCompleteCelebrationView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let session: WorkoutSession
    let unitSystem: UnitSystem
    let prList: [DetectedPRItem]
    let diffItems: [WorkoutChangeLogSheet.ChangeLogDiffItem]
    let onCommitToRoutine: () -> Void
    let onFinishSession: () -> Void

    @State private var updateWorkoutPlanDefault: Bool = true

    struct DetectedPRItem: Identifiable, Sendable {
        var id: String { "\(exerciseName)_\(type.rawValue)_\(value)" }
        let exerciseName: String
        let type: PRType
        let value: Double
        let secondaryValue: Double
    }

    init(
        session: WorkoutSession,
        unitSystem: UnitSystem,
        prList: [DetectedPRItem],
        diffItems: [WorkoutChangeLogSheet.ChangeLogDiffItem],
        onCommitToRoutine: @escaping () -> Void,
        onFinishSession: @escaping () -> Void
    ) {
        self.session = session
        self.unitSystem = unitSystem
        self.prList = prList
        self.diffItems = diffItems
        self.onCommitToRoutine = onCommitToRoutine
        self.onFinishSession = onFinishSession
        _updateWorkoutPlanDefault = State(initialValue: !diffItems.isEmpty)
    }

    private var workedMuscles: Set<MuscleGroup> {
        var set = Set<MuscleGroup>()
        for s in (session.sets ?? []) where s.isCompleted {
            guard let ex = s.exercise else { continue }
            set.formUnion(ex.primaryMuscles)
            set.formUnion(ex.secondaryMuscles)
        }
        return set
    }

    private var durationString: String {
        let elapsed = max(60, Int((session.end ?? .now).timeIntervalSince(session.start)))
        let m = elapsed / 60
        let h = m / 60
        let rm = m % 60
        if h > 0 {
            return "\(h)h \(rm)m"
        } else {
            return "\(m) mins"
        }
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // 1. Anatomical Humanoid Heatmap (Front & Back)
                    VStack(spacing: 8) {
                        AnatomicalHumanoidHeatmapView(
                            workedMuscles: workedMuscles,
                            accentColor: Color(red: 0.18, green: 0.48, blue: 0.96),
                            height: 240,
                            showLabels: true
                        )
                    }
                    .padding(.top, 10)

                    // 2. PR Milestone Trophy Cards
                    if !prList.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(prList) { pr in
                                    prCard(pr)
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    }

                    // 3. Workout Details Section
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Workout Details")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.primary)

                        HStack(spacing: 16) {
                            detailCell(
                                icon: "scalemass.fill",
                                title: "Volume",
                                value: UnitsFormatter.formatGymLoad(session.totalWorkingVolumeKg, system: unitSystem)
                            )
                            detailCell(
                                icon: "clock.fill",
                                title: "Duration",
                                value: durationString
                            )
                        }

                        HStack(spacing: 16) {
                            detailCell(
                                icon: "checkmark.circle.fill",
                                title: "Sets Completed",
                                value: "\(session.completedSetCount) sets"
                            )
                            if let bpm = PhoneWatchSyncService.shared.liveWatchHeartRateBPM, bpm > 0 {
                                detailCell(
                                    icon: "heart.fill",
                                    title: "Heart Rate",
                                    value: "\(Int(bpm.rounded())) BPM"
                                )
                            } else {
                                detailCell(
                                    icon: "flame.fill",
                                    title: "Target Muscles",
                                    value: "\(workedMuscles.count) Groups"
                                )
                            }
                        }
                    }
                    .padding(18)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .padding(.horizontal, 16)

                    // 4. "Update Workout Plan" Switch (MacroFactor Style)
                    if session.programWorkout != nil {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Update Workout Plan")
                                        .font(.subheadline.weight(.bold))
                                        .foregroundStyle(.primary)
                                    Text("Save these changes as the new default for this workout")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Toggle("", isOn: $updateWorkoutPlanDefault)
                                    .labelsHidden()
                            }

                            if !diffItems.isEmpty && updateWorkoutPlanDefault {
                                VStack(alignment: .leading, spacing: 4) {
                                    ForEach(diffItems) { diff in
                                        HStack(spacing: 6) {
                                            Circle()
                                                .fill(Color.accentColor)
                                                .frame(width: 5, height: 5)
                                            Text(diff.detail)
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                                .padding(.top, 4)
                            }
                        }
                        .padding(16)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .padding(.horizontal, 16)
                    }

                    // 5. Done Action Button
                    Button {
                        if updateWorkoutPlanDefault && !diffItems.isEmpty {
                            onCommitToRoutine()
                        }
                        onFinishSession()
                        dismiss()
                    } label: {
                        Text("Done")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(Color(.systemBackground))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.primary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 30)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Workout Complete")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        onFinishSession()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Subviews

    private func prCard(_ pr: DetectedPRItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: prIcon(pr.type))
                    .font(.headline)
                    .foregroundStyle(Color(red: 0.18, green: 0.48, blue: 0.96))
                VStack(alignment: .leading, spacing: 1) {
                    Text(formatPRValue(pr))
                        .font(.headline.weight(.heavy).monospacedDigit())
                        .foregroundStyle(.primary)
                    Text("New!")
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color(red: 0.18, green: 0.48, blue: 0.96))
                }
            }

            Text(pr.exerciseName)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .foregroundStyle(.primary)

            Text(pr.type.displayName)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(width: 175, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    private func detailCell(icon: String, title: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.headline.weight(.bold).monospacedDigit())
                    .foregroundStyle(.primary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func prIcon(_ type: PRType) -> String {
        switch type {
        case .bestSessionVolume: return "trophy.fill"
        case .mostRepsAtWeight: return "star.fill"
        case .e1RM: return "target"
        case .heaviestWeight: return "scalemass.fill"
        }
    }

    private func formatPRValue(_ pr: DetectedPRItem) -> String {
        switch pr.type {
        case .bestSessionVolume:
            return UnitsFormatter.formatGymLoad(pr.value, system: unitSystem)
        case .mostRepsAtWeight:
            return "\(Int(pr.value)) reps"
        case .e1RM, .heaviestWeight:
            return UnitsFormatter.formatGymLoad(pr.value, system: unitSystem)
        }
    }
}
