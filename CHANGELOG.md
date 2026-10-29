# Total Factor — Changelog & Build History

All notable changes, structural milestones, and architectural decisions for the **Total Factor** app are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [1.5.9] - 2026-10-29

### Added — Weight Trend & History Detail View, Date-Specific Weigh-In History & Interactive Chart Scrubbing (Build 19)

#### Added
- **Dedicated Weight Trend & History Screen (`WeightDetailView.swift`)**:
  - Tapping the Weight Trend card on Today Dashboard or Progress Hub now opens an in-depth view with hero metrics, 7-day and 30-day velocity, total net change, and target goal distance.
- **Date-Specific Weigh-In History by Date (`WeightDetailView.swift`)**:
  - Full reverse-chronological list showing exact date, time, scale weight, smoothed trend weight, and prior-entry delta for every recorded weigh-in.
  - Search bar to filter weigh-in history by date, day of week, or month.
- **Weigh-In CRUD Management (`EditWeighInSheet.swift`, `AddWeighInSheet.swift`)**:
  - Tap any history entry to adjust scale weight or timestamp, or delete erroneous and duplicate weigh-ins.
  - Swipe-to-delete and context menu support.
  - "+ Log Weight" button supporting retroactive entry backfilling for any past date.
- **Interactive Chart Scrubbing (`WeightDetailView.swift`, `ProgressHubView.swift`)**:
  - Implemented `.chartXSelection` on both weight charts with dynamic `RuleMark` indicators displaying exact dates, scale points, and smoothed trend weight tooltips on touch/scrub.
  - Multi-window time filtering (2W, 1M, 3M, 6M, 1Y, All).

---

## [1.5.8] - 2026-10-29

### Fixed — Comprehensive Bug Fixes & Reliability Overhaul (Build 18)

#### Fixed
- **MacroFactor CSV Import Weight Parsing (`MacroFactorImportService.swift`)**:
  - Replaced the arbitrary `> 90` threshold heuristic with explicit column header inspection (`kg` vs `lbs`), falling back to the user's unit system. Completely prevents metric users > 90 kg from having their weights halved on import.
- **Apple Watch Rolling Split Advance (`PhoneWatchSyncService.swift`)**:
  - Updating `prog.lastCompletedWorkoutOrder = pw.order` when finishing workouts on Apple Watch, ensuring rolling splits advance to the next scheduled day.
- **Apple Watch Weigh-In Instant Sync (`PhoneWatchSyncService.swift`)**:
  - Added missing `pushCurrentState(context: ctx)` call in `.logWeighIn`, updating the wrist display and trend widgets immediately.
- **Workout Rest Timer Slot Honors (`ActiveWorkoutView.swift`)**:
  - Fixed hardcoded 120-second rest timers, now dynamically reading each exercise slot's configured `restSeconds` (with a 60-second cap on warmup sets).
- **Apple Watch Live Workout Mutation Sync (`ActiveWorkoutView.swift`)**:
  - Pushing state to Apple Watch immediately when deleting an exercise block, deleting a set, or toggling set badges during an active session on iPhone.
- **Food Log Deletion Race Condition (`FoodTimelineView.swift`)**:
  - Extracted HealthKit sample UUIDs synchronously prior to deleting the SwiftData model object, avoiding race conditions and cross-thread access on deleted managed objects.
- **Onboarding Imperial Height Rollover (`OnboardingFlowView.swift`)**:
  - Using `UnitsFormatter.cmToFeetInches()` to eliminate the `5 ft 12 in` rollover bug on heights near 6 feet.
- **Onboarding Rerun Safe Mode (`OnboardingFlowView.swift`)**:
  - Updating today's weigh-in in-place if one already exists and defaulting routine generation to disabled when programs are already active.
- **Goal Strategy Slider Clamping (`GoalStrategySettingsView.swift`)**:
  - Dynamically clamping or resetting `ratePercentPerWeek` to the selected goal type's valid range when switching between Cut, Maintain, and Bulk.
- **Full Weekday Check-In Support (`UnitsScheduleSettingsView.swift`, `SettingsView.swift`)**:
  - Added Tuesday, Wednesday, and Thursday to the check-in day pickers and dashboard text formatters.
- **Day-1 Check-In Prompt Shield (`TodayDashboardView.swift`)**:
  - Requiring at least 7 days of app history since starting a program/goal before prompting new users for a weekly check-in.
- **Locale-Aware Number Parsing (`QuickAddFoodSheet.swift`)**:
  - Sanitizing comma decimals to dots to support European and Latin American decimal entries.

---

## [1.5.7] - 2026-10-29

### Added — MacroFactor-Style Multi-Page Onboarding, Categorized Settings Hub & Workout Builder Fixes (Build 17)

#### Added
- **Multi-Page MacroFactor Onboarding (`OnboardingFlowView.swift`, `OnboardingCardComponents.swift`)**:
  - Replaced cramped 3-step monolithic form with an elegant 10-step guided wizard.
  - Interactive selection cards for Imperial/Metric, Biological Sex, Age, Height & Scale Weight, and Baseline Activity levels.
  - MacroFactor Food: Goal selection cards (Cut/Maintain/Bulk), interactive rate of change slider with zone pills (*Conservative*, *Standard / Recommended*, *Aggressive*), and Day-1 macro split preview bar.
  - MacroFactor Workouts: Strength training frequency (2–6 days/week), lifting focus (Hypertrophy, Strength, Both), gym setup selection, and automated Day-1 program generation via `ProgramGeneratorEngine`.
  - Transparent Apple Health permissions step and Day-1 program launch summary.
- **Categorized Settings Hub Architecture (`SettingsView.swift` & Modular Sub-Views)**:
  - Redesigned Settings into a clean, single-screen dashboard with SF Symbol badges and dedicated drill-down pages.
  - Active Program & Profile Card with a 1-tap "Rerun Setup & Onboarding" button to replay the onboarding wizard anytime.
  - Dedicated child views: `GoalStrategySettingsView`, `FastingSettingsView`, `WorkoutPreferencesSettingsView`, `UnitsScheduleSettingsView`, `NotificationsSettingsView`, `AppleHealthSettingsView`, `AIDatabaseSettingsView`, `DataManagementSettingsView`, and `AttributionSettingsView`.
- **Workout Day Removal (`ProgramBuilderView.swift`)**:
  - Added an ellipsis action menu and "Delete Day" button to every workout day in `ProgramBuilderView`.
  - Confirms via alert, cascades exercise slots, and automatically re-indexes remaining workout days consecutively (`order = 0, 1, 2...`) while updating `daysPerWeek`.
- **Workout & Program Export Sharing Fix (`ShareSheetHelper.swift`, `TrainHubView.swift`, `ProgramBuilderView.swift`)**:
  - Added `ShareSheetHelper` to resolve the topmost active `UIViewController` across nested modal presentations.
  - Fixes silent presentation failures when exporting `.totalfactorprogram` files and workout CSV exports.

---

## [1.5.6.5] - 2026-10-29

### Added — Direct MacroFactor CSV Importer, Deterministic Fingerprint Deduplication & Apple Health Loop Protection (Build 16)

#### Added
- **Direct MacroFactor Data Importer (`MacroFactorImportService.swift`, `SettingsView.swift`)**:
  - Added 1-tap "Import MacroFactor Nutrition Data (CSV)..." in Settings using native iOS file picker.
  - Flexible CSV header parser mapping foods, serving sizes, gram weights, calories, protein, carbs, fat, fiber, sugar, sodium, and scale weigh-ins without third-party cloud APIs.
- **Deterministic Fingerprinting Deduplication**:
  - Generates composite row signatures (`DayKey_Time_Name_Calories_Protein`).
  - Ensures re-importing the same CSV or overlapping export periods skips existing items and produces 0 duplicates.
