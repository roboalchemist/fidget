#!/usr/bin/env swift
// Experiment: minimal, carefully controlled mouse movements to prevent sleep. Avoids large
// jumps by moving 1 pixel and warping straight back after each movement.
// Note: CGWarpMouseCursorPosition moves the cursor without generating input events, so it
// does not reset the system idle timer; this is why Fidget posts real events instead.
// Usage: swift test_scripts/minimal_mouse_test.swift   (Ctrl+C to stop)

import CoreGraphics
import Foundation

/// Current cursor position in Quartz global coordinates (origin top-left), the same
/// coordinate space CGWarpMouseCursorPosition uses.
func getMousePosition() -> CGPoint {
    CGEvent(source: nil)?.location ?? .zero
}

func setMousePosition(_ point: CGPoint) {
    CGWarpMouseCursorPosition(point)
    // Re-enable mouse and cursor position association
    CGAssociateMouseAndMouseCursorPosition(1)
}

/// Move the mouse by 1 pixel and then back to its original position.
func performMinimalMouseMovement() {
    let original = getMousePosition()
    let shifted = CGPoint(x: original.x + 1, y: original.y)

    print(String(format: "Moving mouse from (%.1f, %.1f) to (%.1f, %.1f)", original.x, original.y, shifted.x, shifted.y))
    setMousePosition(shifted)

    Thread.sleep(forTimeInterval: 0.1)

    print(String(format: "Resetting mouse to original position (%.1f, %.1f)", original.x, original.y))
    setMousePosition(original)

    let final = getMousePosition()
    print(String(format: "Final position: (%.1f, %.1f)", final.x, final.y))

    let tolerance = 2.0
    if abs(final.x - original.x) > tolerance || abs(final.y - original.y) > tolerance {
        print(String(format: "WARNING: Mouse did not return to original position! Diff: (%.1f, %.1f)",
                     final.x - original.x, final.y - original.y))
    }
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

print("Starting minimal mouse movement to prevent sleep...")
while true {
    performMinimalMouseMovement()
    // Use a longer interval to minimize disruption
    let sleepTime = Double.random(in: 45...60)
    print("Sleeping for \(String(format: "%.1f", sleepTime)) seconds...")
    fflush(stdout)
    Thread.sleep(forTimeInterval: sleepTime)
}
