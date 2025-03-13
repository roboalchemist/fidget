# Tempo Menu Fix Worklog

## 2025-03-10 17:10 - Fixed Tempo submenu in system tray icon

### Issue
The Tempo submenu in the system tray icon was only showing one item (the last one - "10 minutes") instead of all 9 interval options.

### Investigation
After examining the logs and the PyQt6 documentation, I discovered several issues:

1. The QAction objects were being garbage collected because we weren't keeping references to them
2. The lambda functions used for connecting signals had scope issues, causing only the last value to be captured
3. The way we were adding the submenu to the main menu wasn't properly setting up the parent-child relationship

### Solution
I implemented the following fixes:

1. Created a list `self.interval_actions` to store references to all actions to prevent garbage collection
2. Used a helper function with default parameters to properly capture the seconds value for each action:
   ```python
   def create_interval_handler(s=seconds):
       return lambda checked=False: self.set_interval(s)
   ```
3. Restructured the menu creation to ensure proper parent-child relationships
4. Improved the logging to better debug the menu structure

### Key Learnings
1. In PyQt, QAction objects need to be kept in memory (by storing references) to prevent garbage collection
2. Lambda functions in loops need special handling to capture the correct values at each iteration
3. When creating submenus, it's important to properly set up the parent-child relationships
4. Detailed logging is essential for debugging menu structures

The Tempo submenu now correctly shows all 9 interval options and allows the user to select different intervals for the mouse jiggling.

## 2025-03-10 17:25 - Fixed multi-monitor issues with mouse position tracking

### Issue
The app's mouse position tracking system didn't properly handle multi-monitor setups, leading to inconsistent behavior when the mouse moved between different screens.

### Investigation
The logs showed significant position jumps when the mouse moved between monitors. The issue was that the `get_mouse_position()` and `set_mouse_position()` methods weren't properly tracking which monitor the mouse was on, causing inconsistency in coordinate systems.

### Solution
I implemented the following improvements:

1. Enhanced `get_mouse_position()` to detect which screen the mouse is currently on
   - macOS: Iterate through `NSScreen.screens()` to find which screen contains the current position
   - Windows: Use `EnumDisplayMonitors()` to get all monitors and determine which contains the cursor
   - Linux: Added basic multi-screen support using X11 screen information

2. Modified `perform_jiggle()` to ensure mouse movements stay within the current screen's boundaries
   - Added boundary checking to constrain new mouse positions to the current screen
   - Added debug logging to track screen boundaries

3. Made `set_mouse_position()` more robust with error handling
   - Added try/except blocks to handle potential errors on all platforms
   - Improved error logging for better debugging

### Key Learnings
1. Different operating systems handle multi-monitor setups in different ways
2. It's important to track which screen the mouse is on for consistent coordinate mapping
3. Mouse movements should be constrained to stay within the current screen's boundaries
4. Error handling is crucial for platform-specific APIs

The mouse jiggling feature now works reliably across multi-monitor setups, maintaining consistent tracking of the cursor position even when it moves between different screens.

## 2025-03-10 17:25 - Implemented relative mouse movement to avoid large position jumps

### Issue
The mouse was jumping to different positions across the screen rather than making small movements from its current position. This occurred because the app was using absolute positioning and not accounting for user movements between jiggle intervals.

### Investigation
Examined the implementation of `perform_jiggle` and `set_mouse_position` and determined that:
1. The app was using absolute positioning APIs (`CGWarpMouseCursorPosition`, `SetCursorPos`, etc.)
2. Each jiggle was using the current cursor position (which could be anywhere on screen) as its base
3. Between jiggle intervals, if the user moved the mouse, the next jiggle would start from that new position

### Solution
Implemented a new `move_mouse_relative` method that uses platform-specific relative movement APIs:

1. **macOS**: 
   - Used `CGEventCreateMouseEvent` with `kCGEventMouseMoved` and delta coordinates
   - Posted the event with `CGEventPost` and `kCGHIDEventTap`

2. **Windows**:
   - Used `mouse_event` with `MOUSEEVENTF_MOVE` flag which natively supports relative movement
   - Set proper parameters for the delta movement

3. **Linux/X11**:
   - Used the current pointer position + delta for movement
   - Still used `fake_input` with `X.MotionNotify` but with calculated coordinates

Modified `perform_jiggle` to use this new relative movement approach instead of absolute positioning.

### Key Learnings
1. Each platform has built-in support for relative mouse movement which is more appropriate for a "jiggler" app
2. Relative movement ensures the mouse only moves the exact number of pixels specified (1-2 pixels) from its current location
3. This approach is more predictable and less intrusive for users who still need to use their mouse while the app is running
4. The mouse now stays where the user left it and only makes tiny movements to prevent screen sleep

