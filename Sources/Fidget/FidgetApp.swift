import AppKit

/// A menu entry: the label shown in the menu and the value it selects.
struct MenuChoice: Sendable {
    let label: String
    let value: Int
}

/// The menu bar app: status item, menu, timers, and the sleep-prevention logic.
@MainActor
final class FidgetApp: NSObject, NSApplicationDelegate {
    /// Tempo submenu: seconds between jiggles.
    static let intervals: [MenuChoice] = [
        MenuChoice(label: "5s", value: 5),
        MenuChoice(label: "30s", value: 30),
        MenuChoice(label: "55s", value: 55),
        MenuChoice(label: "4m", value: 240),
        MenuChoice(label: "9m", value: 540),
        MenuChoice(label: "14m", value: 840),
        MenuChoice(label: "29m", value: 1740),
        MenuChoice(label: "59m", value: 3540),
    ]

    /// Range submenu: maximum pixels to move. 0 means caffeinate only, no mouse movement.
    static let ranges: [MenuChoice] = [
        MenuChoice(label: "0 - Script Awake", value: 0),
        MenuChoice(label: "Tiny (1 pixel)", value: 1),
        MenuChoice(label: "Small (2 pixels)", value: 2),
        MenuChoice(label: "Medium (5 pixels)", value: 5),
        MenuChoice(label: "Large (10 pixels)", value: 10),
        MenuChoice(label: "Extra Large (20 pixels)", value: 20),
    ]

    private(set) var interval: Int
    private(set) var movementRange: Int
    private(set) var jiggling = false
    private(set) var caffeinateEnabled: Bool
    private var nextJiggleTime = Date.distantPast

    private let caffeinate = Caffeinate()
    private var statusItem: NSStatusItem?
    private let trayMenu = NSMenu()
    private let intervalMenu = NSMenu(title: "Tempo")
    private let rangeMenu = NSMenu(title: "Range")
    private let statusAction: NSMenuItem
    private let startAction: NSMenuItem
    private let stopAction: NSMenuItem
    private let caffeinateAction: NSMenuItem
    private let quitAction: NSMenuItem
    private var intervalActions: [NSMenuItem] = []
    private var rangeActions: [NSMenuItem] = []
    private var jiggleTimer: Timer?
    private var countdownTimer: Timer?
    private var signalSources: [DispatchSourceSignal] = []
    private var checkedAccessibility = false

