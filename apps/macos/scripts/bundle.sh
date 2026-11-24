#!/usr/bin/env bash
# Build Swft and wrap the executable in a runnable .app bundle at apps/macos/build/Swft.app
set -euo pipefail
cd "$(dirname "$0")/.."
CONFIG="${1:-debug}"
swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)"
APP="build/Swft.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/Swft" "$APP/Contents/MacOS/Swft"
# SwiftPM resource bundles (fonts etc.)
for b in "$BIN"/*.bundle; do [ -e "$b" ] && cp -R "$b" "$APP/Contents/Resources/"; done
cp Resources/Info.plist "$APP/Contents/Info.plist"
echo "Built $APP"