- **Apple Health Re-Export Protection (`HealthKitService.swift`)**:
  - Tags imported MacroFactor foods and strictly skips re-exporting them to Apple Health, preserving outward sync for native Total Factor foods while preventing double-counted calories in Apple Health.
- **Dynamic Alert Title**:
  - Replaced hardcoded `"CSV Import"` alert header with dynamic context titles (`"MacroFactor Import"`, `"Apple Health Sync"`, `"CSV Import"`).

---

## [1.5.6] - 2026-10-29

### Fixed — HealthKit Auto-Authorization & Apple Health Sources Instant Registration (Build 15)

#### Fixed
- **On-Demand HealthKit Authorization (`HealthKitService.swift`)**:
  - Added proactive `requestPermissions()` calls directly inside `importExternalDietaryIntake` and `syncAllHistoryToAppleHealth`.
  - Ensures Total Factor prompts for Health permissions on the first tap of any sync action, immediately registering Total Factor in iOS Settings $\rightarrow$ Health $\rightarrow$ Data Access & Devices (Sources).

---

## [1.5.5] - 2026-10-29

### Fixed & Enhanced — HealthKit External Nutrition Sync Engine, Zero-Duplicate Ingestion, MacroFactor Support, and Deletion Reconciliation (Build 14 / v1.5.3.x Hotfixes)

#### Fixed
- **HealthKit Double-Import Bug (`HealthKitService.swift`)**:
  - Eliminated collision where external meals logged in MacroFactor, MyFitnessPal, or Cronometer via `HKCorrelationType.food` were also re-imported as standalone `dietaryEnergyConsumed` entries with zero macros.
  - Added child quantity sample harvesting to blacklist internal calorie/macro UUIDs from standalone ingestion queries.
- **Bi-Directional Sync Reconciliation**:
  - Meals deleted or modified in external apps are now actively reconciled during sync. Deleted samples are cleanly pruned from SwiftData, and macro edits are updated in-place without generating duplicates.
- **Re-Export Echo Prevention**:
  - Added strict source guards to `syncFoodEntry` and `syncAllHistoryToAppleHealth` ensuring Total Factor never re-exports externally imported foods back to HealthKit.

#### Added
- **Multi-App Dynamic Attribution & Title Synthesis**:
  - Dynamically extracts the app source name (`MacroFactor`, `MyFitnessPal`, `Cronometer`, `Lose It!`) from HealthKit metadata and saves it into `FoodLogEntry.foodBrand`.
  - Intelligently preserves specific food names when available, or formats clean meal titles (e.g., `MacroFactor Lunch`) for aggregated/hourly logs.
- **Intelligent Time-of-Day Meal Tagging**:
  - Replaced unassigned `.none` meal tags with automatic placement into `.breakfast`, `.lunch`, `.dinner`, or `.snack` according to log time.
- **Themed Provenance Badging (`MacroZoneBar.swift`, `FoodTimelineView.swift`, `HourByHourTimelineSection.swift`)**:
  - Updated `FoodSourceBadge` to display the specific external app name (e.g. `MacroFactor`, `MyFitnessPal`) in a themed pink badge on timeline cards and hour-by-hour logs.
- **One-Tap "Remove All Imported HealthKit Meals" Safety Tool (`SettingsView.swift`)**:
  - Added a dedicated maintenance tool under Settings $\rightarrow$ Apple Health with confirmation dialog to safely wipe only third-party imported meals without touching foods or recipes logged natively in Total Factor.

---

## [1.5.4] - 2026-10-29

### Added — SideStore Community Visual Makeover, Retina Screenshots, Schema v2 Manifest & URL Scheme (Build 13)

#### Added
- **High-Resolution App & Source Icon (`TotalFactor/Resources/SideStore/icon.png`)**:
  - Restored missing app logo in SideStore / AltStore caused by raw GitHub 404 URL mismatch.
  - Placed dedicated 1024×1024 `icon.png` in SideStore resources and added fallback asset copy.
- **Widescreen 16:9 Store Header & News Banner (`banner.png`)**:
  - Rendered high-resolution 1200×675 banner graphic with dark slate charcoal background, flame orange radiant glow, squircle logo, and typography for store headers and news cards.
- **Retina iOS 17 Screenshot Gallery (`screenshot_*.png`)**:
  - Rendered full set of 4 native iPhone screenshots (1206×2622) for Today Dashboard, Food Timeline & The Plate dock, Smart Strength Tracker, and Dynamic TDEE Progress.
- **SideStore Schema v2 Manifest (`TotalFactor/Resources/SideStore/source.json`)**:
  - Upgraded community source manifest to official SideStore schema v2 with `versions` array, permissions declarations, rich Markdown description, and `tintColor: "FF5B00"`.
- **Custom URL Scheme (`Info.plist`)**:
  - Registered `totalfactor://` custom URL scheme for widgets, shortcuts, and deep links.

---

## [1.5.3] - 2026-10-29

### Added — Apple Health Two-Way Sync & History Push, Photo Tracker Pose Pill Bar, EXIF Past Photo Import, and Universal Export All App Data (Build 12)

#### Added
- **Apple Health Two-Way Synchronization Engine (`HealthKitService.swift`, `SettingsView.swift`)**:
  - Added full bi-directional sync between Total Factor and Apple Health with live processed events counter.
  - Added read permissions for dietary energy and macronutrients (`.dietaryEnergyConsumed`, `.dietaryProtein`, `.dietaryCarbohydrates`, `.dietaryFatTotal`).
  - Added `FoodSource.healthKit` enum case so external meals display an *"Apple Health (External)"* badge.
- **"Push Complete History to Apple Health"**:
  - 1-tap historical sync iterating over all past food entries, manual weigh-ins, and completed strength workouts and pushing unsynced items directly to Apple Health so other apps (Apple Fitness, MyFitnessPal, MacroFactor, RP Diet, LoseIt) share all data.
- **"Import Nutrition from Apple Health"**:
  - Imports external dietary intake logged by third-party apps via Apple Health into Total Factor's daily nutrition log with bundle ID exclusion and zero duplicates.
- **Photo Tracker Pose Selector Pill Bar (`PhotoCompareView.swift`)**:
  - Replaced native segmented control with haptic-enabled Segmented Pill Bar displaying live photo counters (`Front`, `Side`, `Back`).
  - Interactive empty state drop zone: tap anywhere on the "No Photos Yet" card to quickly capture or choose photos.
  - Pose switching immediately clears selection IDs to prevent comparison freezes, and `pickerItem` immediately resets.
- **Past Photo Import & EXIF Metadata (`PhotoMetadataHelper.swift`)**:
  - Automatic extraction of original camera capture dates from embedded EXIF/TIFF metadata without extra photo library permissions.
  - Automatic matching of historical weigh-in weight closest to capture date.
  - Full screen photo viewer supports interactive pose switching, date adjustments, and scale weight editing.
- **"Export All App Data" (Universal CSVs + AI Coaching Digest) (`ExportAllArchiveService.swift`, `SettingsView.swift`)**:
  - Universal 1-tap "Export All App Data" button in Settings generating a complete export folder and presenting the native iOS Share Sheet.
  - `TotalFactor_AI_Digest.md`: Pre-formatted Markdown report containing user demographics, expenditure targets, a 60-day daily aggregated nutrition & adherence matrix, personal strength PRs, and an evidence-based sports nutrition AI coaching prompt ready to paste into ChatGPT, Claude, or Google Gemini.
  - `TotalFactor_AllData.json` and all 4 universal CSVs (`FoodLog`, `WeighIns`, `Workouts`, `BodyMetrics`).

---

## [1.5.2] - 2026-10-29

### Added — Real-World & Zero-Scale Food Logging: No-Scale Hand & Container Estimators, 3-Second Ballpark Logger, Street Food Composites & Unified Plate (Build 11)

