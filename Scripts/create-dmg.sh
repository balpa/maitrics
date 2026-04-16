#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
APP_NAME="Maitrics"
VERSION="${1:-0.1.0}"
VOL_NAME="$APP_NAME"

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

# Eject any existing volume with the same name
hdiutil detach "/Volumes/$VOL_NAME" 2>/dev/null || true
sleep 1

echo "Creating DMG..."
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"
cp -R "$APP_PATH" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

# Create read-write DMG
rm -f "$TMP_DMG" "$DMG_PATH"
hdiutil create \
    -volname "$VOL_NAME" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDRW \
    -size 10m \
    "$TMP_DMG"

# Mount read-write
DEVICE=$(hdiutil attach -readwrite -noverify -noautoopen "$TMP_DMG" | grep "Apple_APFS\|Apple_HFS" | head -1 | awk '{print $1}')
echo "Mounted device: $DEVICE"
sleep 2

# Set Finder view options via AppleScript
echo "Setting Finder window layout..."
osascript <<EOF
tell application "Finder"
    tell disk "$VOL_NAME"
        open
        delay 1
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set bounds of container window to {200, 120, 740, 440}
        set theViewOptions to the icon view options of container window
        set arrangement of theViewOptions to not arranged
        set icon size of theViewOptions to 100
        set position of item "$APP_NAME.app" of container window to {130, 150}
        set position of item "Applications" of container window to {400, 150}
        update without registering applications
        delay 1
        close
    end tell
end tell
EOF

# Set volume icon
if [ -f "$ROOT_DIR/Resources/AppIcon.icns" ]; then
    cp "$ROOT_DIR/Resources/AppIcon.icns" "/Volumes/$VOL_NAME/.VolumeIcon.icns"
    SetFile -c icnC "/Volumes/$VOL_NAME/.VolumeIcon.icns" 2>/dev/null || true
    SetFile -a C "/Volumes/$VOL_NAME" 2>/dev/null || true
fi

# Make sure .DS_Store is flushed
sync
sleep 2

# Verify DS_Store was created
if [ -f "/Volumes/$VOL_NAME/.DS_Store" ]; then
    echo "DS_Store created successfully"
else
    echo "Warning: DS_Store not found, Finder window may not auto-open"
fi

hdiutil detach "$DEVICE"
sleep 1

# Convert to compressed read-only DMG
hdiutil convert "$TMP_DMG" -format UDZO -o "$DMG_PATH"
rm -f "$TMP_DMG"
rm -rf "$STAGING_DIR"

echo ""
echo "Created: $DMG_PATH"
echo "Size: $(du -h "$DMG_PATH" | cut -f1)"
