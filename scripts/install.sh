#!/bin/zsh
# Build Foreman in Release, install it into /Applications (ad hoc signed) and relaunch it.
# Usage: scripts/install.sh [folder to open]   (default: no folder)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED="$ROOT/DerivedData"
APP="$DERIVED/Build/Products/Release/Foreman.app"
DEST="/Applications/Foreman.app"

echo "-- building Release"
xcodebuild build -scheme Foreman -destination 'platform=macOS' -configuration Release \
  CODE_SIGNING_ALLOWED=NO -skipPackagePluginValidation -derivedDataPath "$DERIVED" -quiet

echo "-- installing to $DEST"
pkill -x Foreman || true
while pgrep -x Foreman >/dev/null; do sleep 0.5; done
rm -rf "$DEST"
cp -R "$APP" "$DEST"
codesign --force --deep --sign - "$DEST"

echo "-- launching"
sleep 2
open -a "$DEST" "$@"
