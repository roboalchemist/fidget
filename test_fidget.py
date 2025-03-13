#!/usr/bin/env python3
"""
Test script for Fidget application.
This script tests the core functionality of the Fidget app without the UI.
"""

import time
import logging
import argparse
import sys
import os

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger('fidget_test')

# Import platform-specific modules for mouse control
if sys.platform == 'darwin':  # macOS
    import Quartz
elif sys.platform == 'win32':  # Windows
    import ctypes
else:  # Linux/Unix
    try:
        import pyautogui
    except ImportError:
        logger.error("pyautogui is required for Linux/Unix. Install with: pip install pyautogui")
        sys.exit(1)

def get_mouse_position():
    """Get the current mouse position."""
    if sys.platform == 'darwin':  # macOS
        pos = Quartz.CGEventGetLocation(Quartz.CGEventCreate(None))
        return (int(pos.x), int(pos.y))
    elif sys.platform == 'win32':  # Windows
        point = ctypes.wintypes.POINT()
        ctypes.windll.user32.GetCursorPos(ctypes.byref(point))
        return (point.x, point.y)
    else:  # Linux/Unix
        return pyautogui.position()

def set_mouse_position(x, y):
    """Set the mouse position to the specified coordinates."""
    if sys.platform == 'darwin':  # macOS
        event = Quartz.CGEventCreateMouseEvent(
            None, 
            Quartz.kCGEventMouseMoved, 
            (x, y), 
            Quartz.kCGMouseButtonLeft
        )
        Quartz.CGEventPost(Quartz.kCGHIDEventTap, event)
    elif sys.platform == 'win32':  # Windows
        ctypes.windll.user32.SetCursorPos(x, y)
    else:  # Linux/Unix
        pyautogui.moveTo(x, y)

def jiggle_mouse(distance=5):
    """Move the mouse cursor slightly and then return it to its original position."""
    try:
        # Get current position
        orig_x, orig_y = get_mouse_position()
        logger.info(f"Original position: ({orig_x}, {orig_y})")
        
        # Move slightly to the right
        new_x, new_y = orig_x + distance, orig_y
        logger.info(f"Moving to: ({new_x}, {new_y})")
        set_mouse_position(new_x, new_y)
        time.sleep(0.1)
        
        # Move slightly down
        new_x, new_y = orig_x + distance, orig_y + distance
        logger.info(f"Moving to: ({new_x}, {new_y})")
        set_mouse_position(new_x, new_y)
        time.sleep(0.1)
        
        # Move back to original position
        logger.info(f"Moving back to: ({orig_x}, {orig_y})")
        set_mouse_position(orig_x, orig_y)
        
        return True
    except Exception as e:
        logger.error(f"Error jiggling mouse: {e}")
        return False

def test_jiggle(interval=5, duration=15, distance=5):
    """Test the mouse jiggling functionality for a specified duration."""
    logger.info(f"Starting jiggle test with interval={interval}s, duration={duration}s, distance={distance}px")
    
    start_time = time.time()
    jiggle_count = 0
    
    try:
        while time.time() - start_time < duration:
            success = jiggle_mouse(distance)
            if success:
                jiggle_count += 1
                logger.info(f"Jiggle {jiggle_count} successful")
            else:
                logger.warning("Jiggle failed")
            
            # Wait for the next interval
            time_to_wait = interval - ((time.time() - start_time) % interval)
            if time_to_wait < 0.1:  # Avoid very short waits
                time_to_wait = interval
            
            logger.info(f"Waiting {time_to_wait:.2f}s until next jiggle")
            time.sleep(time_to_wait)
    
    except KeyboardInterrupt:
        logger.info("Test interrupted by user")
    
    logger.info(f"Test completed. Performed {jiggle_count} jiggle(s) in {time.time() - start_time:.2f} seconds")
    return jiggle_count > 0

def main():
    """Main function to run the test."""
    parser = argparse.ArgumentParser(description='Test Fidget mouse jiggling functionality')
    parser.add_argument('--interval', type=int, default=5, help='Interval between jiggle events in seconds (default: 5)')
    parser.add_argument('--duration', type=int, default=15, help='Duration of the test in seconds (default: 15)')
    parser.add_argument('--distance', type=int, default=5, help='Distance to move the mouse in pixels (default: 5)')
    parser.add_argument('--verbose', '-v', action='store_true', help='Enable verbose logging')
    
    args = parser.parse_args()
    
    # Set logging level based on verbosity
    if args.verbose:
        logger.setLevel(logging.DEBUG)
    
    # Run the test
    success = test_jiggle(args.interval, args.duration, args.distance)
    
    # Exit with appropriate status code
    sys.exit(0 if success else 1)

if __name__ == "__main__":
    main() 