import Foundation

/// Runtime options selected on the command line.
struct Options: Equatable, Sendable {
    var interval = 240
    var distance = 5
    var verbose = false
    var forceMouse = false
}

/// Result of parsing the command line: either run the app, or print text and exit.
enum ParseOutcome: Equatable, Sendable {
    case run(Options)
    case exit(code: Int32, stdout: String, stderr: String)
}

/// Command-line parser that reproduces the behavior and messages of the original
/// Python `argparse` parser: unique-prefix abbreviations, `--opt=value` syntax,
/// left-to-right processing (so `--help` wins over later errors), unrecognized
/// arguments reported last, and exit status 2 on errors.
struct ArgumentParser: Sendable {
    static let description = "Prevent screen sleep by jiggling the mouse."

    private enum Kind: Sendable {
        case help, interval, distance, verbose, forceMouse
    }

    private struct Spec: Sendable {
        let kind: Kind
        let flags: [String]
        let metavar: String?
        let help: String

        var displayName: String { flags.joined(separator: "/") }
    }

    private static let specs: [Spec] = [
        Spec(kind: .help, flags: ["-h", "--help"], metavar: nil,
             help: "show this help message and exit"),
        Spec(kind: .interval, flags: ["--interval"], metavar: "INTERVAL",
             help: "Interval between jiggling in seconds (default: 4m)"),
        Spec(kind: .distance, flags: ["--distance"], metavar: "DISTANCE",
             help: "Maximum distance to move in pixels (default: 5)"),
        Spec(kind: .verbose, flags: ["--verbose"], metavar: nil,
             help: "Enable verbose logging"),
        Spec(kind: .forceMouse, flags: ["--force_mouse"], metavar: nil,
             help: "Force use of mouse movement"),
    ]

    /// argparse formats for an 80-column terminal (text width 78) when output is not a TTY.
    private static let textWidth = 78

    let prog: String

    init(prog: String) {
        self.prog = prog
    }

    // MARK: - Help text

    func usage() -> String {
        let parts = Self.specs.map { spec -> String in
            let flag = spec.flags[0]
            if let metavar = spec.metavar {
                return "[\(flag) \(metavar)]"
            }
            return "[\(flag)]"
        }
        let prefix = "usage: "
        let indent = String(repeating: " ", count: prefix.count + prog.count + 1)
        var lines: [String] = []
        var line: [String] = []
        var lineLength = prefix.count - 1
        for part in [prog] + parts {
            if lineLength + 1 + part.count > Self.textWidth && !line.isEmpty {
                lines.append(line.joined(separator: " "))
                line = []
                lineLength = indent.count - 1
            }
            line.append(part)
            lineLength += part.count + 1
        }
        if !line.isEmpty {
            lines.append(line.joined(separator: " "))
        }
        return prefix + lines.joined(separator: "\n" + indent) + "\n"
    }

    func help() -> String {
        let invocations = Self.specs.map { spec -> String in
            if let metavar = spec.metavar {
                return spec.flags.map { "\($0) \(metavar)" }.joined(separator: ", ")
            }
            return spec.flags.joined(separator: ", ")
        }
        let helpPosition = min((invocations.map(\.count).max() ?? 0) + 2 + 2, 24)
        var text = usage() + "\n" + Self.description + "\n\noptional arguments:\n"
        for (spec, invocation) in zip(Self.specs, invocations) {
            let start = "  " + invocation
            if start.count + 2 <= helpPosition {
                text += start.padding(toLength: helpPosition, withPad: " ", startingAt: 0) + spec.help + "\n"
            } else {
                text += start + "\n" + String(repeating: " ", count: helpPosition) + spec.help + "\n"
            }
        }
        return text
    }

    // MARK: - Parsing

