#!/usr/bin/env python3
"""
Test script for simulating keyboard input to prevent sleep on macOS.
This approach simulates pressing the F15 key, which is rarely used and shouldn't
interfere with normal usage.
"""
import time
import signal
import sys
import random

try:
    import Quartz
except ImportError:
    print("Quartz module not available. Please run 'pip install pyobjc-framework-Quartz'")
    sys.exit(1)

def simulate_keyboard_activity():
    # Simulate pressing and immediately releasing a function key (F15)
    # F15 is typically not used and won't interfere with normal usage
    
    # Create the key down event
    down_event = Quartz.CGEventCreateKeyboardEvent(None, 113, True)  # 113 is F15
    
    # Create the key up event
    up_event = Quartz.CGEventCreateKeyboardEvent(None, 113, False)
    
    # Set flags to avoid interfering with other applications
    Quartz.CGEventSetFlags(down_event, 0)
    Quartz.CGEventSetFlags(up_event, 0)
    
    # Post the events
    Quartz.CGEventPost(Quartz.kCGHIDEventTap, down_event)
    time.sleep(0.05)  # Brief delay
    Quartz.CGEventPost(Quartz.kCGHIDEventTap, up_event)
    
    print("Simulated keyboard activity (F15 key)")

def cleanup(signum, frame):
    print("Exiting...")
    sys.exit(0)

# Set up signal handling for clean termination
signal.signal(signal.SIGINT, cleanup)
signal.signal(signal.SIGTERM, cleanup)

# Main loop
try:
    print("Starting keyboard simulation to prevent sleep...")
    while True:
        simulate_keyboard_activity()
        # Add randomness to interval to appear more natural
        sleep_time = random.uniform(45, 75)
        print(f"Sleeping for {sleep_time:.1f} seconds...")
        time.sleep(sleep_time)
except KeyboardInterrupt:
    cleanup(None, None) 