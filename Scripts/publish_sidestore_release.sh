#!/usr/bin/env bash
set -euo pipefail

# Scripts/publish_sidestore_release.sh
# Builds TotalFactor.ipa and updates the SideStore community source manifest (source.json)
# with the exact version, date, byte size, and release description so anyone with your
# SideStore source gets an automatic over-the-air "UPDATE" badge!

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_DIR"

echo "==============================================="
echo " Total Factor — SideStore Remote Release Builder"
echo "==============================================="

# 1. Package the fresh .ipa
./Scripts/build_ipa.sh

IPA_PATH="$PROJECT_DIR/TotalFactor.ipa"
SOURCE_JSON="$PROJECT_DIR/TotalFactor/Resources/SideStore/source.json"
INFO_PLIST="$PROJECT_DIR/TotalFactor/Resources/Info.plist"

VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$INFO_PLIST" 2>/dev/null || echo "1.5.0")"
BUILD="$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$INFO_PLIST" 2>/dev/null || echo "9")"
FILE_SIZE="$(stat -f%z "$IPA_PATH")"
TODAY="$(date +%Y-%m-%d)"

echo ""
echo "Updating SideStore source.json..."
python3 -c "
import json

source_path = '$SOURCE_JSON'
with open(source_path, 'r') as f:
    data = json.load(f)

for app in data.get('apps', []):
    if app.get('bundleIdentifier') == 'com.prerak.totalfactor':
        app['version'] = '$VERSION'
        app['versionDate'] = '$TODAY'
        app['size'] = int('$FILE_SIZE')
        app['downloadURL'] = f'https://github.com/prerakchavda/TotalFactor/releases/download/v$VERSION/TotalFactor.ipa'

with open(source_path, 'w') as f:
    json.dump(data, f, indent=2)

print('✓ Updated source.json to v$VERSION (Build $BUILD, $FILE_SIZE bytes)')
"

echo ""
echo "==============================================="
echo " ✓ Remote Release Package Ready!"
echo " Manifest: $SOURCE_JSON"
echo " IPA:      $IPA_PATH ($((FILE_SIZE / 1024 / 1024)) MB)"
echo "==============================================="
echo ""
echo "How remote distribution works for your friends & testers:"
echo " 1. Push source.json and upload TotalFactor.ipa to your GitHub repository."
echo " 2. Anyone with SideStore opens SideStore -> Sources -> '+' -> enters:"
echo "    https://raw.githubusercontent.com/<YOUR_GITHUB_USER>/<REPO>/main/TotalFactor/Resources/SideStore/source.json"
echo " 3. Total Factor will appear under their SideStore Browse tab."
echo " 4. Whenever you publish an update, SideStore will display an 'UPDATE' badge"
echo "    and your friends can update remotely over Wi-Fi with 1 tap!"
echo "==============================================="
