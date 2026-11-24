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
# SwiftPM records the deployment target (15.0) as the binary's SDK version, which makes macOS 26+ run Swft in
# compatibility mode: old small traffic lights, no Liquid Glass. Stamp the real SDK and re-sign ad hoc.
SDK_VERSION="$(xcrun --show-sdk-version)"
xcrun vtool -set-build-version macos 15.0 "$SDK_VERSION" -replace -output "$APP/Contents/MacOS/Swft" "$APP/Contents/MacOS/Swft" 2>/dev/null
codesign --force --sign - "$APP/Contents/MacOS/Swft" >/dev/null
# SwiftPM resource bundles (fonts etc.)
for b in "$BIN"/*.bundle; do [ -e "$b" ] && cp -R "$b" "$APP/Contents/Resources/"; done
cp Resources/Info.plist "$APP/Contents/Info.plist"
echo "Built $APP"
