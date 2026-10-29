# Total Factor — Spec Review & Engineering Decisions

This document reviews the original **Nutrition + Training App Build Spec** (`Total Factor`) across product mechanics, coaching mathematics, iOS 17+ framework constraints, and real-world gym/kitchen edge cases, and documents how each subtle trap was resolved in the codebase.

---

## 1. What Is Strongest in Your Spec

1. **Ground Rules (`§0`) are spot-on**:
   - Treating **tap count** as a primary engineering constraint (`2 taps` for repeat food, `1 tap` for a gym set) prevents the bloat that slows down most trackers.
   - Making **Apple Watch active calories strictly display-only** avoids the #1 flaw in mainstream fitness apps (double-counting wearable wrist estimates on top of observed weight change).
   - Keeping **all core coaching algorithms deterministic and rule-based** makes every target and load recommendation inspectable, offline-capable, and unit-testable.
2. **Phase 8 Combined Features (`§12`) are a genuine differentiator**:
   - Even best-in-class standalone apps (MacroFactor for nutrition + standalone strength trackers) operate in silos. Connecting **active program schedules -> isocaloric training-day carb cycling**, **deficit rate -> cut-aware progression**, and **trailing 7-day protein floor -> load progression gating** solves real coaching failure modes.
3. **Immutable `FoodLogEntry` Snapshots (`§2`)**:
   - Snapshotting nutrients at log time ensures fixing or editing a food later never rewrites past daily intake or corrupts historical adaptive expenditure.

---

## 2. Subtle Traps Caught & Solved in This Build

### A. SwiftData + CloudKit Schema Pitfalls (`§1–§2`)
Your spec notes *"all properties need defaults or be optional, no unique constraints"*. Three additional `NSPersistentCloudKitContainer` / SwiftData rules cause crashes in iOS 17+ if missed:
1. **Explicit Relationship Inverses & Optionality**: CloudKit rejects unidirectional relationships and non-optional relationships. Every `@Relationship` in `TotalFactor/Models/` is Optional with an explicit `inverse:` and paired with sorted computed helpers (e.g., `sortedWorkouts`, `sortedSlots`, `sortedSets`).
2. **Composite Arrays & Dictionaries in `@Model`**: Storing `[ServingSize]`, `[String: Double]`, `[UUID]`, or `[MuscleGroup]` directly as CoreData transformable attributes frequently fails lightweight migration or CloudKit sync in iOS 17. We store these as `Data` (`JSONEncoder`/`JSONDecoder`) behind clean typed computed properties.
3. **Free Provisioning vs. CloudKit Crash on Launch**: Signing with a Free Personal Apple ID blocks the CloudKit entitlement, which causes `ModelContainer(cloudKitDatabase: .automatic)` to throw on launch. `TotalFactorApp.swift` defaults to local persistent SQLite and attempts `.automatic` CloudKit sync only when toggled on a paid team, with graceful fallback.

### B. Timezone-Proof Calendar Day Keys (`§2, §6, §7, §8`)
Grouping food entries, `DailyNote.isComplete`, and weigh-ins by raw `Date` (`startOfDay`) shifts meals across midnight whenever you travel across timezones, corrupting which days are "complete."
- **Solution**: Every daily entity stores both an exact `timestamp: Date` and a canonical local `"YYYY-MM-DD"` `dayKey: String` (`DateDayKey.swift`).

### C. HealthKit `.food` Correlation Crash (`§3`)
Passing `HKCorrelationType(.food)` into `HKHealthStore.requestAuthorization(toShare:read:)` throws an `NSInvalidArgumentException` crash on iOS.
- **Solution**: `HealthKitService.swift` requests read/write permissions on the constituent `HKQuantityType`s (`dietaryEnergyConsumed`, `dietaryProtein`, etc.), then constructs and saves the `.food` `HKCorrelation` with `HKMetadataKeyFoodType`, recording both constituent and correlation UUIDs on `FoodLogEntry.healthKitSampleIDs` for clean edit/delete replacement.

### D. Open Food Facts Sodium Unit Trap (`§4`)
In the Open Food Facts v2 API, `sodium_100g` is reported in **grams** per 100 g (whereas USDA reports `mg`). Treating OFF `sodium_100g` as milligrams under-reports sodium by 1,000×.
- **Solution**: `OpenFoodFactsClient.swift` converts `sodium_100g * 1000` (with fallback from `salt_100g / 2.5 * 1000`) and decodes mixed string/numeric fields (`"12,5"` vs `12.5`) via `FlexibleDouble`.

### E. Adaptive Expenditure Stability & Frequency (`§8`)
1. **Update Cadence**: Running `blended(previous, raw, weight: 0.15)` on every app launch would drift multiple times in a single day. `ExpenditureEngine.computeTrajectory` computes a deterministic once-per-calendar-day trajectory from history.
2. **Week 1–2 Glycogen/Water Drop**: Early in a cut, rapid glycogen + water loss overstates energy deficit if adaptive math switches on with only 2–3 days of logs. `ExpenditureEngine` holds Mifflin-St Jeor for `<7` complete days, ramps adaptive weight smoothly across days `7–13`, and enforces the `±100 kcal` per-step clamp.
3. **High-Bodyweight / Steep-Cut Macro Floor**: At `2.0 g/kg` protein + `0.6 g/kg` fat, a heavy lifter on an aggressive cut can exceed target calories before carbs are allocated. `MacroTargetEngine` guarantees a minimum 40 g carbohydrate floor before gracefully trimming fat/protein down toward their `0.6 g/kg` and `1.6 g/kg` floors.

### F. Personal Rep Curve `k` Regularization (`§11`)
Fitting `e1RM = weight * (1 + (reps + rir) / k)` across sets that all have the same rep count (e.g., `3 × 8`) is mathematically underdetermined.
- **Solution**: `ProgressionEngine.fitPersonalRepCurveK` requires `>= 4` working sets (`RIR <= 4`) spanning at least a 4-rep spread across `[18, 50]` and applies sample-scaled Bayesian shrinkage (`0.006 / N`) toward the Epley prior `k = 30.0`.

---

## 3. Recommended Phase 9.5 Future Additions
- **watchOS Companion Target**: The shared `SharedSnapshotStore` and `RestTimerAttributes` are already isolated in `Shared/`, making a watchOS `WKExtension` straightforward once you're ready to log sets from the wrist.
- **Full 8,000-Item USDA Bulk Bundle**: We shipped 78 lab-verified high-frequency whole foods in `BundledUSDAFoods.json` so repo size stays nimble, plus `Scripts/build_full_usda_bundle.py` to compile the full ~8,000 USDA Foundation + SR Legacy bulk JSON release into the exact same bundle file whenever desired.
