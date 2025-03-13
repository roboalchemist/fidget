#!/usr/bin/env python3
"""
Fidget - A simple app that prevents your screen from going to sleep by periodically moving your mouse cursor.
"""

import sys
import time
import random
import logging
import os
import threading
import argparse
from datetime import datetime
import subprocess  # For alternate mouse movement approach

# Parse command line arguments
parser = argparse.ArgumentParser(description='Prevent screen sleep by jiggling the mouse.')
parser.add_argument('--interval', type=int, default=240, help='Interval between jiggling in seconds (default: 4m)')
parser.add_argument('--distance', type=int, default=5, help='Maximum distance to move in pixels (default: 5)')
parser.add_argument('--verbose', action='store_true', help='Enable verbose logging')
parser.add_argument('--force_mouse', action='store_true', help='Force use of mouse movement')
args = parser.parse_args()

# Configure logging
if args.verbose:
    log_file = '/tmp/fidget.log'
    logging.basicConfig(
        level=logging.INFO,
        format='%(asctime)s - %(levelname)s - %(message)s',
        handlers=[
            logging.FileHandler(log_file),
            logging.StreamHandler()
        ]
    )
else:
    logging.basicConfig(
        level=logging.WARNING,
        format='%(asctime)s - %(levelname)s - %(message)s'
    )

# Import PyQt6 for the UI
from PyQt6.QtWidgets import QApplication, QSystemTrayIcon, QMenu
from PyQt6.QtGui import QIcon, QCursor, QAction
from PyQt6.QtCore import QTimer, Qt, QPoint

# Import platform-specific modules for mouse control
if sys.platform == 'darwin':  # macOS
    import Quartz
    import AppKit
    import objc
    from Foundation import NSObject
elif sys.platform == 'win32':  # Windows
    import ctypes
else:  # Linux/X11
    from Xlib import display, X
    from Xlib.ext import xtest

