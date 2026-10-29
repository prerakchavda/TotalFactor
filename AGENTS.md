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

## 3. SideStore Release & OTA Distribution ("Push to SideStore")
Whenever the user asks to push to SideStore (e.g. `"push to sidestore"`, `"pus to side store"`):
1. **Automated Pipeline**: Run `./Scripts/publish_sidestore_release.sh --push`.
   - It invokes `./Scripts/build_ipa.sh` to package a clean `TotalFactor.ipa` in the workspace root.
   - It inspects `Info.plist` for `CFBundleShortVersionString` and `CFBundleVersion`, updates `TotalFactor/Resources/SideStore/source.json` with the exact file size, version, and download URL.
   - It commits all files, pushes `main` to GitHub, and publishes/updates the GitHub Release with `TotalFactor.ipa` via the `gh` CLI.
2. **Build Isolation & Lock Prevention**:
   - `build_ipa.sh` uses a dedicated derived data path (`/tmp/TotalFactorDerivedData_SideStoreBuild`) to prevent `build.db` SQLite locking collisions with active Xcode IDE instances or `SWBBuildService`.
   - `publish_sidestore_release.sh` ensures `git config http.postBuffer 524288000` is set to prevent `curl 55 Send failure: Broken pipe` on large asset pushes.
3. **No-Data-Loss In-Place OTA Instructions**:
   - Never instruct the user to uninstall/delete the app.
   - Guide the user:
     1. Open **SideStore** on the iPhone with WireGuard VPN active.
     2. Pull down to refresh the **Sources** tab.
     3. Go to the **Apps** or **Browse** tab -> **Total Factor**.
     4. Tap **UPDATE** (installs in-place over the existing data store wirelessly).
