import SwiftUI
import SwiftData

struct FastingSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]

    private var profile: UserProfile {
        profiles.first ?? CoachingCoordinator.fetchOrCreateProfile(context: modelContext)
    }

    var body: some View {
        @Bindable var bindableProfile = profile

        Form {
            Section {
                Toggle("Enable Intermittent Fasting", isOn: $bindableProfile.enableIntermittentFasting)
            } footer: {
                Text("Enables native fasting tracking and eating-window indicators across your Food timeline and Today dashboard.")
            }

            if bindableProfile.enableIntermittentFasting {
                Section("Fasting Protocol") {
                    Picker("Protocol", selection: $bindableProfile.fastingProtocol) {
                        ForEach(FastingProtocol.allCases) { proto in
                            Text(proto.displayName).tag(proto)
                        }
                    }

                    HStack {
                        Text("Fast / Eat Schedule")
                        Spacer()
                        Text("\(Int(bindableProfile.fastingProtocol.fastHours))h Fast • \(Int(bindableProfile.fastingProtocol.eatingHours))h Eating")
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(Color.accentColor)
                    }
                }

                Section("Manual Fast Controls") {
                    if bindableProfile.isManualFastActive, let startTime = bindableProfile.manualFastStartTime {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Fast in Progress")
                                    .font(.headline)
                                    .foregroundStyle(.green)
                                Spacer()
                                Text(startTime.formatted(date: .omitted, time: .shortened))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            Text("Started on \(startTime.formatted(date: .abbreviated, time: .omitted))")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Button(role: .destructive) {
                                bindableProfile.isManualFastActive = false
                                bindableProfile.manualFastStartTime = nil
                                try? modelContext.save()
                            } label: {
                                Label("End Fast Now", systemImage: "stop.circle.fill")
                                    .font(.subheadline.weight(.semibold))
                            }
                            .padding(.top, 4)
                        }
                    } else {
                        Button {
                            bindableProfile.isManualFastActive = true
                            bindableProfile.manualFastStartTime = .now
                            try? modelContext.save()
                        } label: {
                            Label("Start Fast Now", systemImage: "play.circle.fill")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
            }
        }
        .navigationTitle("Intermittent Fasting")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: bindableProfile.enableIntermittentFasting) { _, _ in
            try? modelContext.save()
        }
        .onChange(of: bindableProfile.fastingProtocolRaw) { _, _ in
            try? modelContext.save()
        }
    }
}
