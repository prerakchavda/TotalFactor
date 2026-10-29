# Total Factor — Progress & Implementation Report

**Project**: Total Factor (Adaptive Nutrition Coach & Smart Strength Training Tracker)  
**Platform**: Native iOS 17.0+ (SwiftUI, SwiftData, Swift Charts, HealthKit, ActivityKit, WidgetKit, Vision, App Intents)  
**Test Harness**: macOS 14.0+ & iOS 17.0+ (Swift Package Manager `TotalFactorCore` + XCTest)  
**Last Updated**: October 2026  
**Status**: **Phases 1–9 Fully Implemented & Test-Verified** (Pre-Release / TestFlight Candidate)

---

## 1. Executive Summary

Total Factor is a high-performance, offline-first iOS application that merges an **adaptive macro nutrition coach** (energy balance expenditure modeling, dynamic carb cycling) with an **intelligent strength training tracker** (effort-adjusted 1RM, personal rep-endurance curves, cut-aware double progression).

All core mathematical engines are **deterministic, rule-based, and offline-capable**. User interaction adheres strictly to low-friction ground rules:
- **Food Logging**: 2 taps for repeat food logging; inline kitchen-scale calculator.
- **Gym Logging**: 1 tap (`✓`) for set completion with automatic rest interval capture.
- **Wearables**: Apple Watch active calories are treated as **display-only** to prevent double-counting wrist errors on top of true observed scale weight trends.
- **Sync**: SwiftData with CloudKit-safe schema patterns and graceful offline/local fallback.

---

## 2. Phase-by-Phase Completion Matrix

