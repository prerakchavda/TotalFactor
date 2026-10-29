#!/usr/bin/env bash
set -euo pipefail

# Scripts/build_ipa.sh
# Packages Total Factor into a standards-compliant TotalFactor.ipa in your iCloud Drive workspace
# so the SideStore app on your iPhone can install and perpetually re-sign it wirelessly over Wi-Fi.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_DIR"

export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
DERIVED_DATA="/tmp/TotalFactorDerivedData"
STAGING_DIR="/tmp/TotalFactorIPAStaging"
IPA_DEST="$PROJECT_DIR/TotalFactor.ipa"

echo "==============================================="
echo " Total Factor — SideStore .ipa Packager"
echo "==============================================="

echo "1/4 Regenerating Xcode project (xcodegen)..."
if command -v xcodegen >/dev/null 2>&1; then
  xcodegen generate --quiet
fi

echo "2/4 Compiling Total Factor workspace (iOS + Watch + Widgets)..."
xcodebuild \
  -project TotalFactor.xcodeproj \
  -scheme TotalFactor \
  -configuration Debug \
  -destination "generic/platform=iOS" \
  -derivedDataPath "$DERIVED_DATA" \
  build | tail -n 15

APP_PATH="$DERIVED_DATA/Build/Products/Debug-iphoneos/TotalFactor.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "Error: Built app not found at $APP_PATH"
  exit 1
fi

echo "3/4 Verifying embedded watchOS and WidgetKit extensions..."
if [[ -d "$APP_PATH/Watch/TotalFactorWatch.app" ]]; then
  echo "    ✓ Embedded Apple Watch Companion verified"
fi
if [[ -d "$APP_PATH/PlugIns/TotalFactorWidgetsExtension.appex" ]]; then
  echo "    ✓ Embedded WidgetKit Extension verified"
fi

echo "4/4 Packaging Payload into TotalFactor.ipa..."
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR/Payload"
cp -R "$APP_PATH" "$STAGING_DIR/Payload/"

# Clean up bundles and artifacts that cause SideStore / AltSign to fail:
# 1. Strip test bundles and dSYM folders from PlugIns and root (causes "The app's Info.plist could not be found.")
rm -rf "$STAGING_DIR/Payload/TotalFactor.app/PlugIns/"*.xctest*
rm -rf "$STAGING_DIR/Payload/TotalFactor.app/PlugIns/"*.dSYM*
rm -rf "$STAGING_DIR/Payload/TotalFactor.app/"*.dSYM*

# 2. Strip watchOS companion app (SideStore only signs iOS bundles; watch apps require devicectl / paid team certs)
rm -rf "$STAGING_DIR/Payload/TotalFactor.app/Watch"

# 3. Strip preview dylibs
rm -f "$STAGING_DIR/Payload/TotalFactor.app/__preview.dylib"
rm -f "$STAGING_DIR/Payload/TotalFactor.app/PlugIns/TotalFactorWidgetsExtension.appex/__preview.dylib" 2>/dev/null || true

rm -f "$IPA_DEST"
(cd "$STAGING_DIR" && zip -qry "$IPA_DEST" Payload)
rm -rf "$STAGING_DIR"

FILE_SIZE="$(ls -lh "$IPA_DEST" | awk '{print $5}')"

echo ""
echo "==============================================="
echo " ✓ TotalFactor.ipa created successfully! ($FILE_SIZE)"
echo " Saved to: $IPA_DEST"
echo "==============================================="
echo ""
echo "How to install & auto-refresh with SideStore on your iPhone:"
echo " 1. Open the SideStore app on your iPhone."
echo " 2. Ensure your SideStore WireGuard VPN is active."
echo " 3. Tap '+' (top left) in the 'My Apps' tab."
echo " 4. Navigate to iCloud Drive -> Total Factor -> TotalFactor.ipa."
echo " 5. SideStore installs Total Factor and perpetually re-signs"
echo "    it in the background every 3–5 days over your local Wi-Fi!"
echo "==============================================="
