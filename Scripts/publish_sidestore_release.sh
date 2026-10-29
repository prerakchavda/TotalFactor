#!/usr/bin/env bash
set -euo pipefail

# Scripts/publish_sidestore_release.sh
# Builds TotalFactor.ipa, updates the SideStore community source manifest (source.json)
# with the exact version, date, byte size, and release description, commits & pushes to GitHub,
# and creates a GitHub Release so your SideStore app receives an over-the-air "UPDATE" badge!

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_DIR"

DO_PUSH=false
SKIP_BUILD=false

for arg in "$@"; do
  case "$arg" in
    --push) DO_PUSH=true ;;
    --skip-build) SKIP_BUILD=true ;;
    --help|-h)
      echo "Usage: $0 [--push] [--skip-build]"
      echo "  --push:       Commit, git push to main, and upload release to GitHub via 'gh release create'"
      echo "  --skip-build: Use existing TotalFactor.ipa without rebuilding"
      exit 0
      ;;
  esac
done

echo "==============================================="
echo " Total Factor — SideStore Release Publisher"
echo "==============================================="

# 1. Package the fresh .ipa (if not skipped)
if [[ "$SKIP_BUILD" != "true" || ! -f "$PROJECT_DIR/TotalFactor.ipa" ]]; then
  ./Scripts/build_ipa.sh
fi

IPA_PATH="$PROJECT_DIR/TotalFactor.ipa"
SOURCE_JSON="$PROJECT_DIR/TotalFactor/Resources/SideStore/source.json"
INFO_PLIST="$PROJECT_DIR/TotalFactor/Resources/Info.plist"

VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$INFO_PLIST" 2>/dev/null || echo "1.5.1")"
BUILD="$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$INFO_PLIST" 2>/dev/null || echo "10")"
FILE_SIZE="$(stat -f%z "$IPA_PATH")"
TODAY="$(date +%Y-%m-%d)"

echo ""
echo "Updating SideStore source.json manifest..."
python3 -c "
import json

source_path = '$SOURCE_JSON'
with open(source_path, 'r') as f:
    data = json.load(f)

desc = 'Kitchen Rehaul & Workout UI Bug Fixes: The Plate multi-add dock, hourly timeline, adherence strip, recipe explosion, and workout pause/discard fixes.'

for app in data.get('apps', []):
    if app.get('bundleIdentifier') == 'com.prerak.totalfactor':
        app['version'] = '$VERSION'
        app['versionDate'] = '$TODAY'
        app['versionDescription'] = desc
        app['size'] = int('$FILE_SIZE')
        app['downloadURL'] = f'https://github.com/prerakchavda/TotalFactor/releases/download/v$VERSION/TotalFactor.ipa'

news_list = data.get('news', [])
news_id = 'v$VERSION-release'
if not any(n.get('identifier') == news_id for n in news_list):
    news_list.insert(0, {
        'title': f'Total Factor v$VERSION Released!',
        'identifier': news_id,
        'caption': desc,
        'date': '$TODAY',
        'appID': 'com.prerak.totalfactor'
    })
data['news'] = news_list

with open(source_path, 'w') as f:
    json.dump(data, f, indent=2)

print('✓ Updated source.json to v$VERSION (Build $BUILD, $FILE_SIZE bytes)')
"

echo ""
echo "==============================================="
echo " Manifest: $SOURCE_JSON"
echo " IPA:      $IPA_PATH ($((FILE_SIZE / 1024 / 1024)) MB)"
echo "==============================================="

if [[ "$DO_PUSH" == "true" ]]; then
  echo ""
  echo "1. Staging and committing workspace changes to git..."
  git add -A
  if ! git diff --cached --quiet; then
    git commit -m "Total Factor v$VERSION (Build $BUILD) — Kitchen Rehaul & Workout UI Bug Fixes"
  else
    echo "No uncommitted git changes."
  fi

  echo ""
  echo "2. Pushing main branch to GitHub..."
  git push origin main

  echo ""
  echo "3. Creating GitHub Release v$VERSION and uploading TotalFactor.ipa..."
  RELEASE_NOTES=$(cat << 'EOF'
### Total Factor v1.5.1 (Build 10) — Kitchen Rehaul & Workout UI Bug Fixes

#### Kitchen Rehaul & Food Logging
- **The Plate Multi-Add Workspace**: Persistent floating dock to stage multiple foods while searching or browsing without logging one-by-one. Dedicated workspace sheet for batch gram adjustments, unit conversions, and bulk committing.
- **Hour-by-Hour Timeline Mode**: Hourly food logging view mode with macro subtotals, inline '+' buttons, left-handed mode, and collapsible empty hours.
- **7-Day Adherence Calendar Strip**: Weekly circular calorie target rings atop the food log with 1-tap fast day switching.
- **Remaining vs. Consumed Budget Toggle**: 1-tap switcher between consumed intake and remaining daily allowance.
- **Kitchen Hub**: Centralized manager consolidating Recipes, Saved Meals, and Custom Foods, with moisture loss & water absorption yields.
- **Explode Recipe to Ingredients**: Unpack logged recipes from the timeline into constituent items scaled to portion eaten.
- **Food Detail Polish**: Macro Calorie Ratio Donut, Daily Goal Impact Bar, subtractive kitchen-scale tare math (245 - 65 = 180 g), and micronutrient accordion preview.

#### Workout UI & Stability Bug Fixes
- **Action Pill Typography Fix**: Replaced cramped horizontal container with a smooth scrollable strip, preventing labels like Wand, Warm Up, and Note from breaking awkwardly into two lines.
- **Exercise Carousel Polish**: Expanded exercise title labels from 58pt to 72pt with 2-line wrapping to eliminate aggressive ellipsis truncation.
- **Pause & Resume Workout**: Freeze elapsed workout duration with live amber PAUSED badge across the header and RootTabView mini-bar.
- **Confirmed Discard Session**: Cascade deletion of draft sets, session state, rest timer Live Activities, and active session reset.
EOF
)

  # Check if release already exists
  if gh release view "v$VERSION" >/dev/null 2>&1; then
    echo "Release v$VERSION already exists. Uploading new TotalFactor.ipa..."
    gh release upload "v$VERSION" "$IPA_PATH" --clobber
  else
    gh release create "v$VERSION" "$IPA_PATH" \
      --title "Total Factor v$VERSION (Build $BUILD) — Kitchen Rehaul & Workout UI Fixes" \
      --notes "$RELEASE_NOTES"
  fi

  echo ""
  echo "==============================================="
  echo " ✓ PUBLISHED TO SIDESTORE SUCCESSFULLY!"
  echo "==============================================="
  echo "Your community source is live at:"
  echo "https://raw.githubusercontent.com/prerakchavda/TotalFactor/main/TotalFactor/Resources/SideStore/source.json"
  echo ""
  echo "How to get it in SideStore on your iPhone:"
  echo "1. Open SideStore on your iPhone."
  echo "2. Go to the 'Sources' tab and pull-down to refresh (or tap refresh icon)."
  echo "3. Go to 'Apps' or 'Browse' tab -> Total Factor."
  echo "4. You will see the new 'UPDATE' button (v$VERSION)."
  echo "5. Tap 'UPDATE' — SideStore downloads the .ipa directly from your GitHub Release"
  echo "   and signs/installs it in-place over Wi-Fi without losing your data!"
  echo "==============================================="
else
  echo ""
  echo "To push this release live to GitHub so SideStore receives the update:"
  echo "  ./Scripts/publish_sidestore_release.sh --push --skip-build"
fi