    init(options: Options) {
        interval = options.interval
        movementRange = options.distance
        caffeinateEnabled = !options.forceMouse
        statusAction = NSMenuItem(title: "Idle", action: nil, keyEquivalent: "")
        startAction = NSMenuItem(title: "Start Fidget", action: #selector(FidgetApp.startJiggling), keyEquivalent: "")
        stopAction = NSMenuItem(title: "Stop Fidget", action: #selector(FidgetApp.stopJiggling), keyEquivalent: "")
        caffeinateAction = NSMenuItem(title: "Caffeinate", action: #selector(FidgetApp.toggleCaffeinate), keyEquivalent: "")
        quitAction = NSMenuItem(title: "Quit Fidget", action: #selector(FidgetApp.quit), keyEquivalent: "")
        super.init()
    }

    // MARK: - NSApplicationDelegate

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupTrayIcon()
        installSignalHandlers()
        startJiggling()
    }

    func applicationWillTerminate(_ notification: Notification) {
        stopJiggling()
    }

    // MARK: - Menu

    private func setupTrayIcon() {
        trayMenu.autoenablesItems = false
        intervalMenu.autoenablesItems = false
        rangeMenu.autoenablesItems = false

        for (index, choice) in Self.intervals.enumerated() {
            let action = NSMenuItem(title: choice.label, action: #selector(intervalSelected(_:)), keyEquivalent: "")
            action.target = self
            action.tag = choice.value
            intervalMenu.addItem(action)
            intervalActions.append(action)
            log.info("Added interval option \(index + 1): \(choice.label)")
        }
        log.info("Created Tempo menu with \(Self.intervals.count) options")

        for (index, choice) in Self.ranges.enumerated() {
            let action = NSMenuItem(title: choice.label, action: #selector(rangeSelected(_:)), keyEquivalent: "")
            action.target = self
            action.tag = choice.value
            rangeMenu.addItem(action)
            rangeActions.append(action)
            log.info("Added range option \(index + 1): \(choice.label)")
        }
        log.info("Created Range menu with \(Self.ranges.count) options")

        statusAction.isEnabled = false
        for action in [startAction, stopAction, caffeinateAction, quitAction] {
            action.target = self
        }

        let tempoItem = NSMenuItem(title: intervalMenu.title, action: nil, keyEquivalent: "")
        tempoItem.submenu = intervalMenu
        let rangeItem = NSMenuItem(title: rangeMenu.title, action: nil, keyEquivalent: "")
        rangeItem.submenu = rangeMenu

        trayMenu.addItem(statusAction)
        trayMenu.addItem(startAction)
        trayMenu.addItem(stopAction)
        trayMenu.addItem(.separator())
        trayMenu.addItem(tempoItem)
        trayMenu.addItem(rangeItem)
        trayMenu.addItem(caffeinateAction)
        trayMenu.addItem(.separator())
        trayMenu.addItem(quitAction)

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = "Fidget"
        if let button = item.button {
            if let icon = Self.loadIcon() {
                button.image = icon
            } else {
                log.warning("Icon file fidget.png not found, showing a text title instead")
                button.title = "Fidget"
            }
            button.toolTip = "Fidget"
        }
        item.menu = trayMenu
        statusItem = item

        let titles = trayMenu.items.filter { !$0.isSeparatorItem }.map { "'\($0.title)'" }
        log.info("Main menu items: [\(titles.joined(separator: ", "))]")

        updateMenuState()
    }

    /// Looks for fidget.png in the app bundle, next to the executable, then in the
    /// working directory (for `swift run` from the repository root).
    static func findIconURL() -> URL? {
        var candidates: [URL] = []
        if let bundled = Bundle.main.url(forResource: "fidget", withExtension: "png") {
            candidates.append(bundled)
        }
        if let executable = Bundle.main.executableURL?.resolvingSymlinksInPath() {
            candidates.append(executable.deletingLastPathComponent().appendingPathComponent("fidget.png"))
        }
        let workingDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        candidates.append(workingDirectory.appendingPathComponent("Resources/fidget.png"))
        candidates.append(workingDirectory.appendingPathComponent("fidget.png"))
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// The icon is a white silhouette on transparency, so it is used as a template image
    /// and macOS tints it for light and dark menu bars.
    static func loadIcon() -> NSImage? {
        guard let url = findIconURL(), let image = NSImage(contentsOf: url) else {
            return nil
        }
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        return image
    }

    private func updateMenuState() {
        startAction.isHidden = jiggling
        stopAction.isHidden = !jiggling
        statusAction.title = jiggling ? "Fidget in: \(Self.formatTimeRemaining(timeRemaining()))" : "Idle"
        for action in intervalActions {
            action.state = action.tag == interval ? .on : .off
        }
        for action in rangeActions {
            action.state = action.tag == movementRange ? .on : .off
        }
        caffeinateAction.state = caffeinateEnabled ? .on : .off
        let tempoTitle = intervalActions.first { $0.state == .on }?.title ?? "custom \(interval)s"
        let rangeTitle = rangeActions.first { $0.state == .on }?.title ?? "custom \(movementRange)px"
        log.info("Menu state - status: '\(statusAction.title)', tempo: '\(tempoTitle)', range: '\(rangeTitle)', caffeinate: \(caffeinateEnabled ? "on" : "off")")
    }

    @objc private func intervalSelected(_ sender: NSMenuItem) {
        setInterval(sender.tag)
    }

    @objc private func rangeSelected(_ sender: NSMenuItem) {
        setMovementRange(sender.tag)
    }

    @objc private func toggleCaffeinate() {
        setCaffeinateEnabled(!caffeinateEnabled)
    }

    /// Enables or disables the `caffeinate` child process, independent of jiggling.
    /// Range 0 needs caffeinate, so it is re-enabled when the range is 0.
    func setCaffeinateEnabled(_ enabled: Bool) {
        guard enabled != caffeinateEnabled else { return }
        caffeinateEnabled = enabled
        log.info("Caffeinate \(enabled ? "enabled" : "disabled")")
        if jiggling {
            if enabled {
                caffeinate.start()
            } else {
                caffeinate.stop()
                if movementRange == 0 {
                    log.warning("Range is 0 and caffeinate is disabled - sleep prevention is inactive")
                }
            }
        }
        updateMenuState()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - Jiggling

    @objc func startJiggling() {
        guard !jiggling else { return }
        jiggling = true
        nextJiggleTime = Date().addingTimeInterval(TimeInterval(interval))

        // Caffeinate is on by default; --force_mouse starts with it off, and the
        // menu toggle can change it at any time.
        if caffeinateEnabled {
            caffeinate.start()
        }

        jiggleTimer = scheduleTimer(every: TimeInterval(interval), selector: #selector(jiggleTimerFired))
        countdownTimer = scheduleTimer(every: 1, selector: #selector(updateCountdown))

        log.info("Jiggling started with interval \(interval) seconds, range \(movementRange) pixels, caffeinate \(caffeinateEnabled ? "on" : "off")")
        updateMenuState()
    }

    @objc func stopJiggling() {
        guard jiggling else { return }
        jiggling = false
        jiggleTimer?.invalidate()
        jiggleTimer = nil
        countdownTimer?.invalidate()
        countdownTimer = nil
        caffeinate.stop()
        log.info("Jiggling stopped")
        updateMenuState()
    }

    func setInterval(_ seconds: Int) {
        let oldInterval = interval
        interval = seconds
        if jiggling {
            nextJiggleTime = Date().addingTimeInterval(TimeInterval(seconds))
            jiggleTimer?.invalidate()
            jiggleTimer = scheduleTimer(every: TimeInterval(seconds), selector: #selector(jiggleTimerFired))
        }
        log.info("Interval changed from \(oldInterval) to \(interval) seconds")
        updateMenuState()
        log.info("Set tempo to: \(Self.tempoLabel(seconds))")
    }

    func setMovementRange(_ pixels: Int) {
        log.info("Setting movement range to \(pixels) pixels")
        movementRange = pixels
        // Range 0 means "no mouse movement", so caffeinate is the only way to prevent sleep.
        if pixels == 0 && !caffeinateEnabled {
            caffeinateEnabled = true
            if jiggling {
                caffeinate.start()
            }
        }
        updateMenuState()
    }

    /// Timers are added for the common run loop modes so they keep firing (and the
    /// countdown keeps updating) while the menu is open.
    private func scheduleTimer(every interval: TimeInterval, selector: Selector) -> Timer {
        let timer = Timer(timeInterval: interval, target: self, selector: selector, userInfo: nil, repeats: true)
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }

    @objc private func jiggleTimerFired() {
        performJiggle()
    }

    @objc private func updateCountdown() {
        if jiggling {
            statusAction.title = "Fidget in: \(Self.formatTimeRemaining(timeRemaining()))"
        }
    }

    /// Keeps the Mac awake: confirms caffeinate is running (restarting it if it died),
    /// or nudges the mouse by a small random offset when mouse movement is in use.
    @discardableResult
    func performJiggle() -> Bool {
        if caffeinateEnabled {
            if caffeinate.hasExited {
                log.warning("Caffeinate process exited unexpectedly, restarting...")
                caffeinate.start()
            }
            if caffeinate.isManaged {
                nextJiggleTime = Date().addingTimeInterval(TimeInterval(interval))
                log.debug("Sleep prevention active via caffeinate")
                return true
            }
        }

        if movementRange == 0 {
            log.warning("Range is 0 and caffeinate is unavailable - sleep prevention may not work")
            nextJiggleTime = Date().addingTimeInterval(TimeInterval(interval))
            return true
        }

        let before = Mouse.position()
        let range = movementRange
        var dx = Int.random(in: -range...range)
        let dy = Int.random(in: -range...range)
        if dx == 0 && dy == 0 {
            dx = 1
        }
        log.info("Attempting to move mouse by delta: dx=\(dx), dy=\(dy) (using Range setting: \(range))")

        if !checkedAccessibility {
            checkedAccessibility = true
            if !Mouse.hasAccessibilityPermission(prompt: true) {
                log.warning("Accessibility permission is required to move the mouse; grant it to Fidget in System Settings > Privacy & Security > Accessibility")
            }
        }

        guard Mouse.moveRelative(dx: dx, dy: dy) else {
            log.error("Error during jiggling: could not create a mouse event")
            return false
        }

        // Give the window server a moment to apply the move before measuring it.
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 100_000_000)
            self?.reportMovement(from: before, dx: dx, dy: dy, range: range)
        }

        nextJiggleTime = Date().addingTimeInterval(TimeInterval(interval))
        return true
    }

    private func reportMovement(from before: Mouse.Position, dx: Int, dy: Int, range: Int) {
        let after = Mouse.position()
        let actualDX = after.x - before.x
        let actualDY = after.y - before.y
        let intended = (Double(dx * dx + dy * dy)).squareRoot()
        let actual = (Double(actualDX * actualDX + actualDY * actualDY)).squareRoot()
        log.info("Mouse movement: Intended [dx=\(dx), dy=\(dy), dist=\(String(format: "%.2f", intended))] vs Actual [dx=\(actualDX), dy=\(actualDY), dist=\(String(format: "%.2f", actual))]")
        log.info("Moved mouse from (\(before.x), \(before.y)) to (\(after.x), \(after.y)) on screen \(before.screenIndex)")
        if actualDX == 0 && actualDY == 0 {
            log.warning("Mouse position did not change after jiggle attempt!")
        } else if abs(actualDX) > range * 2 || abs(actualDY) > range * 2 {
            log.warning("Mouse moved more than expected! Range: \(range), Actual: dx=\(actualDX), dy=\(actualDY)")
        }
    }

    // MARK: - Time display

    func timeRemaining() -> Int {
        guard jiggling else { return interval }
        return Int(max(0, nextJiggleTime.timeIntervalSinceNow))
    }

    static func formatTimeRemaining(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        return minutes > 0 ? "\(minutes)m\(remainingSeconds)s" : "\(remainingSeconds)s"
    }

    static func tempoLabel(_ seconds: Int) -> String {
        guard seconds >= 60 else {
            return seconds == 1 ? "1 second" : "\(seconds) seconds"
        }
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        switch (minutes, remainingSeconds) {
        case (1, 0): return "1 minute"
        case (1, _): return "1 minute \(remainingSeconds) seconds"
        case (_, 0): return "\(minutes) minutes"
        default: return "\(minutes) minutes \(remainingSeconds) seconds"
        }
    }

    // MARK: - Signals

    /// SIGINT/SIGTERM/SIGHUP quit cleanly so caffeinate is stopped before exiting.
    private func installSignalHandlers() {
        for signalNumber in [SIGINT, SIGTERM, SIGHUP] {
            signal(signalNumber, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
            source.setEventHandler { [weak self] in
                MainActor.assumeIsolated {
                    if signalNumber == SIGINT {
                        log.info("Keyboard interrupt received, exiting...")
                    } else {
                        log.info("Signal \(signalNumber) received, exiting...")
                    }
                    self?.stopJiggling()
                    NSApp.terminate(nil)
                }
            }
            source.resume()
            signalSources.append(source)
        }
    }
}
