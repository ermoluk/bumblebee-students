#!/bin/bash
# Build the Bumblebee GCS native macOS app and assemble it into a .app bundle.
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Bumblebee GCS"
CONFIG="${1:-release}"

echo "==> swift build ($CONFIG)"
swift build -c "$CONFIG"
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"
BIN="$BIN_DIR/GCSApp"

APP="build/${APP_NAME}.app"
echo "==> assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/GCSApp"
cp Info.plist "$APP/Contents/Info.plist"

# Bundle the SwiftPM resource bundle (AppIcon.png etc.) so Bundle.module resolves
# at runtime, and place the .icns for the Finder/Dock icon.
for b in "$BIN_DIR"/*.bundle; do
  [ -e "$b" ] && cp -R "$b" "$APP/Contents/Resources/"
done
cp Sources/GCSApp/Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Ad-hoc sign so it launches without a quarantine/Gatekeeper hard stop.
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true

echo "==> done: $APP"
echo "    run with:  open \"$APP\"   (or: \"$APP/Contents/MacOS/GCSApp\")"
