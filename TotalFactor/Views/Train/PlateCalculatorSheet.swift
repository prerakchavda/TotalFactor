import SwiftUI

struct PlateCalculatorSheet: View {
    @Environment(\.dismiss) private var dismiss

    let targetWeightKg: Double
    let gymProfile: GymProfile?
    let unitSystem: UnitSystem

    @State private var customWeightDisplay: Double = 135

    private var barKg: Double {
        gymProfile?.barWeightKg ?? 20.0
    }

    private var platesKg: [Double] {
        gymProfile?.availablePlatesKg ?? [25, 20, 15, 10, 5, 2.5, 1.25]
    }

    var body: some View {
        let internalKg = UnitsFormatter.internalKg(fromDisplay: customWeightDisplay, system: unitSystem)
        let breakdown = ProgressionEngine.calculatePlatesPerSide(
            targetWeightKg: internalKg,
            barWeightKg: barKg,
            availablePlatesKg: platesKg
        )

        NavigationStack {
            VStack(spacing: 20) {
                HStack {
                    Text("Target Load (\(unitSystem.weightSymbol))")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    TextField("Weight", value: $customWeightDisplay, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .font(.title2.weight(.bold).monospacedDigit())
                        .frame(width: 110)
                }
                .padding(.horizontal)

                VStack(spacing: 8) {
                    Text("Load Per Side of \(UnitsFormatter.formatGymLoad(barKg, system: unitSystem)) Bar")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if breakdown.platesPerSide.isEmpty {
                        Text("Empty Bar Only")
                            .font(.headline)
                            .padding()
                    } else {
                        HStack(spacing: 6) {
                            Rectangle()
                                .fill(Color.secondary)
                                .frame(width: 28, height: 14)
                            ForEach(Array(breakdown.platesPerSide.enumerated()), id: \.offset) { _, plateKg in
                                VStack {
                                    Text(UnitsFormatter.formatGymLoad(plateKg, system: unitSystem))
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(.white)
                                }
                                .padding(.horizontal, 8)
                                .frame(height: max(44, min(95, CGFloat(plateKg) * 3.4)))
                                .background(plateColor(plateKg), in: RoundedRectangle(cornerRadius: 6))
                            }
                        }
                        .padding(.vertical, 8)
                    }

                    Text("Achieved Total: \(UnitsFormatter.formatGymLoad(breakdown.achievedWeightKg, system: unitSystem))")
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal)

                Spacer()
            }
            .padding(.top)
            .navigationTitle("Plate Calculator")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                customWeightDisplay = (UnitsFormatter.displayWeight(targetWeightKg, system: unitSystem) * 10).rounded() / 10
            }
        }
    }

    private func plateColor(_ kg: Double) -> Color {
        if kg >= 24 { return .red }
        if kg >= 19 { return .blue }
        if kg >= 14 { return .yellow.opacity(0.85) }
        if kg >= 9 { return .green }
        return .gray
    }
}
