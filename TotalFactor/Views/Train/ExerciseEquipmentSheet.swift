import SwiftUI
import SwiftData

/// Edit an exercise's equipment from inside a workout (or anywhere): equipment type, load mode, the
/// smallest weight jump, and the exact weights a machine stack can be set to (uneven stacks, add-on plates).
struct ExerciseEquipmentSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let exercise: Exercise
    let gymProfile: GymProfile?
    let unitSystem: UnitSystem
    var onSaved: (() -> Void)? = nil

    @State private var equipment: Equipment = .barbell
    @State private var bodyweightMode: BodyweightMode = .standardLoad
    @State private var incrementText: String = ""
    /// Available weights in display units (kg or lb).
    @State private var weights: [Double] = []

    // Stack builder (display units)
    @State private var stackStartText: String = ""
    @State private var stackStepText: String = ""
    @State private var stackCount: Int = 12
    @State private var addOnText: String = ""
    @State private var customWeightText: String = ""
    @State private var didLoad = false

    private var unit: String { unitSystem.weightSymbol }

    private var gymEditTitle: String {
        guard let gymProfile else { return "Edit Gym Equipment" }
        return "Edit Gym Equipment (\(gymProfile.name))"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Equipment", selection: $equipment) {
                        ForEach(Equipment.allCases, id: \.self) { eq in
                            Text(eq.displayName).tag(eq)
                        }
                    }
                    Picker("Load", selection: $bodyweightMode) {
                        ForEach(BodyweightMode.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    HStack {
                        Text("Smallest Jump")
                        Spacer()
                        TextField("2.5", text: $incrementText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Text(unit).foregroundStyle(.secondary)
                    }
                } header: {
                    Text(exercise.name)
                } footer: {
                    if let gymProfile, equipment == .dumbbell || equipment == .cable || equipment.usesBarbellPlates {
                        Text("Your gym profile \"\(gymProfile.name)\" also sets dumbbell, cable and plate jumps; the larger of the two is used.")
                    }
                }

                Section {
                    if weights.isEmpty {
                        Text("Not set. Suggestions round to the smallest jump above.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(weights, id: \.self) { w in
                                    Button {
                                        weights.removeAll { $0 == w }
                                    } label: {
                                        HStack(spacing: 3) {
                                            Text(format(w))
                                                .font(.caption.weight(.semibold).monospacedDigit())
                                            Image(systemName: "xmark")
                                                .font(.system(size: 8, weight: .bold))
                                        }
                                        .padding(.horizontal, 9)
                                        .padding(.vertical, 6)
                                        .background(AppleTheme.tertiarySurface, in: Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                        Button("Clear All Weights", role: .destructive) { weights = [] }
                    }

                    HStack {
                        TextField("Add a weight", text: $customWeightText)
                            .keyboardType(.decimalPad)
                        Text(unit).foregroundStyle(.secondary)
                        Button("Add") {
                            if let w = parse(customWeightText), w > 0 {
                                weights = Array(Set(weights + [w])).sorted()
                                customWeightText = ""
                            }
                        }
                        .disabled(parse(customWeightText) == nil)
                    }
                } header: {
                    Text("Available Weights (\(unit))")
                } footer: {
                    Text("For machines and cable stacks whose weights aren't evenly spaced. Targets and auto-adjustments only use these weights. Tap a weight to remove it.")
                }

                Section {
                    numberRow("First plate", text: $stackStartText)
                    numberRow("Each plate adds", text: $stackStepText)
                    Stepper("Plates: \(stackCount)", value: $stackCount, in: 2...40)
                    numberRow("Add-on weight (optional)", text: $addOnText)
                    Button {
                        buildStack()
                    } label: {
                        Label("Fill From Stack", systemImage: "square.stack.3d.up.fill")
                    }
                    .disabled(parse(stackStartText) == nil || (parse(stackStepText) ?? 0) <= 0)
                } header: {
                    Text("Machine Stack Builder")
                } footer: {
                    Text("Example: a stack of 12 plates starting at 10 and going up by 7.5, with a 2.5 add-on magnet, gives 10, 12.5, 17.5, 20 …")
                }

                if let videoURL = exercise.formVideoSearchURL {
                    Section {
                        Link(destination: videoURL) {
                            Label("Watch Form Video", systemImage: "play.rectangle.fill")
                        }
                    }
                }

                Section {
                    NavigationLink {
                        GymProfileEditorView()
                    } label: {
                        Label(gymEditTitle, systemImage: "dumbbell.fill")
                    }
                } footer: {
                    Text("Change which equipment your gym has, its plates, bar weight and dumbbell range.")
                }
            }
            .navigationTitle("Equipment & Weights")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                }
            }
            .onAppear(perform: loadIfNeeded)
        }
    }

    private func numberRow(_ title: String, text: Binding<String>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("0", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
            Text(unit).foregroundStyle(.secondary)
        }
    }

    private func loadIfNeeded() {
        guard !didLoad else { return }
        didLoad = true
        equipment = exercise.equipment
        bodyweightMode = exercise.bodyweightMode
        incrementText = format(UnitsFormatter.displayWeight(exercise.loadIncrementKg, system: unitSystem))
        weights = exercise.availableWeightsKg.map { roundDisplay(UnitsFormatter.displayWeight($0, system: unitSystem)) }
        if let first = weights.first {
            stackStartText = format(first)
        }
        if weights.count >= 2 {
            stackStepText = format(weights[1] - weights[0])
        }
    }

    private func buildStack() {
        guard let start = parse(stackStartText), let step = parse(stackStepText), step > 0 else { return }
        let addOns = parse(addOnText).map { [$0] } ?? []
        weights = ProgressionEngine.machineStack(startKg: start, stepKg: step, count: stackCount, addOnsKg: addOns)
            .map(roundDisplay)
    }

    private func save() {
        exercise.equipment = equipment
        exercise.bodyweightMode = bodyweightMode
        if let inc = parse(incrementText), inc > 0 {
            exercise.loadIncrementKg = max(0.25, UnitsFormatter.internalKg(fromDisplay: inc, system: unitSystem))
        }
        exercise.availableWeightsKg = weights.map { UnitsFormatter.internalKg(fromDisplay: $0, system: unitSystem) }
        try? modelContext.save()
        onSaved?()
        dismiss()
    }

    private func parse(_ text: String) -> Double? {
        let cleaned = text.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)
        guard !cleaned.isEmpty, let value = Double(cleaned), value >= 0 else { return nil }
        return value
    }

    private func roundDisplay(_ value: Double) -> Double {
        (value * 100).rounded() / 100
    }

    private func format(_ value: Double) -> String {
        let rounded = roundDisplay(value)
        if rounded == rounded.rounded() {
            return String(Int(rounded))
        }
        return String(format: "%g", rounded)
    }
}
