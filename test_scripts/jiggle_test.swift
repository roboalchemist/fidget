#!/usr/bin/env swift
// Manual integration test for mouse jiggling, without the menu bar UI.
// Every --interval seconds it moves the cursor right, then down, then back to where it
// started, for --duration seconds. The terminal running it needs the Accessibility permission.
//
// Usage: swift test_scripts/jiggle_test.swift [--interval 5] [--duration 15] [--distance 5] [--verbose]
// Exits 0 if at least one jiggle succeeded.

import CoreGraphics
import Foundation

var verbose = false

let timestampFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss,SSS"
    return formatter
}()

func log(_ level: String, _ message: String) {
    if level == "DEBUG" && !verbose {
        return
    }
    print("\(timestampFormatter.string(from: Date())) - fidget_test - \(level) - \(message)")
    fflush(stdout)
}

func getMousePosition() -> (x: Int, y: Int) {
    let location = CGEvent(source: nil)?.location ?? .zero
    return (Int(location.x), Int(location.y))
}

func setMousePosition(x: Int, y: Int) -> Bool {
    guard let event = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
                              mouseCursorPosition: CGPoint(x: x, y: y), mouseButton: .left) else {
        return false
    }
    event.post(tap: .cghidEventTap)
    return true
}

/// Moves the cursor slightly and then returns it to its original position.
func jiggleMouse(distance: Int) -> Bool {
    let original = getMousePosition()
    log("INFO", "Original position: (\(original.x), \(original.y))")

    let steps = [
        (original.x + distance, original.y),
        (original.x + distance, original.y + distance),
    ]
    for (x, y) in steps {
        log("INFO", "Moving to: (\(x), \(y))")
        guard setMousePosition(x: x, y: y) else {
            log("ERROR", "Error jiggling mouse: could not create a mouse event")
            return false
        }
        Thread.sleep(forTimeInterval: 0.1)
    }

    log("INFO", "Moving back to: (\(original.x), \(original.y))")
    return setMousePosition(x: original.x, y: original.y)
}

func testJiggle(interval: Int, duration: Int, distance: Int) -> Bool {
    log("INFO", "Starting jiggle test with interval=\(interval)s, duration=\(duration)s, distance=\(distance)px")
    let start = Date()
    var jiggleCount = 0

    while Date().timeIntervalSince(start) < Double(duration) {
        if jiggleMouse(distance: distance) {
            jiggleCount += 1
            log("INFO", "Jiggle \(jiggleCount) successful")
        } else {
            log("WARNING", "Jiggle failed")
        }

        var timeToWait = Double(interval) - Date().timeIntervalSince(start).truncatingRemainder(dividingBy: Double(interval))
        if timeToWait < 0.1 {
            timeToWait = Double(interval)
        }
        log("INFO", "Waiting \(String(format: "%.2f", timeToWait))s until next jiggle")
        Thread.sleep(forTimeInterval: timeToWait)
    }

    log("INFO", "Test completed. Performed \(jiggleCount) jiggle(s) in \(String(format: "%.2f", Date().timeIntervalSince(start))) seconds")
    return jiggleCount > 0
}

func usage() -> Never {
    print("usage: jiggle_test.swift [-h] [--interval INTERVAL] [--duration DURATION] [--distance DISTANCE] [--verbose]")
    exit(2)
}

var interval = 5
var duration = 15
var distance = 5
var arguments = CommandLine.arguments.dropFirst()
while let argument = arguments.popFirst() {
    switch argument {
    case "--interval", "--duration", "--distance":
        guard let value = arguments.popFirst().flatMap({ Int($0) }), value > 0 || argument == "--distance" else {
            usage()
        }
        if argument == "--interval" { interval = value }
        if argument == "--duration" { duration = value }
        if argument == "--distance" { distance = value }
    case "--verbose", "-v":
        verbose = true
    case "-h", "--help":
        print("Test Fidget mouse jiggling functionality (moves the real cursor).")
        usage()
    default:
        usage()
    }
}

// Ctrl+C ends the test like the original's KeyboardInterrupt handler.
signal(SIGINT, SIG_IGN)
let interruptSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .global())
interruptSource.setEventHandler {
    log("INFO", "Test interrupted by user")
    exit(1)
}
interruptSource.resume()

exit(testJiggle(interval: interval, duration: duration, distance: distance) ? 0 : 1)
