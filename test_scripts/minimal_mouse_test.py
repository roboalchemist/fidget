#!/usr/bin/env python3
"""
Test script for making minimal, carefully controlled mouse movements to prevent sleep.
This approach avoids large jumps or erratic behavior by using tiny movements and
resetting the mouse back after each movement.
"""
import time
import signal
import sys
import random

try:
    import Quartz
    import AppKit
except ImportError:
    print("Required modules not available. Please run 'pip install pyobjc-framework-Quartz pyobjc-framework-AppKit'")
    sys.exit(1)

def get_mouse_position():
    """Get the current mouse position."""
    pos = AppKit.NSEvent.mouseLocation()
    return pos.x, pos.y

def set_mouse_position(x, y):
    """Set the mouse position using the lowest-level API available."""
    move_to = Quartz.CGPoint(x=x, y=y)
    Quartz.CGWarpMouseCursorPosition(move_to)
    # Re-enable mouse and cursor position association
    Quartz.CGAssociateMouseAndMouseCursorPosition(True)

def perform_minimal_mouse_movement():
    """Move mouse by 1 pixel and then back to original position."""
    # Get current position
    original_x, original_y = get_mouse_position()
    
    # Calculate a 1-pixel shift
    delta = 1  # Just 1 pixel
    new_x = original_x + delta
    new_y = original_y  # Keep Y the same
    
    # Move to new position
    print(f"Moving mouse from ({original_x:.1f}, {original_y:.1f}) to ({new_x:.1f}, {new_y:.1f})")
    set_mouse_position(new_x, new_y)
    
    # Brief pause
    time.sleep(0.1)
    
    # Move back to original position
    print(f"Resetting mouse to original position ({original_x:.1f}, {original_y:.1f})")
    set_mouse_position(original_x, original_y)
    
    # Verify position
    final_x, final_y = get_mouse_position()
    print(f"Final position: ({final_x:.1f}, {final_y:.1f})")
    
    # Check if we ended up close to the original position
    tolerance = 2.0  # Allow for minor floating point differences
    if (abs(final_x - original_x) > tolerance or abs(final_y - original_y) > tolerance):
        print(f"WARNING: Mouse did not return to original position! Diff: ({final_x - original_x:.1f}, {final_y - original_y:.1f})")

def cleanup(signum, frame):
    print("Exiting...")
    sys.exit(0)

# Set up signal handling for clean termination
signal.signal(signal.SIGINT, cleanup)
signal.signal(signal.SIGTERM, cleanup)

# Main loop
try:
    print("Starting minimal mouse movement to prevent sleep...")
    while True:
        perform_minimal_mouse_movement()
        # Use a longer interval to minimize disruption
        sleep_time = random.uniform(45, 60)
        print(f"Sleeping for {sleep_time:.1f} seconds...")
        time.sleep(sleep_time)
except KeyboardInterrupt:
    cleanup(None, None) 