# Total Factor — Running Update Log

Every feature, performance fix, data tweak, and small polish shipped to **Total Factor** is logged here (newest at the top) and mirrored inside the app under **Settings → What's New & Update Log** (`TotalFactor/Resources/UpdateLog.json`).

> **Automatic Maintenance**: `AGENTS.md` enforces that every future update—even tiny tweaks—is appended here, synced to the in-app Update Log, and given a bumped build number so you can always check which build is installed on your iPhone.

---

## v1.6.0 — Build 20 (2026-10-29) — Instant Local Meal Description & 1-Tap Import Engine ("Describe & Import")

### 1. Search Bar Live Meal Description & 1-Tap Import (`QuickAddFoodSheet.swift`)
- **Real-Time Natural-Language Meal Deconstruction**:
  - Typing conversational multi-item descriptions directly in the primary Search bar (e.g. `"apples with caramel dip and Heath candy in"`, `"3 eggs, 2 slices toast and a banana"`) now instantly deconstructs the meal locally in < 5ms.
  - Automatically recognizes multi-item conjunctions (`with`, `and`, `+`, `&`, commas) and complex food phrases without requiring you to switch tabs.
- **Instant Described Meal Breakdown Card**:
  - Displays a dedicated hero card at the top of the search list showing each detected food item, realistic serving portions, macros, and match origin badges.
  - **⚡️ 1-Tap Log Meal**: Instantly logs all component foods to today's log, increments food use counts, and syncs directly to Apple Health.
  - **🍽️ Add to Plate**: Stages all detected items onto The Plate multi-add dock in a single tap.
  - **✏️ Review & Adjust**: Opens the full confirmation sheet to fine-tune individual gram amounts or exclude specific items.

### 2. Dialed-In Offline Natural Language Matching & Token Normalization (`NaturalLanguageMealParser.swift`, `OfflineUSDACatalogIndex.swift`, `FoodSearchRanker.swift`)
- **Trailing Filler & Preposition Cleansing**:
  - Implemented automatic stripping of trailing conversational words and prepositions (`in`, `on`, `inside`, `please`, `too`, `as well`, `for me`, `total`) so phrases like `"Heath candy in"` cleanly resolve to `"Heath candy"`.
- **Bidirectional Inflection & Lemmatization**:
  - Built `FoodSearchTokenizer.inflectionVariants` to bridge singular and plural food forms (e.g. `candy` <-> `candies`, `berry` <-> `berries`, `egg` <-> `eggs`).
  - Search queries for `"candy"` or `"heath candy"` now immediately hit `Candies, HEATH BITES` across the offline index without dropping candidates.
- **Auxiliary Food Descriptor Relaxation**:
  - When compound phrases like `"caramel dip"` don't exist verbatim in the USDA database, the ranker relaxes auxiliary descriptors (`dip`, `sauce`, `topping`, `bites`, `bar`) to match the primary food noun (`caramel`), resolving to verified lab entries like `Toppings, butterscotch or caramel`.
- **Leading Word & Name Prefix Ranking**:
  - Re-weighted search scoring so items starting with the primary query word (e.g. `Apple, Raw with Skin`) receive prioritized bonuses over obscure compound entries (e.g. `Rose-apples, raw`).

### 3. Verified Real-World Snacks, Dips & Treats (`CompositeFoodLibrary.swift`)
- **New Snack & Treat Catalog Entries**:
  - Added verified composite entries for `Caramel Dip (Single-Serve / 2 tbsp)`, `Heath English Toffee Candy Bar`, and `Apple Slices with Caramel Dip & Heath Candy` with exact household portions and macros.
  - Refined `CompositeFoodLibrary.find` to prevent single-word queries from triggering false-positive multi-item composite matches.

---

## v1.5.9 — Build 19 (2026-10-29) — Dedicated Weight Trend & History View, Date-Specific Weigh-In History & Chart Scrubbing

### 1. Interactive Weight Trend Navigation (`TodayDashboardView.swift`, `ProgressHubView.swift`)
- **Tappable Dashboard & Progress Weight Cards**:
  - Tapping the Weight Trend card on either the Today Dashboard or the Progress Hub now immediately navigates into the full **Weight Trend & History** screen (`WeightDetailView`).
  - Added disclosure chevron indicators and clear "View History" / "View Weigh-Ins by Date" prompt links for effortless one-tap discovery.

### 2. Date-Specific Weigh-In History & CRUD Editing (`WeightDetailView.swift`)
- **Complete Chronological Weigh-In History**:
  - Built a comprehensive history list displaying every recorded scale weigh-in by date and time (e.g. "Today", "Yesterday", "Wed, Oct 28, 2026", "7:15 AM").
  - Each entry displays the scale weight in user units (lb or kg), the smoothed trend weight on that calendar date, and the directional delta vs the prior weigh-in (e.g. `↓ 0.4 lb`).
  - Labeled source badges clearly indicate entries from Manual logging or Apple Health.
- **Direct Entry Editing & Deletion**:
  - Tapping any weigh-in in the history opens `EditWeighInSheet` to modify the recorded scale weight (with ±0.2 nudge buttons) or timestamp, or delete accidental/duplicate entries.
  - Context menu and swipe-to-delete support for swift management.
- **Date Search & Retroactive Logging**:
  - Integrated a fast search bar to filter weigh-ins by date or month.
  - Added "+ Log Weight" with `AddWeighInSheet` supporting retroactive backfilling for any past date.

### 3. Interactive Chart Scrubbing & Tooltip Inspection (`WeightDetailView.swift`, `ProgressHubView.swift`)
- **Touch & Drag Chart Scrubbing**:
  - Implemented `.chartXSelection` with dynamic `RuleMark` indicators on both the Progress Hub and Weight Detail charts.
  - Dragging a finger across the chart displays an instant floating HUD tooltip with the exact date, recorded scale weight, and smoothed trend weight at that timeline position.
- **Multi-Window Time Range Filtering**:
  - Added range selection (2W, 1M, 3M, 6M, 1Y, All) with smooth interpolation of smoothed trend trajectories and scale dot points.

---

## v1.5.8 — Build 18 (2026-10-29) — Comprehensive Bug Fixes & Reliability Overhaul

### 1. MacroFactor CSV Importer & Units Correctness (`MacroFactorImportService.swift`)
- **Direct Weight Unit Header Detection**:
  - Replaced the brittle `> 90` threshold heuristic (which halved body weights to pounds for metric users weighing >90 kg and treated <90 lb entries as kg) with explicit column header inspection (`kg` vs `lbs` / `pound`).
  - Added seamless fallback to the active `UserProfile.unitSystem`, guaranteeing zero body weight distortion when importing external data archives.

### 2. Apple Watch Bi-Directional Workout & Weigh-In Synchronization (`PhoneWatchSyncService.swift`, `ActiveWorkoutView.swift`)
- **Rolling Split Advance on Apple Watch Finish**:
  - Finishing a workout directly on Apple Watch via `finishActiveWorkoutFromWatch` now properly updates `prog.lastCompletedWorkoutOrder = pw.order`, allowing rolling training routines to advance to the next scheduled day seamlessly.
- **Instant Wrist Weigh-In Refresh**:
  - Tapping to log a morning weigh-in from Apple Watch now immediately triggers `pushCurrentState(context: ctx)`, refreshing the watch's display and trend charts with the latest scale entry without requiring an app relaunch.
- **Active Workout Live Watch Mutation Sync**:
  - Deleting an exercise block, deleting a set, or switching a set badge (warmup, drop, failure) during an active session on iPhone now immediately pushes the updated state to Apple Watch via `pushCurrentState()`, preventing dangling set logs and desync issues.

### 3. Workout Rest Timer Customization (`ActiveWorkoutView.swift`)
- **Dynamic Program Slot Rest Honors**:
  - Fixed hardcoded 120-second rest timers in `commitFocusedSet` and row completion toggles. The workout runner now dynamically inspects each exercise slot's configured `restSeconds` (capping warmup sets at 60s), ensuring heavy compounds (180s) and isolation movements (60s) use their designated rest times.

### 4. Food Log Concurrency & SwiftData Deletion Race (`FoodTimelineView.swift`)
- **Main-Thread Model Deletion Safeguard**:
  - Extracted HealthKit sample UUIDs synchronously before invoking `modelContext.delete(entry)`, eliminating a race condition where the background `Task` attempted to access properties on a deleted SwiftData `@Model` across thread boundaries.

### 5. Onboarding & Settings Refinements (`OnboardingFlowView.swift`, `OnboardingCardComponents.swift`, `GoalStrategySettingsView.swift`, `UnitsScheduleSettingsView.swift`, `SettingsView.swift`, `TodayDashboardView.swift`)
- **Imperial Height 12-Inch Rollover Fix**:
  - Switched onboarding height decomposition to `UnitsFormatter.cmToFeetInches()`, preventing fractional rounding bugs that generated `5 ft 12 in` instead of `6 ft 0 in`.
- **Safe Rerun Setup**:
  - Rerunning onboarding now updates today's existing weigh-in rather than creating duplicate records, and automatically preserves existing active workout programs by defaulting program generation to disabled when routines are already active.
- **Goal Strategy Slider Bounds**:
  - Added an `onChange` handler on `GoalType` that dynamically clamps or resets `ratePercentPerWeek` to the new goal's valid range when switching between Cut, Maintain, and Bulk.
- **Full 7-Day Check-In Selection**:
  - Added Tuesday (3), Wednesday (4), and Thursday (5) to `UnitsScheduleSettingsView` and `SettingsView`, allowing check-ins on any day of the week.
