#!/usr/bin/env swift
// Experiment: prevent sleep with the caffeinate command. This approach doesn't move the mouse at all.
// Usage: swift test_scripts/caffeinate_test.swift   (Ctrl+C to stop)

import Foundation

func runCaffeinate() throws -> Process {
    print("Starting caffeinate to prevent sleep...")
    // -d prevents display sleep, -i prevents idle sleep
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
    process.arguments = ["-d", "-i"]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try process.run()
    print("Caffeinate running with PID: \(process.processIdentifier)")
    return process
}

let caffeinatePID = try runCaffeinate().processIdentifier

// Clean termination on Ctrl+C or kill
var signalSources: [DispatchSourceSignal] = []
for signalNumber in [SIGINT, SIGTERM] {
    signal(signalNumber, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .global())
    source.setEventHandler {
        print("Terminating caffeinate process...")
        kill(caffeinatePID, SIGTERM)
        exit(0)
    }
    source.resume()
    signalSources.append(source)
}

// Keep the script running
while true {
    print("Sleep prevention active...")
    fflush(stdout)
    Thread.sleep(forTimeInterval: 10)
}
