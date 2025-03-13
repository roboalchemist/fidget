# Fidget

Fidget is a simple macOS application that prevents your screen from sleeping by periodically moving the mouse cursor slightly. It runs in the background with a system tray icon, allowing you to control when the jiggling is active.

## Features

- Runs in the system tray/menu bar
- Periodically moves the mouse cursor by a small amount to prevent screen sleep
- Configurable jiggle interval (15s, 30s, 1m, 2m, 5m)
- Start/stop jiggling with a single click
- Minimal resource usage

## Installation

### Option 1: Install from DMG

1. Download the latest `Fidget-1.0.0.dmg` file from the `dist` directory
2. Open the DMG file
3. Drag the Fidget app to your Applications folder
4. Open the app from your Applications folder

### Option 2: Run from source

1. Clone this repository
2. Create a virtual environment: `python3 -m venv venv`
3. Activate the virtual environment: `source venv/bin/activate`
4. Install dependencies: `pip install pystray pillow`
5. Run the script: `python fidget.py`

### Option 3: Use the wrapper script

1. Clone this repository
2. Make the wrapper script executable: `chmod +x fidget_wrapper.sh`
3. Run the wrapper script: `./fidget_wrapper.sh`

## Building from Source

To build the app as a standalone macOS application:

```bash
# For development build (references original script)
./build_app.sh -d

# For production build (standalone app)
./build_app.sh

# To run the app after building
./build_app.sh -r
```

## Usage

1. Launch the app
2. Look for the Fidget icon in your menu bar
3. Click on the icon to access the menu
4. Select "Start Jiggling" to begin preventing screen sleep
5. Select "Stop Jiggling" to pause the functionality
6. Choose a different interval from the "Set Interval" submenu if desired
7. Select "Quit" to exit the application

## Requirements

- macOS 10.14 or later
- Python 3.6 or later (for running from source)

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Acknowledgements

- Uses [pystray](https://github.com/moses-palmer/pystray) for system tray functionality
- Uses [Pillow](https://python-pillow.org/) for image processing 