#### Added
- **"No-Scale & Container Estimator" Sheet (`NoScaleEstimatorSheet.swift`)**:
  - Interactive visual estimator featuring biological hand rulers (Palm of Protein ~30g P, Fist of Carbs ~1 cup, Cupped Hand of Snacks ~½ cup, Thumb of Fat ~1 tbsp) and standardized takeout containers (Deli Pint 16 oz, Deli Quart 32 oz, 3-Compartment Box, Foil Round Tin).
  - Real-time aggregated macro and calorie calculation with 1-tap options to Add to Plate or Log Directly.
- **Cultural & Street Food Composite Library (`CompositeFoodLibrary.swift`)**:
  - Curated composite dishes with natural piece-count steppers for unmeasured foods: Panipuri/Golgappa (~28 kcal/pc, default 10 pieces), Samosas (Standard 260 kcal vs Cocktail 90 kcal), Street Tacos (180 kcal), Steamed Dumplings/Momos (45 kcal), Sushi Rolls (320 kcal), Plain Roti (80 kcal), Roti with Ghee (110 kcal), Dal Tadka Katori (150 kcal), Chicken Biryani (320 kcal/cup), Pizza Slices (285 kcal), Chicken Wings (85 kcal), Falafel (60 kcal), Masala Dosa Set (380 kcal), Pav Bhaji (450 kcal), Chole Bhature (620 kcal), Burrito Bowl (720 kcal), and Pad Thai (650 kcal).
  - Searchable directly from Quick Add and Kitchen Hub with 1-tap staging onto The Plate.
- **"Ballpark My Meal" 3-Second Quick Logger (`MealBallparkSheet.swift`)**:
  - 3-second rapid logger for buffets, weddings, dining out, and unmeasured restaurant meals.
  - 4 size tiers: Light Snack (300 kcal), Standard Meal (650 kcal), Hearty Restaurant (950 kcal), and Feast/Buffet (1,350 kcal) with vibe modifiers (`High Protein`, `Fried / Oily`, `Carb Heavy`) and fine-tune calorie stepper.
- **Street Food & Hand-Size Offline Voice Aliases (`NaturalLanguageMealParser.swift`)**:
  - Upgraded the 2ms deterministic offline natural language parser to resolve street foods and hand proportions (*"10 panipuri and 2 samosas"*, *"2 street tacos and a handful of chips"*, *"1 palm chicken, 1 fist rice, and 1 thumb olive oil"*, *"deli pint of soup"*, *"takeout container of biryani"*) with 100% offline accuracy and zero cloud API key required.
  - Added new unit primitives: `palm`, `fist`, `thumb`, `handful`, `pint`, `quart`, `taco`, `wing`, `roll`, `roti`, `samosa`, and `katori`.
- **Unified AI Describe with "The Plate" (`DescribeMealView.swift`, `QuickAddFoodSheet.swift`)**:
  - Added 1-tap **"Add to Plate"** button in `MultiItemMealConfirmationSheet` so users can stage voice-described or AI-analyzed items directly onto the persistent bottom Plate dock and combine them with barcode scans before logging.
  - Mode 3 ("Quick") in Quick Add now features two prominent 1-tap launcher cards for **Ballpark My Meal** and **No-Scale Estimator** alongside manual macro overrides.
  - Added "Street & Bites" filter tab to Quick Add search and "Composites" segment tab to Kitchen Hub.

---

## [1.5.1] - 2026-10-29

### Added — Kitchen Rehaul & Workout UI Bug Fixes: The Plate Multi-Add Dock, Hourly Timeline, Adherence Calendar, Pause/Resume & Jammed Typography Fix (Build 10)

#### Fixed & Polished
- **Workout Action Pill Lettering & Wrapping (`ActiveWorkoutView.swift`)**:
  - Replaced rigid, unscrollable action button `HStack` with horizontal `ScrollView` featuring `.fixedSize(horizontal: true, vertical: false)` and `.lineLimit(1)`, preventing labels like `Wand`, `Warm Up`, and `Note` from wrapping awkwardly into two lines.
- **Top Carousel Exercise Title Truncation (`ActiveWorkoutView.swift`)**:
  - Widened thumbnail label width from `58pt` to `72pt` with `.lineLimit(2)` multi-line wrapping so exercise titles remain legible without abrupt ellipsis truncation.
- **Pause & Resume Workout (`ActiveWorkoutView.swift`, `TrainingModels.swift`, `RootTabView.swift`)**:
  - Implemented pause/resume mechanics for active workout sessions. Freezes elapsed timer, tracks cumulative pause duration (`totalPausedSeconds`), and updates the UI and mini-bar with amber `⏸ PAUSED` status.
- **Discard Workout Cascade Deletion (`ActiveWorkoutView.swift`)**:
  - Replaced silent dismissal with safety confirmation alert that cascade deletes draft sets, session model, rest timer Live Activity, and clears active session state.

#### Added
- **7-Day Adherence Calendar Strip (`WeekAdherenceCalendarStrip.swift`)**:
  - MacroFactor-style weekly adherence carousel atop the food log featuring circular target rings and 1-tap day switching.
- **Hour-by-Hour Timeline Mode (`HourByHourTimelineSection.swift`)**:
  - Added hourly food log view mode with hourly macro subtotals, inline `+` buttons, left/right handedness alignment, and empty-hour collapsing.
- **"The Plate" Multi-Add Staging Workspace (`ThePlateDockView.swift`, `ThePlateWorkspaceSheet.swift`)**:
  - Persistent bottom plate dock staging multiple foods during search/browse workflows.
  - Swipe-to-stage gesture directly on catalog search items.
  - Plate Workspace sheet for batch quantity editing, unit conversions, and 1-tap bulk logging to any meal tag or custom timestamp.
- **Explode Recipe to Ingredients (`FoodTimelineView.swift`)**:
  - Unpack logged recipes directly from the timeline into constituent ingredients scaled to portion consumed.
- **Kitchen Hub (`KitchenHubView.swift`)**:
  - Centralized manager for Recipes, Saved Meals (`SavedMeal` / `SavedMealItem`), and Custom Foods.
  - Recipe moisture loss / water absorption percentage math and yields in `RecipeBuilderSheet.swift`.
- **Enhanced Food Detail Sheet (`FoodDetailSheet.swift`)**:
  - Macro Calorie Ratio Donut (`MacroRatioDonutView`).
  - Daily Goal Impact before/after progress bar.
  - Kitchen-scale subtractive tare math (`245 - 65 = 180 g`) via `.minus` operator in `InlineQuantityCalculator`.
  - Micronutrient accordion preview drawer.
- **Smart Search Filter Tabs (`QuickAddFoodSheet.swift`)**:
  - Filter pills for `All`, `History`, `Favorites`, `Custom`, `Recipes`, `Common`, and `Branded`.

---

## [1.5.0] - 2026-10-28

### Added — MacroFactor Workouts UI Revamp, Top Exercise Carousel, Docked Custom Gym Keypad & Anatomical Heatmap Celebration (Build 9)

#### Added
- **Top Horizontal Exercise Switcher Carousel (`ActiveWorkoutView.swift`)**:
  - Replaced long vertical exercise scrolling with MacroFactor's top horizontal exercise switcher strip.
  - Browse all exercises in the workout with visual thumbnails (`ExerciseThumbnailView`), exercise names, and set progress badges (e.g. `4/4` with green checkmark when complete).
  - Tap any exercise tile to jump to it in 1 tap, with a dedicated `+` tile at the end to add exercises on the fly.
  - Added quick `≡` menu toggle to switch between **Carousel (Focused)** and **All Exercises (List)** modes.
