# Fidget — CLAUDE.md

## Project Overview

Fidget is a macOS menu bar app that prevents screen sleep by periodically running `caffeinate` or moving the mouse cursor. It runs as a `LSUIElement` (no Dock icon), showing only in the menu bar.

Version 2.1 is a native Swift/AppKit rewrite of the original Python/PyQt6 implementation. This file documents the Swift codebase; `worklog.md` retains the earlier Python history.

---

## Directory Structure

```
fidget/
├── Package.swift              # Swift Package (swift-tools-version 6.0, macOS 11)
├── Sources/Fidget/
│   ├── FidgetMain.swift       # @main: argument parsing, NSApplication bootstrap
│   ├── FidgetApp.swift        # NSApplicationDelegate: status item, menu, timers, jiggle logic
│   ├── Caffeinate.swift       # Manages the `caffeinate -d -i` child process
│   ├── Mouse.swift            # Cursor queries, screen detection, relative movement
│   ├── Options.swift          # Command-line parser (argparse-compatible)
│   └── Logger.swift           # Timestamped stderr/file logging
├── Resources/
│   ├── Info.plist             # Bundle metadata (LSUIElement, identifier, icon)
│   ├── fidget.png             # Menu bar icon (used as a template image)
│   └── fidget.icns            # App icon fallback
├── build_app.sh               # Production/dev build → dist/Fidget.app (+ DMG)
├── fidget_wrapper.sh          # Build and run in the background
├── kill_fidget.sh             # SIGTERM/SIGKILL running Fidget processes
├── test_scripts/              # Manual Swift experiments (not a test target)
│   ├── caffeinate_test.swift
│   ├── iokit_test.swift
│   ├── jiggle_test.swift
│   ├── keyboard_test.swift
│   └── minimal_mouse_test.swift
├── build/                     # Build intermediates (gitignored)
├── dist/                      # Fidget.app + Fidget-<version>.dmg (gitignored)
├── worklog.md                 # Development history, including the Python era
└── README.md
```

---

## Key Frameworks

| Framework | Purpose |
|-----------|---------|
| AppKit | `NSStatusItem`, `NSMenu`, `NSMenuItem`, `NSApplication`, `NSImage` |
| CoreGraphics / ApplicationServices | Cursor position, `CGEvent` posting, `AXIsProcessTrustedWithOptions` |
| Foundation | `Process` (caffeinate), `Timer`, `DateFormatter`, `DispatchSourceSignal` |

---

## Architecture

### Entry point — `FidgetMain`

`@main enum FidgetMain.main()`:

1. Builds an `ArgumentParser` (prog name from `CommandLine.arguments[0]`).
2. On `.exit(code, stdout, stderr)`, writes the output and exits (0 for `--help`, 2 for parse errors).
3. On `.run(options)`, ignores `SIGPIPE`, configures logging (`FIDGET_LOG_FILE` overrides `/tmp/fidget.log`), then starts `NSApplication` with `.accessory` activation policy and a `FidgetApp` delegate.

### `FidgetApp` (NSApplicationDelegate, @MainActor)

Holds the status item, menus, timers and settings:

- `intervals` — Tempo choices: 5s, 30s, 55s, 4m, 9m, 14m, 29m, 59m
- `ranges` — Range choices: 0 ("0 - Script Awake"), 1, 2, 5, 10, 20 pixels
- `interval`, `movementRange`, `jiggling`, `nextJiggleTime`
- `caffeinate` — the `Caffeinate` process manager

Lifecycle: `applicationDidFinishLaunching` → `setupTrayIcon()`, `installSignalHandlers()`, `startJiggling()`. `applicationWillTerminate` calls `stopJiggling()`.

### Menu construction

`setupTrayIcon()` builds:

```
Fidget in: Xm Ys   [disabled countdown]
Start Fidget       [hidden while running]
Stop Fidget        [hidden while stopped]
─────────────
Tempo ▶            [5s, 30s, 55s, 4m✓, 9m, 14m, 29m, 59m]
Range ▶            [0 - Script Awake, Tiny (1 pixel), Small (2 pixels),
                    Medium (5 pixels)✓, Large (10 pixels), Extra Large (20 pixels)]
✓ Caffeinate       [toggle: starts/stops the caffeinate process]
─────────────
Quit Fidget
```

Menu items are retained in `intervalActions` / `rangeActions` and selection is tracked with `NSMenuItem.state` (AppKit renders `.on` as a checkmark). `caffeinateAction` is a checkbox backed by `caffeinateEnabled`. `autoenablesItems` is disabled so items stay enabled regardless of selector resolution.