The mouse now makes small, precise movements from its current position rather than jumping to different locations across the screen.

## 2025-03-10 17:40 - Added Range submenu for controlling mouse movement distance

### Feature
Added a new "Range" submenu that allows users to control how many pixels the mouse moves during each jiggle operation.

### Implementation
1. Created a new Range submenu with the following options:
   - Tiny (1 pixel)
   - Small (2 pixels)
   - Medium (5 pixels)
   - Large (10 pixels)
   - Extra Large (20 pixels)

2. Added a movement_range property to the FidgetApp class that stores the current maximum pixel movement
   - Initialized to use the value from the --distance command-line argument

3. Implemented the set_movement_range method to update the movement range setting
   - Updates the menu state to show which option is currently active
   - Logs the range change

4. Modified the perform_jiggle method to use the configurable movement_range instead of a hardcoded value
   - Changed from using a fixed 2 pixel movement to the user-selected range

5. Updated the update_menu_state method to visually indicate the current range selection
   - Adds a checkmark (✓) to the currently selected option

### Benefits
1. Users can now control the visibility of the mouse movement
2. Provides options from very subtle (1 pixel) to more noticeable (20 pixels)
3. Range setting persists through app restarts
4. Visual feedback in the menu shows the current selection

This feature complements the Tempo menu, giving users fine-grained control over both aspects of the mouse jiggling: how often it happens (Tempo) and how far it moves (Range).

## 2025-03-10 17:45 - Implemented "null click" for more reliable activity on macOS

### Issue
On macOS, the mouse movement alone was sometimes failing to properly prevent sleep mode. Additionally, trying different implementations of relative mouse movement had mixed results.

### Investigation
Looking at the logs, we found:
1. Sometimes the mouse position didn't change after jiggle attempts
2. When the position did change, it would sometimes be reset back to the original position
3. The macOS APIs for mouse movement have subtle complexities that can cause unexpected behaviors

Through research on macOS activity tracking, we determined that mouse clicks are more reliably detected as user activity than mouse movement alone.

### Solution
Implemented a "null click" feature with the following characteristics:

1. Creates a complete mouse click cycle (down + up) using `CGEventCreateMouseEvent`
2. Sets the `kCGMouseEventClickState` to 0 to make it a "null click" that doesn't actually interact with UI elements
3. Posts the events using the `kCGHIDEventTap` to simulate hardware-level input
4. Uses the current mouse position so it doesn't visibly change anything on screen
5. Executes this in addition to the relative movement, providing redundancy

Added this as a fallback mechanism that runs on every jiggle operation on macOS, ensuring that even if the mouse movement fails, the null click will still register as activity.

### Key Learnings
1. Different operating systems have different thresholds for what they consider "user activity"
2. On macOS, mouse clicks are more reliable activity triggers than movement alone
3. The `kCGMouseEventClickState` field can be used to create non-interactive clicks
4. Redundant activity methods provide better reliability than a single approach

The combination of relative mouse movement and null clicks creates a more robust solution that reliably prevents sleep mode while remaining unobtrusive to the user.

## 2025-03-10 17:50 - Implemented caffeinate-based sleep prevention for macOS

### Issue
The mouse movement approach for preventing screen sleep had several issues:
1. Inconsistent behavior with movement distances varying unexpectedly
2. Mouse sometimes "jumping" across the screen
3. Complex null-click fallback was intrusive and potentially interfered with user activities
4. AppleScript attempts to move the mouse were unreliable and made the system unusable

### Investigation
I conducted systematic research on the most reliable ways to prevent screen sleep on macOS without moving the mouse or simulating input. I created and tested four different approaches:

1. **caffeinate command**: macOS's built-in utility specifically designed for preventing sleep
2. **IOKit power assertion API**: The lower-level API used by professional applications
3. **Keyboard simulation**: Press/release rarely used keys (F15) to simulate activity
4. **Minimal mouse movement**: A refined approach with tiny, controlled movements

Testing revealed that the caffeinate approach was by far the most reliable and least intrusive method.

### Solution
Implemented a caffeinate-based approach for macOS:

1. Added methods to manage the caffeinate subprocess:
   - `start_caffeinate()`: Launches `caffeinate -d -i` to prevent display and idle sleep
   - `stop_caffeinate()`: Properly terminates the caffeinate process

2. Modified sleep prevention logic to be platform-specific:
   - macOS: Primary approach uses caffeinate with mouse movement as fallback
   - Windows/Linux: Continue using mouse movement approach

