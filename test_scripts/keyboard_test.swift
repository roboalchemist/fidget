#!/usr/bin/env swift
// Experiment: simulate keyboard input to prevent sleep by pressing F15, which is rarely
// used and shouldn't interfere with normal usage. The terminal running it needs the
// Accessibility permission.
// Usage: swift test_scripts/keyboard_test.swift   (Ctrl+C to stop)

import CoreGraphics
import Foundation

let f15KeyCode: CGKeyCode = 113

func simulateKeyboardActivity() {
    // Press and immediately release F15, with no modifier flags
    guard let down = CGEvent(keyboardEventSource: nil, virtualKey: f15KeyCode, keyDown: true),
          let up = CGEvent(keyboardEventSource: nil, virtualKey: f15KeyCode, keyDown: false) else {
        print("Could not create keyboard events")
        return
    }
    down.flags = []
    up.flags = []

    down.post(tap: .cghidEventTap)
    Thread.sleep(forTimeInterval: 0.05)
    up.post(tap: .cghidEventTap)

    print("Simulated keyboard activity (F15 key)")
}

var signalSources: [DispatchSourceSignal] = []
for signalNumber in [SIGINT, SIGTERM] {
    signal(signalNumber, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .global())
    source.setEventHandler {
        print("Exiting...")
        exit(0)
    }
    source.resume()
    signalSources.append(source)
}

print("Starting keyboard simulation to prevent sleep...")
while true {
    simulateKeyboardActivity()
    // Add randomness to the interval to appear more natural
    let sleepTime = Double.random(in: 45...75)
    print("Sleeping for \(String(format: "%.1f", sleepTime)) seconds...")
    fflush(stdout)
    Thread.sleep(forTimeInterval: sleepTime)
}
