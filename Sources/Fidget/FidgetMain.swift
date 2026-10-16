import AppKit

@main
enum FidgetMain {
    @MainActor
    static func main() {
        let prog = URL(fileURLWithPath: CommandLine.arguments.first ?? "Fidget").lastPathComponent
        let parser = ArgumentParser(prog: prog)

        switch parser.parse(Array(CommandLine.arguments.dropFirst())) {
        case let .exit(code, stdout, stderr):
            try? FileHandle.standardOutput.write(contentsOf: Data(stdout.utf8))
            try? FileHandle.standardError.write(contentsOf: Data(stderr.utf8))
            exit(code)

        case let .run(options):
            // Logging must never kill the app if its terminal goes away.
            signal(SIGPIPE, SIG_IGN)
            let logFile = ProcessInfo.processInfo.environment["FIDGET_LOG_FILE"] ?? Logger.defaultLogFile
            Logger.shared.configure(verbose: options.verbose, logFile: logFile)

            let application = NSApplication.shared
            application.setActivationPolicy(.accessory)
            let delegate = FidgetApp(options: options)
            application.delegate = delegate
            application.run()
            withExtendedLifetime(delegate) {}
        }
    }
}
