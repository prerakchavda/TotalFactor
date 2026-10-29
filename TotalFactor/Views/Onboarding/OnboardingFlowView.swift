import SwiftUI
import SwiftData

enum OnboardingStep: Int, CaseIterable, Identifiable {
    case welcome = 0
    case unitsAndDemographics = 1
    case bodyMetrics = 2
    case activityBaseline = 3
    case primaryGoal = 4
    case targetRate = 5
    case workoutSetup = 6
    case nutritionPreview = 7
    case appleHealth = 8
    case readyToLaunch = 9

    var id: Int { rawValue }
}

struct OnboardingFlowView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(HealthKitService.self) private var healthService

    @Bindable var profile: UserProfile

    @Query private var gymProfiles: [GymProfile]
    @Query private var exercises: [Exercise]
    @Query private var programs: [Program]
    @Query private var goals: [Goal]

    @State private var step: OnboardingStep = .welcome

    // Demographics
    @State private var unitSystem: UnitSystem = .imperial
    @State private var sex: BiologicalSex = .male
    @State private var age: Int = 29
    @State private var heightFeet: Int = 5
    @State private var heightInches: Int = 10
    @State private var heightCmInput: Double = 178
    @State private var weightInput: Double = 180

    // Nutrition & Goal
    @State private var activityLevel: ActivityLevel = .moderate
    @State private var goalType: GoalType = .cut
    @State private var ratePercent: Double = 0.50
    @State private var enableCarbCycling: Bool = true

    // Workouts (MacroFactor Workouts Setup)
    @State private var setupWorkoutProgram: Bool = true
    @State private var workoutDaysPerWeek: Int = 4
    @State private var trainingFocus: TrainingGoalFocus = .both
    @State private var experienceLevel: ExperienceLevel = .intermediate
    @State private var selectedGymProfileID: UUID? = nil

    // Integrations
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
                if step != .welcome {
                    OnboardingHeader(
                        currentStep: step.rawValue,
                        totalSteps: OnboardingStep.allCases.count - 1,
                        title: stepTitle,
                        subtitle: stepSubtitle
                    )
                }

                ScrollView {
                    VStack(spacing: 18) {
                        switch step {
                        case .welcome:
                            welcomePage
                        case .unitsAndDemographics:
                            unitsDemographicsPage
                        case .bodyMetrics:
                            bodyMetricsPage
                        case .activityBaseline:
                            activityBaselinePage
                        case .primaryGoal:
                            primaryGoalPage
                        case .targetRate:
                            targetRatePage
                        case .workoutSetup:
                            workoutSetupPage
                        case .nutritionPreview:
                            nutritionPreviewPage
                        case .appleHealth:
                            appleHealthPage
                        case .readyToLaunch:
                            readyToLaunchPage
                        }
                    }
                    .padding()
                }

                OnboardingBottomBar(
                    canGoBack: step != .welcome,
                    continueTitle: step == .readyToLaunch ? "Enter Total Factor" : "Continue",
                    onBack: goBack,
                    onContinue: goNext
                )
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if profile.onboardingCompleted {
                        Button("Close") { dismiss() }
                    }
                }
            }
            .onAppear {
                initFromProfile()
            }
        }
    }

    // MARK: - Navigation Titles & Subtitles

    private var stepTitle: String {
        switch step {
        case .welcome: return "Welcome"
        case .unitsAndDemographics: return "Units & Demographics"
        case .bodyMetrics: return "Height & Body Weight"
        case .activityBaseline: return "Lifestyle & Baseline Activity"
        case .primaryGoal: return "Select Your Primary Goal"
        case .targetRate: return "Target Rate of Change"
        case .workoutSetup: return "Training & Gym Setup"
        case .nutritionPreview: return "Your Day-1 Nutrition Strategy"
        case .appleHealth: return "Apple Health Deep Sync"
        case .readyToLaunch: return "You're All Set!"
        }
    }

    private var stepSubtitle: String? {
        switch step {
        case .welcome:
            return nil
        case .unitsAndDemographics:
            return "Used to configure your display preferences and seed the Mifflin-St Jeor metabolic baseline."
        case .bodyMetrics:
            return "Your starting scale weight and height establish your baseline BMI and lean mass protections."
        case .activityBaseline:
            return "Seeds weeks 1–2 before your personal scale weight and food log take over automatically."
        case .primaryGoal:
            return "Choose the core physiological objective for your upcoming coaching macro cycle."
        case .targetRate:
            return "Pick a sustainable weekly pace. Total Factor dynamically adapts calories to keep you on this pace."
        case .workoutSetup:
            return "Total Factor unites strength training with nutrition, syncing carb cycling and recovery."
        case .nutritionPreview:
            return "Review your initial daily energy and macronutrient targets calculated specifically for you."
        case .appleHealth:
            return "Seamless bidirectional sync with Apple Health, smart scales, and Apple Watch workouts."
        case .readyToLaunch:
            return "Everything is calibrated and ready. Your adaptive coaching journey starts now."
        }
    }

    // MARK: - Step 0: Welcome Page

    private var welcomePage: some View {
        VStack(spacing: 24) {
            VStack(spacing: 12) {
                Image(systemName: "bolt.heart.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(Color.accentColor)
                    .padding(.top, 24)

                Text("Total Factor")
                    .font(.system(size: 34, weight: .heavy, design: .rounded))

                Text("The Adaptive Diet & Training Co-Pilot")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 16) {
                pillarRow(
                    icon: "flame.fill",
                    color: .orange,
                    title: "Adaptive Metabolic Math",
                    desc: "No more guessing calories. Total Factor dynamically calculates your true Daily Energy Expenditure from your food and scale data."
                )
                pillarRow(
                    icon: "checkmark.seal.fill",
                    color: .green,
                    title: "Adherence-Neutral Coaching",
                    desc: "100% judgment-free. No broken streaks, no red penalty warnings. Honest data always yields honest coaching adjustments."
                )
                pillarRow(
                    icon: "figure.strengthtraining.traditional",
                    color: .blue,
                    title: "Lifting & Nutrition in Sync",
                    desc: "MacroFactor-style workouts and automated Training-Day Carb Cycling fuel your heavy lifts while trimming body fat."
                )
                pillarRow(
                    icon: "lock.shield.fill",
                    color: .purple,
                    title: "100% Private & On-Device",
                    desc: "All logs, weights, and photos stay stored locally on your iPhone in SwiftData. Works completely offline with zero subscriptions."
                )
            }
            .padding(.top, 8)
        }
    }

    private func pillarRow(icon: String, color: Color, title: String, desc: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 38, height: 38)
                .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.bold))
                Text(desc)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Step 1: Units & Demographics

    private var unitsDemographicsPage: some View {
        VStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Measurement System")
                    .font(.headline)

                HStack(spacing: 12) {
                    OnboardingSelectableCard(
                        title: "Imperial",
                        subtitle: "Pounds (lb), Feet/Inches",
                        systemImage: "scalemass.fill",
                        accentColor: .blue,
                        isSelected: unitSystem == .imperial
                    ) {
                        unitSystem = .imperial
                    }

                    OnboardingSelectableCard(
                        title: "Metric",
                        subtitle: "Kilograms (kg), Centimeters",
                        systemImage: "ruler.fill",
                        accentColor: .indigo,
                        isSelected: unitSystem == .metric
                    ) {
                        unitSystem = .metric
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Biological Sex")
                    .font(.headline)

                HStack(spacing: 12) {
                    OnboardingSelectableCard(
                        title: "Male",
                        subtitle: "Baseline formula & fat floor",
                        systemImage: "figure.stand",
                        accentColor: .cyan,
                        isSelected: sex == .male
                    ) {
                        sex = .male
                    }

                    OnboardingSelectableCard(
                        title: "Female",
                        subtitle: "Baseline formula & fat floor",
                        systemImage: "figure.stand.dress",
                        accentColor: .pink,
                        isSelected: sex == .female
                    ) {
                        sex = .female
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Age")
                    .font(.headline)

                HStack {
                    Text("\(age) years old")
                        .font(.title3.weight(.bold).monospacedDigit())
                    Spacer()
                    Stepper("", value: $age, in: 16...95)
                        .labelsHidden()
                }
                .padding(14)
                .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }

    // MARK: - Step 2: Body Metrics

    private var bodyMetricsPage: some View {
        VStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Current Height")
                    .font(.headline)

                if unitSystem == .imperial {
                    HStack(spacing: 14) {
                        HStack {
                            Text("Feet")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Picker("Feet", selection: $heightFeet) {
                                ForEach(4...7, id: \.self) { Text("\($0) ft").tag($0) }
                            }
                        }
                        .padding(12)
                        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                        HStack {
                            Text("Inches")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Picker("Inches", selection: $heightInches) {
                                ForEach(0...11, id: \.self) { Text("\($0) in").tag($0) }
                            }
                        }
                        .padding(12)
                        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                } else {
                    HStack {
                        Text("Centimeters")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        TextField("178", value: $heightCmInput, format: .number)
                            .keyboardType(.decimalPad)
                            .font(.title3.weight(.bold).monospacedDigit())
                            .multilineTextAlignment(.trailing)
                        Text("cm")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(14)
                    .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Current Scale Weight")
                    .font(.headline)

                HStack {
                    Image(systemName: "scalemass.fill")
                        .foregroundStyle(Color.accentColor)
                    Text("Scale Weight")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    TextField("Weight", value: $weightInput, format: .number)
                        .keyboardType(.decimalPad)
                        .font(.title2.weight(.bold).monospacedDigit())
                        .multilineTextAlignment(.trailing)
                    Text(unitSystem.weightSymbol)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                .padding(14)
                .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                Text("💡 Tip: Use your morning weight (right after waking up and using the bathroom). Total Factor smooths out daily water weight fluctuations automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    // MARK: - Step 3: Activity Baseline

    private var activityBaselinePage: some View {
        VStack(spacing: 12) {
            ForEach(ActivityLevel.allCases) { level in
                let (icon, desc): (String, String) = {
                    switch level {
                    case .sedentary:
                        return ("chair.lounge.fill", "Desk job, mostly seated, <5,000 steps per day")
                    case .light:
                        return ("figure.walk", "1–3 light workouts per week or 6,000–8,000 steps")
                    case .moderate:
                        return ("figure.run", "3–5 strength/cardio sessions per week or 8,000–11,000 steps")
                    case .veryActive:
                        return ("bolt.fill", "Hard training 6+ days/wk or demanding physical occupation, 12,000+ steps")
                    }
                }()

                OnboardingSelectableCard(
                    title: level.displayName.components(separatedBy: " (").first ?? level.displayName,
                    subtitle: desc,
                    systemImage: icon,
                    accentColor: .accentColor,
                    isSelected: activityLevel == level,
                    badgeText: String(format: "%.2fx", level.multiplier)
                ) {
                    activityLevel = level
                }
            }
        }
    }

    // MARK: - Step 4: Primary Goal

    private var primaryGoalPage: some View {
        VStack(spacing: 14) {
            ForEach(GoalType.allCases) { g in
                MacroFactorGoalCard(goal: g, isSelected: goalType == g) {
                    goalType = g
                    ratePercent = g.defaultRatePercent
                }
            }
        }
    }

    // MARK: - Step 5: Target Rate of Change

    private var targetRatePage: some View {
        VStack(spacing: 16) {
            if goalType == .maintain {
                VStack(spacing: 14) {
                    Image(systemName: "equal.circle.fill")
                        .font(.system(size: 54))
                        .foregroundStyle(.blue)

                    Text("Weight Maintenance Cycle")
                        .font(.title3.weight(.bold))

                    Text("When maintaining, Total Factor keeps your calories anchored directly to your dynamic energy expenditure. Your goal is to keep scale weight stable within a natural ±1.5% body weight fluid buffer while maximizing recovery and lifting strength.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .padding(24)
                .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            } else {
                MacroFactorRateSliderCard(
                    goalType: goalType,
                    ratePercent: $ratePercent,
                    bodyWeightKg: computedWeightKg,
                    unitSystem: unitSystem
                )
            }
        }
    }

    // MARK: - Step 6: Workouts & Training Setup (MacroFactor Workouts)

    private var workoutSetupPage: some View {
        VStack(spacing: 18) {
            Toggle(isOn: $setupWorkoutProgram) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Activate Strength Training Routine")
                        .font(.headline)
                    Text("Generates a personalized gym program aligned with your lifting goals.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .tint(Color.accentColor)
            .padding(14)
            .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            if setupWorkoutProgram {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Weekly Training Frequency")
                        .font(.headline)

                    HStack {
                        Text("\(workoutDaysPerWeek) days / week")
                            .font(.title3.weight(.bold).monospacedDigit())
                        Spacer()
                        Stepper("", value: $workoutDaysPerWeek, in: 2...6)
                            .labelsHidden()
                    }
                    .padding(14)
                    .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Primary Training Focus")
                        .font(.headline)

                    HStack(spacing: 10) {
                        ForEach(TrainingGoalFocus.allCases) { focus in
                            OnboardingSelectableCard(
                                title: focus.displayName,
                                systemImage: focus == .hypertrophy ? "figure.strengthtraining.traditional" : (focus == .strength ? "dumbbell.fill" : "flame.fill"),
                                accentColor: .blue,
                                isSelected: trainingFocus == focus
                            ) {
                                trainingFocus = focus
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Primary Gym Setup")
                        .font(.headline)

                    if !gymProfiles.isEmpty {
                        Picker("Gym Profile", selection: Binding(
                            get: { selectedGymProfileID ?? gymProfiles.first?.id },
                            set: { selectedGymProfileID = $0 }
                        )) {
                            ForEach(gymProfiles) { gym in
                                Text(gym.name).tag(Optional(gym.id))
                            }
                        }
                        .pickerStyle(.menu)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    } else {
                        Text("Standard Commercial Gym (Dumbbells, Barbells, Cables & Machines)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
            }
        }
    }

    // MARK: - Step 7: Nutrition Strategy Preview

    private var nutritionPreviewPage: some View {
        VStack(spacing: 18) {
            MacroFactorSplitPreviewBar(
                calories: previewTargets.calories,
                targets: previewTargets
            )

            VStack(spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Starting Energy Expenditure (TDEE)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                        Text("\(Int(previewTDEE.rounded())) kcal / day")
                            .font(.title3.weight(.bold).monospacedDigit())
                    }
                    Spacer()
                    Text("Baseline Formula")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.secondary.opacity(0.12), in: Capsule())
                        .foregroundStyle(.secondary)
                }
                .padding(14)
                .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                Toggle(isOn: $enableCarbCycling) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Training-Day Carb Cycling")
                            .font(.headline)
                        Text("Shifts carbohydrates and calories higher on workout days and lower on rest days for better gym recovery.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .tint(Color.accentColor)
                .padding(14)
                .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }

    // MARK: - Step 8: Apple Health Deep Sync

    private var appleHealthPage: some View {
        VStack(spacing: 16) {
            VStack(spacing: 12) {
                permissionRow(
                    icon: "scalemass.fill",
                    color: .blue,
                    title: "Smart Scale Weight (Read/Write)",
                    detail: "Syncs morning weigh-ins in the background from Withings, Garmin, or manual logs."
                )
                permissionRow(
                    icon: "fork.knife.circle.fill",
                    color: .orange,
                    title: "Dietary Macros & Nutrition (Read/Write)",
                    detail: "Writes complete macro & calorie records; reads external third-party meals cleanly."
                )
                permissionRow(
                    icon: "dumbbell.fill",
                    color: .green,
                    title: "Strength Workouts (Write)",
                    detail: "Completed gym sessions save as Traditional Strength Training with timestamps."
                )
                permissionRow(
                    icon: "applewatch.watchface",
                    color: .pink,
                    title: "Watch Steps & Telemetry (Display Only)",
                    detail: "Shown on your dashboard for context. Watch calories never distort coaching targets."
                )
            }

            Button {
                Task {
                    _ = await healthService.requestPermissions()
                    await MainActor.run {
                        healthPermissionRequested = true
                    }
                }
            } label: {
                HStack {
                    Image(systemName: healthPermissionRequested ? "checkmark.circle.fill" : "heart.fill")
                    Text(healthPermissionRequested ? "Apple Health Connected" : "Connect Apple Health Access")
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(healthPermissionRequested ? .green : .pink)

            Button("Skip for Now / Configure Later") {
                goNext()
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
        }
    }

    private func permissionRow(icon: String, color: Color, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 32, height: 32)
                .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Step 9: Ready to Launch

    private var readyToLaunchPage: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.green)

                Text("Your Program is Ready")
                    .font(.title.weight(.heavy))
            }

            VStack(spacing: 12) {
                summaryRow(title: "Starting Weight", value: String(format: "%.1f %@", UnitsFormatter.displayWeight(computedWeightKg, system: unitSystem), unitSystem.weightSymbol))
                summaryRow(title: "Goal", value: goalType.displayName)
                if goalType != .maintain {
                    summaryRow(title: "Target Pace", value: String(format: "%.2f%% BW/wk", ratePercent))
                }
                summaryRow(title: "Calorie Target", value: "\(Int(previewTargets.calories)) kcal / day")
                summaryRow(title: "Protein Target", value: "\(Int(previewTargets.protein))g (floor \(Int(previewTargets.proteinFloor))g)")
                if setupWorkoutProgram {
                    summaryRow(title: "Workout Split", value: "\(workoutDaysPerWeek) Days / Week (\(trainingFocus.displayName))")
                }
            }
            .padding(16)
            .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            Text("Total Factor will monitor your weight and intake daily, guiding your weekly check-ins with 100% adherence-neutral science.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
    }

    private func summaryRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.bold))
        }
    }

    // MARK: - Actions

    private func initFromProfile() {
        unitSystem = profile.unitSystem
        sex = profile.biologicalSex
        age = profile.ageYears
        heightFeet = Int(profile.heightCm / 30.48)
        heightInches = Int(((profile.heightCm / 2.54).truncatingRemainder(dividingBy: 12)).rounded())
        heightCmInput = profile.heightCm
        weightInput = UnitsFormatter.displayWeight(profile.startingWeightKg, system: profile.unitSystem)
        activityLevel = profile.activityLevel
        enableCarbCycling = profile.enableTrainingDayCarbCycling

        if let g = goals.first(where: \.isActive) ?? goals.first {
            goalType = g.type
            ratePercent = g.ratePercentPerWeek
        }
    }

    private func goBack() {
        guard let prev = OnboardingStep(rawValue: step.rawValue - 1) else { return }
        withAnimation(.easeInOut(duration: 0.25)) {
            step = prev
        }
    }

    private func goNext() {
        if step == .readyToLaunch {
            completeOnboarding()
            dismiss()
            return
        }

        guard let next = OnboardingStep(rawValue: step.rawValue + 1) else { return }
        withAnimation(.easeInOut(duration: 0.25)) {
            step = next
        }
    }

    private func completeOnboarding() {
        let currentYear = Calendar.current.component(.year, from: .now)
        profile.unitSystem = unitSystem
        profile.biologicalSex = sex
        profile.birthYear = currentYear - age
        profile.heightCm = computedHeightCm
        profile.startingWeightKg = computedWeightKg
        profile.activityLevel = activityLevel
        profile.enableTrainingDayCarbCycling = enableCarbCycling
        profile.onboardingCompleted = true

        let goal = CoachingCoordinator.fetchOrCreateGoal(profile: profile, context: modelContext)
        goal.type = goalType
        goal.ratePercentPerWeek = ratePercent
        goal.startWeightKg = computedWeightKg
        goal.startDate = .now

        let initialWeighIn = WeighIn(date: .now, weightKg: computedWeightKg, source: .manual)
        modelContext.insert(initialWeighIn)

        // Generate and activate workout routine if requested
        if setupWorkoutProgram && !exercises.isEmpty {
            let activeGym = gymProfiles.first(where: { $0.id == selectedGymProfileID })
                ?? gymProfiles.first(where: \.isDefault)
                ?? gymProfiles.first
            let equip = Set(activeGym?.availableEquipment ?? Equipment.allCases)
            let blueprint = ProgramGeneratorEngine.generateProgram(
                goalFocus: trainingFocus,
                experience: experienceLevel,
                daysPerWeek: workoutDaysPerWeek,
                minutesPerSession: 60,
                availableEquipment: equip,
                exercisePool: exercises.map(\.asBlueprint)
            )

            // Deactivate any old programs and insert new one
            for p in programs { p.isActive = false }
            let program = Program(name: blueprint.name, daysPerWeek: blueprint.daysPerWeek, isActive: true)
            modelContext.insert(program)

            for (wIdx, wb) in blueprint.workouts.enumerated() {
                let workout = ProgramWorkout(name: wb.name, order: wIdx, scheduledWeekday: wb.scheduledWeekday)
                workout.program = program
                modelContext.insert(workout)

                for (sIdx, sb) in wb.slots.enumerated() {
                    let matchingEx = exercises.first(where: { $0.id == sb.exercise.id }) ?? exercises.first
                    let slot = ExerciseSlot(
                        order: sIdx,
                        exercise: matchingEx,
                        sets: sb.sets,
                        repRangeLow: sb.repRangeLow,
                        repRangeHigh: sb.repRangeHigh,
                        targetRIR: sb.targetRIR,
                        restSeconds: sb.restSeconds,
                        progressionRule: sb.progressionRule,
                        supersetGroup: sb.supersetGroup
                    )
                    slot.workout = workout
                    modelContext.insert(slot)
                }
            }
        }

        try? modelContext.save()
        _ = CoachingCoordinator.evaluate(context: modelContext)

        Task {
            await healthService.saveManualWeighIn(initialWeighIn)
            await healthService.importExternalBodyMetrics(context: modelContext)
            await healthService.refreshTodayDashboardTelemetry()
        }
    }
}
