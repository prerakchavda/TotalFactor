import SwiftUI

/// MacroFactor Workouts Weekly Hypertrophy Volume Landmarks Card (§11)
/// Displays trailing 7-day hard sets mapped against evidence-based volume landmarks (MV, MEV, MAV, MRV).
struct HypertrophyVolumeCardView: View {
    let statuses: [HypertrophyVolumeEngine.MuscleVolumeStatus]

    @State private var showingDetailSheet: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "figure.strengthtraining.traditional")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.purple)
                    Text("Volume Landmarks")
                        .font(.headline)
                        .foregroundStyle(.primary)
                }

                Spacer()

                Button {
                    showingDetailSheet = true
                } label: {
                    HStack(spacing: 4) {
                        Text("7-Day Trailing")
                            .font(.caption2.weight(.semibold))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundStyle(.secondary)
                }
            }

            // Legend Strip
            HStack(spacing: 8) {
                legendItem(label: "MV (<8)", color: .secondary)
                legendItem(label: "MEV (8–11)", color: .blue)
                legendItem(label: "MAV (12–20)", color: .green)
                legendItem(label: "MRV (21+)", color: .orange)
            }
            .font(.system(size: 10, weight: .medium))

            // Muscle volume bars (Show top active muscles or preview of key groups)
            VStack(spacing: 10) {
                ForEach(statuses.prefix(6)) { status in
                    muscleRow(status)
                }
            }

            if statuses.count > 6 {
                Button {
                    showingDetailSheet = true
                } label: {
                    Text("View All \(statuses.count) Muscle Groups")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.bordered)
            }
        }
        .appleHealthCard(padding: 16)
        .sheet(isPresented: $showingDetailSheet) {
            HypertrophyVolumeDetailSheet(statuses: statuses)
        }
    }

    private func legendItem(label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(label)
                .foregroundStyle(.secondary)
        }
    }

    private func muscleRow(_ status: HypertrophyVolumeEngine.MuscleVolumeStatus) -> some View {
        VStack(spacing: 4) {
            HStack {
                Text(status.muscle.displayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Text(String(format: "%.1f sets", status.weeklyHardSets))
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(.primary)
                Text(zoneLabel(status.zone))
                    .font(.system(size: 9, weight: .bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(zoneColor(status.zone).opacity(0.16), in: Capsule())
                    .foregroundStyle(zoneColor(status.zone))
            }

            // Segmented/continuous progress gauge
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.secondary.opacity(0.12))
                        .frame(height: 6)

                    RoundedRectangle(cornerRadius: 3)
                        .fill(zoneColor(status.zone))
                        .frame(width: max(4, min(geo.size.width, geo.size.width * CGFloat(status.targetPercentage))), height: 6)
                }
            }
            .frame(height: 6)
        }
    }

    private func zoneColor(_ zone: HypertrophyVolumeEngine.VolumeZone) -> Color {
        switch zone {
        case .maintenance: return .gray
        case .effective: return .blue
        case .optimal: return .green
        case .overreaching: return .orange
        }
    }

    private func zoneLabel(_ zone: HypertrophyVolumeEngine.VolumeZone) -> String {
        switch zone {
        case .maintenance: return "MV"
        case .effective: return "MEV"
        case .optimal: return "MAV"
        case .overreaching: return "MRV"
        }
    }
}

/// Full sheet displaying all muscle groups with direct vs indirect set breakdowns
struct HypertrophyVolumeDetailSheet: View {
    @Environment(\.dismiss) private var dismiss

    let statuses: [HypertrophyVolumeEngine.MuscleVolumeStatus]

    var body: some View {
        NavigationStack {
            List(statuses) { status in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(status.muscle.displayName)
                            .font(.headline)
                        Spacer()
                        Text(String(format: "%.1f hard sets", status.weeklyHardSets))
                            .font(.subheadline.weight(.bold).monospacedDigit())
                    }

                    Text("Direct: \(status.directSets) sets • Indirect: \(status.indirectSets) sets (0.5x)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        Text(status.zone.displayName)
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(zoneColor(status.zone).opacity(0.15), in: Capsule())
                            .foregroundStyle(zoneColor(status.zone))

                        Spacer()

                        Text("Target: 12–20 sets/wk")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
            .navigationTitle("Hypertrophy Landmarks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private func zoneColor(_ zone: HypertrophyVolumeEngine.VolumeZone) -> Color {
        switch zone {
        case .maintenance: return .gray
        case .effective: return .blue
        case .optimal: return .green
        case .overreaching: return .orange
        }
    }
}
