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

echo "Built: $ROOT_DIR/dist/$APP_NAME.app"