    func parse(_ arguments: [String]) -> ParseOutcome {
        var options = Options()
        var extras: [String] = []
        var index = 0
        var positionalOnly = false

        while index < arguments.count {
            let argument = arguments[index]
            index += 1

            if positionalOnly {
                extras.append(argument)
                continue
            }
            if argument == "--" {
                positionalOnly = true
                extras.append(argument)
                continue
            }
            // Finder used to pass a process serial number argument; it is never a user option.
            if argument.hasPrefix("-psn_") {
                continue
            }
            guard Self.looksLikeOption(argument) else {
                extras.append(argument)
                continue
            }
            guard let (spec, explicitValue) = Self.resolve(argument) else {
                extras.append(argument)
                continue
            }

            switch spec.kind {
            case .help:
                if let explicitValue {
                    return error("argument \(spec.displayName): ignored explicit argument '\(explicitValue)'")
                }
                return .exit(code: 0, stdout: help(), stderr: "")

            case .verbose, .forceMouse:
                if let explicitValue {
                    return error("argument \(spec.displayName): ignored explicit argument '\(explicitValue)'")
                }
                if spec.kind == .verbose {
                    options.verbose = true
                } else {
                    options.forceMouse = true
                }

            case .interval, .distance:
                let rawValue: String
                if let explicitValue {
                    rawValue = explicitValue
                } else if index < arguments.count, !Self.looksLikeOption(arguments[index]), arguments[index] != "--" {
                    rawValue = arguments[index]
                    index += 1
                } else {
                    return error("argument \(spec.displayName): expected one argument")
                }
                guard let value = Self.pythonInt(rawValue) else {
                    return error("argument \(spec.displayName): invalid int value: '\(rawValue)'")
                }
                if spec.kind == .interval {
                    guard value >= 1 else {
                        return error("argument \(spec.displayName): invalid positive int value: '\(rawValue)'")
                    }
                    options.interval = value
                } else {
                    guard value >= 0 else {
                        return error("argument \(spec.displayName): invalid non-negative int value: '\(rawValue)'")
                    }
                    options.distance = value
                }
            }
        }

        if !extras.isEmpty {
            return error("unrecognized arguments: \(extras.joined(separator: " "))")
        }
        return .run(options)
    }

    private func error(_ message: String) -> ParseOutcome {
        .exit(code: 2, stdout: "", stderr: usage() + "\(prog): error: \(message)\n")
    }

    /// argparse treats `-5`, `-1.5` and `-.5` as values (this parser has no options that look
    /// like negative numbers), and anything containing a space as a positional argument.
    private static func looksLikeOption(_ argument: String) -> Bool {
        guard argument.hasPrefix("-"), argument.count > 1 else {
            return false
        }
        if argument.range(of: #"^-\d+$|^-\d*\.\d+$"#, options: .regularExpression) != nil {
            return false
        }
        if resolve(argument) != nil {
            return true
        }
        return !argument.contains(" ")
    }

    /// Resolves an option string (exact match, `--name=value`, or a unique `--prefix`).
    private static func resolve(_ argument: String) -> (Spec, String?)? {
        var name = argument
        var explicitValue: String?
        if argument.hasPrefix("--"), let equals = argument.firstIndex(of: "=") {
            name = String(argument[..<equals])
            explicitValue = String(argument[argument.index(after: equals)...])
        }
        if let spec = specs.first(where: { $0.flags.contains(name) }) {
            return (spec, explicitValue)
        }
        guard name.hasPrefix("--"), name.count > 2 else {
            return nil
        }
        let matches = specs.filter { spec in spec.flags.contains { $0.hasPrefix("--") && $0.hasPrefix(name) } }
        guard matches.count == 1 else {
            return nil
        }
        return (matches[0], explicitValue)
    }

    /// Mirrors Python's `int()` for base-10 strings: surrounding whitespace, an optional sign,
    /// and single underscores between digits are allowed.
    static func pythonInt(_ text: String) -> Int? {
        var body = Substring(text.trimmingCharacters(in: .whitespacesAndNewlines))
        var negative = false
        if let sign = body.first, sign == "+" || sign == "-" {
            negative = sign == "-"
            body = body.dropFirst()
        }
        guard let first = body.first, let last = body.last,
              first.isASCII, first.isNumber, last.isASCII, last.isNumber,
              !body.contains("__"),
              body.allSatisfy({ ($0.isASCII && $0.isNumber) || $0 == "_" })
        else {
            return nil
        }
        guard let magnitude = Int(body.replacingOccurrences(of: "_", with: "")) else {
            return nil
        }
        return negative ? -magnitude : magnitude
    }
}
