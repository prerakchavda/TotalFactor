import SwiftUI
import SwiftData

struct MicronutrientDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query private var customTargets: [NutrientTarget]

    let dayKey: String
    let entries: [FoodLogEntry]
    let targets: MacroTargets
    let sex: BiologicalSex

    @State private var editingNutrientZone: NutrientZoneTarget? = nil
    @State private var showingFullTargetsEditor: Bool = false

    private var customByLowerName: [String: NutrientTarget] {
        Dictionary(
            customTargets.map { ($0.nutrient.lowercased(), $0) },
            uniquingKeysWith: { _, latest in latest }
        )
    }

    var body: some View {
        let defaultZones = MacroTargetEngine.nutrientZones(for: targets, sex: sex)
        let zones = MacroTargetEngine.nutrientZones(
            for: targets,
            sex: sex,
            customOverrides: customTargets.map(\.asStruct)
        )
        let totals = aggregateTotals()

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 6) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Tap any nutrient below to customize its floor, target, or ceiling.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 4)

                    ForEach(zones) { zone in
                        let currentVal = value(forZone: zone.nutrient, totals: totals)
                        let isCustom = customByLowerName[zone.nutrient.lowercased()] != nil

                        Button {
                            editingNutrientZone = zone
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                if isCustom {
                                    HStack {
                                        Spacer()
                                        Text("Custom Target")
                                            .font(.caption2.weight(.semibold))
                                            .padding(.horizontal, 7)
                                            .padding(.vertical, 2)
                                            .background(Color.accentColor.opacity(0.14), in: Capsule())
                                            .foregroundStyle(Color.accentColor)
                                    }
                                }
                                MacroZoneBar(
                                    title: zone.nutrient,
                                    current: currentVal,
                                    unit: zone.unit,
                                    floor: zone.floor,
                                    target: zone.target,
                                    ceiling: zone.ceiling,
                                    tint: color(for: zone.nutrient)
                                )
                            }
                            .padding(12)
                            .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .navigationTitle("Nutrients • \(DayKey.displayTitle(for: dayKey))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingFullTargetsEditor = true
                    } label: {
                        Label("Edit Targets", systemImage: "slider.horizontal.3")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $editingNutrientZone) { zone in
                let defaultZone = defaultZones.first { $0.nutrient.lowercased() == zone.nutrient.lowercased() } ?? zone
                SingleNutrientTargetEditorSheet(
                    effectiveZone: zone,
                    defaultZone: defaultZone,
                    existingOverride: customByLowerName[zone.nutrient.lowercased()]
                )
            }
            .sheet(isPresented: $showingFullTargetsEditor) {
                NavigationStack {
                    NutrientTargetsEditorView(targets: targets, sex: sex)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { showingFullTargetsEditor = false }
                            }
                        }
                }
            }
        }
    }

    private func aggregateTotals() -> NutrientsPer100g {
        var total = NutrientsPer100g()
        var micros: [String: Double] = [:]
        for e in entries {
            let n = e.loggedNutrients
            total.calories += n.calories
            total.protein += n.protein
            total.carbs += n.carbs
            total.fat += n.fat
            total.fiber += n.fiber
            total.sugar += n.sugar
            total.sodiumMg += n.sodiumMg
            for (k, v) in n.micronutrients {
                micros[k, default: 0] += v
            }
        }
        total.micronutrients = micros
        return total
    }

    private func value(forZone name: String, totals: NutrientsPer100g) -> Double {
        switch name {
        case "Calories": return totals.calories
        case "Protein": return totals.protein
        case "Fat": return totals.fat
        case "Carbs": return totals.carbs
        case "Fiber": return totals.fiber
        case "Sugar": return totals.sugar
        case "Sodium": return totals.sodiumMg
        case MicronutrientKey.potassiumMg.displayName:
            return totals.micronutrients[MicronutrientKey.potassiumMg.rawValue] ?? 0
        case MicronutrientKey.calciumMg.displayName:
            return totals.micronutrients[MicronutrientKey.calciumMg.rawValue] ?? 0
        case MicronutrientKey.ironMg.displayName:
            return totals.micronutrients[MicronutrientKey.ironMg.rawValue] ?? 0
        case MicronutrientKey.vitaminDMcg.displayName:
            return totals.micronutrients[MicronutrientKey.vitaminDMcg.rawValue] ?? 0
        case MicronutrientKey.vitaminCMg.displayName:
            return totals.micronutrients[MicronutrientKey.vitaminCMg.rawValue] ?? 0
        case MicronutrientKey.magnesiumMg.displayName:
            return totals.micronutrients[MicronutrientKey.magnesiumMg.rawValue] ?? 0
        case MicronutrientKey.zincMg.displayName:
            return totals.micronutrients[MicronutrientKey.zincMg.rawValue] ?? 0
        case MicronutrientKey.cholesterolMg.displayName:
            return totals.micronutrients[MicronutrientKey.cholesterolMg.rawValue] ?? 0
        case MicronutrientKey.saturatedFatG.displayName:
            return totals.micronutrients[MicronutrientKey.saturatedFatG.rawValue] ?? 0
        default:
            return 0
        }
    }

    private func color(for nutrient: String) -> Color {
        switch nutrient {
        case "Calories": return .orange
        case "Protein": return .red
        case "Carbs": return .blue
        case "Fat", "Saturated Fat": return .yellow
        case "Fiber": return .green
        case "Sugar": return .purple
        case "Sodium", "Cholesterol": return .pink
        default: return .teal
        }
    }
}