| Phase | Module / Capability | File References | Status | Test Coverage |
|---|---|---|:---:|:---:|
| **Phase 1** | **Foundation & Architecture**<br>• 21 SwiftData `@Model` classes with CloudKit-safe optional relationships<br>• 3-step Onboarding flow (`OnboardingFlowView`)<br>• 5-tab root architecture (`RootTabView`)<br>• Plain-English HealthKit authorization flow | `TotalFactor/App/`<br>`TotalFactor/Models/`<br>`TotalFactor/Views/Onboarding/` | **Complete** | Architecture audit passed |
| **Phase 2** | **Food Logging & Database**<br>• Chronological `FoodTimelineView` with day switcher<br>• Dynamic `MacroZoneBar` (Floor / Target / Ceiling)<br>• `QuickAddFoodSheet` with 2-tap repeat logging<br>• `InlineQuantityCalculator` (pre-selected overwrite, kitchen scale math)<br>• >15% Atwater macro discrepancy detection<br>• `RecipeBuilderSheet` (raw vs. cooked yield weight calculation)<br>• Multi-select meal operations (batch move, copy, save as recipe)<br>• Multi-source search: 78 bundled whole foods, USDA API, Open Food Facts API | `TotalFactor/Views/Food/`<br>`TotalFactor/Core/InlineQuantityCalculator.swift`<br>`TotalFactor/Engines/FoodSearchRanker.swift`<br>`TotalFactor/Services/USDAFoodClient.swift`<br>`TotalFactor/Services/OpenFoodFactsClient.swift` | **Complete** | Unit tests for calculator & Atwater validation |
| **Phase 3** | **Body & Metric Tracking**<br>• `WeightTrendEngine` (EMA $\alpha = 0.1$, carry-forward missing days)<br>• Weigh-in resolution rules (`firstMorning`, `average`, `last`)<br>• Swift Charts scale scatter + trend curve (2W–All)<br>• Multi-point circumference tracking (`BodyMetric`)<br>• `PhotoCompareView` with interactive split slider | `TotalFactor/Engines/WeightTrendEngine.swift`<br>`TotalFactor/Views/Progress/PhotoCompareView.swift`<br>`TotalFactor/Views/Progress/ProgressHubView.swift`<br>`TotalFactor/Views/Components/QuickWeighInSheet.swift` | **Complete** | Unit tests for EMA & resolution rules |
| **Phase 4** | **Adaptive Nutrition Engine**<br>• `ExpenditureEngine` (Mifflin-St Jeor baseline + dynamic energy balance)<br>• 14–28 day rolling expenditure model strictly using `isComplete` days<br>• 3-tier confidence rating (Low, Medium, High)<br>• Maximum $\pm 100\text{ kcal}$ per-step rate clamp<br>• `MacroTargetEngine` (BMR safety floors, protein/fat floors, carb allocation)<br>• `WeeklyCheckInSheet` audit and check-in cadence | `TotalFactor/Engines/ExpenditureEngine.swift`<br>`TotalFactor/Engines/MacroTargetEngine.swift`<br>`TotalFactor/Views/Today/WeeklyCheckInSheet.swift`<br>`TotalFactor/Models/CoachingModels.swift` | **Complete** | 8-week 500 kcal deficit simulation verified within 5% error |
| **Phase 5** | **Strength Workout Logging**<br>• 68 bundled exercises (`BundledExercises.json`) with muscle groups & movement patterns<br>• `ActiveWorkoutView` with 1-tap `✓` logging and rest timer trigger<br>• Set types: Warmup, Working, Drop, Failure, Partial (`W`, `WK`, `D`, `F`, `P`)<br>• Auto-alternating supersets & automated warm-up generator<br>• Visual `PlateCalculatorSheet` for standard Olympic plates<br>• `RestTimerService` + ActivityKit Live Activity & Dynamic Island<br>• `HKWorkout` HealthKit synchronization | `TotalFactor/Views/Train/ActiveWorkoutView.swift`<br>`TotalFactor/Views/Train/PlateCalculatorSheet.swift`<br>`TotalFactor/Services/RestTimerService.swift`<br>`Shared/RestTimerAttributes.swift`<br>`Shared/RestTimerLiveIntents.swift`<br>`TotalFactorWidgets/RestTimerLiveActivityView.swift` | **Complete** | Plate math & rest timer intents verified |
| **Phase 6** | **Programs & Templates**<br>• `ProgramBuilderView` for custom multi-week split authoring<br>• Built-in starter templates (Full Body A/B, Upper/Lower, PPL)<br>• `GymProfileEditorView` with equipment tagging<br>• Automatic movement-pattern equipment swap logic<br>• Rule-based `PlanGeneratorSheet` program synthesizer | `TotalFactor/Views/Train/ProgramBuilderView.swift`<br>`TotalFactor/Views/Train/GymProfileEditorView.swift`<br>`TotalFactor/Views/Train/PlanGeneratorSheet.swift`<br>`TotalFactor/Engines/ProgramGeneratorEngine.swift` | **Complete** | Equipment swap & template generation verified |
| **Phase 7** | **Smart Progression & Fatigue**<br>• Effort-adjusted e1RM: $\text{Weight} \times (1 + \frac{\text{Reps} + \text{RIR}}{k})$<br>• Bayesian personal rep-endurance curve fitting ($k \in [18, 50]$)<br>• Double-progression load/rep recommendations<br>• Acute:chronic fatigue & deload detection<br>• 4-tier automated PR detection (e1RM, Max Weight, Rep-PR at weight, Best Volume)<br>• Anatomical `MuscleVolumeMapView` with set volume vs MEV/MRV | `TotalFactor/Engines/ProgressionEngine.swift`<br>`TotalFactor/Views/Progress/MuscleVolumeMapView.swift`<br>`TotalFactor/Models/TrainingModels.swift` | **Complete** | Unit tests for $k$-curve fitting & PR detection |
| **Phase 8** | **Nutrition × Training Combined**<br>• Isocaloric training-day vs rest-day carb cycling tied to program days<br>• Cut-aware progression (suppresses false deloads on $>0.5\%\text{ BW/wk}$ deficit)<br>• Trailing 7-day protein floor gate for load progression<br>• Dual Weight $\times$ Strength Index correlation chart<br>• Fasted pre-workout alert ($>4\text{ hours}$ without food)<br>• Unified weekly check-in combining intake and strength trends | `TotalFactor/Engines/MacroTargetEngine.swift`<br>`TotalFactor/Engines/ProgressionEngine.swift`<br>`TotalFactor/Services/CoachingCoordinator.swift`<br>`TotalFactor/Views/Progress/ProgressHubView.swift`<br>`TotalFactor/Views/Today/TodayDashboardView.swift` | **Complete** | Protein gate & cut-aware deload suppression verified |
| **Phase 9** | **Polish, Extensions & Widgets**<br>• `TodayDashboardView` unified hub (with Apple Watch display-only badges)<br>• Vision OCR `LabelScannerView` + `NutritionLabelParser`<br>• `MicronutrientDetailSheet` for comprehensive micro breakdown<br>• `TotalFactorWidgetsBundle` Home & Lock screen widgets<br>• Interactive Live Activity with `+30s`, `-15s`, `Skip` App Intents<br>• Siri Shortcuts integration (`TotalFactorShortcuts`)<br>• RFC-4180 compliant `CSVExportService`<br>• Standalone SPM test suite (`Package.swift` + `TotalFactorAlgorithmTests.swift`) | `TotalFactor/Views/Food/LabelScannerView.swift`<br>`TotalFactor/Core/NutritionLabelParser.swift`<br>`TotalFactor/Services/CSVExportService.swift`<br>`TotalFactor/Intents/TotalFactorShortcuts.swift`<br>`TotalFactorWidgets/`<br>`TotalFactorTests/TotalFactorAlgorithmTests.swift` | **Complete** | All unit tests passing |

