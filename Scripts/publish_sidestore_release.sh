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

desc = 'HealthKit External Nutrition Sync Engine: Zero-duplicate ingestion, multi-app attribution (MacroFactor, MyFitnessPal, Cronometer), bi-directional deletion reconciliation, and auto meal slotting.'

for app in data.get('apps', []):
    if app.get('bundleIdentifier') == 'com.prerak.totalfactor':
        app['version'] = '$VERSION'
        app['versionDate'] = '$TODAY'
        app['versionDescription'] = desc
        app['size'] = int('$FILE_SIZE')
        app['downloadURL'] = f'https://github.com/prerakchavda/TotalFactor/releases/download/v$VERSION/TotalFactor.ipa'

        # Update or prepend versions array
        versions = app.get('versions', [])
        ver_entry = next((v for v in versions if v.get('version') == '$VERSION'), None)
        if ver_entry:
            ver_entry['date'] = '$TODAY'
            ver_entry['size'] = int('$FILE_SIZE')
            ver_entry['localizedDescription'] = desc
            ver_entry['downloadURL'] = f'https://github.com/prerakchavda/TotalFactor/releases/download/v$VERSION/TotalFactor.ipa'
        else:
            versions.insert(0, {
                'version': '$VERSION',
                'date': '$TODAY',
                'localizedDescription': desc,
                'downloadURL': f'https://github.com/prerakchavda/TotalFactor/releases/download/v$VERSION/TotalFactor.ipa',
                'size': int('$FILE_SIZE'),
                'minOSVersion': '17.0'
            })
        app['versions'] = versions

news_list = data.get('news', [])
news_id = 'v$VERSION-release'
existing_news = next((n for n in news_list if n.get('identifier') == news_id), None)
if existing_news:
    existing_news['title'] = f'Total Factor v$VERSION Released!'
    existing_news['caption'] = desc
    existing_news['date'] = '$TODAY'
    existing_news['tintColor'] = 'FF5B00'
    existing_news['imageURL'] = 'https://raw.githubusercontent.com/prerakchavda/TotalFactor/main/TotalFactor/Resources/SideStore/banner.png'
    existing_news['notify'] = True
    existing_news['appID'] = 'com.prerak.totalfactor'
else:
    news_list.insert(0, {
        'title': f'Total Factor v$VERSION Released!',
        'identifier': news_id,
        'caption': desc,
        'date': '$TODAY',
        'tintColor': 'FF5B00',
        'imageURL': 'https://raw.githubusercontent.com/prerakchavda/TotalFactor/main/TotalFactor/Resources/SideStore/banner.png',
        'notify': True,
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
    git commit -m "Total Factor v$VERSION (Build $BUILD) — Real-World & Zero-Scale Food Logging"
  else
    echo "No uncommitted git changes."
  fi

  echo ""
  echo "2. Pushing main branch to GitHub..."
  git config http.postBuffer 524288000
  git push origin main

  echo ""
  echo "3. Creating GitHub Release v$VERSION and uploading TotalFactor.ipa..."
  read -r -d '' RELEASE_NOTES << 'EOF' || true
### Total Factor v1.5.5 (Build 14) — HealthKit External Nutrition Sync Engine & Bug Fixes

#### Multi-App External Nutrition Ingestion Engine
- **Zero-Duplicate Ingestion**: Fixed a HealthKit collision where meals logged in external apps (MacroFactor, MyFitnessPal, Cronometer, Lose It) via HKCorrelationType.food were imported twice.
- **Child Sample Blacklisting**: Harvests all child quantity sample UUIDs from correlations to prevent double-counting in standalone energy queries.
- **Bi-Directional Deletion Reconciliation**: Deleting or editing foods in MacroFactor, MyFitnessPal, or Apple Health automatically prunes or updates the entry in Total Factor on next sync.
- **Dynamic App Attribution**: Detects external source app names (MacroFactor, MyFitnessPal, Cronometer, Lose It) and assigns proper brand tags.
- **Natural Title Synthesis**: Keeps specific food names when available, or formats clean meal titles (e.g. 'MacroFactor Lunch') for hourly/aggregated sync blocks.

#### Timeline & User Controls
- **Auto Time-Slotting**: External meals automatically slot into Breakfast, Lunch, Dinner, or Snack based on timestamp rather than landing in untagged space.
- **Themed Provenance Badges**: FoodSourceBadge displays custom app pills (e.g. 'MacroFactor', 'MyFitnessPal') in themed pink styling on timeline cards and hour-by-hour views.
- **Loop Protection**: Strict safeguards prevent Total Factor from ever re-exporting third-party imported meals back to HealthKit.
- **Safety Maintenance Tool**: Added 1-tap 'Remove All Imported HealthKit Meals' in Settings to safely wipe external entries with zero risk to locally logged foods.
EOF

  # Check if release already exists
  if gh release view "v$VERSION" >/dev/null 2>&1; then
    echo "Release v$VERSION already exists. Uploading new TotalFactor.ipa..."
    gh release upload "v$VERSION" "$IPA_PATH" --clobber
  else
    gh release create "v$VERSION" "$IPA_PATH" \
      --title "Total Factor v$VERSION (Build $BUILD) — HealthKit External Nutrition Sync Engine & Bug Fixes" \
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
