import Foundation

/// Manages the `caffeinate -d -i` child process that blocks display (-d) and idle (-i) sleep.
///
/// `-w <our pid>` makes caffeinate exit on its own if Fidget dies without cleaning up,
/// so the sleep assertion can never be orphaned.
@MainActor
final class Caffeinate {
    static let executable = "/usr/bin/caffeinate"

    private var process: Process?

    /// True while a caffeinate process is being managed (it may have exited unexpectedly).
    var isManaged: Bool { process != nil }

    /// True when the managed process has exited without being stopped by us.
    var hasExited: Bool {
        guard let process else { return false }
        return !process.isRunning
    }

    var pid: Int32? { process?.processIdentifier }

    /// Starts a fresh caffeinate process, replacing any existing one. Returns false on failure.
    @discardableResult
    func start() -> Bool {
        stop()
        log.info("Starting caffeinate to prevent sleep...")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: Self.executable)
        process.arguments = ["-d", "-i", "-w", String(getpid())]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            log.error("Error starting caffeinate process: \(error.localizedDescription)")
            log.warning("Falling back to mouse movement for sleep prevention")
            self.process = nil
            return false
        }
        self.process = process
        log.info("Caffeinate process started with PID: \(process.processIdentifier)")
        return true
    }

    /// Terminates the managed caffeinate process (SIGTERM, then SIGKILL after 1 second).
    func stop() {
        guard let process else { return }
        self.process = nil
        let pid = process.processIdentifier
        log.info("Stopping caffeinate process (PID: \(pid))...")
        if process.isRunning {
            process.terminate()
        }
        let deadline = Date().addingTimeInterval(1)
        while process.isRunning && Date() < deadline {
            usleep(10_000)
        }
        if process.isRunning {
            log.error("Error stopping caffeinate process: PID \(pid) did not exit within 1 second, killing it")
            kill(pid, SIGKILL)
        } else {
            log.info("Caffeinate process terminated")
        }
    }
}