# Global variables for the application
class FidgetApp:
    def __init__(self):
        self.app = QApplication(sys.argv)
        self.app.setQuitOnLastWindowClosed(False)
        
        self.interval = args.interval  # seconds between jiggling
        self.movement_range = args.distance  # maximum pixels to move
        self.jiggling = False
        self.next_jiggle_time = 0
        
        # For the caffeinate process on macOS
        self.caffeinate_process = None
        
        # Create tray icon
        self.setup_tray_icon()
        
        # Create timers
        self.jiggle_timer = QTimer()
        self.jiggle_timer.timeout.connect(self.perform_jiggle)
        
        self.countdown_timer = QTimer()
        self.countdown_timer.timeout.connect(self.update_countdown)
        self.countdown_timer.setInterval(1000)  # Update every second
        
        # Start jiggling by default
        self.start_jiggling()
    
    def setup_tray_icon(self):
        """Set up the system tray icon and menu."""
        # Load icon
        icon_path = self.find_icon_path()
        self.tray_icon = QSystemTrayIcon()
        self.tray_icon.setIcon(QIcon(icon_path))
        self.tray_icon.setToolTip("Fidget")
        
        # Interval submenu - completely new approach
        self.interval_menu = QMenu("Tempo")
        
        intervals = [
            ("5s", 5),
            ("30s", 30),
            ("55s", 55),
            ("4m", 240),
            ("9m", 540),
            ("14m", 840),
            ("29m", 1740),
            ("59m", 3540)
        ]
        
        # Store references to actions to prevent garbage collection
        self.interval_actions = []
        
        # Add interval options to the menu
        for i, (label, seconds) in enumerate(intervals):
            # Create action with proper text
            action = QAction(text=label, parent=None)
            # Create a function to handle interval selection to avoid lambda scope issues
            def create_interval_handler(s=seconds):
                return lambda checked=False: self.set_interval(s)
            
            # Connect using our handler function
            action.triggered.connect(create_interval_handler())
            # Add the action to the interval menu
            self.interval_menu.addAction(action)
            # Store reference to prevent garbage collection
            self.interval_actions.append(action)
            logging.info(f"Added interval option {i+1}: {label}")
        
        # Debug the menu contents
        logging.info(f"Created Tempo menu with {len(intervals)} options")
        
        # Range submenu for movement distance
        self.range_menu = QMenu("Range")
        
        # Add a "Script Awake" option on macOS that uses caffeinate instead of mouse movement
        ranges = []
        
        # Add the "Script Awake" option only on macOS
        if sys.platform == 'darwin':
            ranges.append(("0 - Script Awake", 0))
            
        # Add standard range options for all platforms
        ranges.extend([
            ("Tiny (1 pixel)", 1),
            ("Small (2 pixels)", 2),
            ("Medium (5 pixels)", 5),
            ("Large (10 pixels)", 10),
            ("Extra Large (20 pixels)", 20)
        ])
        
        # Store references to actions to prevent garbage collection
        self.range_actions = []
        
        # Add range options to the menu
        for i, (label, pixels) in enumerate(ranges):
            # Create action with proper text
            action = QAction(text=label, parent=None)
            # Create a function to handle range selection to avoid lambda scope issues
            def create_range_handler(p=pixels):
                return lambda checked=False: self.set_movement_range(p)
            
            # Connect using our handler function
            action.triggered.connect(create_range_handler())
            # Add the action to the range menu
            self.range_menu.addAction(action)
            # Store reference to prevent garbage collection
            self.range_actions.append(action)
            logging.info(f"Added range option {i+1}: {label}")
        
        # Debug the menu contents
        logging.info(f"Created Range menu with {len(ranges)} options")
        for i, action in enumerate(self.range_menu.actions()):
            logging.info(f"  Range menu item {i+1}: {action.text()}")
        
        # Create the main menu
        self.tray_menu = QMenu()
        
        # Status item (non-clickable)
        self.status_action = QAction("Idle")
        self.status_action.setEnabled(False)
        
        # Start/Stop actions
        self.start_action = QAction("Start Fidget")
        self.start_action.triggered.connect(self.start_jiggling)
        
        self.stop_action = QAction("Stop Fidget")
        self.stop_action.triggered.connect(self.stop_jiggling)
        
        # Quit action
        self.quit_action = QAction("Quit Fidget")
        self.quit_action.triggered.connect(self.app.quit)
        
        # Add all actions to the menu
        self.tray_menu.addAction(self.status_action)
        self.tray_menu.addAction(self.start_action)
        self.tray_menu.addAction(self.stop_action)
        self.tray_menu.addSeparator()
        
        # Add the interval menu directly to the tray menu
        self.tray_menu.addMenu(self.interval_menu)
        
        # Debug the submenu
        logging.info(f"Added Tempo submenu with {len(self.interval_menu.actions())} items")
        for i, action in enumerate(self.interval_menu.actions()):
            logging.info(f"  Tempo menu item {i+1}: {action.text()}")
        
        # Add the range menu directly to the tray menu
        self.tray_menu.addMenu(self.range_menu)
        
        # Debug the submenu
        logging.info(f"Added Range submenu with {len(self.range_menu.actions())} items")
        for i, action in enumerate(self.range_menu.actions()):
            logging.info(f"  Range menu item {i+1}: {action.text()}")
            
        # Add separator
        self.tray_menu.addSeparator()
        
        # Add quit action
        self.tray_menu.addAction(self.quit_action)
        
        # Set the tray icon menu
        self.tray_icon.setContextMenu(self.tray_menu)
        self.tray_icon.show()
        
        # Log menu items for debugging
        logging.info(f"Tempo menu has {len(self.interval_menu.actions())} items")
        menu_items = [action.text() if hasattr(action, 'text') else action.menu().title() for action in self.tray_menu.actions() if action.text() or (hasattr(action, 'menu') and action.menu())]
        logging.info(f"Main menu items: {menu_items}")
        
        # Update action visibility
        self.update_menu_state()
    
    def find_icon_path(self):
        """Find the fidget icon file."""
        script_dir = os.path.dirname(os.path.abspath(__file__))
        icon_path = os.path.join(script_dir, "fidget.png")
        
        if not os.path.exists(icon_path):
            logging.warning(f"Icon file not found at {icon_path}, using default app icon")
            return None
        
        return icon_path
    
    def start_jiggling(self):
        """Start jiggling the mouse."""
        if not self.jiggling:
            self.jiggling = True
            self.next_jiggle_time = time.time() + self.interval
            
            # On macOS, use caffeinate if:
            # 1. Movement range is 0 (Script Awake option), or
            # 2. We're on macOS and not explicitly using mouse movement
            if sys.platform == 'darwin' and (self.movement_range == 0 or not args.force_mouse):
                self.start_caffeinate()
            
            # Start timers (used for all platforms)
            self.jiggle_timer.start(self.interval * 1000)
            self.countdown_timer.start()
            
            logging.info(f"Jiggling started with interval {self.interval} seconds and range {self.movement_range} pixels")
            self.update_menu_state()
    
    def stop_jiggling(self):
        """Stop jiggling the mouse."""
        if self.jiggling:
            self.jiggling = False
            
            # Stop timers
            self.jiggle_timer.stop()
            self.countdown_timer.stop()
            
            # Stop caffeinate process on macOS
            if sys.platform == 'darwin':
                self.stop_caffeinate()
            
            logging.info("Jiggling stopped")
            self.update_menu_state()
    
    def start_caffeinate(self):
        """Start the caffeinate process to prevent sleep on macOS."""
        if sys.platform != 'darwin':
            return
            
        try:
            # Stop any existing process
            self.stop_caffeinate()
            
            # Start a new caffeinate process
            # -d prevents display sleep
            # -i prevents idle sleep
            logging.info("Starting caffeinate to prevent sleep...")
            self.caffeinate_process = subprocess.Popen(
                ["caffeinate", "-d", "-i"],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE
            )
            logging.info(f"Caffeinate process started with PID: {self.caffeinate_process.pid}")
            
        except Exception as e:
            logging.error(f"Error starting caffeinate process: {e}")
            # Fallback to mouse movement if caffeinate fails
            logging.warning("Falling back to mouse movement for sleep prevention")
            self.caffeinate_process = None
            
    def stop_caffeinate(self):
        """Stop the caffeinate process."""
        if self.caffeinate_process:
            try:
                logging.info(f"Stopping caffeinate process (PID: {self.caffeinate_process.pid})...")
                self.caffeinate_process.terminate()
                self.caffeinate_process.wait(timeout=1)
                logging.info("Caffeinate process terminated")
            except Exception as e:
                logging.error(f"Error stopping caffeinate process: {e}")
                try:
                    # Try to kill it if terminate fails
                    self.caffeinate_process.kill()
                except:
                    pass
            finally:
                self.caffeinate_process = None
    
    def set_interval(self, seconds):
        """Set the interval between jiggling."""
        old_interval = self.interval
        self.interval = seconds
        
        if self.jiggling:
            # Reset next jiggle time
            self.next_jiggle_time = time.time() + seconds
            
            # Restart timer with new interval
            self.jiggle_timer.stop()
            self.jiggle_timer.start(seconds * 1000)
        
        logging.info(f"Interval changed from {old_interval} to {self.interval} seconds")
        self.update_menu_state()
        
        # Add visual feedback by updating menu text to show current tempo
        tempo_label = "1 second" if seconds == 1 else f"{seconds} seconds"
        if seconds >= 60:
            minutes = seconds // 60
            remaining_seconds = seconds % 60
            if minutes == 1 and remaining_seconds == 0:
                tempo_label = "1 minute"
            elif minutes == 1:
                tempo_label = f"1 minute {remaining_seconds} seconds"
            elif remaining_seconds == 0:
                tempo_label = f"{minutes} minutes"
            else:
                tempo_label = f"{minutes} minutes {remaining_seconds} seconds"
                
        logging.info(f"Set tempo to: {tempo_label}")
    
    def get_time_remaining(self):
        """Get the time remaining until the next jiggle in seconds."""
        if not self.jiggling:
            return self.interval
        
        remaining = max(0, self.next_jiggle_time - time.time())
        return int(remaining)
    
    def format_time_remaining(self, seconds):
        """Format the time remaining as a string."""
        minutes = seconds // 60
        remaining_seconds = seconds % 60
        
        if minutes > 0:
            return f"{minutes}m{remaining_seconds}s"
        else:
            return f"{remaining_seconds}s"
    
    def update_countdown(self):
        """Update the countdown timer in the menu."""
        if self.jiggling:
            remaining = self.get_time_remaining()
            self.status_action.setText(f"Fidget in: {self.format_time_remaining(remaining)}")
    
    def update_menu_state(self):
        """Update the menu state based on the current jiggling state."""
        # Update action visibility
        self.start_action.setVisible(not self.jiggling)
        self.stop_action.setVisible(self.jiggling)
        
        # Update status action text
        if self.jiggling:
            remaining = self.get_time_remaining()
            status_text = f"Fidget in: {self.format_time_remaining(remaining)}"
            self.status_action.setText(status_text)
        else:
            self.status_action.setText("Idle")
            
        # Update interval menu to show current setting
        for action in self.interval_actions:
            action_text = action.text()
            # Remove checkmark if present
            if action_text.startswith("✓ "):
                action.setText(action_text[2:])
                action_text = action_text[2:]
                
            # Add checkmark to current interval
            if (self.interval == 5 and action_text == "5s") or \
               (self.interval == 30 and action_text == "30s") or \
               (self.interval == 55 and action_text == "55s") or \
               (self.interval == 240 and action_text == "4m") or \
               (self.interval == 540 and action_text == "9m") or \
               (self.interval == 840 and action_text == "14m") or \
               (self.interval == 1740 and action_text == "29m") or \
               (self.interval == 3540 and action_text == "59m"):
                action.setText(f"✓ {action_text}")
                
        # Update range menu to show current setting
        for action in self.range_actions:
            action_text = action.text()
            # Remove checkmark if present
            if action_text.startswith("✓ "):
                action.setText(action_text[2:])
                action_text = action_text[2:]
                
            # Add checkmark to current movement range
            if (self.movement_range == 0 and action_text == "0 - Script Awake") or \
               (self.movement_range == 1 and action_text == "Tiny (1 pixel)") or \
               (self.movement_range == 2 and action_text == "Small (2 pixels)") or \
               (self.movement_range == 5 and action_text == "Medium (5 pixels)") or \
               (self.movement_range == 10 and action_text == "Large (10 pixels)") or \
               (self.movement_range == 20 and action_text == "Extra Large (20 pixels)"):
                action.setText(f"✓ {action_text}")
    
    def move_mouse_relative(self, dx, dy):
        """Move the mouse cursor by a relative delta."""
        if sys.platform == 'darwin':  # macOS
            try:
                # Use a completely different approach: AppleScript
                # This bypasses potential conflicts with other mouse-positioning APIs
                
                # Create AppleScript to move mouse relatively and return before/after positions
                script = f"""
                tell application "System Events"
                    set beforePos to mouse location
                    set x to (item 1 of beforePos) + {dx}
                    set y to (item 2 of beforePos) + {dy}
                    set mouse location to {{x, y}}
                    delay 0.1
                    set afterPos to mouse location
                    return beforePos & afterPos
                end tell
                """
                
                # Execute the AppleScript
                result = subprocess.run(['osascript', '-e', script], capture_output=True, text=True)
                
                # Parse the result (format will be: "x1, y1, x2, y2")
                if result.stdout.strip():
                    try:
                        positions = [int(p.strip()) for p in result.stdout.split(',')]
                        if len(positions) == 4:
                            before_x, before_y, after_x, after_y = positions
                            script_dx = after_x - before_x
                            script_dy = after_y - before_y
                            logging.debug(f"AppleScript reports: Before ({before_x}, {before_y}), After ({after_x}, {after_y}), Delta ({script_dx}, {script_dy})")
                    except Exception as e:
                        logging.error(f"Failed to parse AppleScript output: {e} - Output was: {result.stdout}")
                
                logging.debug(f"Used AppleScript to move mouse by dx={dx}, dy={dy}")
                
            except Exception as e:
                logging.error(f"Error moving mouse with AppleScript on macOS: {e}")
                
                # Fall back to the CGEvent approach if AppleScript fails
                try:
                    # Get current mouse location
                    pos = AppKit.NSEvent.mouseLocation()
                    
                    # Create a mouse moved event
                    move_event = Quartz.CGEventCreateMouseEvent(
                        None,  # No source
                        Quartz.kCGEventMouseMoved,  # Event type
                        Quartz.CGPoint(x=pos.x + dx, y=pos.y + dy),  # Position with delta
                        0  # Left button (irrelevant for move)
                    )
                    
                    # Post the event directly to the session
                    Quartz.CGEventPost(Quartz.kCGSessionEventTap, move_event)
                    
                    # Always re-enable mouse cursor association
                    Quartz.CGAssociateMouseAndMouseCursorPosition(True)
                    
                    logging.debug(f"Fallback: Used CGEvent to move mouse by dx={dx}, dy={dy}")
                    
                except Exception as e2:
                    logging.error(f"Fallback also failed: {e2}")
                
        elif sys.platform == 'win32':  # Windows
            try:
                # Windows MOUSEEVENTF_MOVE uses relative movement
                ctypes.windll.user32.mouse_event(
                    0x0001,  # MOUSEEVENTF_MOVE
                    dx, dy,   # Relative movement
                    0, 0      # Additional data (wheel delta, etc.)
                )
                logging.debug(f"Relative mouse move on Windows: dx={dx}, dy={dy}")
                
            except Exception as e:
                logging.error(f"Error moving mouse relatively on Windows: {e}")
                
        else:  # Linux/X11
            try:
                d = display.Display()
                root = d.screen().root
                
                # Get current pointer position
                pointer = d.screen().root.query_pointer()
                current_x, current_y = pointer.root_x, pointer.root_y
                
                # Move to new position (still using MotionNotify but with calculated position)
                xtest.fake_input(root, X.MotionNotify, x=current_x + dx, y=current_y + dy)
                d.sync()
                
                logging.debug(f"Relative mouse move on Linux: dx={dx}, dy={dy}")
                
            except Exception as e:
                logging.error(f"Error moving mouse relatively on Linux: {e}")

    def perform_jiggle(self):
        """Move the mouse cursor slightly and/or trigger activity to prevent screen sleep."""
        try:
            # For macOS when using the "Script Awake" option (movement_range = 0)
            # or when not explicitly using mouse movement
            if sys.platform == 'darwin' and (self.movement_range == 0 or not args.force_mouse):
                # Check if caffeinate is running, restart if needed
                if self.caffeinate_process and self.caffeinate_process.poll() is not None:
                    logging.warning("Caffeinate process exited unexpectedly, restarting...")
                    self.start_caffeinate()
                # We return True without moving the mouse on macOS if caffeinate is running
                if self.caffeinate_process:
                    # Reset next jiggle time
                    self.next_jiggle_time = time.time() + self.interval
                    logging.debug("Sleep prevention active via caffeinate")
                    return True
            
            # Skip mouse movement if range is 0
            if self.movement_range == 0:
                # This should only happen if we're on a platform that doesn't support caffeinate
                # or if caffeinate failed on macOS
                logging.warning("Range is 0 but no caffeinate available - sleep prevention may not work")
                self.next_jiggle_time = time.time() + self.interval
                return True
                
            # For non-macOS platforms, or if caffeinate failed on macOS,
            # or if explicitly using mouse movement, use mouse movement to prevent sleep
            
            # Get current position for logging only
            x, y, screen_index = self.get_mouse_position()
            
            # Calculate small random movement (using configured range)
            tiny_distance = self.movement_range  # Use the configurable range
            dx = random.randint(-tiny_distance, tiny_distance)
            dy = random.randint(-tiny_distance, tiny_distance)
            
            # Ensure we move at least 1 pixel in some direction to trigger activity
            if dx == 0 and dy == 0:
                dx = 1  # Move at least 1 pixel horizontally if both were zero
            
            logging.info(f"Attempting to move mouse by delta: dx={dx}, dy={dy} (using Range setting: {self.movement_range})")
            
            # Try to move the mouse relatively
            self.move_mouse_relative(dx, dy)
            
            # Get new position for logging
            new_x, new_y, new_screen_index = self.get_mouse_position()
            
            # Calculate actual movement
            actual_dx = new_x - x
            actual_dy = new_y - y
            intended_distance = (dx**2 + dy**2)**0.5  # Pythagorean distance
            actual_distance = (actual_dx**2 + actual_dy**2)**0.5  # Pythagorean distance
            
            logging.info(f"Mouse movement: Intended [dx={dx}, dy={dy}, dist={intended_distance:.2f}] vs Actual [dx={actual_dx}, dy={actual_dy}, dist={actual_distance:.2f}]")
            logging.info(f"Moved mouse from ({x}, {y}) to ({new_x}, {new_y}) on screen {screen_index}")
            
            # Report if the movement was successful
            if x == new_x and y == new_y:
                logging.warning("Mouse position did not change after jiggle attempt!")
            elif abs(actual_dx) > self.movement_range * 2 or abs(actual_dy) > self.movement_range * 2:
                logging.warning(f"Mouse moved more than expected! Range: {self.movement_range}, Actual: dx={actual_dx}, dy={actual_dy}")
                
            # Reset next jiggle time
            self.next_jiggle_time = time.time() + self.interval
            
            return True
        except Exception as e:
            logging.error(f"Error during jiggling: {e}")
            return False
    
    def get_mouse_position(self):
        """Get the current mouse position with multi-monitor support."""
        if sys.platform == 'darwin':  # macOS
            # Get mouse position in global coordinates
            pos = AppKit.NSEvent.mouseLocation()
            
            # Get all screens
            screens = AppKit.NSScreen.screens()
            current_screen = None
            screen_index = 0
            
            # Find which screen the mouse is on
            for i, screen in enumerate(screens):
                frame = screen.frame()
                if (frame.origin.x <= pos.x < frame.origin.x + frame.size.width and
                    frame.origin.y <= pos.y < frame.origin.y + frame.size.height):
                    current_screen = screen
                    screen_index = i
                    break
            
            # If no screen was found, default to main screen
            if current_screen is None:
                current_screen = AppKit.NSScreen.mainScreen()
                screen_index = 0
            
            # Store the current screen info for later use when setting position
            self.current_screen = current_screen
            
            # Return global coordinates and the screen index
            return (int(pos.x), int(pos.y), screen_index)
            
        elif sys.platform == 'win32':  # Windows
            try:
                # Get current cursor position
                pt = ctypes.wintypes.POINT()
                ctypes.windll.user32.GetCursorPos(ctypes.byref(pt))
                
                # Get information about all monitors
                monitor_info = []
                
                def callback(hMonitor, hdcMonitor, lprcMonitor, dwData):
                    monitor_info.append({
                        'handle': hMonitor,
                        'rect': lprcMonitor.contents
                    })
                    return True
                
                # Define callback function type
                MONITORENUMPROC = ctypes.WINFUNCTYPE(
                    ctypes.c_bool,
                    ctypes.c_ulong,
                    ctypes.c_ulong,
                    ctypes.POINTER(ctypes.wintypes.RECT),
                    ctypes.c_ulong
                )
                
                # Enumerate monitors
                ctypes.windll.user32.EnumDisplayMonitors(
                    None, None, MONITORENUMPROC(callback), 0
                )
                
                # Find which monitor the cursor is on
                screen_index = 0
                for i, monitor in enumerate(monitor_info):
                    rect = monitor['rect']
                    if (rect.left <= pt.x <= rect.right and
                        rect.top <= pt.y <= rect.bottom):
                        screen_index = i
                        self.current_monitor = monitor
                        break
                
                return (pt.x, pt.y, screen_index)
            except Exception as e:
                logging.error(f"Error getting mouse position on Windows: {e}")
                return (0, 0, 0)
                
        else:  # Linux/X11
            try:
                d = display.Display()
                s = d.screen()
                root = s.root
                pointer = root.query_pointer()
                
                # Get information about all screens
                screens = []
                for i in range(d.screen_count()):
                    screen = d.screen(i)
                    screens.append({
                        'index': i,
                        'width': screen.width_in_pixels,
                        'height': screen.height_in_pixels
                    })
                
                # Find which screen the pointer is on
                screen_index = 0
                # This is a simplified approach - a more complete implementation would
                # need to consider screen arrangement
                
                self.current_screen_linux = screens[screen_index]
                
                return (pointer.root_x, pointer.root_y, screen_index)
            except Exception as e:
                logging.error(f"Error getting mouse position on Linux: {e}")
                return (0, 0, 0)
    
    def set_mouse_position(self, x, y):
        """Set the mouse position with multi-monitor support."""
        if sys.platform == 'darwin':  # macOS
            # Use global coordinates for setting position
            move_to = Quartz.CGPoint(x=x, y=y)
            Quartz.CGWarpMouseCursorPosition(move_to)
            Quartz.CGAssociateMouseAndMouseCursorPosition(True)
        elif sys.platform == 'win32':  # Windows
            try:
                ctypes.windll.user32.SetCursorPos(x, y)
            except Exception as e:
                logging.error(f"Error setting mouse position on Windows: {e}")
        else:  # Linux/X11
            try:
                d = display.Display()
                root = d.screen().root
                xtest.fake_input(root, X.MotionNotify, x=x, y=y)
                d.sync()
            except Exception as e:
                logging.error(f"Error setting mouse position on Linux: {e}")
    
    def set_movement_range(self, pixels):
        """Set the movement range (maximum pixels to move)."""
        logging.info(f"Setting movement range to {pixels} pixels")
        self.movement_range = pixels
        
        # If changing to 0 range on macOS, start caffeinate
        if sys.platform == 'darwin' and pixels == 0 and self.jiggling:
            self.start_caffeinate()
        # If changing from 0 range on macOS, stop caffeinate if running
        elif sys.platform == 'darwin' and pixels > 0 and args.force_mouse:
            self.stop_caffeinate()
            
        # Update the menu state to reflect the new range
        self.update_menu_state()
    
    def run(self):
        """Run the application main loop."""
        try:
            self.tray_icon.show()
            return self.app.exec()
        except KeyboardInterrupt:
            logging.info("Keyboard interrupt received, exiting...")
            self.stop_jiggling()
            return 0
        except Exception as e:
            logging.error(f"Error: {e}")
            return 1

if __name__ == "__main__":
    app = FidgetApp()
    sys.exit(app.run()) 