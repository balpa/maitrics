#!/bin/bash
set -euo pipefail

CONFIG="${1:-release}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
APP_NAME="Maitrics"

echo "Building $APP_NAME ($CONFIG)..."
cd "$ROOT_DIR"
swift build -c "$CONFIG"

BIN_PATH=".build/$CONFIG/$APP_NAME"
if [ ! -f "$BIN_PATH" ]; then
    echo "Error: binary not found at $BIN_PATH"
    exit 1
fi

APP_DIR="$ROOT_DIR/dist/$APP_NAME.app/Contents"
rm -rf "$ROOT_DIR/dist/$APP_NAME.app"
mkdir -p "$APP_DIR/MacOS"
mkdir -p "$APP_DIR/Resources"

cp "$BIN_PATH" "$APP_DIR/MacOS/$APP_NAME"
cp "$ROOT_DIR/Resources/Info.plist" "$APP_DIR/Info.plist"
cp "$ROOT_DIR/Resources/Maitrics.entitlements" "$APP_DIR/Resources/"
cp "$ROOT_DIR/Resources/AppIcon.icns" "$APP_DIR/Resources/"

# Ad-hoc code sign (for local/DMG distribution)
codesign --force --sign - --entitlements "$ROOT_DIR/Resources/Maitrics.entitlements" "$ROOT_DIR/dist/$APP_NAME.app" 2>/dev/null || true

echo "Built: $ROOT_DIR/dist/$APP_NAME.app"