---

## 3. Mathematical & Algorithmic Engines Breakdown

### A. Adaptive Expenditure Engine (`ExpenditureEngine.swift`)
1. **Mifflin-St Jeor Baseline**:
   $$\text{BMR}_{\text{male}} = 10 \times \text{wt(kg)} + 6.25 \times \text{ht(cm)} - 5 \times \text{age} + 5$$
   $$\text{BMR}_{\text{female}} = 10 \times \text{wt(kg)} + 6.25 \times \text{ht(cm)} - 5 \times \text{age} - 161$$
2. **Energy Balance Differential**:
   $$\Delta \text{Weight}_{\text{rate}} = \frac{\text{TrendWeight}_{t} - \text{TrendWeight}_{t-14}}{14} \text{ (kg/day)}$$
   $$\text{Daily Energy Surplus/Deficit} = \Delta \text{Weight}_{\text{rate}} \times 7,700\text{ kcal/kg}$$
   $$\text{Expenditure}_{\text{raw}} = \overline{\text{Intake}}_{\text{complete}} - \text{Energy Imbalance}$$
3. **Safety Clamps & Ramp**:
   - Days 1–6: Pure Mifflin-St Jeor baseline.
   - Days 7–13: Linear blending ($w = \frac{N - 6}{8}$) to protect against early water/glycogen shifts.
   - Day $\ge 14$: High confidence adaptive tracking with a maximum daily change cap of $\pm 100\text{ kcal}$.
   - Non-compliant days (`isComplete == false` or $<800\text{ kcal}$) are strictly excluded from averaging.

### B. Smart Progression & Rep-Endurance Curve (`ProgressionEngine.swift`)
1. **Effort-Adjusted 1RM**:
   $$\text{e1RM} = \text{Weight} \times \left(1 + \frac{\text{Reps} + \text{RIR}}{k}\right)$$
2. **Personal $k$-Factor Bayesian Shrinkage**:
   - Baseline prior: $k_0 = 30.0$ (Epley formula).
   - Minimum sample criteria: $\ge 4$ working sets ($\text{RIR} \le 4$) spanning a $\ge 4$-rep differential.
   - Regularization shrinks noisy individual estimates back toward $30.0$ using sample size weighting:
     $$k_{\text{fitted}} = \text{clamp}\left(k_{\text{sample}} \times (1 - \lambda) + 30.0 \times \lambda, 18.0, 50.0\right) \quad \text{where } \lambda = \frac{0.006}{N}$$
3. **Combined Cut-Aware & Protein-Gated Progression**:
   - If weekly weight loss rate $>0.5\%\text{ BW/week}$, a temporary performance stall ($<3\%$ dip over 3 sessions) triggers `.holdSteadyOnCut` instead of an erroneous deload.
   - If trailing 7-day average protein falls below the user's protein floor ($<1.6\text{ g/kg}$), load increases are gated with `.holdDueToProteinGate` to prevent injury during insufficient recovery.

### C. Weight Trend Engine (`WeightTrendEngine.swift`)
- Exponential Moving Average with smoothing parameter $\alpha = 0.1$:
  $$\text{Trend}_{t} = \text{Trend}_{t-1} + 0.1 \times (\text{Scale}_{t} - \text{Trend}_{t-1})$$
