#!/usr/bin/env swift
// Experiment: prevent sleep with IOKit power assertions, the API that caffeinate and
// professional apps use internally. Check with `pmset -g assertions` while it runs.
// Usage: swift test_scripts/iokit_test.swift   (Ctrl+C to stop)

import Foundation
import IOKit.pwr_mgt

let assertionName = "Fidget Sleep Prevention Test" as CFString

func createAssertion(_ type: String) -> IOPMAssertionID? {
    var assertionID = IOPMAssertionID(0)
    let result = IOPMAssertionCreateWithName(type as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                             assertionName, &assertionID)
    return result == kIOReturnSuccess ? assertionID : nil
}

print("Creating power assertions to prevent sleep...")
let displayAssertion = createAssertion(kIOPMAssertionTypeNoDisplaySleep)
let idleAssertion = createAssertion(kIOPMAssertionTypeNoIdleSleep)

func allowSleep() {
    print("Releasing power assertions...")
    if let displayAssertion {
        IOPMAssertionRelease(displayAssertion)
    }
    if let idleAssertion {
        IOPMAssertionRelease(idleAssertion)
    }
}

guard displayAssertion != nil, idleAssertion != nil else {
    print("Failed to create power assertions (display: \(displayAssertion != nil), idle: \(idleAssertion != nil))")
    allowSleep()
    exit(1)
}
print("Power assertions created successfully")

// Release the assertions on Ctrl+C or kill
var signalSources: [DispatchSourceSignal] = []
for signalNumber in [SIGINT, SIGTERM] {
    signal(signalNumber, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .global())
    source.setEventHandler {
        allowSleep()
        exit(0)
    }
    source.resume()
    signalSources.append(source)
}

while true {
    print("Sleep prevention active...")
    fflush(stdout)
    Thread.sleep(forTimeInterval: 10)
}