/// Full list editor of custom floor / target / ceiling overrides (`§8 & §13`), reachable from both
/// `SettingsView` and `MicronutrientDetailSheet`.
struct NutrientTargetsEditorView: View {
    @Environment(\.modelContext) private var modelContext

    @Query private var customTargets: [NutrientTarget]
    @Query private var profiles: [UserProfile]

    var explicitTargets: MacroTargets? = nil
    var explicitSex: BiologicalSex? = nil

    @State private var selectedZoneToEdit: NutrientZoneTarget? = nil

    init(targets: MacroTargets? = nil, sex: BiologicalSex? = nil) {
        self.explicitTargets = targets
        self.explicitSex = sex
    }

    private var customByLowerName: [String: NutrientTarget] {
        Dictionary(
            customTargets.map { ($0.nutrient.lowercased(), $0) },
            uniquingKeysWith: { _, latest in latest }
        )
    }

    var body: some View {
        let profile = profiles.first ?? CoachingCoordinator.fetchOrCreateProfile(context: modelContext)
        let resolvedSex = explicitSex ?? profile.biologicalSex
        let resolvedMacroTargets = explicitTargets ?? CoachingCoordinator.cachedOrComputeDigest(context: modelContext).todayTargets

        let defaultZones = MacroTargetEngine.nutrientZones(for: resolvedMacroTargets, sex: resolvedSex)
        let effectiveZones = MacroTargetEngine.nutrientZones(
            for: resolvedMacroTargets,
            sex: resolvedSex,
            customOverrides: customTargets.map(\.asStruct)
        )

        List {
            Section {
                ForEach(effectiveZones) { zone in
                    let hasCustom = customByLowerName[zone.nutrient.lowercased()] != nil
                    Button {
                        selectedZoneToEdit = zone
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Text(zone.nutrient)
                                        .font(.subheadline.weight(.semibold))
                                    if hasCustom {
                                        Text("Custom")
                                            .font(.caption2.weight(.bold))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 1)
                                            .background(Color.accentColor.opacity(0.15), in: Capsule())
                                            .foregroundStyle(Color.accentColor)
                                    }
                                }
                                Text(summaryString(for: zone))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 2)
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("Nutrient Floors, Targets & Ceilings")
            } footer: {
                Text("Adaptive coaching sets default macro & micronutrient zones automatically. Any custom override you save takes priority on Today and the Micronutrients panel.")
            }

            if !customTargets.isEmpty {
                Section {
                    Button(role: .destructive) {
                        for item in customTargets {
                            modelContext.delete(item)
                        }
                        try? modelContext.save()
                    } label: {
                        Label("Reset All \(customTargets.count) Custom Overrides to Coaching Defaults", systemImage: "arrow.counterclockwise")
                    }
                }
            }
        }
        .navigationTitle("Nutrient Targets")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedZoneToEdit) { zone in
            let defaultZone = defaultZones.first { $0.nutrient.lowercased() == zone.nutrient.lowercased() } ?? zone
            SingleNutrientTargetEditorSheet(
                effectiveZone: zone,
                defaultZone: defaultZone,
                existingOverride: customByLowerName[zone.nutrient.lowercased()]
            )
        }
    }

    private func summaryString(for zone: NutrientZoneTarget) -> String {
        var parts: [String] = []
        if let f = zone.floor { parts.append("Floor \(formatNumber(f))\(zone.unit)") }
        if let t = zone.target { parts.append("Target \(formatNumber(t))\(zone.unit)") }
        if let c = zone.ceiling { parts.append("Ceiling \(formatNumber(c))\(zone.unit)") }
        return parts.isEmpty ? "No bounds set" : parts.joined(separator: " • ")
    }

    private func formatNumber(_ v: Double) -> String {
        if abs(v.rounded() - v) < 0.05 {
            return "\(Int(v.rounded()))"
        }
        return String(format: "%.1f", v)
    }
}

