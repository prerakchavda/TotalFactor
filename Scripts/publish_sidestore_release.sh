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

desc = 'Apple Health Bi-Directional Sync, Universal CSV & AI Digest Export, Zero-Scale Hand Estimators, Street Food Composites & 3-Sec Ballpark Logger.'

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
    git commit -m "Total Factor v$VERSION (Build $BUILD) — Real-World & Zero-Scale Food Logging"
  else
    echo "No uncommitted git changes."
  fi

  echo ""
  echo "2. Pushing main branch to GitHub..."
  git push origin main

  echo ""
  echo "3. Creating GitHub Release v$VERSION and uploading TotalFactor.ipa..."
  read -r -d '' RELEASE_NOTES << 'EOF' || true
### Total Factor v1.5.3 (Build 12) — Apple Health Bi-Directional Sync & Real-World Food Logging

#### Apple Health Sync & Data Ownership
- **Bidirectional Apple Health Sync**: Full 2-way sync for dietary calories, protein, carbs, and fat with automatic deduplication.
- **Push Complete History**: 1-tap historical sync pushing past food logs, weigh-ins, and workouts to Apple Health.
- **Universal Data Export**: Prominent 1-tap "Export All App Data" bundle in Settings with pre-formatted Markdown AI coaching digest, full structured JSON, and universal CSVs.

#### Zero-Scale & Real-World Food Logging
- **No-Scale & Container Estimator Sheet**: Biological hand rulers (Palm of Protein ~30g P, Fist of Carbs ~1 cup, Cupped Hand of Snacks ~½ cup, Thumb of Fat ~1 tbsp) and standardized takeout container presets (Deli Pint 16 oz, Deli Quart 32 oz, 3-Compartment Box, Foil Round Tin).
- **Cultural & Street Food Composite Library**: Verified offline composite library with natural piece-count steppers for foods you cannot weigh raw: Panipuri/Golgappa (~28 kcal/pc, default 10 pieces = 280 kcal), Samosas (Standard 260 kcal vs Cocktail 90 kcal), Street Tacos (180 kcal), Steamed Dumplings/Momos (45 kcal), Sushi Rolls (320 kcal), Plain Roti (80 kcal), Roti with Ghee (110 kcal), Dal Tadka Katori (150 kcal), Chicken Biryani (320 kcal/cup), Pizza Slices (285 kcal), Chicken Wings (85 kcal), Falafel (60 kcal), Masala Dosa Set (380 kcal), Pav Bhaji (450 kcal), Chole Bhature (620 kcal), Burrito Bowl (720 kcal), and Pad Thai (650 kcal).
- **Ballpark My Meal 3-Second Quick Logger**: 3-second rapid logger for buffets, weddings, dining out, and unmeasured restaurant meals without tracking friction or diet guilt. 4 size tiers (Light Snack 300 kcal, Standard Meal 650 kcal, Hearty Restaurant 950 kcal, Feast/Buffet 1,350 kcal) + vibe modifiers (High Protein, Fried/Oily, Carb Heavy) and fine-tuning calorie stepper.

#### Voice NLP & Workflow Polish
- **Street Food & Hand-Size Offline Voice Aliases**: 2ms deterministic offline natural language parser now resolves street foods and hand proportions ("10 panipuri and 2 samosas", "2 street tacos and a handful of chips", "1 palm chicken, 1 fist rice, and 1 thumb olive oil", "deli pint of soup", "takeout container of biryani") with zero cloud API keys.
- **Unified AI Describe with The Plate**: 1-tap Add to Plate button in multi-item confirmation sheet to drop voice-described or AI-analyzed items directly into the persistent Plate tray and combine with barcode scans before logging.
- **Quick Add & Kitchen Hub Integration**: Mode 3 features prominent 1-tap launcher cards for Ballpark My Meal and No-Scale Estimator, new "Street & Bites" filter in Search, and "Composites" segment tab in Kitchen Hub.
EOF

  # Check if release already exists
  if gh release view "v$VERSION" >/dev/null 2>&1; then
    echo "Release v$VERSION already exists. Uploading new TotalFactor.ipa..."
    gh release upload "v$VERSION" "$IPA_PATH" --clobber
  else
    gh release create "v$VERSION" "$IPA_PATH" \
      --title "Total Factor v$VERSION (Build $BUILD) — Real-World & Zero-Scale Food Logging" \
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
