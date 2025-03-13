#!/usr/bin/env python3
"""
Test script for using IOKit power assertions to prevent sleep on macOS.
This approach is more sophisticated than caffeinate and is used by professional apps.
"""
import ctypes
import time
import signal
import sys

# Load the IOKit framework
iokit = ctypes.cdll.LoadLibrary('/System/Library/Frameworks/IOKit.framework/IOKit')

# Define the IOPMAssertionCreateWithName function
IOPMAssertionCreateWithName = iokit.IOPMAssertionCreateWithName
IOPMAssertionCreateWithName.argtypes = [
    ctypes.c_void_p,  # CFStringRef
    ctypes.c_uint32,  # IOPMAssertionLevel
    ctypes.c_void_p,  # CFStringRef
    ctypes.POINTER(ctypes.c_uint32)  # IOPMAssertionID
]
IOPMAssertionCreateWithName.restype = ctypes.c_int32

# Define the IOPMAssertionRelease function
IOPMAssertionRelease = iokit.IOPMAssertionRelease
IOPMAssertionRelease.argtypes = [ctypes.c_uint32]  # IOPMAssertionID
IOPMAssertionRelease.restype = ctypes.c_int32

# Create a CFString from a Python string
def cf_string(string):
    return ctypes.c_void_p.in_dll(
        ctypes.cdll.LoadLibrary('/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation'),
        string
    )

# Constants
kIOPMAssertionTypeNoDisplaySleep = cf_string("kIOPMAssertionTypeNoDisplaySleep")
kIOPMAssertionTypeNoIdleSleep = cf_string("kIOPMAssertionTypeNoIdleSleep")
kIOPMAssertionLevelOn = 255

assertion_id_display = ctypes.c_uint32(0)
assertion_id_idle = ctypes.c_uint32(0)

def prevent_sleep():
    print("Creating power assertions to prevent sleep...")
    
    # Prevent display sleep
    result_display = IOPMAssertionCreateWithName(
        kIOPMAssertionTypeNoDisplaySleep,
        kIOPMAssertionLevelOn,
        cf_string("Python Sleep Prevention"),
        ctypes.byref(assertion_id_display)
    )
    
    # Prevent idle sleep
    result_idle = IOPMAssertionCreateWithName(
        kIOPMAssertionTypeNoIdleSleep,
        kIOPMAssertionLevelOn,
        cf_string("Python Sleep Prevention"),
        ctypes.byref(assertion_id_idle)
    )
    
    if result_display == 0 and result_idle == 0:
        print("Power assertions created successfully")
        return True
    else:
        print(f"Failed to create power assertions: {result_display}, {result_idle}")
        return False

def allow_sleep():
    print("Releasing power assertions...")
    
    if assertion_id_display.value != 0:
        IOPMAssertionRelease(assertion_id_display)
    
    if assertion_id_idle.value != 0:
        IOPMAssertionRelease(assertion_id_idle)

def cleanup(signum, frame):
    allow_sleep()
    sys.exit(0)

# Set up signal handling for clean termination
signal.signal(signal.SIGINT, cleanup)
signal.signal(signal.SIGTERM, cleanup)

# Start sleep prevention
if prevent_sleep():
    try:
        while True:
            print("Sleep prevention active...")
            time.sleep(10)
    except KeyboardInterrupt:
        cleanup(None, None)
else:
    print("Failed to initialize sleep prevention") 