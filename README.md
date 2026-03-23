# Fidget

Fidget is a macOS menu bar app that prevents screen sleep by periodically moving the mouse cursor or running `caffeinate`. It runs as a `LSUIElement` (no Dock icon), showing only in the menu bar.

## Features

- Lives in the menu bar — no Dock icon
- Prevents display and idle sleep via `caffeinate -d -i` (default) or mouse movement
- Configurable jiggle interval: 5s, 30s, 55s, 4m, 9m, 14m, 29m, 59m
- Configurable movement range: 0 (caffeinate-only), 1px, 2px, 5px, 10px, 20px
- Countdown timer shown in menu
- Start/stop from the menu bar

## Installation

### Option 1: Install from DMG

1. Download `Fidget-1.0.0.dmg` from the `dist/` directory
2. Open the DMG and drag Fidget to your Applications folder
3. Launch Fidget from Applications

### Option 2: Run from source

```bash
git clone <repo>
cd fidget
python3 -m venv venv
source venv/bin/activate
pip install PyQt6==6.6.1
python fidget.py
```

### Option 3: Use the wrapper script

```bash
./fidget_wrapper.sh   # auto-creates venv, installs PyQt6, starts app
```

## Building

```bash
./build_app.sh        # production build → dist/Fidget.app + dist/Fidget-1.0.0.dmg
./build_app.sh -d     # dev/alias build (references original script)
./build_app.sh -r     # build and immediately run
```

## Usage

Launch the app and click the Fidget icon in the menu bar:

- **Start Fidget** / **Stop Fidget** — toggle sleep prevention
- **Tempo** — set how often the jiggle fires (default: 4m)
- **Range** — set mouse movement distance; 0 = caffeinate only, no mouse move (default: 5px)
- **Quit Fidget** — exit

## Command-Line Options

```
--interval INT    Jiggle interval in seconds (default: 240)
--distance INT    Max mouse movement in pixels (default: 5)
--verbose         Log to /tmp/fidget.log + stderr
--force_mouse     Force mouse movement instead of caffeinate
```

## Requirements

- macOS 10.14+
- Python 3.9+ (3.9.18 recommended, see `.python-version`)
- PyQt6 6.6.1

## Sleep Prevention

By default, Fidget runs `caffeinate -d -i` as a background process to block display and idle sleep. Mouse movement is also performed unless Range is set to 0. Use `--force_mouse` to rely solely on mouse movement instead of caffeinate.
