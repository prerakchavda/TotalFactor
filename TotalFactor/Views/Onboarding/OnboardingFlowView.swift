import SwiftUI
import SwiftData

struct OnboardingFlowView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(HealthKitService.self) private var healthService

    @Bindable var profile: UserProfile

    @State private var step: Int = 0
    @State private var unitSystem: UnitSystem = .imperial
    @State private var sex: BiologicalSex = .male
    @State private var age: Int = 29
    @State private var heightFeet: Int = 5
    @State private var heightInches: Int = 10
    @State private var heightCmInput: Double = 178
    @State private var weightInput: Double = 180
    @State private var activityLevel: ActivityLevel = .moderate
    @State private var goalType: GoalType = .cut
    @State private var ratePercent: Double = 0.5
    @State private var healthPermissionRequested: Bool = false

    private var computedWeightKg: Double {
        UnitsFormatter.internalKg(fromDisplay: weightInput, system: unitSystem)
    }

    private var computedHeightCm: Double {
        unitSystem == .imperial
            ? UnitsFormatter.feetInchesToCm(feet: heightFeet, inches: heightInches)
            : heightCmInput
    }

    private var previewTDEE: Double {
        ExpenditureEngine.startingExpenditure(
            sex: sex,
            weightKg: computedWeightKg,
            heightCm: computedHeightCm,
            ageYears: age,
            activityLevel: activityLevel
        )
    }

    private var previewTargets: MacroTargets {
        let bmr = ExpenditureEngine.mifflinStJeorBMR(
            sex: sex,
            weightKg: computedWeightKg,
            heightCm: computedHeightCm,
            ageYears: age
        )
        return MacroTargetEngine.calculateTargets(
            expenditureKcal: previewTDEE,
            goalType: goalType,
            ratePercentPerWeek: ratePercent,
            bodyWeightKg: computedWeightKg,
            sex: sex,
            bmrKcal: bmr
        )
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ProgressView(value: Double(step + 1), total: 3)
                    .padding(.horizontal)
                    .padding(.top, 8)

                if step == 0 {
                    profileStep
                } else if step == 1 {
                    goalStep
                } else {
                    healthPermissionsStep
                }

                HStack(spacing: 12) {
                    if step > 0 {
                        Button("Back") {
                            withAnimation { step -= 1 }
                        }
                        .buttonStyle(.bordered)
                    }
                    Button(step < 2 ? "Continue" : "Finish & Start Coaching") {
                        if step < 2 {
                            withAnimation { step += 1 }
                        } else {
                            completeOnboarding()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                }
                .padding()
            }
            .navigationTitle("Total Factor Setup")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var profileStep: some View {
        Form {
            Section("Preferred Units") {
                Picker("Units", selection: $unitSystem) {
                    ForEach(UnitSystem.allCases) { u in
                        Text(u.displayName).tag(u)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: unitSystem) { oldVal, newVal in
                    let kg = UnitsFormatter.internalKg(fromDisplay: weightInput, system: oldVal)
                    weightInput = (UnitsFormatter.displayWeight(kg, system: newVal) * 10).rounded() / 10
                }
            }

            Section("Baseline Physiology (Mifflin-St Jeor)") {
                Picker("Sex", selection: $sex) {
                    ForEach(BiologicalSex.allCases) { s in
                        Text(s.displayName).tag(s)
                    }
                }
                .pickerStyle(.segmented)

                Stepper("Age: \(age) years", value: $age, in: 16...95)

                if unitSystem == .imperial {
                    HStack {
                        Text("Height")
                        Spacer()
                        Picker("Feet", selection: $heightFeet) {
                            ForEach(4...7, id: \.self) { Text("\($0) ft").tag($0) }
                        }
                        .labelsHidden()
                        Picker("Inches", selection: $heightInches) {
                            ForEach(0...11, id: \.self) { Text("\($0) in").tag($0) }
                        }
                        .labelsHidden()
                    }
                } else {
                    HStack {
                        Text("Height (cm)")
                        Spacer()
                        TextField("178", value: $heightCmInput, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                }

                HStack {
                    Text("Current Weight (\(unitSystem.weightSymbol))")
                    Spacer()
                    TextField("Weight", value: $weightInput, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
            }

            Section {
                Picker("Activity Level", selection: $activityLevel) {
                    ForEach(ActivityLevel.allCases) { level in
                        Text(level.displayName).tag(level)
                    }
                }
            } header: {
                Text("Starting Activity Estimate")
            } footer: {
                Text("Used only in weeks 1–2 before your personal intake + weight trend takes over.")
            }
        }
    }

    private var goalStep: some View {
        Form {
            Section("Primary Goal") {
                Picker("Goal", selection: $goalType) {
                    ForEach(GoalType.allCases) { g in
                        Text(g.displayName).tag(g)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: goalType) { _, newGoal in
                    ratePercent = newGoal.defaultRatePercent
                }

                if goalType != .maintain {
                    VStack(alignment: .leading, spacing: 8) {
                        let weeklyKg = computedWeightKg * (ratePercent / 100.0)
                        let weeklyDisp = UnitsFormatter.formatWeight(weeklyKg, system: unitSystem)
                        HStack {
                            Text("Target Rate")
                            Spacer()
                            Text("\(String(format: "%.2f", ratePercent))% BW/wk (~\(weeklyDisp)/wk)")
                                .font(.subheadline.weight(.semibold).monospacedDigit())
                        }
                        Slider(
                            value: $ratePercent,
                            in: goalType.suggestedRateRangePercent,
                            step: 0.05
                        )
                    }
                }
            }

            Section("Day-1 Coaching Targets Preview") {
                LabeledContent("Starting Expenditure (Formula)", value: "\(Int(previewTDEE.rounded())) kcal")
                LabeledContent("Daily Calories", value: "\(Int(previewTargets.calories)) kcal")
                LabeledContent("Protein Target (Floor \(Int(previewTargets.proteinFloor))g)", value: "\(Int(previewTargets.protein)) g")
                LabeledContent("Carbohydrates", value: "\(Int(previewTargets.carbs)) g")
                LabeledContent("Fat (Floor \(Int(previewTargets.fatFloor))g)", value: "\(Int(previewTargets.fat)) g")
            }
        }
    }

    private var healthPermissionsStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Label("Apple Health Deep Integration", systemImage: "heart.text.square.fill")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.pink)

                Text("Total Factor syncs transparently with Apple Health while keeping coaching math honest:")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                permissionRow(
                    icon: "scalemass.fill",
                    title: "Smart Scale Weight & Body Fat (Read/Write)",
                    detail: "Automatically imports morning weigh-ins in the background and saves manual weigh-ins without duplicating your own entries."
                )
                permissionRow(
                    icon: "fork.knife.circle.fill",
                    title: "Dietary Macros & Micronutrients (Write)",
                    detail: "Every logged food writes a complete Apple Health food correlation. Editing or deleting a food updates Health cleanly."
                )
                permissionRow(
                    icon: "dumbbell.fill",
                    title: "Strength Workouts (Write)",
                    detail: "Completed gym sessions save as Traditional Strength Training workouts with start and end times."
                )
                permissionRow(
                    icon: "applewatch.watchface",
                    title: "Steps, Sleep & Watch Calories (Display Only)",
                    detail: "Shown on your Today dashboard for context. Watch calories NEVER feed your calorie targets — expenditure comes strictly from your intake and weight trend."
                )

                Button {
                    Task {
                        _ = await healthService.requestPermissions()
                        healthPermissionRequested = true
                    }
                } label: {
                    Label(
                        healthPermissionRequested ? "Apple Health Connected" : "Grant Apple Health Access",
                        systemImage: healthPermissionRequested ? "checkmark.seal.fill" : "heart.fill"
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .tint(healthPermissionRequested ? .green : .pink)
            }
            .padding()
        }
    }

    private func permissionRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    private func completeOnboarding() {
        let currentYear = Calendar.current.component(.year, from: .now)
        profile.unitSystem = unitSystem
        profile.biologicalSex = sex
        profile.birthYear = currentYear - age
        profile.heightCm = computedHeightCm
        profile.startingWeightKg = computedWeightKg
        profile.activityLevel = activityLevel
        profile.onboardingCompleted = true

        let goal = CoachingCoordinator.fetchOrCreateGoal(profile: profile, context: modelContext)
        goal.type = goalType
        goal.ratePercentPerWeek = ratePercent
        goal.startWeightKg = computedWeightKg
        goal.startDate = .now

        let initialWeighIn = WeighIn(date: .now, weightKg: computedWeightKg, source: .manual)
        modelContext.insert(initialWeighIn)
        try? modelContext.save()

        _ = CoachingCoordinator.evaluate(context: modelContext)
        Task {
            await healthService.saveManualWeighIn(initialWeighIn)
            await healthService.importExternalBodyMetrics(context: modelContext)
            await healthService.refreshTodayDashboardTelemetry()
        }
    }
}