- Missing days carry forward the previous trend without generating fictitious scale data points (`scaleKg = nil`).
- Configurable morning weigh-in resolution rules: `firstMorning` (earliest before 12:00 PM), `average` (mean of day's weigh-ins), or `last` (most recent).

---

## 4. Architecture & Engineering Decisions Audit

1. **SwiftData & CloudKit Interoperability**:
   - Avoided non-optional relationships and unidirectional links that trigger CloudKit sync aborts.
   - Complex nested structures (`[ServingSize]`, `[String: Double]`, `[UUID]`) are serialized as binary `Data` backing typed computed properties, avoiding CoreData lightweight migration errors.
   - Default SQLite local container allows the app to compile and run on free Apple Developer teams without provisioning errors, while paid teams can toggle CloudKit sync seamlessly in Settings.
2. **Timezone-Resilient Calendar Day Keys**:
   - All time-series entities store an exact `timestamp: Date` alongside a canonical local `dayKey: String` (`"YYYY-MM-DD"` via `DateDayKey.swift`), guaranteeing meals and weigh-ins do not drift across midnight boundaries during travel.
3. **HealthKit Correlation Handling**:
   - Resolved iOS `NSInvalidArgumentException` crash when querying `HKCorrelationType(.food)` by querying constituent quantity types and constructing `.food` correlations with explicit metadata keys.
4. **Open Food Facts API Data Normalization**:
   - Normalized OFF v2 `sodium_100g` from grams to milligrams (preventing a $1,000\times$ under-reporting defect).
   - Handled comma-decimal localization string fields (`"14,5"`) via `FlexibleDouble` decoding.

---

## 5. Verification & Test Suite Summary

The app includes a dedicated XCTest suite (`TotalFactorTests/TotalFactorAlgorithmTests.swift`) executable via both Xcode (`Cmd + U`) and Swift Package Manager command-line:

```bash
swift test
```

### Verified Test Cases:
1. `testWeightTrendEMAAndMissingDaysCarryForward`: Verifies missing day trend stability and null scale preservation.
2. `testDailyWeighInResolutionRules`: Verifies `firstMorning`, `average`, and `last` resolution.
3. `testEightWeek500KcalDeficitSimulationLandsWithinFivePercent`: 56-day simulated lifter with water noise and missing logs; converges within 5% of true 2700 kcal TDEE with high confidence.
4. `testExpenditureClampLimitsSingleUpdateTo100Kcal`: Verifies $\pm 100\text{ kcal}$ update clamp.
5. `testMacroTargetMathAndCalorieFloorEnforcement`: Verifies BMR safety floor, 40 g carb floor, and protein floors.
6. `testTrainingDayCarbCyclingPreservesWeeklyCalories`: Verifies exact weekly calorie parity across high/low days.
7. `testPersonalRepCurveKFittingDistinguishesEnduranceVsFastTwitch`: Verifies differentiation between fast-twitch ($k \approx 23$) and endurance ($k \approx 38$) profiles.
8. `testSmartProgressionProteinGateAndCutAwareDeloadSuppression`: Verifies protein gating and cut-aware deload suppression.
9. `testBarbellPlateCalculator`: Verifies optimal Olympic plate breakdowns per side.
10. `testNutritionLabelOCRParserAndQualityFlag`: Verifies Vision OCR parsing and Atwater discrepancy flag ($>15\%$).
11. `testDetectSessionPRsIncludesMostRepsAtWeightAndRejectsLighterSubPR`: Verifies 4 PR types and rejection of inferior sub-PRs.
12. `testInlineQuantityCalculatorOverwriteAndKitchenScaleMath`: Verifies first-digit overwrite and kitchen scale math (`+`/`×`).

---

## 6. Pre-Launch Checklist (Path to 1.0 Release)

- [x] Swift 5.10 / iOS 17 + watchOS 10 Native Compilation (`TotalFactor`, `TotalFactorWidgets`, `TotalFactorWatch`)
- [x] Offline Bundled Foods (8,156 USDA Foundation + SR Legacy Foods via `OfflineUSDACatalogService`)
- [x] Voice Dictation, Offline Multi-Item Natural-Language Meal Parser & Optional Gemini Photo/Text Meal Logging
- [x] Offline Bundled Exercises & Guides (96 Movements + 182 Offline Demo Photos)
- [x] Planet Fitness Active Gym Profile & 4-Day Planet Fitness Split
- [x] Bundled Strong Workout History (124 Sessions / 1,214 Sets) + CSV Importer
- [x] App Icon & Accent Color Asset Catalogs
- [x] Live Activities & Dynamic Island Layouts
- [x] Lock Screen & Home Screen Widgets
- [x] HealthKit Authorization & Background Delivery
- [x] Camera Permissions (Barcode & OCR Label Scanning)
- [x] Unit Test Suite (SPM + XCTest — 14 Suites Passing)
- [ ] TestFlight Internal Beta Build Distribution
- [ ] Ingest Full 8,000-Item USDA Bulk Dataset (`Scripts/build_full_usda_bundle.py`)
- [ ] App Store Screenshots & Privacy Nutrition Nutrition Nutrition Label Documentation
- [ ] watchOS Companion App (Targeted for v1.1)
