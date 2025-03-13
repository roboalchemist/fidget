#!/bin/bash
# Script to build Fidget as a proper macOS application bundle and create a DMG for distribution

# Enable verbose output
set -x

# Parse command line arguments
DEV_BUILD=false
RUN_APP=false

usage() {
    echo "Usage: $0 [-d] [-r]"
    echo "  -d    Create development build (alias mode) instead of production build"
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

echo "Building Fidget as a macOS application..."

# Clean up previous build artifacts
echo "Cleaning up previous build artifacts..."
rm -rf build dist
rm -f setup.py
find . -name "*.pyc" -delete
find . -name "__pycache__" -type d -exec rm -rf {} +

# Install dependencies
echo "Installing dependencies..."
pip install --upgrade pip
pip install --upgrade PyQt6 py2app==0.28.6

# Make sure PyQt6 is properly installed
echo "Verifying PyQt6 installation..."
python -c "from PyQt6.QtWidgets import QApplication; print('PyQt6 is installed correctly')"

# Version number for the app and DMG
VERSION="1.0.0"

# Prepare icon paths
ICON_PNG=$(pwd)/fidget.png
ICON_ICNS=$(pwd)/fidget.icns

# Check if icon conversion tools are available
if command -v sips &> /dev/null && command -v iconutil &> /dev/null; then
    echo "Converting PNG to ICNS format for app icon..."
    
    # Create temporary iconset directory
    ICONSET_DIR="fidget.iconset"
    mkdir -p "$ICONSET_DIR"
    
    # Generate different icon sizes
    for size in 16 32 64 128 256 512; do
        # Standard resolution
        sips -z $size $size "$ICON_PNG" --out "${ICONSET_DIR}/icon_${size}x${size}.png"
        
        # High resolution (retina)
        if [ $size -le 256 ]; then
            sips -z $((size*2)) $((size*2)) "$ICON_PNG" --out "${ICONSET_DIR}/icon_${size}x${size}@2x.png"
        fi
    done
    
    # Convert iconset to icns
    iconutil -c icns "$ICONSET_DIR"
    
    # Clean up
    rm -rf "$ICONSET_DIR"
    
    echo "Icon conversion complete: $ICON_ICNS"
else
    echo "Warning: Icon conversion tools not available. Will use original PNG for icon."
    # We'll just use the PNG directly in this case
    ICON_ICNS="$ICON_PNG"
fi

# Find PyQt6 location for Qt libraries
PYQT_PATH=$(python -c "import PyQt6; print(PyQt6.__path__[0])")
QT_PATH="$PYQT_PATH/Qt6"
echo "PyQt6 path: $PYQT_PATH"
echo "Qt6 path: $QT_PATH"

# Create a simple setup.py file for py2app
echo "Creating setup.py for py2app..."
cat > setup.py << EOF
from setuptools import setup
import PyQt6

APP = ['fidget.py']
DATA_FILES = [
    ('', ['fidget.png']),
]

OPTIONS = {
    'argv_emulation': False,
    'iconfile': '$ICON_ICNS',
    'plist': {
        'LSUIElement': True,  # This makes it a menu bar app without a dock icon
        'CFBundleName': 'Fidget',
        'CFBundleDisplayName': 'Fidget',
        'CFBundleIdentifier': 'com.yourname.fidget',
        'CFBundleVersion': '$VERSION',
        'CFBundleShortVersionString': '$VERSION',
        'NSHumanReadableCopyright': '© $(date +%Y)',
    },
    'packages': ['PyQt6'],
    'includes': [
        'PyQt6',
        'PyQt6.QtCore',
        'PyQt6.QtGui',
        'PyQt6.QtWidgets',
    ],
    'frameworks': [],
    'excludes': ['matplotlib', 'numpy', 'pandas', 'scipy', 'tkinter', 'PIL'],
    'qt_plugins': ['platforms'],
    'resources': [],
}

setup(
    app=APP,
    name='Fidget',
    data_files=DATA_FILES,
    options={'py2app': OPTIONS},
    setup_requires=['py2app'],
)
EOF

if [ "$DEV_BUILD" = true ]; then
    # Development build (alias mode)
    echo "Building development (alias) app bundle..."
    python3 setup.py py2app -A
    
    if [ -d "dist/Fidget.app" ]; then
        echo "Copying Qt frameworks to app bundle..."
        # Copy specific Qt libraries if needed
        # mkdir -p dist/Fidget.app/Contents/Frameworks/
        # cp -R "$QT_PATH"/lib/*.framework dist/Fidget.app/Contents/Frameworks/
        
        echo "-------------------------------------------------------"
        echo "Development build successful! The app is located at: dist/Fidget.app"
        echo ""
        echo "This is an alias build that references the original script."
        echo "For distribution, run without the -d flag."
        echo "-------------------------------------------------------"
    else
        echo "Build failed. Check the output for errors."
        exit 1
    fi
else
    # Production build (standalone)
    echo "Building production (standalone) app bundle..."
    python3 setup.py py2app
    
    # Create DMG for distribution
    if [ -d "dist/Fidget.app" ]; then
        echo "Copying Qt frameworks to app bundle..."
        # Copy specific Qt libraries if needed
        # mkdir -p dist/Fidget.app/Contents/Frameworks/
        # cp -R "$QT_PATH"/lib/*.framework dist/Fidget.app/Contents/Frameworks/
        
        echo "Creating DMG for distribution..."
        
        # Create a temporary directory for DMG contents
        DMG_DIR=$(mktemp -d)
        DMG_NAME="Fidget-$VERSION"
        DMG_TMP="$DMG_NAME-tmp.dmg"
        DMG_FINAL="dist/$DMG_NAME.dmg"
        
        # Copy the app to the temporary directory
        cp -R "dist/Fidget.app" "$DMG_DIR/"
        
        # Create symlink to Applications folder for easy installation
        ln -s /Applications "$DMG_DIR/Applications"
        
        # Create a beautiful DMG with custom icon
        echo "Creating temporary DMG..."
        hdiutil create \
            -volname "$DMG_NAME" \
            -srcfolder "$DMG_DIR" \
            -ov \
            -quiet \
            -format UDRW \
            "$DMG_TMP"
            
        echo "Mounting temporary DMG..."
        MOUNT_DIR="/Volumes/$DMG_NAME"
        
        # Unmount if already mounted
        if [ -d "$MOUNT_DIR" ]; then
            hdiutil detach "$MOUNT_DIR" -force
        fi
        
        # Mount the temporary DMG
        hdiutil attach -readwrite -nobrowse -noautoopen "$DMG_TMP"
        
        echo "Customizing DMG appearance..."
        
        # Wait for the mount to complete
        sleep 2
        
        # Set the volume icon using the ICNS file (if available)
        if [ -f "$ICON_ICNS" ]; then
            # Copy icon to the volume
            cp "$ICON_ICNS" "$MOUNT_DIR/.VolumeIcon.icns"
            
            # Set the volume to use a custom icon
            SetFile -a C "$MOUNT_DIR"
        fi
        
        # Set volume name
        diskutil rename "$MOUNT_DIR" "$DMG_NAME"
        
        # Set window size and position
        echo '
            tell application "Finder"
                set mountPoint to POSIX file "/Volumes/'$DMG_NAME'" as alias
                tell folder mountPoint
                    open
                    set current view of container window to icon view
                    set toolbar visible of container window to false
                    set statusbar visible of container window to false
                    set the bounds of container window to {400, 100, 900, 450}
                    set theViewOptions to the icon view options of container window
                    set arrangement of theViewOptions to not arranged
                    set icon size of theViewOptions to 72
                    
                    # Position the app and Applications symlink
                    set position of item "Fidget.app" of container window to {120, 180}
                    set position of item "Applications" of container window to {380, 180}
                    
                    # Update without background image for now
                    update without registering applications
                    delay 2
                    close
                end tell
            end tell
        ' | osascript || true
        
        # Finalizing DMG
        echo "Finalizing DMG..."
        
        # Unmount the DMG
        hdiutil detach "$MOUNT_DIR" -force
        
        # Convert to compressed read-only DMG
        hdiutil convert "$DMG_TMP" \
            -format UDZO \
            -imagekey zlib-level=9 \
            -o "$DMG_FINAL"
        
        # Apply custom icon to the DMG file itself
        if [ -f "$ICON_ICNS" ]; then
            echo "Applying custom icon to the DMG file..."
            sips -i "$ICON_ICNS" >/dev/null 2>&1 || true
            DeRez -only icns "$ICON_ICNS" > /tmp/icns.rsrc
            Rez -append /tmp/icns.rsrc -o "$DMG_FINAL"
            SetFile -a C "$DMG_FINAL"
            rm -f /tmp/icns.rsrc
        fi
        
        # Clean up
        rm -rf "$DMG_DIR" "$DMG_TMP"
        
        echo "-------------------------------------------------------"
        echo "Build successful!"
        echo "App bundle: dist/Fidget.app"
        echo "DMG installer: $DMG_FINAL"
        echo "Both app and DMG use the fidget icon."
        echo "-------------------------------------------------------"
    else
        echo "Build failed. App bundle was not created."
        exit 1
    fi
fi

# Run the app if requested
if [ "$RUN_APP" = true ]; then
    echo "Starting Fidget.app..."
    open dist/Fidget.app
fi 