- **Day-1 New User Check-In Shield**:
  - Guarded `isCheckInDue` in `TodayDashboardView` to require at least 7 days of tracking history since starting a program/goal before prompting the first weekly check-in.
- **Locale-Aware Quick Add**:
  - Normalized comma decimals in `QuickAddFoodSheet` so users in European and Latin American locales can log decimal macros without values being truncated to zero.

---

## v1.5.7 — Build 17 (2026-10-29) — MacroFactor Multi-Page Onboarding & Categorized Settings Hub

### 1. MacroFactor-Style Multi-Page Onboarding Flow (`OnboardingFlowView.swift`, `OnboardingCardComponents.swift`)
- **10-Step Bite-Sized Guided Setup**:
  - Replaced the cramped 3-step monolithic form with an elegant 10-page progressive wizard featuring animated step indicators (`Step X of 9`), smooth transitions, and tactile selection cards.
  - **MacroFactor Food Setup**:
    - **Demographics & Units**: Selectable cards for Imperial vs Metric, Biological Sex (anchoring Mifflin-St Jeor and fat floor protections), and Age stepper.
    - **Body Metrics**: Height (feet/inches or cm) and scale weight with morning weigh-in guidance.
    - **Baseline Activity**: Rich descriptive cards for Sedentary (<5k steps), Light (6k–8k steps), Moderate (8k–11k steps), and Very Active (12k+ steps) with clear notes that dynamic intake/scale data takes over in weeks 1–2.
    - **Primary Goal Selection**: Interactive goal cards for Lose Fat (Cut), Maintain Weight, and Gain Muscle (Bulk).
    - **Target Rate of Change Slider**: MacroFactor-style dynamic slider with live weekly % body weight change, weekly weight change display, and zone recommendation pills (*Conservative*, *Standard / Recommended*, *Aggressive*).
    - **Day-1 Nutrition Strategy Preview**: Visual stacked macro bar breakdown (Protein, Carbs, Fat) with gram targets, calorie percentages, and Training-Day Carb Cycling toggle.
  - **MacroFactor Workouts Setup**:
    - Integrates strength training directly into onboarding: training frequency (2–6 days/week), primary lifting focus (Hypertrophy, Strength, Both), and primary gym setup.
    - Automatically generates and activates an initial workout blueprint on Day 1 using `ProgramGeneratorEngine`.
  - **Apple Health Integration & Launch**:
    - Transparent permission breakdown (Smart Scale, Macros, Workouts, Watch Telemetry) with instant connection feedback.
    - Summary card with Day-1 starting weight, calorie/protein targets, and workout split.

### 2. Categorized Settings Hub Redesign (`SettingsView.swift` & Modular Sub-Views)
- **Master Hub & Drill-Down Navigation Architecture**:
  - Modularized the 538-line single form into a clean, high-level **Settings Hub** with SF Symbol badged navigation rows leading to dedicated subpages.
  - **Active Program & Profile Card**: Displays biological sex, age, current weight, active goal pill, and weekly check-in day, with a 1-tap **"Rerun Setup & Onboarding"** button to replay the onboarding wizard anytime.
  - **Coaching & Nutrition (`GoalStrategySettingsView.swift`, `FastingSettingsView.swift`)**:
    - Goals & Target Rates (goal picker, weekly rate slider, carb cycling, BMR floor override).
    - Intermittent Fasting (protocol picker, fasting timer controls).
    - Deep link to `NutrientTargetsEditorView`.
  - **Workouts & Training (`WorkoutPreferencesSettingsView.swift`)**:
    - Rest timer sound & Apple Watch haptic wrist vibration mirroring.
    - Gym Equipment Profiles management.
  - **Preferences & Schedule (`UnitsScheduleSettingsView.swift`, `NotificationsSettingsView.swift`)**:
    - Preferred units, weigh-in rule, first day of week, weekly check-in weekday.
    - Weigh-in alarm, lunch/dinner meal logging reminders, evening missed food check, pre-workout alert.
  - **Integrations & Cloud (`AppleHealthSettingsView.swift`, `AIDatabaseSettingsView.swift`)**:
    - Two-way sync, push history, import nutrition, iCloud sync toggle.
    - USDA FoodData Central API key, Gemini AI meal/photo logging, model picker, secure Keychain key storage.
  - **Data Management & Exports (`DataManagementSettingsView.swift`)**:
    - Direct MacroFactor CSV Importer with zero-duplicate protection.
    - Universal Export Package (CSVs + AI Coaching prompt digest).
    - Individual CSV Exports (Food Log, Weigh-Ins, Workouts).
    - Strong Workout CSV Importer.
  - **About & Science (`AttributionSettingsView.swift`, `UpdateLogView.swift`)**:
    - Running update log with `v1.5.7 (Build 17)` badge and open-data attributions.

### 3. Workout Builder Fixes: Day Removal & Share Sheet Presentation (`ProgramBuilderView.swift`, `TrainHubView.swift`, `ShareSheetHelper.swift`)
- **Workout Day Removal**:
  - Added an ellipsis action menu and destructive "Delete Day" button to every workout day section in `ProgramBuilderView.swift`.
  - Cascades exercise slots, prompts with a confirmation alert, and automatically re-indexes remaining workout days consecutively (`order = 0, 1, 2...`) while updating `daysPerWeek`.
- **Workout & Program Export Fix**:
  - Built `ShareSheetHelper.swift` to resolve the topmost presented `UIViewController` across active modal sheets.
  - Fixes silent presentation failures when exporting `.totalfactorprogram` files in `ProgramBuilderView` and `TrainHubView`, and ensures instant 1-tap sharing for workout CSV exports.

---

## v1.5.6.5 — Build 16 (2026-10-29) — Direct MacroFactor CSV Importer & Zero-Duplicate Protection

### 1. Direct MacroFactor Data Importer (`MacroFactorImportService.swift`, `SettingsView.swift`)
- **1-Tap Direct Nutrition Import**:
  - Added a dedicated **"Import MacroFactor Nutrition Data (CSV)..."** button under **Settings → Data Management** using native iOS file picker (`.commaSeparatedText`).
  - Supports flexible header parsing across granular food logs and daily summaries (`Date`, `Time`, `Food Name`, `Serving Size`, `Calories`, `Protein`, `Carbs`, `Fat`, `Fiber`, `Sugar`, `Sodium`).
  - Automatically imports scale body weights if present in the CSV file into `WeighIn`.
- **Deterministic Fingerprint Deduplication (Zero Duplicates)**:
  - Generates a unique signature for each row (`[DayKey]_[Time]_[FoodName]_[Kcal]_[Protein]`).
  - Idempotent import: re-importing the same CSV or overlapping date ranges checks existing diary signatures and skips duplicates completely (0 duplicate entries guaranteed).
- **Apple Health Anti-Echo Safeguard (`HealthKitService.swift`)**:
  - Imported MacroFactor items are tagged with `foodBrand = "MacroFactor"`.
  - Added strict guards to `syncFoodEntry` and `syncAllHistoryToAppleHealth` ensuring Total Factor never re-exports imported MacroFactor food logs back to Apple Health.
  - Native food logs and recipes logged in Total Factor continue syncing normally without echo loops or double-counting.
- **Alert Title Polish**:
  - Replaced the hardcoded `"CSV Import"` modal alert header with dynamic context-aware titles (`"MacroFactor Import"`, `"Apple Health Sync"`, and `"CSV Import"`).

---

## v1.5.6 — Build 15 (2026-10-29) — HealthKit Auto-Authorization & Apple Health Sources Fix

### 1. Automatic HealthKit Authorization on Demand (`HealthKitService.swift`)
- **Proactive Permission Prompting**:
  - Added proactive `requestPermissions()` triggers directly inside `importExternalDietaryIntake` and `syncAllHistoryToAppleHealth`.
  - Tapping **"Import Nutrition from Apple Health"** or **"Sync All History"** now immediately prompts iOS for HealthKit permissions if not already granted.
- **Apple Health "Sources" Registration**:
  - Resolves the issue where Total Factor did not appear under **Settings → Health → Data Access & Devices (Sources)** on fresh installs prior to running a full two-way sync.
  - As soon as the permission prompt is accepted, Total Factor is instantly registered in iOS Health Sources.

---

## v1.5.5 — Build 14 (2026-10-29) — HealthKit External Nutrition Sync Engine & Bug Fixes (1.5.3.x Fixes)

### 1. Robust Multi-App Nutrition Ingestion Engine (`HealthKitService.swift`)
- **Zero Duplicate Calorie & Macro Ingestion**:
  - Fixed a fundamental HealthKit query collision where meals logged in external apps (MacroFactor, MyFitnessPal, Cronometer, Lose It) via `HKCorrelationType.food` were being imported a second time as standalone `dietaryEnergyConsumed` entries with `0g` macros.
  - Extracted all child `HKQuantitySample` UUIDs from active correlations and blacklisted them from standalone calorie ingestion, ensuring single-entry ingestion for every external meal.
- **Bi-Directional Deletion & Modification Reconciliation**:
  - Total Factor now actively reconciles external entries against HealthKit. When a meal is deleted or changed in MacroFactor, MyFitnessPal, or Apple Health, Total Factor automatically prunes the deleted entry from SwiftData or updates its macros in-place without generating duplicates.
- **Automatic Time-of-Day Meal Tagging**:
  - Replaced unassigned `.none` tags with intelligent time-of-day timeline placement:
    - 5am–11am: `.breakfast`
    - 11am–3pm: `.lunch`
    - 3pm–6pm: `.snack`
    - 6pm–10pm: `.dinner`
    - 10pm–5am: `.snack`