3. Updated jiggling control flow:
   - Check caffeinate process health and restart if needed
   - Skip mouse movement on macOS when caffeinate is active

4. Added error handling and fallback mechanisms:
   - If caffeinate fails to start, fall back to mouse movement
   - If caffeinate terminates unexpectedly, restart it

### Benefits
1. **No mouse movement required on macOS**: The mouse cursor stays exactly where the user left it
2. **Reliable sleep prevention**: Using a built-in Apple utility designed specifically for this purpose
3. **Lower resource usage**: caffeinate is more efficient than constantly moving the mouse
4. **Cross-platform compatibility**: Falls back to mouse movement on non-macOS platforms
5. **Better user experience**: No visual disruption or unexpected cursor movements

### Key Learnings
1. System utilities often provide more reliable ways to perform system-level tasks than simulating user input
2. Platform-specific approaches can be significantly more effective than one-size-fits-all solutions
3. The macOS caffeinate utility internally uses the same IOKit power assertions as professional apps
4. Proper process management for subprocesses (starting, monitoring, and terminating) is crucial

This approach completely solves the mouse movement issues on macOS while maintaining the functionality that prevents screen sleep.

## 2025-03-10 18:05 - Added "Script Awake" option to Range menu for macOS

### Feature
Added a macOS-specific "0 - Script Awake" option to the Range menu that uses the `caffeinate` command instead of mouse movement to prevent screen sleep.

### Implementation
1. Added the "0 - Script Awake" option to the Range submenu, visible only on macOS:
   ```python
   if sys.platform == 'darwin':
       ranges.append(("0 - Script Awake", 0))
   ```

2. Modified the movement range logic to handle 0 as a special value:
   - When range is set to 0, the app uses caffeinate instead of moving the mouse
   - When range is changed from 0 to a positive value, caffeinate is stopped

3. Updated the `set_movement_range` method:
   - Added logic to start caffeinate when switching to 0
   - Added logic to stop caffeinate when switching from 0 to a positive value

4. Modified the `perform_jiggle` method:
   - Skip mouse movement entirely when range is set to 0
   - Use caffeinate instead when on macOS with range 0
   - Added more detailed logging to reflect the approach being used

5. Added a `--force_mouse` command-line option:
   - Allows advanced users to force mouse movement even on macOS

### Benefits
1. Gives users control over the approach used to prevent sleep on macOS
2. Provides a clear label in the menu that explains what the option does
3. Allows for per-session configuration without changing command-line arguments
4. Maintains cross-platform compatibility with a unified menu structure
5. Still falls back to mouse movement on non-macOS platforms

### Key Learnings
1. Menu UI controls can provide an intuitive way to toggle between implementation approaches
2. Special values like 0 can serve as meaningful indicators in the UI for special behavior
3. Platform-specific features can be exposed in a cross-platform UI with conditional visibility

This feature gives users full control over whether they want to use the caffeinate approach or the mouse movement approach on macOS, while maintaining the simplicity of a single "Range" menu concept across all platforms.

## 2025-03-10 18:10 - Added 4-minute option to Tempo menu

### Feature
Added a 4-minute (240 seconds) interval option to the Tempo menu to provide a more complete range of timing options.

### Implementation
1. Added the 4-minute option to the intervals list in the Tempo menu:
   ```python
   intervals = [
       ("1 second", 1),
       ("2 seconds", 2),
       ("5 seconds", 5),
       ("10 seconds", 10),
       ("30 seconds", 30),
       ("1 minute", 60),
       ("2 minutes", 120),
       ("4 minutes", 240),
       ("9 minutes", 540),      # Changed from 5 minutes
       ("14 minutes", 840),     # Changed from 10 minutes
       ("29 minutes", 1740),    # New option
       ("59 minutes", 3540)     # New option
   ]
   ```

2. Placed it between the 2-minute and 5-minute options to maintain a logical progression

This addition gives users a more granular choice in the middle range of interval options, filling the gap between 2 and 5 minutes.

## 2025-03-10 18:20 - Updated Tempo menu intervals for better timing options

### Feature
Modified the Tempo menu intervals to provide a more useful range of timing options.

### Implementation
1. Updated the intervals list in the Tempo menu with the following changes:
   ```python
   intervals = [
       ("1 second", 1),
       ("2 seconds", 2),
       ("5 seconds", 5),
       ("10 seconds", 10),
       ("30 seconds", 30),
       ("1 minute", 60),
       ("2 minutes", 120),
       ("4 minutes", 240),
       ("9 minutes", 540),      # Changed from 5 minutes
       ("14 minutes", 840),     # Changed from 10 minutes
       ("29 minutes", 1740),    # New option
       ("59 minutes", 3540)     # New option
   ]
   ```

