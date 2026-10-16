import AppKit
import ApplicationServices

/// Cursor queries and synthetic movement. All coordinates are Quartz global display
/// coordinates (origin at the top-left of the main display, y grows downward), which is
/// what both `CGEvent.location` and posted mouse events use.
@MainActor
enum Mouse {
    struct Position: Equatable {
        let x: Int
        let y: Int
        let screenIndex: Int
    }

    static func location() -> CGPoint {
        CGEvent(source: nil)?.location ?? .zero
    }

    /// Current cursor position (truncated to whole points) and the index of the screen
    /// (in `NSScreen.screens` order) that contains it.
    static func position() -> Position {
        let point = location()
        return Position(x: Int(point.x), y: Int(point.y), screenIndex: screenIndex(containing: point))
    }

    static func screenIndex(containing point: CGPoint) -> Int {
        var displayID: CGDirectDisplayID = 0
        var count: UInt32 = 0
        guard CGGetDisplaysWithPoint(point, 1, &displayID, &count) == .success, count > 0 else {
            return 0
        }
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return NSScreen.screens.firstIndex { screen in
            (screen.deviceDescription[key] as? NSNumber)?.uint32Value == displayID
        } ?? 0
    }

    /// Moves the cursor by a relative offset by posting a mouse-moved event at the HID
    /// event tap, so the system treats it as user activity.
    static func moveRelative(dx: Int, dy: Int) -> Bool {
        let origin = location()
        let target = CGPoint(x: origin.x + CGFloat(dx), y: origin.y + CGFloat(dy))
        let source = CGEventSource(stateID: .hidSystemState)
        guard let event = CGEvent(mouseEventSource: source, mouseType: .mouseMoved,
                                  mouseCursorPosition: target, mouseButton: .left) else {
            return false
        }
        event.setIntegerValueField(.mouseEventDeltaX, value: Int64(dx))
        event.setIntegerValueField(.mouseEventDeltaY, value: Int64(dy))
        event.post(tap: .cghidEventTap)
        return true
    }

    /// Posting synthetic events requires the Accessibility permission. When `prompt` is
    /// true and the permission is missing, macOS shows its standard request dialog.
    static func hasAccessibilityPermission(prompt: Bool) -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}
