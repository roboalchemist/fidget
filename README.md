# Fidget

Fidget is a macOS menu bar app that prevents screen sleep. By default it runs `caffeinate -d -i` in the background; it can instead nudge the mouse cursor at a configurable tempo. It runs as a `LSUIElement` (no Dock icon), showing only in the menu bar.

Version 2.1 is a native Swift/AppKit rewrite of the original Python/PyQt6 app, with the same menu and options plus an explicit caffeinate toggle.

## Features

- Lives in the menu bar — no Dock icon
- Prevents display and idle sleep via `caffeinate -d -i` (default) or mouse movement
- **Caffeinate** menu toggle — turn the `caffeinate` process on/off independently of jiggling (on by default)
- Configurable jiggle interval: 5s, 30s, 55s, 4m, 9m, 14m, 29m, 59m (default 4m)
- Configurable movement range: 0 (caffeinate-only), 1px, 2px, 5px, 10px, 20px (default 5px)
- Live countdown shown in the menu ("Fidget in: 3m27s")
- Start/stop from the menu bar
- Universal binary (Apple Silicon + Intel)

## Requirements

- macOS 11 (Big Sur) or later
- Xcode or the Xcode Command Line Tools (Swift 6 toolchain) to build from source

## Installation

### Option 1: Install from DMG

Build the installer with `./build_app.sh` (see [Building](#building)), then:

1. Open `dist/Fidget-2.1.0.dmg`
2. Drag Fidget to your Applications folder
3. Launch Fidget from Applications

### Option 2: Run from source

```bash
git clone <repo>
cd fidget
swift run Fidget
```

Run it with options:

```bash
swift run Fidget --verbose --interval 30 --distance 10
```

### Option 3: Use the wrapper script

```bash
./fidget_wrapper.sh                      # builds if needed and runs in the background
./fidget_wrapper.sh --verbose --interval 30
```

## Building

```bash
./build_app.sh        # production build → dist/Fidget.app + dist/Fidget-2.1.0.dmg
./build_app.sh -d     # dev build (debug, native arch, no DMG)
./build_app.sh -r     # build and immediately run
```

Environment variables:

- `CODESIGN_IDENTITY` — signing identity (default `-`, ad-hoc)
- `DMG_FINDER_LAYOUT=1` — arrange the DMG window via Finder (opens a Finder window while building)

## Usage

Launch the app and click the Fidget icon in the menu bar:

- **Fidget in: …** — countdown to the next jiggle (disabled menu item)
- **Start Fidget** / **Stop Fidget** — toggle sleep prevention
- **Tempo** — set how often the jiggle fires (default: 4m)
- **Range** — set mouse movement distance; 0 = caffeinate only, no mouse move (default: 5px)
- **Caffeinate** — checkbox that starts/stops the `caffeinate` process immediately (default: on; `--force_mouse` starts it off). Turning it off falls back to mouse movement; with Range 0 it also re-enables automatically, since jiggling cannot prevent sleep without a range.
- **Quit Fidget** — exit

The active Tempo and Range choices and the Caffeinate checkbox are marked with a checkmark.

## Command-Line Options

```
-h, --help        show the help message and exit
--interval INT    Jiggle interval in seconds (default: 240 = 4m)
--distance INT    Max mouse movement in pixels, 0 = caffeinate only (default: 5)
--verbose         Log to /tmp/fidget.log and stderr (default: warnings only)
--force_mouse     Start with caffeinate off (mouse movement only)
```

A value set with `--interval` that is not in the Tempo menu still works; the menu then shows no checkmark until you pick one of its options. Unrecognized or invalid arguments print usage and exit with status 2.

## Sleep Prevention

Fidget runs `caffeinate -d -i -w <fidget pid>` as a background process, which blocks display (`-d`) and idle (`-i`) sleep. The `-w` flag makes caffeinate exit if Fidget dies, so the sleep assertion is never orphaned. If caffeinate exits unexpectedly, the next jiggle restarts it. Stopping Fidget (menu, `SIGINT`, or `SIGTERM`) terminates caffeinate.

The **Caffeinate** menu item controls this process explicitly:

- Checked (default): caffeinate runs and the cursor is left alone.
- Unchecked: caffeinate stops; mouse movement takes over (Range must be greater than 0).
- `--force_mouse` starts with the item unchecked, preserving the old "mouse only" behavior.
- Selecting Range 0 (`0 - Script Awake`) re-checks it, because a zero range disables mouse movement.

Each jiggle posts a `mouseMoved` event at the HID event tap with a random offset within the configured range, so the system treats it as activity. Posting synthetic events requires the Accessibility permission (System Settings → Privacy & Security → Accessibility); Fidget prompts the first time it needs it. In caffeinate mode no permission is needed.

Each jiggle posts a `mouseMoved` event at the HID event tap with a random offset within the configured range, so the system treats it as activity. Posting synthetic events requires the Accessibility permission (System Settings → Privacy & Security → Accessibility); Fidget prompts the first time it needs it. In caffeinate mode no permission is needed.

## Testing

There is no automated test suite; tests are manual/experimental scripts under `test_scripts/`, run directly with `swift`:

```bash
swift test_scripts/jiggle_test.swift --interval 5 --duration 15 --distance 5 --verbose
swift test_scripts/caffeinate_test.swift
swift test_scripts/iokit_test.swift
swift test_scripts/keyboard_test.swift
swift test_scripts/minimal_mouse_test.swift
```

`jiggle_test.swift` exercises mouse movement without the menu bar UI and exits 0 if at least one jiggle succeeded. The terminal running it needs the Accessibility permission.

## Related Projects

- **vfidget** — an internal downstream variant that adds workstation login automation. It is maintained in a separate private repository and is not published here. Fidget itself stays the simple, keep-awake-only app.

## Project Layout

```
fidget/
├── Package.swift              # Swift Package definition (executable target "Fidget")
├── Sources/Fidget/
│   ├── FidgetMain.swift       # @main entry point: parse args, start NSApplication
│   ├── FidgetApp.swift        # Status item, menu, timers, jiggle logic
│   ├── Caffeinate.swift       # caffeinate -d -i child process management
│   ├── Mouse.swift            # Cursor position and relative movement (CoreGraphics)
│   ├── Options.swift          # Command-line parser (argparse-compatible)
│   └── Logger.swift           # Timestamped stderr/file logging
├── Resources/
│   ├── Info.plist             # Bundle metadata (LSUIElement, identifier)
│   ├── fidget.png             # Menu bar icon (template image)
│   └── fidget.icns            # App icon fallback
├── build_app.sh               # Builds .app + DMG
├── fidget_wrapper.sh          # Build-and-run helper
├── kill_fidget.sh             # Stops running Fidget processes cleanly
├── test_scripts/              # Manual component tests (Swift scripts)
├── worklog.md                 # Development history and decisions
└── CLAUDE.md                  # Architecture notes for agents/contributors
```
