#!/bin/bash
# Build Fidget as a macOS application bundle (Swift Package Manager) and create a DMG for distribution.
#
# Environment:
#   CODESIGN_IDENTITY   signing identity (default "-" = ad-hoc)
#   DMG_FINDER_LAYOUT=1 arrange the DMG window via Finder (opens a Finder window while building)

set -euo pipefail

DEV_BUILD=false
RUN_APP=false

usage() {
    echo "Usage: $0 [-d] [-r]"
    echo "  -d    Create a development build (debug, native arch, no DMG) instead of a production build"
    echo "  -r    Run the app after building"
    exit 1
}

while getopts "dr" opt; do
    case $opt in
        d) DEV_BUILD=true ;;
        r) RUN_APP=true ;;
        *) usage ;;
    esac
done

cd "$(dirname "$0")"

VERSION="2.0.0"
APP_NAME="Fidget"
BUILD_DIR="build"
DIST_DIR="dist"
APP="$DIST_DIR/$APP_NAME.app"
SIGN_IDENTITY="${CODESIGN_IDENTITY:--}"

echo "Building $APP_NAME $VERSION as a macOS application..."

echo "Cleaning up previous build artifacts..."
rm -rf "$BUILD_DIR" "$DIST_DIR"
mkdir -p "$BUILD_DIR" "$DIST_DIR"

if [ "$DEV_BUILD" = true ]; then
    echo "Compiling (debug)..."
    swift build -c debug --product "$APP_NAME"
    BIN_DIR=$(swift build -c debug --show-bin-path)
else
    echo "Compiling (release, universal arm64 + x86_64)..."
    swift build -c release --arch arm64 --arch x86_64 --product "$APP_NAME"
    BIN_DIR=$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)
fi

echo "Assembling $APP..."
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"
cp Resources/Info.plist "$APP/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$VERSION" "$APP/Contents/Info.plist"
plutil -replace CFBundleShortVersionString -string "$VERSION" "$APP/Contents/Info.plist"
plutil -replace NSHumanReadableCopyright -string "© $(date +%Y)" "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"
cp Resources/fidget.png "$APP/Contents/Resources/fidget.png"

# Generate the app icon from fidget.png; fall back to the committed fidget.icns.
ICON_ICNS="$BUILD_DIR/fidget.icns"
ICONSET_DIR="$BUILD_DIR/fidget.iconset"
generate_icns() {
    local size
    mkdir -p "$ICONSET_DIR"
    for size in 16 32 128 256 512; do
        sips -z $size $size Resources/fidget.png --out "$ICONSET_DIR/icon_${size}x${size}.png" >/dev/null || return 1
        sips -z $((size * 2)) $((size * 2)) Resources/fidget.png --out "$ICONSET_DIR/icon_${size}x${size}@2x.png" >/dev/null || return 1
    done
    iconutil -c icns "$ICONSET_DIR" -o "$ICON_ICNS"
}
if generate_icns; then
    echo "Icon generated from Resources/fidget.png"
else
    echo "Warning: icon generation failed, using Resources/fidget.icns"
    cp Resources/fidget.icns "$ICON_ICNS"
fi
cp "$ICON_ICNS" "$APP/Contents/Resources/fidget.icns"

echo "Signing (identity: $SIGN_IDENTITY)..."
codesign --force --sign "$SIGN_IDENTITY" --timestamp=none "$APP"
codesign --verify --strict --verbose=1 "$APP"

if [ "$DEV_BUILD" = true ]; then
    echo "-------------------------------------------------------"
    echo "Development build successful! The app is located at: $APP"
    echo "For distribution, run without the -d flag."
    echo "-------------------------------------------------------"
else
    echo "Creating DMG for distribution..."
    DMG_NAME="$APP_NAME-$VERSION"
    DMG_TMP="$BUILD_DIR/$DMG_NAME-tmp.dmg"
    DMG_FINAL="$DIST_DIR/$DMG_NAME.dmg"
    STAGING="$BUILD_DIR/dmg"
    MOUNT_DIR="$BUILD_DIR/mount"

    mkdir -p "$STAGING" "$MOUNT_DIR"
    cp -R "$APP" "$STAGING/"
    ln -s /Applications "$STAGING/Applications"
    cp "$ICON_ICNS" "$STAGING/.VolumeIcon.icns"

    hdiutil create -volname "$DMG_NAME" -srcfolder "$STAGING" -ov -quiet -format UDRW "$DMG_TMP"

    if [ "${DMG_FINDER_LAYOUT:-0}" = "1" ]; then
        hdiutil attach -readwrite -noautoopen -mountpoint "$MOUNT_DIR" "$DMG_TMP" >/dev/null
    else
        hdiutil attach -readwrite -nobrowse -noautoopen -mountpoint "$MOUNT_DIR" "$DMG_TMP" >/dev/null
    fi
    trap 'hdiutil detach "$MOUNT_DIR" -force >/dev/null 2>&1 || true' EXIT

    # Show the custom volume icon.
    SetFile -a C "$MOUNT_DIR" || echo "Warning: could not set the volume icon"

    if [ "${DMG_FINDER_LAYOUT:-0}" = "1" ]; then
        echo "Arranging the DMG window via Finder..."
        osascript <<EOF || echo "Warning: Finder layout failed"
tell application "Finder"
    tell folder (POSIX file "$(cd "$MOUNT_DIR" && pwd)" as alias)
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {400, 100, 900, 450}
        set theViewOptions to the icon view options of container window
        set arrangement of theViewOptions to not arranged
        set icon size of theViewOptions to 72
        set position of item "$APP_NAME.app" of container window to {120, 180}
        set position of item "Applications" of container window to {380, 180}
        update without registering applications
        delay 2
        close
    end tell
end tell
EOF
    fi

    sync
    hdiutil detach "$MOUNT_DIR" -force >/dev/null
    trap - EXIT

    hdiutil convert "$DMG_TMP" -format UDZO -imagekey zlib-level=9 -quiet -o "$DMG_FINAL"
    rm -f "$DMG_TMP"

    # Give the DMG file itself the app icon (best effort; stored in the resource fork).
    ICON_RSRC="$BUILD_DIR/icns.rsrc"
    cp "$ICON_ICNS" "$BUILD_DIR/dmg-icon.icns"
    if sips -i "$BUILD_DIR/dmg-icon.icns" >/dev/null 2>&1 &&
        DeRez -only icns "$BUILD_DIR/dmg-icon.icns" > "$ICON_RSRC" 2>/dev/null &&
        Rez -append "$ICON_RSRC" -o "$DMG_FINAL" 2>/dev/null &&
        SetFile -a C "$DMG_FINAL" 2>/dev/null; then
        echo "Applied the app icon to the DMG file"
    else
        echo "Warning: could not apply a custom icon to the DMG file"
    fi

    echo "-------------------------------------------------------"
    echo "Build successful!"
    echo "App bundle: $APP"
    echo "DMG installer: $DMG_FINAL"
    echo "-------------------------------------------------------"
fi

if [ "$RUN_APP" = true ]; then
    echo "Starting $APP_NAME.app..."
    open "$APP"
fi
