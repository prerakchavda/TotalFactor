import SwiftUI
import SwiftData

/// 2-tap Weigh-In sheet: pre-filled with your latest scale weight, +/- 0.1 nudge buttons, and 1-tap Save.
struct QuickWeighInSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \WeighIn.date, order: .reverse) private var weighIns: [WeighIn]
    @Query private var profiles: [UserProfile]

    @State private var weightText: String = ""
    @State private var weighDate: Date = .now
    @FocusState private var focused: Bool

    private var profile: UserProfile {
        profiles.first ?? CoachingCoordinator.fetchOrCreateProfile(context: modelContext)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                HStack(spacing: 16) {
                    Button {
                        nudge(-0.2)
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.title)
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        TextField("0.0", text: $weightText)
                            .keyboardType(.decimalPad)
                            .font(.system(size: 44, weight: .bold, design: .rounded).monospacedDigit())
                            .multilineTextAlignment(.center)
                            .frame(width: 150)
                            .focused($focused)

                        Text(profile.unitSystem.weightSymbol)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        nudge(+0.2)
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title)
                    }
                }
                .padding(.top, 12)

                DatePicker("Time", selection: $weighDate)
                    .labelsHidden()

                Button {
                    saveWeighIn()
                } label: {
                    Text("Save Weigh-In")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal)

                Spacer()
            }
            .padding()
            .navigationTitle("Log Weight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                let latestKg = weighIns.first?.weightKg ?? profile.startingWeightKg
                let disp = UnitsFormatter.displayWeight(latestKg, system: profile.unitSystem)
                weightText = String(format: "%.1f", disp)
                focused = true
            }
        }
    }

    private func nudge(_ delta: Double) {
        let current = Double(weightText) ?? UnitsFormatter.displayWeight(profile.startingWeightKg, system: profile.unitSystem)
        weightText = String(format: "%.1f", max(40, current + delta))
    }

    private func saveWeighIn() {
        guard let val = Double(weightText.replacingOccurrences(of: ",", with: ".")), val > 20 else { return }
        let kg = UnitsFormatter.internalKg(fromDisplay: val, system: profile.unitSystem)
        let entry = WeighIn(date: weighDate, weightKg: kg, source: .manual)
        modelContext.insert(entry)
        try? modelContext.save()
        _ = CoachingCoordinator.evaluate(context: modelContext)
        Task {
            await HealthKitService.shared.saveManualWeighIn(entry)
        }
        dismiss()
    }
}