- **MacroFactor Set Grid & Mini Colored RIR Badges (`ActiveWorkoutView.swift`)**:
  - Streamlined table hierarchy: `Set` | `Previous ↔` | `Lb` | `Reps` | `▢`.
  - Input boxes feature high-contrast active focus borders (bold outline around the active field).
  - **Mini Colored RIR Badges**: Reps box features MacroFactor's signature colored circular badge on the bottom-right corner (`0` red, `1` coral, `2` orange, `3` yellow, `4` mint, `5` green, `6+` electric blue) displaying logged RIR at a glance.
  - Rounded square completion checkboxes `▢` fill `☑` with haptic feedback upon logging.
- **Docked Custom Gym Keypad (`MacroFactorGymKeypad.swift`)**:
  - Eliminates modal sheet steppers: tapping any weight or reps box docks the custom gym keypad at the bottom.
  - **Top Colored RIR Strip**: `0` (Failure / Red) through `6+` (Easy / Blue) and `?` (Unrated); 1-tap immediately stamps the set with RIR.
  - **10-Key Pad with First-Digit Overwrite**: Large, chalky-finger friendly numeric keys (`1 2 3`, `4 5 6`, `7 8 9`, `. 0 ⌫`); typing automatically overwrites suggested load/reps without tedious backspacing.
  - **Utility Keys**: Keyboard dismiss, plate calculator shortcut, set type toggle (`W`, `D`, `F`, `P`, `M`), and a prominent black checkmark commit button (`✓`) that logs the set, starts the rest timer, and auto-focuses the next set or exercise.
- **MacroFactor "Workout Complete" Celebration Screen (`WorkoutCompleteCelebrationView.swift`, `AnatomicalHumanoidHeatmapView.swift`)**:
  - Front and back humanoid muscle vector drawings in SwiftUI `Canvas` illuminating every muscle trained in the session in MacroFactor's signature **electric royal blue** (`#2F7CF6`) against sleek charcoal body contours.
  - PR milestone trophy cards celebrating Volume Records, Reps Records, and Est. 1RM Records.
  - Summary metrics: total working volume, completed sets, elapsed duration, and live Apple Watch heart rate / active calories.
  - MacroFactor's *"Save these changes as the new default for this workout"* toggle switch, automatically committing added exercises, swaps, and set targets to the program routine template upon tapping **Done**.
- **Preserved All Superior Total Factor Features**:
  - Retained the **Progression Wand (🪄)** with diagnostic overload reasoning and dynamic rep range expansion.
  - Retained the **Live Heart Rate Corner Badge (`❤️ 142 BPM`)** streaming from Apple Watch.
  - Retained the **Rest Timer Live Activity & Dynamic Island** with lock screen controls and Apple Watch wrist haptics.
  - Retained **Pre-Workout Fuel Warnings**, **Bilateral & Unilateral (L/R) Logging**, **Biomechanical Equipment Swapping**, **Persistent Machine Setup Notes**, and the **Olympic Plate Calculator**.

---

## [1.4.1] - 2026-10-28

### Added — Siri AI & Apple Intelligence Spoken Food Logging, On-Device Apple Vision Plate Classification & Semantic Embeddings (Build 8)

#### Added
- **Siri AI & Apple Intelligence Spoken Food Logging (`LogFoodIntent`, `TotalFactorShortcuts.swift`)**:
  - Hands-free conversational food logging: speak directly to Siri via iPhone, Apple Watch, AirPods, or CarPlay (*"Hey Siri, log 3 scrambled eggs and 2 slices of sourdough toast in Total Factor"*).
  - Siri parses natural language using Apple Intelligence on-device, dispatches to `LogFoodIntent`, resolves items and grams via our offline 8,156-food USDA database, enqueues the meal, updates widgets instantly, and speaks spoken confirmation with exact calories and protein.
  - 100% offline, zero cloud API fees, and zero reliance on Google Gemini.
- **Siri Quick Calorie & Macro Intent (`LogQuickCaloriesIntent`, `TotalFactorShortcuts.swift`)**:
  - 1-sentence quick calorie logging (*"Hey Siri, log 450 calories in Total Factor"*).
  - Immediately enqueues entry, increments daily targets, and syncs to Apple Health.
- **On-Device Apple Vision Plate Classifier (`AppleVisionFoodClassifier.swift`, `DescribeMealView.swift`)**:
  - 100% offline meal photo recognition using Apple's built-in `Vision.framework` (`VNClassifyImageRequest`) running locally on the Apple Neural Engine in <50ms.
  - Classifies common food items (grilled chicken, eggs, steak, salmon, pizza, burgers, salad, pasta, rice, oatmeal, yogurt, bread, fruit, etc.) without cloud AI.
  - Added **"Identify Plate On-Device (Apple Vision AI)"** button in `DescribeMealView`: snap a plate or choose a photo from your library to recognize foods and generate USDA macro breakdowns without any Gemini API key or internet connection.
- **Apple `NaturalLanguage` Vector Embedding Fallback (`NaturalLanguageMealParser.swift`)**:
  - Neural Engine word embeddings (`NLEmbedding`) map colloquial slang and synonyms (e.g. "poultry" $\rightarrow$ chicken, "flapjack" $\rightarrow$ pancake, "espresso" $\rightarrow$ coffee) to USDA whole foods.
- **Instant Background & Lock Screen Widget Sync (`SharedSnapshotStore.swift`, `CoachingCoordinator.swift`)**:
  - Extended `PendingQuickAction` to carry calories, protein, carbs, fat, grams, serving label, and meal tag.
  - Siri food logs immediately update `WidgetDashboardSnapshot` and trigger `WidgetCenter.reloadAllTimelines()` so widgets reflect your meal within 50ms without opening the app.
  - Upon app opening, `CoachingCoordinator` automatically inserts full `FoodLogEntry` records into SwiftData and syncs with Apple Health.
- **SideStore IPA Packaging Cleanliness (`Scripts/build_ipa.sh`)**:
  - Fixed `"The app's Info.plist could not be found"` error during SideStore IPA import by stripping `.xctest` bundles and `.dSYM` folders from `PlugIns/` before compression.
  - Excluded watchOS companion target from the standalone sideload package to ensure flawless personal-team certificate validation in SideStore.

---

## [1.4.0] - 2026-10-28

### Added — Multi-Add Food Logging, Native Intermittent Fasting, Flexible Rolling Splits, Program Import/Export & Progress Photos Overhaul (Build 7)

#### Added
- **Multi-Add Food Logging ("Multi-Select Staging Tray") (`QuickAddFoodSheet.swift`)**:
  - Direct `+` staging button on each search result row to quickly stage multiple foods into a persistent bottom dock with haptic feedback.
  - Real-time staging dock displays selected food count, total calories, and protein (`3 Items Staged • 520 kcal • 42g protein`).
  - Added full `StagedFoodReviewSheet` to adjust serving sizes, multiplier steppers (0.25×–20×), or remove items before committing.
  - 1-tap "Log All (N)" commits all staged foods into SwiftData and Apple Health in a single atomic transaction.
- **Native Intermittent Fasting (IF) Engine (`DomainEnums.swift`, `UserProfileModels.swift`, `TodayDashboardView.swift`, `SettingsView.swift`)**:
  - Integrated native Intermittent Fasting with 6 protocols: 16:8 LeanGains (Standard), 18:6 Deep Fast, 20:4 Warrior Diet, OMAD (23:1), 14:10 Moderate, and Circadian (13:11).
  - Added dedicated Intermittent Fasting card on Today Dashboard displaying active fast elapsed time, target countdown, and eating window progress.
  - Smart automatic calculation starting from yesterday's last logged food timestamp, plus 1-tap "Start Fast" / "End Fast" override controls.
  - Added configuration toggle and protocol selector in **Settings → Intermittent Fasting**.
