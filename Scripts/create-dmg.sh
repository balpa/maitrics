#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
APP_NAME="Maitrics"
VERSION="${1:-0.1.0}"

echo "Building release..."
"$SCRIPT_DIR/build-app.sh" release

APP_PATH="$ROOT_DIR/dist/$APP_NAME.app"
DMG_NAME="$APP_NAME-$VERSION.dmg"
DMG_PATH="$ROOT_DIR/dist/$DMG_NAME"
STAGING_DIR="$ROOT_DIR/dist/dmg-staging"
TMP_DMG="$ROOT_DIR/dist/tmp-$APP_NAME.dmg"

if [ ! -d "$APP_PATH" ]; then
    echo "Error: $APP_PATH not found"
    exit 1
fi

echo "Creating DMG..."
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"

cp -R "$APP_PATH" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

# Create a read-write DMG first so we can set Finder view options
rm -f "$TMP_DMG" "$DMG_PATH"
hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDRW \
    "$TMP_DMG"

# Mount it and configure the Finder window
MOUNT_DIR=$(hdiutil attach -readwrite -noverify "$TMP_DMG" | grep "/Volumes/" | sed 's/.*\/Volumes/\/Volumes/')
echo "Mounted at: $MOUNT_DIR"

# Set Finder window properties via AppleScript
osascript <<APPLESCRIPT
tell application "Finder"
    tell disk "$APP_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set bounds of container window to {200, 200, 720, 480}
        set theViewOptions to the icon view options of container window
        set arrangement of theViewOptions to not arranged
        set icon size of theViewOptions to 96
        set background color of theViewOptions to {14906, 14906, 14906}
        set position of item "$APP_NAME.app" of container window to {140, 130}
        set position of item "Applications" of container window to {380, 130}
        close
        open
        update without registering applications
        delay 1
        close
    end tell
end tell
APPLESCRIPT

# Set the volume icon
if [ -f "$ROOT_DIR/Resources/AppIcon.icns" ]; then
    cp "$ROOT_DIR/Resources/AppIcon.icns" "$MOUNT_DIR/.VolumeIcon.icns"
    SetFile -c icnC "$MOUNT_DIR/.VolumeIcon.icns" 2>/dev/null || true
    SetFile -a C "$MOUNT_DIR" 2>/dev/null || true
fi

sync
hdiutil detach "$MOUNT_DIR"

# Convert to compressed read-only DMG
hdiutil convert "$TMP_DMG" -format UDZO -o "$DMG_PATH"
rm -f "$TMP_DMG"
rm -rf "$STAGING_DIR"

echo "Created: $DMG_PATH"
echo "Size: $(du -h "$DMG_PATH" | cut -f1)"
