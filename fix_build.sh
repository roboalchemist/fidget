#!/bin/bash
# Fix script for building Fidget app with PyQt6

# Enable verbose output
set -x

echo "Creating a clean build environment for Fidget..."

# Create a temporary directory for our build
TEMP_DIR=$(mktemp -d)
echo "Building in temporary directory: $TEMP_DIR"

# Copy the necessary files to the temp directory
cp fidget.py "$TEMP_DIR/"
cp fidget.png "$TEMP_DIR/"
cp -r venv "$TEMP_DIR/"

# Change to the temp directory
cd "$TEMP_DIR"

# Convert PNG to ICNS
echo "Converting PNG to ICNS..."
mkdir -p icon.iconset
sips -z 16 16 fidget.png --out icon.iconset/icon_16x16.png
sips -z 32 32 fidget.png --out icon.iconset/icon_16x16@2x.png
sips -z 32 32 fidget.png --out icon.iconset/icon_32x32.png
sips -z 64 64 fidget.png --out icon.iconset/icon_32x32@2x.png
sips -z 128 128 fidget.png --out icon.iconset/icon_128x128.png
sips -z 256 256 fidget.png --out icon.iconset/icon_128x128@2x.png
sips -z 256 256 fidget.png --out icon.iconset/icon_256x256.png
sips -z 512 512 fidget.png --out icon.iconset/icon_256x256@2x.png
sips -z 512 512 fidget.png --out icon.iconset/icon_512x512.png
sips -z 1024 1024 fidget.png --out icon.iconset/icon_512x512@2x.png
iconutil -c icns icon.iconset
mv icon.icns fidget.icns

# Create setup.py with specific PyQt6 includes
cat > setup.py << EOF
from setuptools import setup

APP = ['fidget.py']
DATA_FILES = ['fidget.png']
OPTIONS = {
    'argv_emulation': False,
    'iconfile': 'fidget.icns',
    'plist': {
        'CFBundleName': 'Fidget',
        'CFBundleDisplayName': 'Fidget',
        'CFBundleGetInfoString': 'Prevents screen timeout by jiggling the mouse',
        'CFBundleIdentifier': 'com.fidget',
        'CFBundleVersion': '1.0.0',
        'CFBundleShortVersionString': '1.0.0',
        'NSHumanReadableCopyright': 'Copyright © 2025',
        'NSHighResolutionCapable': True,
        'LSUIElement': True,  # This makes it a background app without a dock icon
    },
    'packages': ['PyQt6'],
    'includes': [
        'PyQt6',
        'PyQt6.QtCore',
        'PyQt6.QtGui',
        'PyQt6.QtWidgets',
    ],
    'frameworks': [
        '/System/Library/Frameworks/AppKit.framework',
    ],
}

setup(
    app=APP,
    data_files=DATA_FILES,
    options={'py2app': OPTIONS},
    setup_requires=['py2app'],
)
EOF

# Activate the virtual environment
source venv/bin/activate

# Install required packages
pip install py2app==0.28.6 PyQt6

# Build the app in production mode
echo "Building production app..."
python setup.py py2app

# Create DMG
echo "Creating DMG..."
hdiutil create -volname "Fidget" -srcfolder dist/Fidget.app -ov -format UDZO "dist/Fidget-1.0.0.dmg"

# Copy the built app and DMG back to the original directory
echo "Copying built app and DMG back to original directory..."
mkdir -p /Users/joseph.schlesinger/ptools/fidget/dist
cp -R dist/Fidget.app /Users/joseph.schlesinger/ptools/fidget/dist/
cp "dist/Fidget-1.0.0.dmg" /Users/joseph.schlesinger/ptools/fidget/dist/

echo "Build completed successfully!"
echo "App location: /Users/joseph.schlesinger/ptools/fidget/dist/Fidget.app"
echo "DMG location: /Users/joseph.schlesinger/ptools/fidget/dist/Fidget-1.0.0.dmg"

# Clean up
echo "Cleaning up temporary directory..."
cd /Users/joseph.schlesinger/ptools/fidget
rm -rf "$TEMP_DIR"

echo "Done!" 