- **Dynamic App Name Attribution & Food Title Fallback**:
  - Dynamically extracts the external source name (`sourceRevision.source.name`) e.g. "MacroFactor", "MyFitnessPal", "Cronometer", "Lose It!".
  - If a specific food item name is present (`HKMetadataKeyFoodType`), Total Factor preserves it (e.g. *"Chicken Breast"*).
  - If an app syncs an hourly or aggregate meal block (common with MacroFactor's hourly mode), Total Factor synthesizes a clean, natural title like `MacroFactor Lunch` or `MyFitnessPal Breakfast` and stores the brand for app-level attribution.
- **Loop & Re-Export Prevention**:
  - Added strict guards in `syncFoodEntry` and `syncAllHistoryToAppleHealth` preventing Total Factor from ever re-exporting third-party imported meals back to HealthKit.

### 2. Timeline & Settings Polish (`MacroZoneBar.swift`, `FoodTimelineView.swift`, `SettingsView.swift`)
- **App-Specific Provenance Badges**:
  - Enhanced `FoodSourceBadge` to take an optional `brand` parameter. Third-party meals now proudly display their source app name (`MacroFactor`, `MyFitnessPal`, `Cronometer`) in a themed pink pill on timeline cards and hour-by-hour logs.
- **One-Tap "Remove All Imported HealthKit Meals" Safety Tool**:
  - Added a dedicated maintenance tool under Settings $\rightarrow$ Apple Health with a native confirmation dialog to wipe only third-party imported HealthKit meals. Local foods, custom items, and recipes created in Total Factor are strictly protected.

---

## v1.5.4 — Build 13 (2026-10-29)

### 1. SideStore & AltStore Visual Makeover & Schema v2 Upgrade
- **High-Res App Icon & Source Branding (`icon.png`, `source.json`)**:
  - Fixed missing logo in SideStore / AltStore: resolved 404 URL caused by mismatched raw file naming by publishing dedicated 1024×1024 `icon.png` in `TotalFactor/Resources/SideStore/`.
  - Added fallback `AppIcon-1024.png` to asset catalog and symlink for full backward compatibility.
- **Official 16:9 News & Store Banner (`banner.png`, 1200×675)**:
  - Designed high-resolution hero graphic featuring a deep midnight charcoal background (`#10141D`), flame orange radiant ambient glow, embossed app icon squircle, and SF Pro typography with feature badges.
  - Linked as `headerURL` in source manifest and featured visual card in SideStore News feed.
- **Full Retina iOS 17 Preview Screenshot Gallery**:
  - Added 4 high-resolution (1206×2622) iPhone screenshots showcasing core workflows:
    1. **Today Dashboard (`screenshot_today.png`)**: Live adherence rings, calories burned, weight trend, and active macro gauges.
    2. **Food Log & The Plate (`screenshot_food.png`)**: 7-day adherence strip, hourly timeline, and persistent Plate dock.
    3. **Smart Strength Tracker (`screenshot_train.png`)**: Live workout session, RIR pills, active rest timer, and hypertrophy volume targets.
    4. **Progress & Adaptive Coaching (`screenshot_progress.png`)**: Dynamic TDEE expenditure chart, weight moving average, and weekly coaching check-in banner.
- **SideStore Schema v2 Manifest & Rich Metadata**:
  - Restructured `TotalFactor/Resources/SideStore/source.json` to conform to official SideStore schema v2.
  - Added `versions` array preserving historical releases (v1.5.0 through v1.5.4) with individual download URLs and byte sizes.
  - Added `permissions` array for Camera, Photos, Microphone, and Speech Recognition with clear user explanations.
  - Added rich Markdown `localizedDescription` breaking down Adaptive TDEE, The Plate, Strength Tracker, and offline privacy.
  - Configured `tintColor: "FF5B00"` and `category: "fitness"`.
- **Release Automation Polish (`Scripts/publish_sidestore_release.sh`)**:
  - Updated publisher script to automatically maintain the `versions` array, news banner graphics, and preserve rich metadata during future releases.

### 2. Deep Linking & UI Robustness
- **Custom URL Scheme Handler (`Info.plist`, `RootTabView.swift`)**:
  - Added `CFBundleURLTypes` registering `totalfactor://` URL scheme for quick-launch widgets and shortcuts.
- **Exhaustive Switch Fix (`MacroZoneBar.swift`)**:
  - Added `.healthKit` badge color case (`.pink`) to eliminate Swift compiler warnings.

---

## v1.5.3 — Build 12 (2026-10-29)

### 1. Apple Health Bi-Directional Synchronization & History Back-Sync
- **"Two-Way Apple Health Sync" (`HealthKitService.swift`, `SettingsView.swift`)**:
  - Full bidirectional sync engine between Total Factor and Apple Health with live events counter.
  - Added read permissions for dietary calories and macronutrients (`.dietaryEnergyConsumed`, `.dietaryProtein`, `.dietaryCarbohydrates`, `.dietaryFatTotal`).
  - Added new `FoodSource.healthKit` enum case so external meals display an *"Apple Health (External)"* badge.
- **"Push Complete History to Apple Health"**:
  - 1-tap historical sync that iterates over all past food entries, manual weigh-ins, and completed strength workouts and pushes any unsynced items directly to Apple Health.
  - Ensures third-party fitness, diet, or health apps (Apple Fitness, MyFitnessPal, MacroFactor, RP Diet, LoseIt, Strava) immediately have access to all nutrition and training history logged in Total Factor.
- **"Import Nutrition from Apple Health"**:
  - Imports external dietary intake logged by third-party apps via Apple Health into Total Factor's daily nutrition log.
  - Robust bundle ID filtering and UUID deduplication ensures Total Factor's own writes are never duplicated.

### 2. Photo Tracker Fixes & Empty State Drop Zones
- **Pose Selector Pill Bar (`PhotoCompareView.swift`)**:
  - Replaced the native segmented control inside `ScrollView` with a custom, haptic-enabled Segmented Pill Bar.
  - Added live photo count badges (`Front (3)`, `Side (0)`, `Back (1)`) and spring animation.
  - Pose switching immediately clears selection IDs (`leftPhotoID = nil`, `rightPhotoID = nil`) to prevent comparison freezes.
- **Interactive Empty State Drop Zones**:
  - The "No Side/Back Photos Yet" empty placeholder card is now an interactive drop zone with dashed accent border.
  - Tapping anywhere on the empty card or the primary button directly opens the photo picker or camera.
  - Immediate `pickerItem = nil` reset ensures subsequent photo picks always re-trigger without cancellation locks.

### 3. EXIF Capture Metadata & Historical Weight Matching
- **Past Photo Import & Metadata Extraction (`PhotoMetadataHelper.swift`)**:
  - Automatically extracts original photo capture timestamps from embedded EXIF/TIFF metadata (`kCGImagePropertyExifDateTimeOriginal`, `DateTimeDigitized`, `TIFFDateTime`) via `ImageIO` without requiring Photo Library permissions.
  - Automatically queries the user's historical `WeighIn` logs closest to the photo's capture date to populate `weightKgAtCapture`.
  - Displays a toast banner upon importing a past photo (e.g. *"Imported past photo from 2024-03-12 • 178.4 lbs"*).
- **Full Screen Photo Viewer Enhancements**:
  - Added interactive Pose switcher menu allowing users to re-assign photos between Front, Side, and Back poses anytime.
  - Added Date & Weight editor sheet to adjust capture timestamps and scale weight.
  - Added destructive photo deletion option.

### 4. "Export All App Data" (Universal CSVs + AI Coaching Digest)
- **Universal Data Package (`ExportAllArchiveService.swift`, `SettingsView.swift`)**:
  - Prominent 1-tap **"Export All App Data"** card in Settings that generates a unified export folder and presents the native iOS Share Sheet (Save to Files, AirDrop, Notes, or AI apps).
  - **`TotalFactor_AI_Digest.md`**: Pre-formatted Markdown report containing user demographics, expenditure targets, a 60-day daily aggregated nutrition & adherence matrix, personal strength PRs, and an evidence-based sports nutrition AI coaching prompt ready to paste into ChatGPT, Claude, or Google Gemini.
  - **`TotalFactor_AllData.json`**: Complete structured JSON export of UserProfile, Goals, FoodLogEntry, WeighIn, WorkoutSession, BodyMetric, and ProgressPhoto records.
  - **Universal CSVs**: `TotalFactor_FoodLog.csv`, `TotalFactor_WeighIns.csv`, `TotalFactor_Workouts.csv`, and `TotalFactor_BodyMetrics.csv`.

---

## v1.5.2 — Build 11 (2026-10-29)

### 1. Zero-Scale & Real-World Food Logging
- **"No-Scale & Container Estimator" Sheet (`NoScaleEstimatorSheet.swift`)**:
  - Built an intuitive visual estimation tool for real-world meals where food scales are unavailable (social dinners, takeout, family gatherings).
  - **Biological Hand Rulers**: Visual Palm of Protein (~30g P / 130g cooked meat/fish/tofu), Fist of Carbs (~1 cup / 158g rice/pasta/oats), Cupped Hand of Snacks (~½ cup / 50g nuts/chips), and Thumb of Fat (~1 tbsp / 14g butter/oil/peanut butter).
  - **Takeout Container Presets**: Standardized restaurant containers including Deli Pint (16 oz / 2 cups curry/soup), Deli Quart (32 oz / 4 cups), 3-Compartment Takeout Box (full meal with sides), and Round Foil Tin.
  - Live aggregated macro calculation with 1-tap **"Add to Plate"** and direct logging.
- **Cultural & Street Food Composite Library (`CompositeFoodLibrary.swift`)**:
  - Added verified offline composite library for foods that cannot be weighed raw or on a scale.
  - **Natural Piece-Count Steppers**: Panipuri/Golgappa (~28 kcal/pc, default 10 pieces = 280 kcal), Samosas (Standard 260 kcal vs Cocktail 90 kcal), Street Tacos (180 kcal), Steamed Dumplings/Momos (45 kcal), Sushi Rolls (320 kcal), Plain Roti (80 kcal), Roti with Ghee (110 kcal), Dal Tadka Katori (150 kcal), Chicken Biryani (320 kcal/cup), Pizza Slices (285 kcal), Chicken Wings (85 kcal), Falafel (60 kcal), Masala Dosa Set (380 kcal), Pav Bhaji (450 kcal), Chole Bhature (620 kcal), Burrito Bowl (720 kcal), and Pad Thai (650 kcal).
  - All composite dishes are fully searchable in Quick Add and materialize as persistent foods on first log.
- **"Ballpark My Meal" 3-Second Quick Logger (`MealBallparkSheet.swift`)**:
  - Ultra-fast 3-second meal logger for buffets, weddings, holiday feasts, dining out, and unmeasured restaurant meals without tracking friction or diet guilt.
  - 4 General Tiers: Light Snack (~300 kcal: 15P / 35C / 10F), Standard Meal (~650 kcal: 35P / 65C / 25F), Hearty Restaurant Meal (~950 kcal: 45P / 100C / 40F), and Feast / Buffet (~1,350 kcal: 50P / 140C / 65F).
  - **Meal Vibe Modifiers**: 1-tap chips for `[🍗 High Protein]` (+15g P, -15g C), `[🍟 Fried / Oily]` (+15g F, +135 kcal), and `[🍚 Carb Heavy]` (+30g C, +120 kcal) plus fine-tune calorie slider.
  - Supports 1-tap "Add to Plate" and direct logging with customizable meal title.

### 2. Voice & Natural Language Parser Enhancements
- **Street Food & Hand-Size Offline Aliases (`NaturalLanguageMealParser.swift`)**:
  - Expanded the 2ms deterministic offline natural language parser to automatically resolve street foods, cultural staples, and hand-size descriptors.
  - Resolves spoken phrases like *"10 panipuri and 2 samosas"*, *"2 street tacos and a handful of chips"*, *"1 palm chicken, 1 fist rice, and 1 thumb olive oil"*, *"deli pint of soup"*, *"takeout container of biryani"*, and *"3 chapatis with ghee and 1 katori of dal"* completely offline with zero API key.
  - Added new canonical unit kinds: `palm`, `fist`, `thumb`, `handful`, `pint`, `quart`, `taco`, `wing`, `roll`, `roti`, `samosa`, and `katori`.

### 3. Workflow & The Plate Unification
- **AI Describe & Plate Dock Synergy (`DescribeMealView.swift`, `QuickAddFoodSheet.swift`)**:
  - Connected `DescribeMealView` directly to `ThePlateDockView`. In `MultiItemMealConfirmationSheet`, users can now tap **"Add to Plate"** to drop voice-described or AI-analyzed items directly into the persistent bottom Plate dock, letting them seamlessly combine AI meals with barcode scans and search items before batch logging.
  - Added real-world sample prompt chips: *"10 panipuri and 2 samosas"*, *"1 palm chicken, 1 fist rice, and 1 thumb olive oil"*.
- **Quick Add & Kitchen Hub Integration (`QuickAddFoodSheet.swift`, `KitchenHubView.swift`)**:
  - Mode 3 ("Quick") in Quick Add now features two prominent 1-tap launcher cards for **Ballpark My Meal** and **No-Scale Estimator** alongside manual macro entry.
  - Added "Street & Bites" filter tab to Quick Add search for instant 1-tap access to composite foods.
  - Added "Composites" segment tab to Kitchen Hub displaying all 20+ verified street foods and hand benchmarks with 1-tap access to the No-Scale Estimator.

---

## v1.5.1 — Build 10 (2026-10-29)

### 1. Workout UI & Stability Bug Fixes
- **Action Pill Lettering & Wrapping Fix (`ActiveWorkoutView.swift`)**:
  - Fixed crushed and hyphenated button labels (`Wa\nnd`, `Warm\nUp`, `Not\ne`) caused by an unscrollable horizontal container. Replaced rigid `HStack` with a smooth horizontal `ScrollView` with `.fixedSize(horizontal: true, vertical: false)` and `.lineLimit(1)`, ensuring pristine typography across all device sizes.
- **Top Exercise Switcher Carousel Polish (`ActiveWorkoutView.swift`)**:
  - Widened thumbnail label width from `58pt` to `72pt` with multi-line wrapping (`.lineLimit(2)`) so longer exercise names (e.g., *Incline Dumbbell Curl*, *Romanian Deadlift*) no longer aggressively truncate with ellipses.
- **Functional Pause & Resume Workout (`ActiveWorkoutView.swift`, `TrainingModels.swift`, `RootTabView.swift`)**:
  - Added full pause/resume capabilities to active sessions. Tapping **Pause Workout** in the navigation header or ellipsis menu freezes the elapsed timer, tracks total paused duration (`totalPausedSeconds`), and updates the UI and mini-bar with an amber `⏸ PAUSED` badge.
- **Fixed Discard Workout Cascade Deletion (`ActiveWorkoutView.swift`)**:
  - Fixed bug where discarding a workout dismissed the screen without resetting session state or deleting SwiftData records. Now presents a safety confirmation alert, wipes orphaned draft sets and session entities, cancels active rest timers, and cleanly resets `appState.activeWorkoutSessionID`.

### 2. Kitchen Rehaul & MacroParity Food Logging
- **7-Day Adherence Calendar Strip (`WeekAdherenceCalendarStrip.swift`)**:
  - Added MacroFactor-style weekly adherence strip atop the food log showing 7 days of calorie target rings. Each day ring displays percentage adherence or over/under status with 1-tap fast day switching.
- **Remaining vs. Consumed Budget Toggle (`FoodTimelineView.swift`)**:
  - Added 1-tap budget perspective switcher allowing users to view macro progress either as consumed intake (`1,850 kcal`) or remaining budget (`650 kcal left`).
- **Hour-by-Hour Timeline Mode (`HourByHourTimelineSection.swift`)**:
  - Added a third timeline view mode alongside "Grouped by Meal" and "Flat Chronological": an hourly timeline clustering food entries by hour of consumption with hourly macro subtotals, inline `+` buttons, handedness alignment (left- vs right-handed logging), and an option to collapse empty hours.
- **"The Plate" Multi-Add Staging Workspace (`ThePlateDockView.swift`, `ThePlateWorkspaceSheet.swift`)**:
  - Built MacroFactor's signature multi-item staging plate. Foods can be staged to a floating bottom tray while browsing or searching without logging individually.
  - The persistent bottom dock displays staged item count, calorie sum, macro breakdown, and a 1-tap **Log All** button.
  - Tapping the plate opens an expansive workspace sheet with inline quantity adjustments, serving unit pickers, swipe-to-delete, and batch commit to any meal slot or custom timestamp.
  - Added swipe-to-stage gesture directly on catalog search results.
- **Explode Recipe to Ingredients (`FoodTimelineView.swift`)**:
  - Logged recipes can now be "exploded" directly from the timeline with a single tap. The parent recipe entry is unpacked into its individual ingredient items, scaled proportionally to the logged portion.
- **Kitchen Hub (`KitchenHubView.swift`)**:
  - Integrated pantry and recipe management center consolidating Custom Foods, Saved Meals (`SavedMeal` / `SavedMealItem`), and Recipes under unified tabbed navigation.
  - Includes raw-to-cooked moisture loss / absorption percentage math and yields in the recipe creator (`RecipeBuilderSheet.swift`).
- **Enhanced Food Detail Sheet (`FoodDetailSheet.swift`)**:
  - **Macro Calorie Ratio Donut (`MacroRatioDonutView`)**: Visual breakdown displaying exact caloric percentage contributions from Protein (red), Carbs (blue), and Fat (yellow).
  - **Daily Goal Impact Bar**: Live before/after preview bar visualizing how the selected food will impact today's remaining calorie target.
  - **Kitchen-Scale Tare Math**: Keypad now supports subtractive tare math (`245 - 65 = 180 g`) via `.minus` operator support in `InlineQuantityCalculator`.
  - **Micronutrient Accordion Preview**: Collapsible nutrient drawer showing vitamin and mineral density before committing the entry.
- **Search Category Filter Tabs (`QuickAddFoodSheet.swift`)**:
  - Added segmented search tabs (`All`, `History`, `Favorites`, `Custom`, `Recipes`, `Common`, `Branded`) to filter search results instantly.

---

## v1.5.0 — Build 9 (2026-10-28)

### 1. MacroFactor Workouts UI Revamp
- **Horizontal Exercise Switcher Carousel (`ActiveWorkoutView.swift`)**:
  - Replaced long vertical exercise scrolling with MacroFactor's top horizontal exercise switcher strip.
  - Browse all exercises in the workout with visual thumbnails (`ExerciseThumbnailView`), exercise names, and set progress badges (e.g. `4/4` with green checkmark when complete).
  - Tap any exercise tile to jump to it in 1 tap, with a dedicated `+` tile at the end to add exercises on the fly.
  - Added quick `≡` menu toggle to switch between **Carousel (Focused)** and **All Exercises (List)** modes.

### 2. MacroFactor Clean Set Grid with Mini Colored RIR Badges
- **Crisp Set Table & Focus States (`ActiveWorkoutView.swift`)**:
  - Streamlined table hierarchy: `Set` | `Previous ↔` | `Lb` | `Reps` | `▢`.
  - Input boxes feature high-contrast active focus borders (bold outline around the active field).
  - **Mini Colored RIR Badges**: Reps box features MacroFactor's signature colored circular badge on the bottom-right corner (`0` red, `1` coral, `2` orange, `3` yellow, `4` mint, `5` green, `6+` electric blue) displaying logged RIR at a glance.
  - Rounded square completion checkboxes `▢` fill `☑` with haptic feedback upon logging.

### 3. Docked Custom Gym Keypad (`MacroFactorGymKeypad.swift`)
- **Integrated Gym Keypad with Colored RIR Strip**:
  - Eliminates modal sheet steppers: tapping any weight or reps box docks the custom gym keypad at the bottom.
  - **Top Colored RIR Strip**: `0` (Failure / Red) through `6+` (Easy / Blue) and `?` (Unrated); 1-tap immediately stamps the set with RIR.
  - **10-Key Pad with First-Digit Overwrite**: Large, chalky-finger friendly numeric keys (`1 2 3`, `4 5 6`, `7 8 9`, `. 0 ⌫`); typing automatically overwrites suggested load/reps without tedious backspacing.
  - **Utility Keys**: Keyboard dismiss, plate calculator shortcut, set type toggle (`W`, `D`, `F`, `P`, `M`), and a prominent black checkmark commit button (`✓`) that logs the set, starts the rest timer, and auto-focuses the next set or exercise.

### 4. MacroFactor "Workout Complete" Celebration Screen (`WorkoutCompleteCelebrationView.swift`)
- **Front & Back Anatomical Humanoid Heatmap (`AnatomicalHumanoidHeatmapView.swift`)**:
  - Full front and back humanoid muscle vector drawings in SwiftUI `Canvas`.
  - Illuminates every muscle trained in the session in MacroFactor's signature **electric royal blue** (`#2F7CF6`) against sleek charcoal body contours.
- **PR Milestone Trophy Cards**:
  - Horizontal card carousel celebrating new records:
    - `🏆 Volume Record` (e.g., *6,645 lb New! — Barbell Back Squat*)
    - `⭐ Reps Record` (e.g., *8 reps New! — Barbell Back Squat*)
    - `🎯 Est. 1RM Record` (e.g., *315 lb New! — Barbell Bench Press*)
- **Workout Details & "Update Workout Plan" Switch**:
  - Summary metrics: total working volume, completed sets, elapsed duration, and live Apple Watch heart rate / active calories.
  - Added MacroFactor's *"Save these changes as the new default for this workout"* toggle switch, automatically committing added exercises, swaps, and set targets to the program routine template upon tapping **Done**.

### 5. Preserved All Superior Total Factor Features
- Retained the **Progression Wand (🪄)** with diagnostic overload reasoning and dynamic rep range expansion.
- Retained the **Live Heart Rate Corner Badge (`❤️ 142 BPM`)** streaming from Apple Watch.
- Retained the **Rest Timer Live Activity & Dynamic Island** with lock screen controls and Apple Watch wrist haptics.
- Retained **Pre-Workout Fuel Warnings**, **Bilateral & Unilateral (L/R) Logging**, **Biomechanical Equipment Swapping**, **Persistent Machine Setup Notes**, and the **Olympic Plate Calculator**.

---

## v1.4.1 — Build 8 (2026-10-28)

### 1. Siri AI & Apple Intelligence Spoken Food Logging
- **Hands-Free Natural Language Food Logging (`TotalFactorShortcuts.swift`)**:
  - Added native `LogFoodIntent` and registered with Apple Intelligence / Siri AppShortcuts.
  - Speak naturally to Siri from your iPhone, Apple Watch, AirPods, or CarPlay:
    - *"Hey Siri, log 3 scrambled eggs and 2 slices of sourdough toast in Total Factor"*
    - *"Hey Siri, log 200g grilled chicken and 1 cup rice for lunch in Total Factor"*
    - *"Hey Siri, log food in Total Factor"* (Siri prompts: *"What did you eat?"*)
  - Dispatches directly to Total Factor's deterministic on-device parser, resolves exact quantities and grams against the ~8,156 offline USDA catalog, immediately increments daily calories and protein, and responds with spoken dialog (*"Logged 3 eggs and 2 slices sourdough bread (400 kcal, 26g protein) to Breakfast."*).
  - 100% offline, zero latency, zero cloud API fees, and zero reliance on Google Gemini.

### 2. Siri Quick Calorie & Macro Intent
- **Direct Calorie Logging (`TotalFactorShortcuts.swift`)**:
  - Added `LogQuickCaloriesIntent`: *"Hey Siri, log 450 calories in Total Factor"*.
  - Immediately enqueues a quick calorie entry, increments your dashboard dial and widgets, and syncs to Apple Health.

### 3. On-Device Apple Vision Plate Classifier
- **Neural Engine Meal Photo Analysis (`AppleVisionFoodClassifier.swift`, `DescribeMealView.swift`)**:
  - Integrated Apple's native `Vision.framework` (`VNClassifyImageRequest`) for 100% private, on-device meal photo recognition.
  - Classifies common food items (grilled chicken, eggs, steak, salmon, pizza, burgers, salad, pasta, rice, oatmeal, yogurt, bread, fruit, etc.) on the Apple Neural Engine in under 50ms.
  - Added **"Identify Plate On-Device (Apple Vision AI)"** button in `DescribeMealView`: snap a plate or choose a photo from your library to recognize foods and generate USDA macro breakdowns without any Gemini API key or internet connection.

### 4. Apple `NaturalLanguage` Vector Embedding Fallback
- **Semantic Synonym Matching (`NaturalLanguageMealParser.swift`)**:
  - Integrated `NLEmbedding.wordEmbedding(for: .english)` on Apple Neural Engine to resolve colloquial terms and slang.
  - Maps words like "poultry" $\rightarrow$ "chicken", "flapjack" $\rightarrow$ "pancake", "espresso" $\rightarrow$ "coffee", "veggies" $\rightarrow$ "vegetables" to exact USDA whole foods when literal token matching misses.

### 5. Instant Widget & Background Action Sync
- **Rich Macro Action Queue (`SharedSnapshotStore.swift`, `CoachingCoordinator.swift`)**:
  - Extended `PendingQuickAction` to carry calories, protein, carbs, fat, grams, serving label, and meal tag.
  - Siri food logs immediately update `WidgetDashboardSnapshot` and trigger `WidgetCenter.reloadAllTimelines()` so your Home Screen and Lock Screen widgets reflect your meal within 50ms.
  - Upon app opening, `CoachingCoordinator` automatically inserts full `FoodLogEntry` records into SwiftData and syncs with Apple Health.

### 6. SideStore IPA Packaging Cleanliness (`build_ipa.sh`)
- **Resolved "The app's Info.plist could not be found" in SideStore**:
  - Automatically strips unit test bundles (`.xctest`) and debug symbol folders (`.dSYM`) from `PlugIns/` before packaging.
  - Strips unsupported companion watchOS targets from the standalone sideload archive (preserving watchOS companion app support for direct `update_iphone.sh` / Xcode deploys).
  - Guarantees clean bundle hierarchy so SideStore's on-device `AltSign` parser verifies `Info.plist` without failing.

---

## v1.4.0 — Build 7 (2026-10-28)

### 1. Multi-Add Food Logging ("Multi-Select Staging Tray")
- **MacroFactor-Style Staging Workflow (`QuickAddFoodSheet.swift`)**:
  - Each search result row now features a dedicated `+` button that adds the food directly into an active bottom Staging Tray with haptic feedback without closing the search.
  - Search for your next food immediately and stage multiple items in seconds.
  - Persistent bottom dock shows real-time staged item count, total calories, and protein (`3 Items Staged • 520 kcal • 42g protein`).
  - Added full **Review Staged Meal** sheet to tweak serving sizes, multipliers (0.25×–20×), or delete items before committing.
  - 1-tap **"Log All (N)"** commits the entire meal into SwiftData and Apple Health in a single transaction.

### 2. Native Intermittent Fasting (IF) Engine
- **Configurable Protocols & Live Fasting Dial (`DomainEnums.swift`, `UserProfileModels.swift`, `TodayDashboardView.swift`, `SettingsView.swift`)**:
  - Integrated native Intermittent Fasting support with 6 protocols: 16:8 LeanGains (Standard), 18:6 Deep Fast, 20:4 Warrior Diet, OMAD (23:1), 14:10 Moderate, and Circadian (13:11).
  - Added dedicated **Intermittent Fasting Card** on Today Dashboard displaying current fasting status, elapsed hours, fasting target countdown, and eating window status.
  - Smart automatic calculation from yesterday's last logged food timestamp, plus 1-tap "Start Fast" / "End Fast" override controls.
  - Added configuration toggle and protocol picker under **Settings → Intermittent Fasting**.

### 3. Flexible Rolling Split Workouts ("Work Out Whatever Days You Want")
- **Sequential Rolling Rotation (`DomainEnums.swift`, `TrainingModels.swift`, `TodayDashboardView.swift`, `TrainHubView.swift`, `ProgramBuilderView.swift`)**:
  - Added `ProgramScheduleMode`: switch between **Fixed Weekdays** and **Rolling Split (Any Day / Flexible)**.
  - In Rolling Split mode, workouts are never locked to calendar days. The app sequences workouts automatically (Workout 1 → 2 → 3 → 4) whenever you train.
  - Today Dashboard dynamically features **"Next Up: [Workout Name]"** and advances automatically upon finishing a workout.
  - Added **"Switch Workout"** menu on the Today dashboard card allowing you to start any routine in your active program at any time with 1 tap.
  - Active program cards in Train Hub display a bright green **"NEXT UP"** badge on the next scheduled routine.

### 4. Complete Program Import & Export Engine
- **Share & Backup Routines (`ProgramImportExportService.swift`, `ProgramBuilderView.swift`, `TrainHubView.swift`)**:
  - Full JSON serialization for workout programs (split configuration, exercises, sets, rep ranges, target RIR, rest intervals, and progression rules).
  - Export programs directly to `.totalfactorprogram` files via the iOS Share Sheet (AirDrop, Messages, Mail, Save to Files) or copy JSON to clipboard.
  - File Importer and Clipboard Importer in Program Builder and Train Hub: seamlessly imports routines, automatically matches against the 118 bundled exercises, auto-creates custom exercises for new movements, and saves directly into SwiftData.

### 5. Overhauled Progress Photos & Mirror Camera Capture
- **Redesigned Progress Photo Experience (`PhotoCompareView.swift`)**:
  - Fixed empty state bug where having 1 photo rendered `ContentUnavailableView`, making photos appear lost.
  - Single-photo showcase prominently renders your photo with date, weight badge, and encouragement to capture a comparison photo.
  - Added comparison controls for 2+ photos: Choose any photo for "Before" and any photo for "After" with days-apart and weight delta badges.
  - Added **Side-by-Side** mode in addition to the draggable **Split Slider**.
  - Added native in-app **Take Photo** mirror camera capture alongside the Photos library picker.
  - Added chronological thumbnail history gallery reel with tap-to-inspect and delete photo with confirmation.
  - Downsamples and compresses captured photos to clean 1600px JPEG to keep SQLite storage fast and lean.

### 6. MacroFactor Visual Polish & Adaptive Expenditure (TDEE) Indicator
- **Energy Balance & TDEE Synergy (`TodayDashboardView.swift`)**:
  - Re-branded "Metabolism" card to **"Adaptive Expenditure (TDEE)"** with clear daily energy burn indicators and confidence pills.
  - Added **Energy Balance (Intake vs. TDEE)** card showing net daily deficit or surplus (Intake − TDEE) with color-coded badges (Blue for deficit, Orange for surplus).
  - Clarified synergy between workout energy expenditure and dynamic TDEE adaptations.

### 7. AI Food Logging & Precision Prompt Overhaul
- **Portion Disambiguation & USDA Linking (`GeminiMealParserService.swift`, `NaturalLanguageMealParser.swift`)**:
  - Explicitly instructed Gemini schema and prompt that all calories, macros, and sodium must represent the **TOTAL portion weight** in grams (preventing accidental division bugs).
  - Added multimodal context coupling: synthesizes photo visual portions with user text notes (cooking oils, seasonings, ingredients).
  - Automatically enriches Gemini-parsed meals with verified offline USDA micronutrients (potassium, iron, zinc, magnesium).
  - Expanded `availableModels` to include `gemini-2.0-flash` and `gemini-1.5-flash`.
  - Added 20+ common everyday food aliases to offline parser (almond milk, steak, salmon, avocado, blueberries, etc.).

### 8. Fixed In-App Update Log Decoding
- **Cleaned UpdateLog.json Structure (`UpdateLog.json`)**:
  - Fixed corrupted nested JSON in releases 1–5 where Build 6 data was erroneously duplicated inside sections arrays, enabling instant decoding of all version releases in **Settings → What's New & Update Log**.

---

## v1.3.0 — Build 6 (2026-10-27)

### 1. Un-Cramped Workout UI Redesign
- **Spacious Apple Health Workout Aesthetics (`ActiveWorkoutView.swift`)**:
  - Completely redesigned exercise cards and set rows with generous touch targets (minimum 44pt height for chalked/sweaty gym fingers).
  - Clear, distinct target buttons separating load and reps (`175 lb  ×  10  @2`) with monospaced SF Rounded typography, generous horizontal and vertical breathing room, and crisp contrast so numbers never feel squished.
  - Removed the repetitive 2-line placeholder coaching text from every exercise card, keeping cards clean and only surfacing dynamic advice when the Progression Wand detects an overload adjustment.
  - Redesigned 32x32 set type badges and 44x44 circular checkmark buttons with smooth completion feedback.
  - Added an on-the-fly **"+ Custom Exercise"** button directly inside the in-workout "Add Exercise to Session" sheet so you never have to leave an active workout to create an unlisted movement.

### 2. Proactive Reminders & Notifications Engine
- **Centralized Notification Manager (`NotificationService.swift`, `SettingsView.swift`)**:
  - Created a local notification system with dedicated controls under **Settings → Reminders & Notifications**:
    - **Daily Morning Weigh-In Reminder** (default 7:30 AM or customized) to step on the scale before breakfast and maintain trend accuracy.
    - **Meal & Nutrition Logging Reminders** (Lunch at 12:30 PM, Dinner at 7:30 PM) with a customizable schedule.
    - **Evening Missed Food Check** (8:45 PM) reminding you to close out daily food logging and mark days complete.
    - **Pre-Workout Fuel & Energy Alert** reminding you to eat carbs & protein 1.5–2 hours before scheduled workouts.

### 3. Apple Watch Rest Timer Vibration Without Companion App
- **Rest Timer Lock-Screen & Wrist Haptics (`RestTimerService.swift`)**:
  - Fixed a rest timer notification cancellation bug: stopped preemptively canceling local notifications at 0:00, allowing native iOS/watchOS notification mirroring to vibrate the Apple Watch on wrist whenever the iPhone is locked or in pocket.
  - Explains ecosystem behavior: With iPhone locked, iOS automatically forwards time-sensitive timer alerts to the Apple Watch with wrist haptic taps—no companion app required.

### 4. Live Heart Rate Tracking & In-Workout Corner Badge
- **Continuous Live Heart Rate Streaming (`HealthKitService.swift`, `ActiveWorkoutView.swift`, `TodayDashboardView.swift`)**:
  - Integrated `HKAnchoredObjectQuery` to stream real-time heart rate from any Apple Watch or Bluetooth monitor into `HealthKitService`.
  - Added a dedicated **Live Heart Rate Corner Badge (`❤️ 142 BPM`)** in `ActiveWorkoutView` toolbar and top banner that updates dynamically whether streamed from the companion app or native Apple Watch HealthKit samples.
  - Added Live / Recent Heart Rate, Resting HR, and Daily HR Range to the Today Dashboard.

### 5. Apple Health & Apple Fitness External Workouts Sync
- **External Activity Integration (`HealthKitService.swift`, `TodayDashboardView.swift`, `FoodTimelineView.swift`)**:
  - Added external `HKWorkout` importer querying all workouts logged in Apple Fitness or third-party apps (Soccer, Running, Cycling, Swimming, HIIT, Basketball, Rowing, etc.).
  - Added **Today's Apple Fitness Workouts** card on `TodayDashboardView` and inline on the `FoodTimelineView` timeline showing sport emoji, duration, active kcal burned, and completion time (display-only per Ground Rule 3).

### 6. Pre-Workout Fuel & Energy Readiness Guidance
- **Pre-Workout Fuel Warnings (`ActiveWorkoutView.swift`, `TodayDashboardView.swift`)**:
  - Integrated smart fasting detection: surfaces a warm warning banner at the top of active workouts and dashboard when you've been fasted for >3.5–4 hours before heavy training, recommending 25–40g fast-digesting carbs and protein to protect workout intensity and glycogen.

### 7. Expanded Exercise Library (+22 New Exercises)
- **118 Bundled Exercises (`BundledExercises.json`, `SeedDataService.swift`)**:
  - Added 22 missing strength, hypertrophy, and conditioning staples: Incline Cable Fly, Decline Dumbbell Press, Decline Barbell Press, Close-Grip Barbell Bench Press, Cable Y-Raise, Cable Behind-the-Back Lateral Raise, Cable Glute Kickback, Dumbbell Bulgarian Split Squat, Sissy Squat, Landmine Press, Landmine Row, Nordic Hamstring Curl, Plank, Hanging Knee Raise, Concentration Curl, Reverse Barbell Curl, Forearm Wrist Curl, Dumbbell Pullover, Outdoor Running, Soccer, Stationary Cycling, Stair Climber, and Swimming.

---

## v1.3.0 — Build 5 (2026-10-27)

### 1. MacroFactor Workouts Complete Feature Suite
- **The Progression Wand (🪄) & Dynamic Rep Range Expansion**:
  - Added the interactive **Progression Wand (🪄)** button to exercise cards in `ActiveWorkoutView` with an Apple Health diagnostic sheet (`ProgressionWandSheet.swift`).
  - Explains the scientific overload rationale with color-coded alerts: 🔵 Blue (Target reached, added load), 🟡 Yellow (Consolidating rep volume, deload, or protein gate), and 🔴 Orange (Equipment increment gap alert).
  - **Dynamic Rep Range Expansion**: Automatically detects when the smallest available weight jump in your gym profile is $\ge 12.5\%$ of working load (e.g. 5 lb dumbbell jump on a 35 lb dumbbell). Dynamically expands the target rep ceiling by +3 reps (e.g., 8–12 expands to 8–15) to build work capacity before making an oversized load jump.
- **Bilateral & Unilateral (Left / Right) Independent Logging**:
  - Extended `SetLog` with unilateral tracking (`isUnilateral`, `weightKgLeft`, `repsLeft`, `weightKgRight`, `repsRight`).
  - 1-tap "Switch to Unilateral (L / R)" toggle in the exercise card menu splits rows into independent `L:` and `R:` inputs.
  - Added dedicated Left and Right editors with a 1-tap "Copy Left to Right" convenience button in `InlineSetEditorSheet`.
- **Persistent Machine & Exercise Setup Notes**:
  - Added `machineSetupNotes` to `Exercise` and created `MachineSetupNotesSheet.swift`.
  - Pinned setup notes (e.g., *"Seat height #4, Chest pad #2, Cable notch #14, neutral grip"*) appear in a neat pill under the exercise title and persist across all current and future workouts.
- **In-Workout Exercise Swapping (Equipment Substitution)**:
  - Added `ExerciseSwapSheet.swift` and `ProgressionEngine.swapCandidates`.
  - When gym equipment or a bench is occupied, tap `...` $\rightarrow$ **Swap Exercise** to view biomechanically ranked replacements matching the exact movement pattern and muscle group (filtered by available gym equipment).
  - Swapping carries over your completed and uncompleted sets, translating equivalent target loads seamlessly.
- **Workout Change Log & Routine Commit Prompt on Finish**:
  - Created `WorkoutChangeLogSheet.swift`.
  - When finishing a workout where exercises were added, swapped, or set counts changed, Total Factor diffs the session against the parent program template and prompts: *"Update '[Program Name]' Routine for future workouts"* or *"Save for Today Only"*.
- **Bodyweight, Weighted & Assisted Exercise Support**:
  - Added `BodyweightMode` (`standardLoad`, `bodyweightOnly`, `weightedBodyweight`, `assistedBodyweight`).
  - Automatically factors in user bodyweight from morning weigh-ins for weighted dips/pull-ups (`+25 lb`) and assisted counterweights (`-40 lb`).
- **Weekly Muscle Group Hypertrophy Volume Landmarks**:
  - Created `HypertrophyVolumeEngine.swift` and `HypertrophyVolumeCardView.swift` inside `TrainHubView`.
  - Displays trailing 7-day hard sets per muscle group mapped against scientific hypertrophy landmarks: Maintenance (MV, <8 sets), Minimum Effective (MEV, 8–11 sets), Maximum Adaptive (MAV, 12–20 sets), and Maximum Recoverable (MRV, 21+ sets).
- **Expanded Set Types (Myo-reps)**:
  - Added `.myorep` (badge `"M"`, "Myo-rep") to `SetType` with support across active logging, exercise library history, and Apple Watch sync.
- **22/22 Passing SPM Unit Tests**:
  - Added 4 new automated algorithm unit tests in `TotalFactorAlgorithmTests.swift` covering rep range expansion, wand diagnostics, volume landmark classification, and swap candidate ranking.

---

## v1.2.0 — Build 4 (2026-10-27)

### 1. Apple Health & Apple Fitness Design System
- **Spacious, First-Party Apple Health Aesthetics**: Re-architected core views (`TodayDashboardView`, `FoodTimelineView`, `TrainHubView`, `ProgressHubView`) around native `.systemGroupedBackground` and `.secondarySystemGroupedBackground` card surfaces (`.appleHealthCard(padding: 16-18, cornerRadius: 20-22)`), replacing tight AI-style cards with un-cramped Apple Health and Apple Fitness layouts.
- **San Francisco Rounded Metric Typography & Apple Palette**:
  - Adopted 38pt `.system(size: 38, weight: .heavy, design: .rounded)` numbers for hero metrics (calories remaining, scale weight, and TDEE).
  - Adopted Apple's official health metric color palette (`AppleTheme`): Flame Orange (`#FF5B00` calories), Coral Pink (`#FF2D55` protein), Electric Cyan (`#00C7BE` carbs), Gold (`#FFCC00` fat), Electric Purple (`#AF52DE` training/workouts), and Teal (`#30B0C7` scale & trend weight).
  - Floating frosted-glass date switcher pill (`.ultraThinMaterial`) with smooth left/right day navigation.
- **Side-by-Side Health Telemetry & Apple Fitness Progress Bars**:
  - Replaced stacked panels with Apple Health side-by-side metric cards (Trend Weight + Metabolism TDEE) and un-cramped 2x2 health telemetry cards (Steps, Sleep, Water, Active Burn).
  - Styled daily macro targets with Apple Fitness-style rounded segmented progress bars (`AppleFitnessBar`) and clean line-item food diary entries with micro-colored macro indicators (`32P • 45C • 12F`).
  - Added smart Goal Target Date projection pill in `ProgressHubView` Weight Trend card (`🎯 Goal Target: 175.0 lb • Est. Nov 14 (3w)`).

### 2. SideStore Wireless IPA Auto-Signer Pipeline
- **SideStore `.ipa` Packaging Automation (`Scripts/build_ipa.sh`)**:
  - Built an automated build script that compiles the complete workspace (iOS app, embedded Apple Watch companion `TotalFactorWatch.app`, and embedded `TotalFactorWidgetsExtension.appex`), verifies code signatures and bundle structures, and outputs a ready-to-import `TotalFactor.ipa` directly into the iCloud Drive workspace root.
  - Enables direct import from iPhone Files into the SideStore app, allowing automatic background re-signing every 3–5 days over local Wi-Fi without needing a Mac, permanently bypassing 7-day Free Personal Team certificate expiration.

---

## v1.2.0 — Build 3 (2026-10-27)

### 1. Full 8,156-Food Offline USDA Database (Zero SwiftData Bloat)
- **8,156 Lab-Verified Whole Foods Offline**: Ingested USDA FoodData Central Foundation (`2026-04-30`) + SR Legacy (`2018-04`) bulk datasets via `Scripts/build_full_usda_bundle.py` into `TotalFactor/Resources/BundledUSDAFoods.json` (3.75 MB) with calories, macros, fiber, sugar, sodium, household serving weights, and full micronutrients (Potassium, Calcium, Iron, Vitamin D, Vitamin C, Magnesium, Zinc, Cholesterol, Saturated Fat). Also updated `USDAFoodClient` to support USDA 2026 4-digit nutrient IDs.
- **Fast Inverted Token Index & Lazy Materialization**: Built `OfflineUSDACatalogIndex` (singular/plural stemmer + inverted posting lists + deterministic UUIDs) and `OfflineUSDACatalogService` (`CatalogSearchItem`). `SeedDataService` no longer bulk-inserts USDA foods into SwiftData on launch — keeping `@Query var foods: [Food]` tiny for 120Hz scrolling — and `Food` `@Model` rows materialize lazily only on first log, favorite, or recipe ingredient selection across `QuickAddFoodSheet`, `FoodDetailSheet`, and `RecipeBuilderSheet` (deduplicated via `FoodSearchRanker.rankWithOfflineCatalog`).

### 2. Voice, Natural-Language & Meal-Photo Logging
- **"Describe / Voice" Tab & 1-Tap Mic Shortcut**: Added **Describe / Voice** (`DescribeMealView`) inside `QuickAddFoodSheet` plus a 1-tap `mic.fill` voice button directly in the Search bar (`SpeechDictationService` live `SFSpeechRecognizer` dictation).
- **100% Offline Multi-Item Parser (`NaturalLanguageMealParser`)**: Splits spoken or typed meals (e.g., *"3 eggs, 80g oats, 200g greek yogurt and 1.5 tbsp peanut butter"*), parses quantities, fractions, `g`/`oz`/`cup`/`tbsp`/`slice` units, and compound foods, and resolves matches against your personal history + all 8,156 offline USDA foods.
- **Optional Gemini Multimodal AI Text + Photo Logging (`GeminiMealParserService`)**: Configure a Gemini API key (stored securely in Keychain via `GeminiConfigStore` in `SettingsView` or inline) and pick `gemini-2.5-flash` or `gemini-2.5-pro` to analyze snapped camera photos, library photos, and/or complex restaurant meal descriptions.
- **1-Tap Multi-Item Confirmation (`MultiItemMealConfirmationSheet`)**: Preview total meal calories & macros, toggle items, nudge portions (`-25%` / `+25%` or exact grams), choose a `MealTag`, and log every item in 1 tap with automatic Apple Health sync.

### 3. Complete Phase 2–9 Spec Sweep
- **Chronological Exercise Session & Set History (`ExerciseLibraryView`)**: Every exercise guide now includes a chronological **Session & Set History** section grouped by workout (date, routine title, working volume, top `e1RM`, and every set's load × reps @ RIR + `e1RM`, with *"Show All N Sessions"* expansion) plus logged set-count badges on library rows.
- **Custom Nutrient Floor / Target / Ceiling Editor (`MicronutrientDetailSheet` & `SettingsView`)**: Expanded `MacroTargetEngine.nutrientZones` to include `Sugar`, `Vitamin C`, and `Cholesterol`, built `NutrientTargetsEditorView` and `SingleNutrientTargetEditorSheet` to customize or reset any nutrient's Floor, Target, and Ceiling (`NutrientTarget` `@Model`), and applied overrides across `TodayDashboardView` and `FoodTimelineView`.
- **Copy From Any Date, MealTag Grouping & Daily Notes (`FoodTimelineView`)**:
  - Added **Copy From Any Date...** (`CopyFromAnyDateSheet`) with a calendar date picker, optional meal filter, and macro preview before copying to the active day.
  - Added a 1-tap **Timeline vs. Grouped by Meal** toggle in the Food toolbar, inline `MealTag` pills/menus on logged entries, and `initialMealTag` support in `FoodDetailSheet`.
  - Added a **Daily Note** editor (`DailyNoteEditorSheet` + tappable preview banner) for hunger, digestion, energy, or travel notes on `DailyNote.notes`.
- **Lean Body Mass HealthKit Sync & Chart (`HealthKitService` & `ProgressHubView`)**: Added `BodyMetricType.leanBodyMass` (`lb`/`kg` unit-aware), bidirectional `.leanBodyMass` Apple Health import/export (plus Vitamin C, Magnesium, Zinc, and Cholesterol dietary sync), and a dedicated **Lean Body Mass (FFM)** Swift Charts card in `ProgressHubView`.
- **Visual Mon–Sun Schedule Strip & Interactive Weigh-In Widget (`ProgramBuilderView`, `TrainHubView` & `TotalFactorWidgets`)**: Added `WeekScheduleStripView` (read-only on program cards and `TrainHubView` + interactive weekday workout assignment in `ProgramDetailEditorView` updating Training-Day Carb Cycling live) and interactive `-` / `✓` / `+` weigh-in buttons (`WidgetNudgeWeighInIntent` & `WidgetLogWeighInIntent`) directly on the Home Screen `TrendAndWorkoutWidget`.

### 4. Apple Watch Companion (`TotalFactorWatch` on watchOS 10+)
- **Free Personal Team Compatible (`8MF8V7WZJB`)**: Added the native watchOS 10+ `TotalFactorWatch` companion target (`com.prerak.totalfactor.watchkitapp`) embedded in `TotalFactor` via `project.yml`, syncing bidirectionally over `WatchConnectivity` (`WatchSyncModels`, `PhoneWatchSyncService`, `WatchStore`) with zero paid App Group entitlements required.
- **4 Focused Wrist Tabs + Live Heart Rate**:
  - **Lift**: Start today's scheduled routine, any program workout, or a freestyle session; adjust Weight or Reps with the **Digital Crown** (or `+/-` buttons) and log sets in **1 tap** (`✓ Log Set`) with `+ Set` and `Finish`.
  - **Rest**: Circular countdown gauge with **3-2-1-Go wrist haptics**, `-15s` / `+30s` / `Skip` controls, and standalone `60s` / `90s` / `120s` / `180s` preset timers.
  - **Macros**: Glanceable remaining calories, Training/Rest Day pill, and Protein / Carbs / Fat remaining bars.
  - **Weight**: EMA Trend readout + Digital Crown wrist weigh-in synced to iPhone and Apple Health.
- **Live `HKWorkoutSession` Heart Rate (`WatchWorkoutSessionManager`)**: Keeps Total Factor Watch active on wrist raise throughout your workout and streams live BPM + display-only active kcal to an isolated `ActiveWatchHeartRateBanner` on iPhone `ActiveWorkoutView` (without re-rendering the workout scroll view).

---

## v1.1.0 — Build 2 (2026-10-27)

### 1. Fixed Vertical Scroll Lag (120Hz Smooth Scrolling)
- **Eliminated `View.body` Database & IPC Stalls**: Previously, `TodayDashboardView`, `FoodTimelineView`, `ProgressHubView`, and `ActiveWorkoutView` ran `CoachingCoordinator.evaluate` inside `body` — executing 7 full SwiftData fetches, mutating `ExpenditureEstimate` (invalidating `@Query`), and reloading WidgetKit over XPC during scroll frames. Views now read `CoachingCoordinator.cachedOrComputeDigest` in O(1) without side effects, and `SharedSnapshotStore` skips XPC reloads when snapshots haven't changed.
- **Zero-Allocation Row Rendering**:
  - Added `@Transient` decoded caches on `Exercise`, `GymProfile`, and `Food`, plus direct arithmetic macro getters on `FoodLogEntry` and a static `DateFormatter` in `DayKey.displayTitle` (removing per-row `JSONDecoder` and `DateFormatter` allocations).
  - Isolated 500ms rest-timer updates into `ActiveWorkoutMiniBar` and `ActiveRestTimerBanner`, switched active workouts to `LazyVStack` with memoized `ActiveExerciseCardView`, and cached search rankings in `QuickAddFoodSheet`.

### 2. Your Workouts & Full Strong History Pre-Loaded
- **124 Sessions & 1,214 Sets Imported Automatically**: `StrongWorkoutImportService` and `StrongCSVParser` automatically import `BundledStrongWorkouts.csv` on launch (safe and deduplicated for existing installs), fit your personal rep-endurance curve $k$ per movement, and compute chronological PRs (`e1RM`, Heaviest Load, Rep PR, Best Volume).
- **Automatic Strong Data Cleanup**: Converts `lb` loads, repairs swapped `7 lb × 140 reps` typos on Seated Row, and normalizes runaway `93h`/`238h` forgotten timers.
- **Your Custom 4-Day Routine Activated**: `ProgramGeneratorEngine.planetFitnessProgramBlueprint` seeds and activates **Planet Fitness Split** (*Push*, *Back and Biceps*, *Lower*, *Upper*) with your actual exercises, sets, and rep ranges, pre-filling your next session's suggested weights from your real history.
- **Future CSV Imports & History Browser**: Tap **Import CSV** in `TrainHubView` or `SettingsView` anytime, or tap **See All** to search all 124+ past workouts in `WorkoutHistoryListView`.

### 3. Offline Exercise Pictures & Step-by-Step How-To Guides
- **182 Offline Demo Photos Across 96 Exercises**: Packaged in `TotalFactor/Resources/ExerciseMedia/` and enriched in `BundledExercises.json`, decoded off the main thread by `ExerciseImageCache`.
- **Interactive Guides Everywhere**:
  - `ExerciseGuideContentView` includes an Animated Start ↔ Finish player + Start vs. Finish side-by-side toggle, Front & Back `TargetMuscleDiagramView`, Planet Fitness & Machine Setup card, numbered execution steps, coaching cues, and common mistakes to avoid.
  - Accessible in 1 tap via the **Guide** button on every workout in `TodayDashboardView` and `TrainHubView` (`WorkoutOverviewGuideSheet`), on every exercise card in `ActiveWorkoutView` (`ExerciseGuideSheet`), and inside `ExerciseLibraryView`.

### 4. Planet Fitness Active Gym Profile
- **Planet Fitness Auto-Configured**: `SeedDataService.makePlanetFitnessGymProfile` configures **Planet Fitness** and automatically sets it as your Active Gym (Machines, Cables with `2.5 lb` micro-stack jumps, counterbalanced `20 lb` Smith Machine carriage, `5–75 lb` Dumbbells in `5 lb` jumps, EZ-Curl Bars, Kettlebells, Bodyweight, and Bands — excluding free Olympic barbells so unavailable barbell lifts auto-swap cleanly).
- **Unit-Aware Gym Editor**: Updated `GymProfileEditorView` to display and edit weights in `lb` (or `kg` based on your unit setting).

### 5. Running Update Log, In-App "What's New", & 1-Step iPhone Updater
- **In-App Update Log**: Added **What's New & Update Log** (`UpdateLogView.swift` + `TotalFactor/Resources/UpdateLog.json`) at the top of `SettingsView`, displaying your live installed version & build (`v1.1.0 (Build 2)`) right on your iPhone.
- **Auto-Maintained Rule (`AGENTS.md`)**: Configured workspace instructions so every future change—big or small—automatically updates `UPDATES.md`, `UpdateLog.json`, `CHANGELOG.md`, and increments the build number.
- **1-Step iPhone Update Script & Signing Fix**: Added `Scripts/update_iphone.sh` to regenerate `TotalFactor.xcodeproj`, compile, and install straight onto your connected iPhone in-place (preserving all existing logged meals, weigh-ins, and workouts), and fixed `DEVELOPMENT_TEAM` in `project.yml` (`8MF8V7WZJB`) so Xcode and CLI signing work automatically without red signing errors.

---

## v1.0.0 — Build 1 (2026-10-27)

### Initial Full App Build (Phases 1–9)
- **Foundation & Sync**: 21 SwiftData `@Model` entities, local-first persistence with optional CloudKit sync, 3-step onboarding, 5-tab navigation (`Today`, `Food`, `Train`, `Progress`, `Settings`), and Apple Health integration.
- **Food Logging**: Chronological `FoodTimelineView`, Floor/Target/Ceiling `MacroZoneBar`, 2-tap `QuickAddFoodSheet`, custom inline calculator keypad, >15% Atwater discrepancy check, `RecipeBuilderSheet`, bundled USDA foods + live USDA/Open Food Facts search + barcode & Vision OCR nutrition label scanner.
- **Adaptive Coaching & Body Metrics**: EMA weight trend ($\alpha = 0.1$), rolling 14–28d dynamic expenditure engine with $\pm 100\text{ kcal}$ safety clamp, macro floor allocation, program-tied carb cycling, circumference metrics, and pose-filtered `PhotoCompareView`.
- **Smart Strength Tracker**: 1-tap `ActiveWorkoutView`, Lock Screen & Dynamic Island rest timer Live Activity, effort-adjusted `e1RM` + personal rep-endurance $k$-curve progression, 4 automatic PR types, `MuscleVolumeMapView`, Home/Lock Screen widgets, Siri Shortcuts, and CSV exports.
