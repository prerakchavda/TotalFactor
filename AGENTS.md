# Total Factor — Workspace Rules & Agent Guidelines

## 1. Mandatory Update Log Rule ("Keep Up With Every Little Update")
Whenever you make **any** change to Total Factor — whether a major feature, bug fix, performance tweak, data adjustment, or tiny UI polish — you **MUST** do all of the following before completing your turn:

1. **Log it in `UPDATES.md`**: Add a concise, clear bullet under the top build section (or create a new build section at the top if bumping the build) describing every little thing that changed. Never skip small tweaks.
2. **Sync the In-App Update Log (`TotalFactor/Resources/UpdateLog.json`)**: Add the matching item(s) to `TotalFactor/Resources/UpdateLog.json` so **Settings → What's New & Update Log** inside the iOS app always matches `UPDATES.md`.
3. **Update `CHANGELOG.md`**: Keep `CHANGELOG.md` aligned for versioned engineering history.
4. **Bump the Build Number Together**: Increment `CFBundleVersion` (and `CFBundleShortVersionString` when appropriate) identically across **all three**:
   - `TotalFactor/Resources/Info.plist`
   - `TotalFactorWidgets/Info.plist`
   - `TotalFactorWatch/Info.plist`
   *(iOS & watchOS require the main app, embedded WidgetKit extension, and embedded Watch companion versions and build numbers to match.)*

## 2. Xcode Project & Build Hygiene
- `TotalFactor.xcodeproj` is generated from `project.yml` via **XcodeGen**. Whenever files or bundled resources are added, renamed, or deleted, run:
  ```bash
  xcodegen generate
  ```
- Note on macOS CLI developer tools: Command Line Tools may be selected globally (`/Library/Developer/CommandLineTools`). Prefix Xcode CLI invocations with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` (or use `./Scripts/update_iphone.sh`), and place `-derivedDataPath` outside iCloud Drive (e.g., `/tmp/TotalFactorDerivedData`) to avoid iCloud extended-attribute codesigning errors.
- **Updating the User's iPhone**: Never instruct the user to delete the existing app before updating (deleting wipes local SwiftData meals/weigh-ins/workouts). Always install **in-place** over `com.prerak.totalfactor` (Team `8MF8V7WZJB`) via `./Scripts/update_iphone.sh` or Xcode **`Cmd + R`**.