- **Flexible Rolling Split Workouts ("Work Out Whatever Days You Want") (`DomainEnums.swift`, `TrainingModels.swift`, `TodayDashboardView.swift`, `TrainHubView.swift`, `ProgramBuilderView.swift`)**:
  - Added `ProgramScheduleMode`: switch between **Fixed Weekdays** and **Rolling Split (Any Day / Flexible)**.
  - In Rolling Split mode, workouts are never locked to calendar days; routines cycle automatically (1 → 2 → 3 → 4) whenever you train.
  - Today Dashboard dynamically features "Next Up: [Workout Name]" and advances to the next routine upon workout completion.
  - Added "Switch Workout" menu on Today's training card to start any routine in your active program at any time with 1 tap.
  - Train Hub displays a bright green "NEXT UP" badge on the next scheduled routine.
- **Complete Program Import & Export Engine (`ProgramImportExportService.swift`, `ProgramBuilderView.swift`, `TrainHubView.swift`)**:
  - Full JSON serialization for workout programs (split configuration, exercises, sets, rep ranges, target RIR, rest intervals, and progression rules).
  - Export programs directly to `.totalfactorprogram` files via the iOS Share Sheet (AirDrop, Messages, Files) or copy JSON to clipboard.
  - File Importer and Clipboard Importer in Program Builder and Train Hub: seamlessly imports routines, automatically matches against the 118 bundled exercise library, auto-creates custom exercises for new movements, and saves directly into SwiftData.
- **Overhauled Progress Photos & Mirror Camera Capture (`PhotoCompareView.swift`)**:
  - Fixed empty state bug where having 1 photo rendered `ContentUnavailableView`, making photos feel lost.
  - Single-photo showcase prominently displays your photo with date and weight badge.
  - Comparison mode for 2+ photos with Before & After photo picker menus, days-apart, and weight delta badges.
  - Supports both Split Slider and Side-by-Side comparison modes.
  - In-app "Take Photo" mirror camera capture alongside Photos library picker.
  - Thumbnail history gallery reel with tap-to-inspect and delete photo with confirmation.
  - Downsamples photos to clean 1600px JPEG to keep SQLite storage fast and lean.
- **MacroFactor Visual Polish & Adaptive Expenditure (TDEE) (`TodayDashboardView.swift`)**:
  - Re-branded "Metabolism" card to "Adaptive Expenditure (TDEE)" with daily energy burn indicators and confidence pills.
  - Added Energy Balance (Intake vs. TDEE) card displaying net daily deficit or surplus with color-coded badges.
  - Clarified synergy between workout energy burn and dynamic TDEE adaptations.
- **AI Food Logging & Precision Prompt Overhaul (`GeminiMealParserService.swift`, `NaturalLanguageMealParser.swift`)**:
  - Explicitly instructed Gemini schema that all calories and macros must represent the TOTAL portion weight in grams.
  - Multimodal coupling: synthesizes photo visual portions with user text notes for hidden ingredients and cooking oils.
  - Enriches Gemini meals with verified offline USDA micronutrients (potassium, iron, zinc, magnesium).
  - Added 20+ common everyday food aliases to offline parser (almond milk, steak, salmon, avocado, blueberries).

#### Fixed
- **Fixed In-App Update Log Decoding (`UpdateLog.json`)**:
  - Repaired corrupted nested JSON in releases 1–5 where Build 6 data was erroneously duplicated inside sections arrays, enabling instant decoding of all version releases in **Settings → What's New & Update Log**.

---

## [1.3.0] - 2026-10-27

### Added — Un-Cramped Workout UI, Proactive Reminders, Apple Fitness Workouts Sync & Live Heart Rate Corner Badge (Build 6)

#### Added
- **Un-Cramped Workout UI Redesign (`ActiveWorkoutView.swift`)**:
  - Spacious 44pt+ touch targets on set rows and target buttons separating load and reps (`175 lb  ×  10  @2`) with monospaced typography, ample padding, and clean contrast for sweaty gym fingers.
  - Removed repetitive 2-line placeholder coaching note from every card, surfacing only actionable recommendations from the Progression Wand.
  - Redesigned 32x32 set type badges and 44x44 circular checkmark buttons with smooth completion feedback.
  - Added an on-the-fly **"+ Custom Exercise"** button directly inside the in-workout "Add Exercise to Session" sheet so users never have to leave an active workout.
- **Proactive Reminders & Notifications Engine (`NotificationService.swift`, `SettingsView.swift`)**:
  - Centralized notification service with dedicated toggles under **Settings → Reminders & Notifications**:
    - Daily Morning Weigh-In Reminder (default 7:30 AM or custom time).
    - Meal & Nutrition Logging Reminders (Lunch at 12:30 PM, Dinner at 7:30 PM).
    - Evening Missed Food Logging Check (8:45 PM).
    - Pre-Workout Fuel & Energy Alert on scheduled training days.
- **Apple Watch Rest Timer Vibration (`RestTimerService.swift`)**:
  - Fixed rest timer notification cancellation bug so timers trigger reliable wrist haptic vibrations on Apple Watch when iPhone is locked (no companion app needed).
  - Time-sensitive alert delivery breaking through lock screens and Focus modes.
- **Live Heart Rate Tracking Everywhere (`HealthKitService.swift`, `ActiveWorkoutView.swift`, `TodayDashboardView.swift`)**:
  - Continuous live heart rate observer (`HKAnchoredObjectQuery`) in `HealthKitService`.
  - Prominent Live Heart Rate Corner Badge (`❤️ 142 BPM`) in `ActiveWorkoutView` navigation bar and top banner that updates dynamically whether streamed from the companion app or native Apple Watch HealthKit samples.
  - Live / Recent Heart Rate, Resting HR, and Daily HR Range on Today Dashboard.
- **Apple Health & Apple Fitness External Workouts Sync (`HealthKitService.swift`, `TodayDashboardView.swift`, `FoodTimelineView.swift`)**:
  - External `HKWorkout` importer querying all workouts logged in Apple Fitness or third-party apps (Soccer, Running, Cycling, Swimming, HIIT, Basketball, Rowing, etc.).
  - Added "Today's Apple Fitness Workouts" card on `TodayDashboardView` and inline on `FoodTimelineView` showing sport emoji, duration, active kcal burned, and completion time (display-only per Ground Rule 3).
- **Pre-Workout Fuel & Energy Readiness Guidance (`ActiveWorkoutView.swift`, `TodayDashboardView.swift`)**:
  - Top warning banner in active workouts and dashboard when fasted for >3.5–4 hours before training, recommending 25–40g carbs and protein.
- **Expanded Exercise Library (+22 New Exercises, `BundledExercises.json`)**:
  - Added 22 missing strength, hypertrophy, and conditioning staples (Incline Cable Fly, Close-Grip Bench Press, Cable Y-Raise, Bulgarian Split Squats, Landmine Press/Row, Running, Soccer, Cycling, Swimming, etc.), expanding catalog to 118 exercises.

### Added — MacroFactor Workouts Complete Feature Suite (Build 5)

#### Added
- **Smart Progression Wand & Dynamic Rep Expansion (`ProgressionWandSheet.swift`, `ProgressionEngine.swift`)**:
  - Interactive Progression Wand (🪄) diagnostic sheet explaining progressive overload decisions with 🔵 Blue (Target reached, added load), 🟡 Yellow (Consolidation/deload/protein gate), and 🔴 Orange (Equipment gap) alerts.
  - Dynamic Rep Range Expansion: Automatically widens rep ceilings by +3 reps (e.g. 8–12 becomes 8–15) when the smallest gym plate or dumbbell jump is $\ge 12.5\%$ of working load.
