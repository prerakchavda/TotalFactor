# Total Factor — Running Update Log

Every feature, performance fix, data tweak, and small polish shipped to **Total Factor** is logged here (newest at the top) and mirrored inside the app under **Settings → What's New & Update Log** (`TotalFactor/Resources/UpdateLog.json`).

> **Automatic Maintenance**: `AGENTS.md` enforces that every future update—even tiny tweaks—is appended here, synced to the in-app Update Log, and given a bumped build number so you can always check which build is installed on your iPhone.

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
