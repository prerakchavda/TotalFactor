#!/usr/bin/env bash
set -euo pipefail

# One-step script to build Total Factor and update it in-place on your connected iPhone
# (USB or same-Wi-Fi wireless debugging) WITHOUT deleting any logged meals, weigh-ins, or workouts.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_DIR"

export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
DERIVED_DATA="/tmp/TotalFactorDerivedData"

echo "1/4 Regenerating Xcode project (xcodegen)..."
if command -v xcodegen >/dev/null 2>&1; then
  xcodegen generate --quiet
fi

echo "2/4 Looking for connected physical iPhone..."
DEVICE_UDID="${1:-}"
if [[ -z "$DEVICE_UDID" ]]; then
  DEVICE_LINE="$(xcrun devicectl list devices 2>/dev/null | awk '/connected/ && /physical/ {print; exit}')"
  if [[ -z "$DEVICE_LINE" ]]; then
    echo "Could not find a connected physical iPhone."
    echo "Plug your iPhone into your Mac (or unlock it on the same Wi-Fi if wireless debugging is paired) and re-run:"
    echo "  ./Scripts/update_iphone.sh"
    exit 1
  fi
  DEVICE_UDID="$(echo "$DEVICE_LINE" | grep -Eo '[0-9A-F]{8}-[0-9A-F]{16}|[0-9A-F-]{24,}' | head -n 1)"
  echo "    Found: $DEVICE_LINE"
fi

echo "3/4 Building Total Factor for iPhone ($DEVICE_UDID)..."
if ! xcodebuild \
  -project TotalFactor.xcodeproj \
  -scheme TotalFactor \
  -configuration Debug \
  -destination "id=$DEVICE_UDID" \
  -derivedDataPath "$DERIVED_DATA" \
  build | tail -n 15; then
  echo "    Retrying with -allowProvisioningUpdates..."
  xcodebuild \
    -project TotalFactor.xcodeproj \
    -scheme TotalFactor \
    -configuration Debug \
    -destination "id=$DEVICE_UDID" \
    -derivedDataPath "$DERIVED_DATA" \
    -allowProvisioningUpdates \
    build | tail -n 15
fi

APP_PATH="$DERIVED_DATA/Build/Products/Debug-iphoneos/TotalFactor.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "Error: Built app not found at $APP_PATH"
  exit 1
fi

echo "4/4 Installing update onto iPhone (preserving existing app data)..."
xcrun devicectl device install app --device "$DEVICE_UDID" "$APP_PATH"

echo ""
echo "Done! Total Factor is updated on your iPhone."
echo "Open Total Factor -> Settings -> What's New & Update Log to verify the new build!"