The status item icon is loaded from the bundle (`fidget.png`), then next to the executable, then `Resources/fidget.png` in the working directory — the last case makes `swift run` from the repo root work. The image is resized to 18×18 and marked `isTemplate` so macOS tints it for light/dark menu bars.

### Two timers

- `jiggleTimer` — fires every `interval` seconds → `performJiggle()`
- `countdownTimer` — fires every 1 s → updates the disabled status item title

Both are added to `RunLoop.main` in `.common` mode so the countdown keeps updating while the menu is open. Timers are invalidated and recreated when the tempo changes.

### Sleep prevention — `Caffeinate`

`Caffeinate.start()` runs `/usr/bin/caffeinate -d -i -w <fidget pid>`:

- `-d` blocks display sleep, `-i` blocks idle sleep
- `-w <pid>` makes caffeinate exit if Fidget dies, preventing an orphaned sleep assertion
- stdin/stdout/stderr are `/dev/null`

`stop()` sends SIGTERM, waits up to 1 second, then SIGKILLs. `hasExited` detects an unexpected death; `performJiggle()` restarts caffeinate on the next tick when that happens.

`caffeinateEnabled` is the user-facing toggle (`caffeinateAction`, the "Caffeinate" menu item):

- Default: on. `--force_mouse` starts it off, preserving the old "mouse only" behavior.
- `setCaffeinateEnabled(_:)` starts or stops the process immediately when running, and updates the checkbox.
- While enabled, caffeinate is the sleep-prevention mechanism and the cursor is left alone. When disabled, the jiggle moves the mouse (Range must be > 0).
- `setMovementRange(0)` re-enables caffeinate, because a zero range can't move the cursor; turning caffeinate off at Range 0 logs a "sleep prevention is inactive" warning.
- `startJiggling()` starts caffeinate iff the toggle is on.

### Mouse movement — `Mouse`

- `position()` returns the cursor location from `CGEvent(source: nil).location` (Quartz global coordinates, origin top-left) plus `screenIndex(containing:)`, which maps `CGGetDisplaysWithPoint` to an index in `NSScreen.screens` via `NSScreenNumber`.
- `moveRelative(dx:dy:)` posts a `.mouseMoved` `CGEvent` at `.cghidEventTap` with `mouseEventDeltaX/Y` set. Posting at the HID tap makes the system count it as activity.
- `hasAccessibilityPermission(prompt:)` wraps `AXIsProcessTrustedWithOptions`; `performJiggle()` checks once and logs a warning (with the standard macOS prompt) if missing.

`performJiggle()` picks `dx`/`dy` independently in `-range...range`, forces `dx = 1` if both are zero, then logs intended vs. actual movement 100 ms later (window server applies the move asynchronously).

### Command-line parser — `Options`

Reproduces Python `argparse` behavior rather than using `CommandLine.arguments` conventions:

- options: `-h/--help`, `--interval`, `--distance`, `--verbose`, `--force_mouse`
- `--opt=value`, unique-prefix abbreviations (`--dist 9`), `--` terminator
- `-psn_...` arguments (legacy Finder) are ignored
- left-to-right processing, so `--help` wins over later errors
- unrecognized arguments reported last as `unrecognized arguments: ...`
- invalid values and missing argument values exit with status 2
- `--interval` must be ≥ 1 ("invalid positive int value"), `--distance` must be ≥ 0 ("invalid non-negative int value")
- `pythonInt` accepts surrounding whitespace, a sign, and underscores between digits

### Logging — `Logger`

Mirrors the Python `logging` format `%(asctime)s - %(levelname)s - %(message)s` with millisecond precision:

- default level: warning, stderr only
- `--verbose`: info and above, stderr + append to `/tmp/fidget.log` (override with `FIDGET_LOG_FILE`)
- `Logger.shared` is lock-protected so logging is safe from signal/timer contexts

### Signals

`installSignalHandlers()` ignores `SIGINT`/`SIGTERM`/`SIGHUP` and installs `DispatchSourceSignal` handlers that stop jiggling (terminating caffeinate) and then terminate the app. This makes `kill_fidget.sh` and Ctrl+C clean.

---

## Building

```bash
# Production: universal binary (arm64 + x86_64), .app bundle, DMG
./build_app.sh

# Debug build, native arch, no DMG
./build_app.sh -d

# Build and run
./build_app.sh -r
```

`build_app.sh`:

1. Removes `build/` and `dist/`.
2. Runs `swift build -c release --arch arm64 --arch x86_64`.
3. Assembles `dist/Fidget.app` (binary, `Info.plist`, `PkgInfo`, icons).
4. Overwrites `CFBundleVersion` / `CFBundleShortVersionString` with `VERSION` (currently `2.0.0`) and the copyright year.
5. Regenerates `fidget.icns` from `Resources/fidget.png` with `sips`/`iconutil`, falling back to the committed `.icns`.
6. Ad-hoc signs (or signs with `CODESIGN_IDENTITY`) and verifies.
7. Creates a UDZO DMG with the app plus an `/Applications` symlink (`DMG_FINDER_LAYOUT=1` for a Finder-arranged window).

Build outputs (`build/`, `dist/`) are gitignored; do not commit them.

---

## Running from Source

```bash
swift run Fidget             # from the repo root, so the icon is found
swift run Fidget --verbose
./fidget_wrapper.sh --verbose --interval 30   # build + background run
./kill_fidget.sh                              # clean shutdown
```

---

## Testing

**No automated test target.** Testing is manual/integration only, using the Swift scripts in `test_scripts/` (each starts with `#!/usr/bin/env swift`):

```bash
swift test_scripts/jiggle_test.swift --interval 5 --duration 15 --distance 5 --verbose
swift test_scripts/caffeinate_test.swift
swift test_scripts/iokit_test.swift
swift test_scripts/keyboard_test.swift
swift test_scripts/minimal_mouse_test.swift
```

Useful manual checks:

```bash
# CLI behavior
swift run Fidget --help; echo $?          # 0
swift run Fidget --interval 0; echo $?    # 2, invalid positive int value

# Caffeinate lifecycle
swift run Fidget --verbose --interval 2 &
pgrep -fl "caffeinate -d -i"              # one caffeinate child
pkill -f "caffeinate -d -i"               # next jiggle restarts it
kill -TERM %1                             # caffeinate is gone afterwards

# Menu state (verbose log)
grep "Menu state" /tmp/fidget.log
# Menu state - status: 'Idle', tempo: '4m', range: 'Medium (5 pixels)'
```

Mouse-movement mode needs the Accessibility permission for the terminal/app; caffeinate mode does not.

---

## Hard-Won Knowledge

- **Caffeinate must be tied to the app PID** (`-w <pid>`), otherwise a crash leaves an orphaned process holding a sleep assertion.
- **Caffeinate is now an explicit toggle.** Keep `caffeinateEnabled` as the single source of truth; `performJiggle()` must consult it, and Range 0 must force it on (a zero range cannot jiggle the mouse).
- **Timers must be in `.common` run loop mode.** In the default mode the countdown freezes while a menu is open.
- **Menu items need strong references.** Python's PyQt version lost actions to garbage collection; in AppKit, keeping `intervalActions`/`rangeActions` also lets `updateMenuState()` toggle checkmarks.
- **`NSMenuItem.state` is the checkmark.** No manual "✓ " title prefixing is needed.
- **Template image for the menu bar.** `NSImage.isTemplate = true` lets macOS tint the icon correctly in dark mode; a colored PNG looks wrong.
- **Mouse coordinates are Quartz global coordinates** (origin top-left, y down), not AppKit's bottom-left origin. Mixing the two breaks multi-monitor movement.
- **Screen index needs `CGGetDisplaysWithPoint`**, matched to `NSScreen.screens` through `NSScreenNumber`; comparing raw frames fails with scaled/rotated displays.
- **`CGEvent` posting needs Accessibility permission** (`AXIsProcessTrustedWithOptions`). Prompt once, log once, don't spam.
- **Swift 6 concurrency:** UI types are `@MainActor`; signal handlers use `MainActor.assumeIsolated` because the dispatch source fires on the main queue.
- **`LSUIElement: true`** is required to hide the Dock icon; `NSApplication.setActivationPolicy(.accessory)` in code provides the same behavior when run outside the bundle.
- **Universal builds:** `swift build --arch arm64 --arch x86_64` produces a fat binary; the DMG ships that binary.
- **`--interval` values outside the Tempo menu are legal** (CLI), and the menu shows no checkmark until a preset is chosen.

---

## Known Limitations

- The menu has no "custom interval" entry; only CLI-set intervals outside the presets lack a checkmark.
- Settings are not persisted across launches; defaults (4m / 5px, caffeinate on) are used unless CLI flags are passed.
- Starting a second instance creates a second menu bar item (each process owns its own `NSStatusItem`).