- **Bilateral & Unilateral (Left / Right) Independent Logging (`TrainingModels.swift`, `ActiveWorkoutView.swift`)**:
  - Independent Left and Right set logging (`weightKgLeft`, `repsLeft`, `weightKgRight`, `repsRight`) with 1-tap Bilateral/Unilateral toggle and "Copy Left to Right" button in `InlineSetEditorSheet`.
- **Persistent Machine & Exercise Setup Notes (`MachineSetupNotesSheet.swift`)**:
  - Exercise-pinned setup notes (seat heights, pin settings, cable notches) displayed under exercise titles that persist automatically across all future sessions.
- **In-Workout Exercise Swapping (`ExerciseSwapSheet.swift`)**:
  - In-session replacement engine that filters and ranks substitutes by exact movement pattern and muscle group matches, preserving completed and pending set structures.
- **Workout Change Log & Routine Commit Prompt (`WorkoutChangeLogSheet.swift`)**:
  - Post-session review sheet that diffs the completed workout against the parent routine blueprint and prompts to update the program routine or keep for today only.
- **Weekly Muscle Group Hypertrophy Volume Landmarks (`HypertrophyVolumeEngine.swift`, `HypertrophyVolumeCardView.swift`)**:
  - Trailing 7-day hard set gauge in `TrainHubView` categorized into Maintenance (MV), Minimum Effective (MEV), Maximum Adaptive (MAV), and Maximum Recoverable (MRV) volume zones.
- **Bodyweight Modes & Myo-reps (`DomainEnums.swift`)**:
  - Added `BodyweightMode` (`standardLoad`, `bodyweightOnly`, `weightedBodyweight`, `assistedBodyweight`) with automatic user bodyweight integration.
  - Added `.myorep` set type (badge `"M"`) across active tracking, history, and Apple Watch sync.
- **SPM Test Expansion**:
  - 4 new algorithm tests covering wand rep range expansion, clean progression, volume landmarks, and swap ranking (22/22 tests passing).

---

## [1.2.0] - 2026-10-27

### Added — Apple Health & Fitness Design System, Un-Cramped Layouts & SideStore Wireless Auto-Signing (Build 4)

#### Added
- **Apple Health & Apple Fitness Design System (`AppleDesignSystem.swift`)**:
  - Re-architected `TodayDashboardView`, `FoodTimelineView`, `TrainHubView`, and `ProgressHubView` with native grouped card surfaces (`.appleHealthCard`), 20-22pt corner radius, and generous 16-18pt padding.
  - Adopted 38pt heavy San Francisco Rounded metric typography (`.design: .rounded`) and Apple's health metric palette (`AppleTheme`: Flame Orange, Coral Pink, Electric Cyan, Gold, Purple, and Teal).
  - Designed floating `.ultraThinMaterial` frosted glass date switcher, Apple Fitness hero calorie summary, side-by-side Trend & Metabolism cards, 2x2 health telemetry grid, and segmented Apple Fitness macro bars.
  - Streamlined `FoodTimelineView` with clean line-item food rows and micro-colored macro indicators.
  - Added smart Goal Target Date projection in `ProgressHubView`.
- **SideStore Wireless Auto-Signing Pipeline (`Scripts/build_ipa.sh`)**:
  - Automated compilation, verification, and `.ipa` packaging of `TotalFactor.app` (with embedded `TotalFactorWatch.app` and `TotalFactorWidgetsExtension.appex`).
  - Generates `TotalFactor.ipa` in the iCloud Drive workspace for direct import into SideStore, enabling perpetual background re-signing over Wi-Fi without a Mac.

---

## [1.2.0] - 2026-10-27 (Build 3)

### Added — 8,156-Food Offline USDA Catalog, Multimodal Voice/Text/Photo Meal Logging, watchOS 10+ Companion, and Full Phase 2–9 Spec Sweep

#### Added
- **Full ~8,156-Food Offline USDA Database (`BundledUSDAFoods.json`, `OfflineUSDACatalogIndex.swift`, `OfflineUSDACatalogService.swift`)**:
  - Updated `Scripts/build_full_usda_bundle.py` and `USDAFoodClient.swift` for USDA 2026 Foundation + SR Legacy nutrient ID schemas and compiled **8,156 lab-verified foods** (`3.75 MB`) with serving weights and micronutrients.
  - Built an in-memory inverted token + singular/plural index (`OfflineUSDACatalogIndex`) with lazy SwiftData `Food` materialization on first log/favorite/recipe use across `QuickAddFoodSheet`, `FoodDetailSheet`, and `RecipeBuilderSheet`, keeping `@Query` row counts minimal for 120Hz scrolling.
- **Voice, Natural-Language & Meal-Photo Logging (`NaturalLanguageMealParser.swift`, `SpeechDictationService.swift`, `GeminiMealParserService.swift`, `DescribeMealView.swift`)**:
  - Added live `SFSpeechRecognizer` voice dictation, deterministic offline multi-item natural-language meal parsing, optional Keychain-backed Gemini API (`gemini-2.5-flash` / `gemini-2.5-pro`) text + camera/library photo meal estimation, and `MultiItemMealConfirmationSheet` batch logging synced to Apple Health.
- **Apple Watch Companion (`TotalFactorWatch` on watchOS 10+, `WatchSyncModels.swift`, `PhoneWatchSyncService.swift`)**:
  - Added embedded `TotalFactorWatch` target (`com.prerak.totalfactor.watchkitapp`) signed with Personal Team `8MF8V7WZJB` using `WCSession` (`updateApplicationContext`, `sendMessageData`, `transferUserInfo`).
  - Implemented 4 watchOS tabs (**Lift** 1-tap set logger + Digital Crown load/rep dial, **Rest** circular countdown + `3-2-1-Go` wrist haptics, **Macros** remaining budget glance, **Weight** Digital Crown weigh-in) plus `WatchWorkoutSessionManager` (`HKWorkoutSession` + `HKLiveWorkoutBuilder`) streaming live wrist BPM to an isolated `ActiveWatchHeartRateBanner` in `ActiveWorkoutView`.
- **100% Phase 2–9 Spec Sweep**:
  - Chronological per-exercise session & set history in `ExerciseLibraryView.swift`.
  - Custom `NutrientTarget` Floor / Target / Ceiling editor (`NutrientTargetsEditorView` & `SingleNutrientTargetEditorSheet`) in `MicronutrientDetailSheet.swift` and `SettingsView.swift`, plus `Sugar`, `Vitamin C`, and `Cholesterol` zones in `MacroTargetEngine.swift`.
  - `CopyFromAnyDateSheet`, optional `MealTag` grouping toggle & inline `MealTag` picker, and `DailyNote.notes` editor (`DailyNoteEditorSheet`) in `FoodTimelineView.swift`.
  - `BodyMetricType.leanBodyMass` HealthKit import/export in `HealthKitService.swift` (plus Vitamin C, Magnesium, Zinc, Cholesterol dietary sync) and Lean Body Mass Swift Charts card in `ProgressHubView.swift`.
  - Visual Mon–Sun `WeekScheduleStripView` in `ProgramBuilderView.swift` & `TrainHubView.swift`, plus interactive `-` / `✓` / `+` weigh-in controls (`WidgetNudgeWeighInIntent`, `WidgetLogWeighInIntent`) on `TrendAndWorkoutWidget`.
- **Expanded Automated Test Suite (`TotalFactorAlgorithmTests.swift`)**:
  - Expanded SPM/XCTest suite to **18 passing test suites** covering the 8,156-food offline USDA index, deduplicated ranking, multi-item natural-language parsing, custom nutrient zone overrides, LBM unit conversion, and `WCSession` wire serialization.

---

## [1.1.0] - 2026-10-27

### Added — Planet Fitness Profile, Strong History Import, Exercise Photos & Guides, and 120Hz Scroll Optimization

