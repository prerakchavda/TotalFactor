# Total Factor

**Total Factor** is an offline-first, native iOS 17+ adaptive nutrition coach and smart strength training tracker built with **SwiftUI**, **SwiftData**, **Swift Charts**, **HealthKit**, **Vision / VisionKit**, **ActivityKit (Live Activities & Dynamic Island)**, **WidgetKit**, and **App Intents (Siri Shortcuts)**.

---

## Project Documentation

- [UPDATES.md](UPDATES.md): Running plain-English log of every feature, bug fix, and small tweak (also viewable inside the app under **Settings → What's New & Update Log**).
- [PROGRESS.md](PROGRESS.md): Detailed phase-by-phase status, mathematical engine specifications, test coverage report, and pre-launch checklist.
- [ROADMAP.md](ROADMAP.md): Product roadmap, post-v1 milestones (watchOS companion app, multimodal meal estimation), and architectural backlog.
- [CHANGELOG.md](CHANGELOG.md): Complete release history, newly built features, and architectural fixes across all 9 development phases.
- [ARCHITECTURE_REVIEW.md](ARCHITECTURE_REVIEW.md): Deep-dive into technical ground rules, SwiftData CloudKit schema patterns, and edge case resolutions.

---

## Updating Total Factor on Your iPhone

**Important**: Do **not** delete Total Factor on your iPhone before updating — installing over the existing app keeps all of your logged meals, weigh-ins, and workouts intact!

- **Option 1 — 1-Command Terminal Update**: With your iPhone plugged in (or unlocked on the same Wi-Fi), run:
  ```bash
  ./Scripts/update_iphone.sh
  ```
- **Option 2 — Xcode (`Cmd + R`)**: Open `TotalFactor.xcodeproj`, select **prerak iPhone** in the top device bar, and press **`Cmd + R`** (the Play button).

---

## Quick Start on macOS (Xcode 15 / 16+)

1. Open **`TotalFactor.xcodeproj`** in Xcode.
2. Select both **`TotalFactor`** and **`TotalFactorWidgetsExtension`** targets under **Signing & Capabilities** and choose your Apple ID / Team:
   - **Free Personal Team ($0)**: Works immediately! Keep `TotalFactor/Resources/TotalFactor.entitlements` selected (CloudKit is disabled by default so free provisioning profiles build and launch cleanly). Note: change the Bundle Identifier prefix (`com.totalfactor.app`) to something unique to your Apple ID (e.g., `com.yourname.totalfactor`).
   - **Paid Apple Developer Program ($99/yr)**: Point `CODE_SIGN_ENTITLEMENTS` to `TotalFactor/Resources/TotalFactor.PaidTeam.entitlements` (or add **iCloud -> CloudKit** and **App Groups -> `group.com.totalfactor.app`** in Signing & Capabilities) and toggle **iCloud / CloudKit Sync** on in Total Factor's **Settings** tab.
3. Press **`Cmd + R`** to run on an iPhone Simulator or physical iPhone, or **`Cmd + U`** to run the `TotalFactorTests` unit test suite.
   - You can also run pure-Swift algorithm tests directly from Terminal via Swift Package Manager:
     ```bash
     swift test
     ```

---

## What's Built (Phases 1–9)

| Phase | Included Modules & Features |
|---|---|
| **1. Foundation** | `TotalFactorApp`, 21 CloudKit-safe SwiftData `@Model` entities, 3-step `OnboardingFlowView`, 5-tab bar (`Today · Food · Train · Progress · Settings`), plain-English HealthKit permission flow |
| **2. Food Logging** | Chronological `FoodTimelineView`, Floor/Target/Ceiling `MacroZoneBar`, 2-tap repeat food logging (`QuickAddFoodSheet` with *"Usually at this time"*), zero-lag custom inline calculator keypad in `FoodDetailSheet` (pre-selected remembered amounts, 1st-digit overwrite, `+`/`×` kitchen-scale math), >15% Atwater discrepancy check, *"Copy to Custom"*, cooked-weight `RecipeBuilderSheet`, multi-select copy/move/save-as-recipe, USDA + Open Food Facts clients, barcode lookup cascade |
| **3. Body Tracking** | `WeightTrendEngine` (EMA `alpha = 0.1`, carry-forward on missing days, First Morning / Average / Latest rule), Swift Charts scale dots + trend curve (`2W–All`), `BodyMetric` charts, pose-filtered `PhotoCompareView` split slider |
| **4. Adaptive Nutrition** | `ExpenditureEngine` (Mifflin-St Jeor start -> 14–28d energy balance using strictly `isComplete` days, Low/Med/High confidence, `±100 kcal` clamp), `MacroTargetEngine` (BMR/sex safety floors, nutrient floors/ceilings), `WeeklyCheckInSheet` |
| **5. Workout Logging** | 68 bundled exercises (`BundledExercises.json`) + custom exercises, 1-tap `✓` logging in `ActiveWorkoutView` with `restTakenSeconds` stamping & live PR celebration banners, set types (`W/WK/D/F/P`), auto-alternating supersets, auto warm-up generator, visual `PlateCalculatorSheet`, `RestTimerService` + Lock Screen Live Activity, Dynamic Island & `0:00` `UNUserNotificationCenter` chime (`+30s` / `-15s` / `Skip`), `HKWorkout` sync |
| **6. Programs** | `ProgramBuilderView`, Built-in Templates (`Full Body A/B`, `Upper / Lower`, `Push / Pull / Legs`), `GymProfileEditorView` with automatic movement-pattern equipment swap, rule-based `PlanGeneratorSheet` |
| **7. Smart Progression** | Effort-adjusted `e1RM`, regularized personal rep-endurance `k` curve fitter per exercise, next-session load/rep/deload prescriptions, all 4 automatic PR types (`e1RM`, `heaviestWeight`, `mostRepsAtWeight` Rep-PR, `bestSessionVolume`), anatomical `MuscleVolumeMapView` |
| **8. Nutrition × Training** | Isocaloric training-day vs. rest-day carb cycling tied to active program schedule, cut-aware progression (`>0.5% BW/wk` deficit), trailing 7-day protein floor gate, dual Weight × Strength Index chart, 4h fasted pre-workout snack nudge, unified nutrition + training weekly check-in |
| **9. Polish** | Unified `TodayDashboardView` (Watch calories badged *Display Only*), Vision OCR `LabelScannerView` + `NutritionLabelParser`, `MicronutrientDetailSheet`, WidgetKit extension (`TotalFactorWidgets`), Siri Shortcuts (`TotalFactorShortcuts`), RFC-4180 `CSVExportService`, `TotalFactorAlgorithmTests` |

---

## Expanding Offline USDA Foods to All ~8,000 Items

`TotalFactor/Resources/BundledUSDAFoods.json` ships preloaded with 78 lab-analyzed whole foods for instant offline search. To compile the full ~8,000-food USDA Foundation + SR Legacy bulk JSON datasets into the app bundle:

```bash
python3 Scripts/build_full_usda_bundle.py \
  --foundation path/to/FoodData_Central_foundation_food_json.json \
  --sr-legacy path/to/FoodData_Central_sr_legacy_food_json.json
```