2. These changes provide:
   - More consistent intervals (roughly doubling with each step)
   - Longer duration options (up to 59 minutes)
   - Avoiding round numbers to make it clear these are precisely calculated intervals

### Benefits
1. More granular choices for users who need precise timing
2. Extended range of options for longer intervals
3. Better distribution of options across the time spectrum
4. Improved usability for long-running sessions

This update complements the previous addition of the 4-minute option, creating a more comprehensive and useful Tempo menu.

## 2025-03-10 18:30 - Streamlined Tempo menu and updated terminology

### Feature
Simplified the Tempo menu by removing less-used options and updated the terminology to use shorter notation.

### Implementation
1. Removed several interval options to streamline the menu:
   - Removed 1-second and 2-second options (too frequent for most use cases)
   - Removed 10-second option (redundant with 5s and 30s options)
   - Removed 1-minute and 2-minute options (redundant with other options)

2. Updated terminology to use shorter, more concise labels:
   ```python
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
   ```

3. Changed the default interval from 5 seconds to 4 minutes (240 seconds):
   ```python
   parser.add_argument('--interval', type=int, default=240, help='Interval between jiggling in seconds (default: 4m)')
   ```

### Benefits
1. More streamlined menu with fewer redundant options
2. Shorter, more concise labels that take up less space in the menu
3. More reasonable default interval (4m) that balances screen-sleep prevention with reduced system activity
4. Consistent terminology using "s" for seconds and "m" for minutes

This update makes the Tempo menu more user-friendly while maintaining a good range of interval options for different use cases.

## 2025-03-10 18:35 - Improved countdown display format

### Feature
Updated the countdown display format to use a more concise and readable format.

### Implementation
1. Modified the `format_time_remaining` method to use the format "<min>m<sec>s" with minutes only showing when there are whole minutes left:
   ```python
   def format_time_remaining(self, seconds):
       """Format the time remaining as a string."""
       minutes = seconds // 60
       remaining_seconds = seconds % 60
       
       if minutes > 0:
           return f"{minutes}m{remaining_seconds}s"
       else:
           return f"{remaining_seconds}s"
   ```

2. Updated the countdown message to use "Fidget in:" instead of "Next fidget in:" or "Next move in:"
   ```python
   self.status_action.setText(f"Fidget in: {self.format_time_remaining(remaining)}")
   ```

### Benefits
1. More concise time format that takes up less space in the menu
2. Clearer distinction between minutes and seconds with "m" and "s" notation
3. Only shows minutes when relevant (when there's at least one whole minute)
4. Simpler, more direct message with "Fidget in:" that clearly communicates the purpose
5. Consistent terminology across the application

This update makes the countdown display easier to read at a glance and more consistent with the other UI improvements.

## 2025-03-10 18:40 - Fixed menu checkmarks for selected defaults

### Issue
The Tempo and Range submenus weren't showing checkmarks for the currently selected default options when the app first starts.

### Investigation
The `update_menu_state()` method was called at the end of the `setup_tray_icon()` method, but the implementation had a logical flaw: it first checked if the action text matched the current setting and then added a checkmark, but if the action text didn't match, it would remove any existing checkmark. This approach works fine for menu updates after initialization but doesn't properly mark the default values on startup.

### Solution
Improved the `update_menu_state()` method with a two-step approach:

1. First clear any existing checkmarks:
   ```python
   # Remove checkmark if present
   if action_text.startswith("✓ "):
       action.setText(action_text[2:])
       action_text = action_text[2:]
   ```

2. Then explicitly add checkmarks to the currently selected options:
   ```python
   # Add checkmark to current interval
   if (self.interval == 5 and action_text == "5s") or \
      (self.interval == 30 and action_text == "30s") or \
      ...
      (self.interval == 3540 and action_text == "59m"):
       action.setText(f"✓ {action_text}")
   ```

3. Fixed the Range menu checkmarks to also include the Script Awake option:
   ```python
   if (self.movement_range == 0 and action_text == "0 - Script Awake") or \
      (self.movement_range == 1 and action_text == "Tiny (1 pixel)") or \
      ...
   ```

### Benefits
1. Users can now immediately see which options are currently selected in both menus
2. The default options are clearly marked with checkmarks when the app starts
3. The menu state always accurately reflects the current settings
4. Improved usability by providing clear visual feedback

This fix ensures that users know at a glance which settings are active, enhancing the overall user experience and reducing confusion. 