struct SingleNutrientTargetEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let effectiveZone: NutrientZoneTarget
    let defaultZone: NutrientZoneTarget
    let existingOverride: NutrientTarget?

    @State private var enableFloor: Bool = false
    @State private var floorValue: Double = 0
    @State private var enableTarget: Bool = false
    @State private var targetValue: Double = 0
    @State private var enableCeiling: Bool = false
    @State private var ceilingValue: Double = 0

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Minimum Floor (\(effectiveZone.unit))", isOn: $enableFloor)
                    if enableFloor {
                        HStack {
                            Text("Floor")
                            Spacer()
                            TextField("0", value: $floorValue, format: .number)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                            Text(effectiveZone.unit)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Toggle("Daily Target (\(effectiveZone.unit))", isOn: $enableTarget)
                    if enableTarget {
                        HStack {
                            Text("Target")
                            Spacer()
                            TextField("0", value: $targetValue, format: .number)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                            Text(effectiveZone.unit)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Toggle("Upper Ceiling (\(effectiveZone.unit))", isOn: $enableCeiling)
                    if enableCeiling {
                        HStack {
                            Text("Ceiling")
                            Spacer()
                            TextField("0", value: $ceilingValue, format: .number)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                            Text(effectiveZone.unit)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("\(effectiveZone.nutrient) Bounds")
                } footer: {
                    Text("Coaching default: \(defaultSummary)")
                }

                if existingOverride != nil {
                    Section {
                        Button(role: .destructive) {
                            if let existingOverride {
                                modelContext.delete(existingOverride)
                                try? modelContext.save()
                            }
                            dismiss()
                        } label: {
                            Label("Reset \(effectiveZone.nutrient) to Coaching Default", systemImage: "arrow.counterclockwise")
                        }
                    }
                }
            }
            .navigationTitle("Edit \(effectiveZone.nutrient)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveOverride()
                    }
                }
            }
            .onAppear {
                enableFloor = (effectiveZone.floor != nil)
                floorValue = effectiveZone.floor ?? defaultZone.floor ?? 0
                enableTarget = (effectiveZone.target != nil)
                targetValue = effectiveZone.target ?? defaultZone.target ?? 0
                enableCeiling = (effectiveZone.ceiling != nil)
                ceilingValue = effectiveZone.ceiling ?? defaultZone.ceiling ?? 0
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var defaultSummary: String {
        var parts: [String] = []
        if let f = defaultZone.floor { parts.append("Floor \(Int(f.rounded()))\(defaultZone.unit)") }
        if let t = defaultZone.target { parts.append("Target \(Int(t.rounded()))\(defaultZone.unit)") }
        if let c = defaultZone.ceiling { parts.append("Ceiling \(Int(c.rounded()))\(defaultZone.unit)") }
        return parts.isEmpty ? "None" : parts.joined(separator: " • ")
    }

    private func saveOverride() {
        let fVal: Double? = enableFloor ? max(0, floorValue) : nil
        let tVal: Double? = enableTarget ? max(0, targetValue) : nil
        let cVal: Double? = enableCeiling ? max(0, ceilingValue) : nil

        if let existingOverride {
            existingOverride.unit = effectiveZone.unit
            existingOverride.floor = fVal
            existingOverride.target = tVal
            existingOverride.ceiling = cVal
        } else {
            let created = NutrientTarget(
                nutrient: effectiveZone.nutrient,
                unit: effectiveZone.unit,
                floor: fVal,
                target: tVal,
                ceiling: cVal
            )
            modelContext.insert(created)
        }
        try? modelContext.save()
        dismiss()
    }
}