#### Added
- **Strong / Hevy CSV Importer (`StrongCSVParser.swift` & `StrongWorkoutImportService.swift`)**:
  - Pre-loaded all **124 historical workout sessions (1,214 sets across 64 movements)** from `BundledStrongWorkouts.csv`, fitting personalized `personalRepCurveK` parameters and replaying chronological `PersonalRecord` milestones per exercise.
  - Added UI CSV import actions in `TrainHubView.swift` and `SettingsView.swift` with minute-level deduplication, automatic `lb -> kg` conversion, swapped `Weight <-> Reps` typo repair, and forgotten timer normalization.
  - Added full searchable `WorkoutHistoryListView` and `WorkoutSessionDetailSheet` to inspect all historical workouts and sets.
- **Offline Exercise Demonstration Photos & How-To Guides (`ExerciseMediaService.swift` & `ExerciseGuideView.swift`)**:
  - Expanded `BundledExercises.json` to **96 exercises** (including 28 Planet Fitness machine, cable, Smith, dumbbell, and bodyweight movements) with **182 offline Start & Finish photos** (`TotalFactor/Resources/ExerciseMedia/`).
  - Built `ExerciseGuideContentView`, `ExerciseGuideSheet`, and `WorkoutOverviewGuideSheet` featuring animated Start ↔ Finish motion playback, side-by-side pose comparison, Front & Back anatomical `TargetMuscleDiagramView`, Planet Fitness machine setup cues, numbered execution steps, coaching cues, and common mistakes.
  - Integrated off-main-thread downsampled `ExerciseThumbnailView` badges across `TrainHubView`, `TodayDashboardView`, `ActiveWorkoutView`, and `ExerciseLibraryView`.
- **Planet Fitness Active Gym & Custom Split (`SeedDataService.swift` & `ProgramGeneratorEngine.swift`)**:
  - Added and activated the **Planet Fitness** `GymProfile` (`5–75 lb` dumbbells, `20 lb` counterbalanced Smith carriage, `2.5 lb` cable add-on increment, excluding free Olympic barbells so unavailable movements auto-swap cleanly), plus unit-aware weight editing (`lb`/`kg`) in `GymProfileEditorView.swift`.
  - Added and activated the 4-day **Planet Fitness Split** (`Push`, `Back and Biceps`, `Lower`, `Upper`) matching the user's real training split.
- **Running Update Log, In-App What's New & 1-Step iPhone Updater (`UpdateLogView.swift`, `UPDATES.md`, `AGENTS.md`, `Scripts/update_iphone.sh`)**:
  - Added `UPDATES.md` and `TotalFactor/Resources/UpdateLog.json` paired with `UpdateLogView` in `SettingsView` showing the live installed version/build (`v1.1.0 • Build 2`) and every feature/tweak right on the phone.
  - Added `AGENTS.md` workspace rule to automatically keep the update log and build numbers updated on every future change, plus `Scripts/update_iphone.sh` for 1-command in-place iPhone updates.

#### Performance (Eliminated Vertical Scroll Hitches)
- **Read-Only Digest Caching (`CoachingCoordinator.swift`)**: Replaced synchronous `CoachingCoordinator.evaluate(...)` calls inside `View.body` across `TodayDashboardView`, `FoodTimelineView`, `ProgressHubView`, and `ActiveWorkoutView` with pure O(1)-cached `cachedOrComputeDigest(...)`, eliminating per-frame SwiftData fetches, `ModelContext` mutations, and `WidgetCenter` IPC reloads during scrolling.
- **Zero-Allocation Model Accessors (`NutritionModels.swift`, `TrainingModels.swift`, `DateDayKey.swift`)**: Added `@Transient` decoded caches on `Food`, `Exercise`, and `GymProfile`, direct arithmetic macro getters on `FoodLogEntry`, O(N) `completedSetCount` / `totalWorkingVolumeKg` on `WorkoutSession`, and a static cached `DateFormatter` in `DayKey`.
- **Rest Timer Isolation & Off-Main-Thread Image Decoding**: Isolated 500ms `RestTimerService` observation into `ActiveWorkoutMiniBar` and `ActiveRestTimerBanner`, memoized `ActiveExerciseCardView` and `QuickAddFoodSheet` search rankings, and decoded thumbnails off the main thread via `CGImageSourceCreateThumbnailAtIndex` + `NSCache`.

---

## [1.0.0-rc1] - 2026-10-27

### Complete Implementation of Phases 1 through 9

#### Added — Phase 1: Foundation & Architecture
- **SwiftData Data Model**: Built 21 `@Model` entities configured for CloudKit synchronization:
  - `UserProfile`, `Goal`, `NutrientTarget` (`UserProfileModels.swift`)
  - `Food`, `Recipe`, `RecipeIngredient`, `FoodLogEntry`, `DailyNote` (`NutritionModels.swift`)
  - `WeighIn`, `BodyMetric`, `ProgressPhoto` (`BodyModels.swift`)
  - `Exercise`, `GymProfile`, `Program`, `ProgramWorkout`, `ExerciseSlot`, `WorkoutSession`, `SetLog`, `PersonalRecord` (`TrainingModels.swift`)
  - `ExpenditureEstimate`, `WeeklyCheckIn` (`CoachingModels.swift`)
- **Provisioning Resilience**: Configured local SQLite default with automatic CloudKit upgrade fallback in `TotalFactorApp.swift` to prevent crashes on Free Apple Developer accounts.
- **Root Navigation**: Implemented 5-tab root view (`RootTabView.swift`): *Today*, *Food*, *Train*, *Progress*, *Settings*.
- **Onboarding Flow**: 3-step interactive setup (`OnboardingFlowView.swift`) capturing sex, height, weight, activity multiplier, primary goal, and gym equipment profile.
- **HealthKit Authorization**: Implemented `HealthKitService.swift` with plain-English permission explainers for weight, dietary energy, macronutrients, and workouts.

#### Added — Phase 2: Food Logging & Nutrition Engine
- **Chronological Timeline**: `FoodTimelineView.swift` displaying daily meals, calories, and macros with custom day navigation.
- **MacroZoneBar**: Visual component displaying current intake against Floor, Target, and Ceiling thresholds.
- **2-Tap Repeat Food Logging**: `QuickAddFoodSheet.swift` surfacing frequent foods filtered by time-of-day heuristic ("Usually at this time").
- **Inline Quantity Calculator**: Custom interactive numeric keypad (`InlineQuantityCalculator.swift` & `FoodDetailSheet.swift`) with pre-selected amount, first-digit overwrite, and live kitchen-scale arithmetic (`+`, `×`).
- **Atwater Discrepancy Detection**: Validates crowdsourced/database foods by checking if stated calories deviate $>15\%$ from $4\text{P} + 4\text{C} + 9\text{F}$.
- **Recipe Builder**: `RecipeBuilderSheet.swift` supporting ingredient composition, raw vs. cooked batch yield ratios, and custom serving division.
- **Multi-Select Meal Management**: Batch actions to delete, move to another meal, copy to today, or save a collection of foods as a new recipe.
- **Food Data Clients**: Offline bundle with 78 whole foods (`BundledUSDAFoods.json`), live USDA FoodData Central client (`USDAFoodClient.swift`), and Open Food Facts client (`OpenFoodFactsClient.swift`).

#### Added — Phase 3: Body & Metric Tracking
- **Exponential Moving Average Weight Trend**: `WeightTrendEngine.swift` utilizing $\alpha = 0.1$ smoothing and carry-forward interpolation for unlogged days without creating fake scale records.
- **Weigh-In Resolution Rules**: Implemented `firstMorning`, `average`, and `last` resolution for multi-weigh-in days.
- **Interactive Weight Charts**: Swift Charts implementation in `ProgressHubView.swift` featuring scale weight scatter plots superimposed over the smoothed EMA curve across selectable ranges (`2W`, `1M`, `3M`, `6M`, `1Y`, `All`).
- **Circumference & Body Composition**: Full tracking for neck, shoulders, chest, waist, hips, biceps, calves, and body fat percentage (`BodyMetric.swift`).
- **Visual Progress Comparison**: `PhotoCompareView.swift` with pose-filtered front/side/back categorization and an interactive split slider.

