import Foundation

enum LogLevel: Int, Comparable, Sendable {
    case debug = 10
    case info = 20
    case warning = 30
    case error = 40

    var name: String {
        switch self {
        case .debug: "DEBUG"
        case .info: "INFO"
        case .warning: "WARNING"
        case .error: "ERROR"
        }
    }

    static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Logger matching the original Python `logging` setup:
/// `%(asctime)s - %(levelname)s - %(message)s`. Verbose mode logs INFO and above to
/// stderr and appends to a log file (default `/tmp/fidget.log`); otherwise WARNING and
/// above go to stderr only.
final class Logger: @unchecked Sendable {
    static let shared = Logger()

    static let defaultLogFile = "/tmp/fidget.log"

    private let lock = NSLock()
    private var level: LogLevel = .warning
    private var file: FileHandle?
    private let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss,SSS"
        return formatter
    }()

    func configure(verbose: Bool, logFile: String = Logger.defaultLogFile) {
        lock.lock()
        defer { lock.unlock() }
        level = verbose ? .info : .warning
        file = nil
        guard verbose else {
            return
        }
        let descriptor = open(logFile, O_WRONLY | O_APPEND | O_CREAT, 0o644)
        if descriptor >= 0 {
            file = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        } else {
            let reason = String(cString: strerror(errno))
            try? FileHandle.standardError.write(contentsOf: Data("Could not open log file \(logFile): \(reason)\n".utf8))
        }
    }

    func log(_ messageLevel: LogLevel, _ message: @autoclosure () -> String) {
        lock.lock()
        defer { lock.unlock() }
        guard messageLevel >= level else {
            return
        }
        let line = Data("\(formatter.string(from: Date())) - \(messageLevel.name) - \(message())\n".utf8)
        try? file?.write(contentsOf: line)
        try? FileHandle.standardError.write(contentsOf: line)
    }
}

let log = Log()

/// Short call-site helpers: `log.info("...")`.
struct Log: Sendable {
    func debug(_ message: @autoclosure () -> String) { Logger.shared.log(.debug, message()) }
    func info(_ message: @autoclosure () -> String) { Logger.shared.log(.info, message()) }
    func warning(_ message: @autoclosure () -> String) { Logger.shared.log(.warning, message()) }
    func error(_ message: @autoclosure () -> String) { Logger.shared.log(.error, message()) }
}
