import SwiftUI
import SwiftData

struct GymProfileEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query private var gymProfiles: [GymProfile]
    @Query private var profiles: [UserProfile]

    private var unitSystem: UnitSystem {
        (profiles.first ?? CoachingCoordinator.fetchOrCreateProfile(context: modelContext)).unitSystem
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Saved Gyms (Tap Checkmark or Select Active)") {
                    ForEach(gymProfiles) { gym in
                        NavigationLink {
                            SingleGymEditor(gym: gym, unitSystem: unitSystem)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 6) {
                                        Text(gym.name)
                                            .font(.subheadline.weight(.semibold))
                                        if gym.isDefault {
                                            Text("Active")
                                                .font(.caption2.weight(.bold))
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Color.green.opacity(0.15), in: Capsule())
                                                .foregroundStyle(.green)
                                        }
                                    }
                                    Text("\(gym.availableEquipment.count) equipment types • DBs up to \(UnitsFormatter.formatGymLoad(gym.maxDumbbellKg, system: unitSystem))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if !gym.isDefault {
                                    Button("Set Active") {
                                        for g in gymProfiles { g.isDefault = (g.id == gym.id) }
                                        try? modelContext.save()
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.mini)
                                } else {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                }
                            }
                        }
                    }
                    .onDelete { offsets in
                        for idx in offsets { modelContext.delete(gymProfiles[idx]) }
                        try? modelContext.save()
                    }
                }

                Section("Add Preset or Travel Gym") {
                    if !gymProfiles.contains(where: { $0.name.localizedCaseInsensitiveContains("Planet Fitness") }) {
                        Button {
                            for g in gymProfiles { g.isDefault = false }
                            let pf = SeedDataService.makePlanetFitnessGymProfile(isDefault: true)
                            modelContext.insert(pf)
                            try? modelContext.save()
                        } label: {
                            Label("Add Planet Fitness (Set Active)", systemImage: "sparkles")
                                .foregroundStyle(.purple)
                        }
                    }

                    Button {
                        let g = GymProfile(name: "Hotel / Travel Gym", availableEquipment: [.dumbbell, .cable, .bodyweight])
                        modelContext.insert(g)
                        try? modelContext.save()
                    } label: {
                        Label("Add Custom / Travel Gym Profile", systemImage: "plus.circle.fill")
                    }
                }
            }
            .navigationTitle("Gym Profiles")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct SingleGymEditor: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var gym: GymProfile
    let unitSystem: UnitSystem

    private func weightBinding(_ keyPath: ReferenceWritableKeyPath<GymProfile, Double>) -> Binding<Double> {
        Binding(
            get: {
                (UnitsFormatter.displayWeight(gym[keyPath: keyPath], system: unitSystem) * 10.0).rounded() / 10.0
            },
            set: { newDisplay in
                gym[keyPath: keyPath] = UnitsFormatter.internalKg(fromDisplay: newDisplay, system: unitSystem)
                try? modelContext.save()
            }
        )
    }

    var body: some View {
        Form {
            Section {
                Button {
                    let all = (try? modelContext.fetch(FetchDescriptor<GymProfile>())) ?? []
                    for g in all { g.isDefault = (g.id == gym.id) }
                    try? modelContext.save()
                } label: {
                    HStack {
                        Label(gym.isDefault ? "Currently Active Gym" : "Set as Active Gym", systemImage: gym.isDefault ? "checkmark.circle.fill" : "circle")
                            .fontWeight(.semibold)
                        Spacer()
                    }
                }
                .disabled(gym.isDefault)
            }

            Section("Identity & Weights (\(unitSystem.weightSymbol))") {
                TextField("Gym Name", text: $gym.name)
                HStack {
                    Text("Bar / Smith Carriage (\(unitSystem.weightSymbol))")
                    Spacer()
                    TextField("20", value: weightBinding(\.barWeightKg), format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
                HStack {
                    Text("Max Dumbbell (\(unitSystem.weightSymbol))")
                    Spacer()
                    TextField("75", value: weightBinding(\.maxDumbbellKg), format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
                HStack {
                    Text("Dumbbell Jump (\(unitSystem.weightSymbol))")
                    Spacer()
                    TextField("5", value: weightBinding(\.dumbbellIncrementKg), format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
                HStack {
                    Text("Cable Stack Increment (\(unitSystem.weightSymbol))")
                    Spacer()
                    TextField("2.5", value: weightBinding(\.cableIncrementKg), format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
            }

            Section("Available Equipment Checklist (§10)") {
                ForEach(Equipment.allCases) { eq in
                    let hasIt = gym.availableEquipment.contains(eq)
                    Button {
                        var current = gym.availableEquipment
                        if hasIt {
                            current.removeAll { $0 == eq }
                        } else {
                            current.append(eq)
                        }
                        gym.availableEquipment = current
                        try? modelContext.save()
                    } label: {
                        HStack {
                            Text(eq.displayName)
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: hasIt ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(hasIt ? Color.accentColor : .secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle(gym.name)
    }
}