#### Added — Phase 4: Adaptive Nutrition Engine
- **Dynamic Expenditure Engine**: `ExpenditureEngine.swift` combining Mifflin-St Jeor baseline with a rolling 14–28 day energy balance model.
- **Confidence Rating**: 3-tier classification (Low $<7\text{ days}$, Medium $7–13\text{ days}$, High $\ge 14\text{ days}$) with smooth transitional blending.
- **Rate Clamping**: $\pm 100\text{ kcal}$ per-update cap to eliminate wild swings caused by temporary water weight shifts.
- **Adherence Filtering**: Strict exclusion of incomplete logging days (`isComplete == false` or $<800\text{ kcal}$).
- **Macro Distribution Engine**: `MacroTargetEngine.swift` providing automated macro allocation with BMR safety floors, $1.6–2.4\text{ g/kg}$ protein floors, $0.6–1.0\text{ g/kg}$ fat floors, and a $40\text{ g}$ minimum carbohydrate reserve.
- **Weekly Check-In**: Automated weekly review sheet (`WeeklyCheckInSheet.swift`) evaluating adherence, weight change vs target rate, and proposed calorie adjustments.

#### Added — Phase 5: Strength Workout Logging
- **Bundled Exercise Library**: 68 comprehensive gym exercises (`BundledExercises.json`) tagged by primary/secondary muscle groups, equipment requirements, and movement patterns.
- **1-Tap Active Logger**: `ActiveWorkoutView.swift` featuring instant set logging (`✓`), automated rest interval measurement, and inline set type selection (`W` Warmup, `WK` Working, `D` Drop, `F` Failure, `P` Partial).
- **Automated Warm-Up Generator**: Calculates progressive ramp sets based on target working weight.
- **Superset Support**: Auto-alternating paired exercise slots with linked rest cycles.
- **Barbell Plate Calculator**: `PlateCalculatorSheet.swift` with visual graphic breakdown for standard Olympic barbells and available plates.
- **Rest Timer & Dynamic Island**: `RestTimerService.swift` with ActivityKit Live Activity rendering rest progress on the Lock Screen and Dynamic Island with `+30s`, `-15s`, and `Skip` interactive controls (`RestTimerLiveIntents.swift`).
- **HealthKit Workout Sync**: Exports completed sessions as `HKWorkout` with calculated active energy and duration.

#### Added — Phase 6: Programs & Workout Templates
- **Program Builder**: `ProgramBuilderView.swift` for authoring multi-week splits and custom routines.
- **Built-in Templates**: Pre-configured routines for Full Body A/B, Upper / Lower, and Push / Pull / Legs.
- **Gym Equipment Profiles**: `GymProfileEditorView.swift` allowing users to configure available gear across Commercial Gym, Home Gym, and Minimalist setups.
- **Automatic Equipment Swapping**: Intelligent movement-pattern substitutions when specified equipment is unavailable.
- **Rule-Based Plan Generator**: `PlanGeneratorSheet.swift` synthesizing personalized routines based on weekly frequency, target split, and available equipment.

#### Added — Phase 7: Smart Progression & Fatigue Modeling
- **Effort-Adjusted 1RM**: Calculates true performance capacity using $\text{Weight} \times (1 + (\text{Reps} + \text{RIR}) / k)$.
- **Bayesian Rep-Endurance Curve**: `ProgressionEngine.fitPersonalRepCurveK` individualizing lifter rep endurance ($k \in [18, 50]$) with shrinkage toward the Epley prior ($k=30$).
- **Next-Session Recommendations**: Actionable load and rep targets using double-progression and target RIR guidelines.
- **Automated PR Engine**: Real-time detection for 4 distinct PR categories:
  1. Estimated 1RM PR (`e1RM`)
  2. Heaviest Absolute Weight PR (`heaviestWeight`)
  3. Rep PR at Weight (`mostRepsAtWeight`)
  4. Best Session Volume PR (`bestSessionVolume`)
- **Muscle Volume Map**: `MuscleVolumeMapView.swift` tracking weekly effective sets per muscle group against Minimum Effective Volume (MEV) and Maximum Recoverable Volume (MRV).

#### Added — Phase 8: Nutrition × Training Integration
- **Program-Tied Carb Cycling**: Automatic isocaloric redistribution providing higher carbohydrates on programmed training days and lower carbohydrates on rest days without altering weekly calorie totals.
- **Cut-Aware Deload Suppression**: Prevents premature deload prescriptions when a lifter is in a steep deficit ($>0.5\%\text{ BW/wk}$) and maintaining strength within $3\%$.
- **Protein-Gated Progression**: Withholds progressive overload weight increases (`.holdDueToProteinGate`) if 7-day average protein falls below the prescribed floor.
- **Dual Weight × Strength Index Chart**: Correlates body mass changes directly against composite strength index trends.
- **Fasted Workout Nudge**: Automatically alerts lifters if their scheduled workout begins $>4\text{ hours}$ after their previous meal.
- **Unified Weekly Check-In**: Synchronized review covering both macro adjustments and strength progression audits.

#### Added — Phase 9: Polish, Widgets, Shortcuts & Quality Assurance
- **Today Dashboard**: `TodayDashboardView.swift` presenting remaining macros, training schedule, weigh-in reminders, and Apple Watch display-only calorie badges.
- **Vision OCR Nutrition Scanner**: `LabelScannerView.swift` paired with regex-driven `NutritionLabelParser.swift` to extract nutrition facts directly from food package camera scans.
- **Micronutrient Details**: `MicronutrientDetailSheet.swift` tracking fiber, sugar, sodium, potassium, calcium, and iron against RDA benchmarks.
- **WidgetKit Extension**: `TotalFactorWidgets` providing Home Screen and Lock Screen widgets for daily remaining macros, quick food logging, and active rest timer tracking.
- **Siri Shortcuts**: `TotalFactorShortcuts.swift` enabling App Intents for voice-activated food, water, and workout logging.
- **Data Portability**: `CSVExportService.swift` generating RFC-4180 compliant CSV exports for all logged foods, workouts, and body metrics.
- **SPM Test Harness**: `Package.swift` and `TotalFactorAlgorithmTests.swift` containing 12 comprehensive unit test suites validating all core mathematical engines.

---

### Fixed & Resolved Engineering Traps
- **CloudKit Schema Safety**: Eliminated non-optional and unidirectional `@Relationship` declarations that triggered CoreData CloudKit sync rejections.
- **Complex SwiftData Attribute Migration**: Replaced raw nested arrays/dictionaries with binary `Data` backing typed computed properties, ensuring painless lightweight migrations.
- **Timezone Day Key Drift**: Implemented canonical `"YYYY-MM-DD"` `dayKey` strings alongside UTC timestamps to prevent meal log shifts across midnight boundaries during travel.
- **HealthKit Food Correlation Crash**: Resolved `NSInvalidArgumentException` crash by requesting permissions on constituent quantity types and constructing `.food` correlations with explicit metadata keys.
- **Open Food Facts Sodium Unit Mismatch**: Fixed $1,000\times$ sodium under-reporting by explicitly converting Open Food Facts grams per 100g to milligrams.
- **Underdetermined Rep Curve Fitting**: Prevented mathematical instability when fitting $k$-curves from uniform rep samples by requiring $\ge 4$ working sets and a $\ge 4$-rep spread with Bayesian shrinkage.
