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

desc = 'Instant Local Natural-Language Meal Description & 1-Tap Import Engine (\"Describe & Import\")'
try:
    with open('$PROJECT_DIR/TotalFactor/Resources/UpdateLog.json', 'r') as uf:
        u_data = json.load(uf)
        if u_data and isinstance(u_data, list):
            desc = u_data[0].get('headline', desc)
except Exception:
    pass

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
  HEADLINE="$(python3 -c "import json; print(json.load(open('$PROJECT_DIR/TotalFactor/Resources/UpdateLog.json'))[0].get('headline', 'Update'))" 2>/dev/null || echo "Update")"

  echo ""
  echo "1. Staging and committing workspace changes to git..."
  git add -A
  if ! git diff --cached --quiet; then
    git commit -m "Total Factor v$VERSION (Build $BUILD) — $HEADLINE"
  else
    echo "No uncommitted git changes."
  fi

  echo ""
  echo "2. Pushing main branch to GitHub..."
  git config http.postBuffer 524288000
  git push origin main

  echo ""
  echo "3. Creating GitHub Release v$VERSION and uploading TotalFactor.ipa..."
  RELEASE_NOTES="$(python3 -c "
with open('$PROJECT_DIR/UPDATES.md') as f:
    text = f.read()
parts = text.split('## v')
if len(parts) > 1:
    section = '## v' + parts[1].split('\n---')[0]
    print(section.strip())
else:
    print('Total Factor v$VERSION Release')
" 2>/dev/null || echo "Total Factor v$VERSION (Build $BUILD)")"

  # Check if release already exists
  if gh release view "v$VERSION" >/dev/null 2>&1; then
    echo "Release v$VERSION already exists. Uploading new TotalFactor.ipa..."
    gh release upload "v$VERSION" "$IPA_PATH" --clobber
  else
    echo "Creating GitHub Release v$VERSION..."
    gh release create "v$VERSION" \
      --title "Total Factor v$VERSION (Build $BUILD) — $HEADLINE" \
      --notes "$RELEASE_NOTES"
    echo "Uploading TotalFactor.ipa to v$VERSION..."
    gh release upload "v$VERSION" "$IPA_PATH" --clobber
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
