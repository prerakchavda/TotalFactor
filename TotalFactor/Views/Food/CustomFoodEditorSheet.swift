import SwiftUI
import SwiftData

struct CustomFoodEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let existingFood: Food?
    let prefilledBarcode: String?
    let parsedLabel: ParsedNutritionLabel?
    var onSaved: (Food) -> Void

    @State private var name: String = ""
    @State private var brand: String = ""
    @State private var barcode: String = ""
    @State private var servingLabel: String = "1 serving"
    @State private var servingGrams: Double = 100
    @State private var caloriesPerServing: Double = 0
    @State private var proteinPerServing: Double = 0
    @State private var carbsPerServing: Double = 0
    @State private var fatPerServing: Double = 0
    @State private var fiberPerServing: Double = 0
    @State private var sugarPerServing: Double = 0
    @State private var sodiumMgPerServing: Double = 0

    var body: some View {
        NavigationStack {
            Form {
                Section("Food Identity") {
                    TextField("Food Name", text: $name)
                    TextField("Brand (optional)", text: $brand)
                    TextField("Barcode / UPC (optional)", text: $barcode)
                        .keyboardType(.numberPad)
                }

                Section("Serving Reference") {
                    TextField("Serving Label (e.g. 1 bar, 1 scoop)", text: $servingLabel)
                    HStack {
                        Text("Serving Weight (grams)")
                        Spacer()
                        TextField("100", value: $servingGrams, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                }

                Section("Nutrients Per Serving (\(Int(max(1, servingGrams).rounded())) g)") {
                    nutrientField("Calories (kcal)", value: $caloriesPerServing)
                    nutrientField("Protein (g)", value: $proteinPerServing)
                    nutrientField("Total Carbs (g)", value: $carbsPerServing)
                    nutrientField("Total Fat (g)", value: $fatPerServing)
                    nutrientField("Dietary Fiber (g)", value: $fiberPerServing)
                    nutrientField("Total Sugars (g)", value: $sugarPerServing)
                    nutrientField("Sodium (mg)", value: $sodiumMgPerServing)
                }
            }
            .navigationTitle(existingFood == nil ? "New Custom Food" : "Edit Custom Food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveFood() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear(perform: populateInitialValues)
        }
    }

    private func nutrientField(_ label: String, value: Binding<Double>) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("0", value: value, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
        }
    }

    private func populateInitialValues() {
        if let food = existingFood {
            name = food.name
            brand = food.brand ?? ""
            barcode = food.barcode ?? ""
            let firstS = food.servingSizes.first ?? ServingSize(label: "100 g", grams: 100)
            servingLabel = firstS.label
            servingGrams = firstS.grams
            let scaled = food.nutrientsPer100g.scaled(forGrams: firstS.grams)
            caloriesPerServing = (scaled.calories * 10).rounded() / 10
            proteinPerServing = (scaled.protein * 10).rounded() / 10
            carbsPerServing = (scaled.carbs * 10).rounded() / 10
            fatPerServing = (scaled.fat * 10).rounded() / 10
            fiberPerServing = (scaled.fiber * 10).rounded() / 10
            sugarPerServing = (scaled.sugar * 10).rounded() / 10
            sodiumMgPerServing = scaled.sodiumMg.rounded()
        } else {
            if let bc = prefilledBarcode { barcode = bc }
            if let parsed = parsedLabel {
                servingLabel = parsed.servingLabel
                servingGrams = parsed.servingGrams
                caloriesPerServing = parsed.perServing.calories
                proteinPerServing = parsed.perServing.protein
                carbsPerServing = parsed.perServing.carbs
                fatPerServing = parsed.perServing.fat
                fiberPerServing = parsed.perServing.fiber
                sugarPerServing = parsed.perServing.sugar
                sodiumMgPerServing = parsed.perServing.sodiumMg
            }
        }
    }

    private func saveFood() {
        let g = max(1.0, servingGrams)
        let factor = 100.0 / g
        let per100 = NutrientsPer100g(
            calories: caloriesPerServing * factor,
            protein: proteinPerServing * factor,
            carbs: carbsPerServing * factor,
            fat: fatPerServing * factor,
            fiber: fiberPerServing * factor,
            sugar: sugarPerServing * factor,
            sodiumMg: sodiumMgPerServing * factor,
            micronutrients: parsedLabel?.per100g.micronutrients ?? existingFood?.micronutrients ?? [:]
        )

        var sizes = [ServingSize(label: servingLabel.isEmpty ? "1 serving" : servingLabel, grams: g)]
        if abs(g - 100.0) > 0.5 {
            sizes.append(ServingSize(label: "100 g", grams: 100.0))
        }

        if let food = existingFood {
            food.name = name
            food.brand = brand.isEmpty ? nil : brand
            food.barcode = barcode.isEmpty ? nil : barcode
            food.servingSizes = sizes
            food.nutrientsPer100g = per100
            try? modelContext.save()
            dismiss()
            onSaved(food)
        } else {
            let created = Food(
                name: name,
                brand: brand.isEmpty ? nil : brand,
                barcode: barcode.isEmpty ? nil : barcode,
                source: .custom,
                servingSizes: sizes,
                nutrientsPer100g: per100
            )
            modelContext.insert(created)
            try? modelContext.save()
            dismiss()
            onSaved(created)
        }
    }
}
