import AppKit
import ApplicationServices

/// Raises and minimises other applications' windows. Each EVE client is its own
/// process, so activating the process is usually enough; the Accessibility API
/// covers un-minimising and the case of a client owning more than one window.
enum WindowActivator {
    static func activate(_ client: EVEClient) {
        let app = AXUIElementCreateApplication(client.pid)
        if let window = axWindow(of: app, titled: client.title) {
            setBool(window, kAXMinimizedAttribute, false)
            AXUIElementPerformAction(window, kAXRaiseAction as CFString)
            AXUIElementSetAttributeValue(app, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        }
        NSRunningApplication(processIdentifier: client.pid)?.activate()
    }

    static func minimize(_ client: EVEClient) {
        let app = AXUIElementCreateApplication(client.pid)
        guard let window = axWindow(of: app, titled: client.title) else { return }
        setBool(window, kAXMinimizedAttribute, true)
    }

    /// Moves and resizes a client's own window, for putting a session back the
    /// way it was left. Accessibility measures from the top left of the main
    /// display, the same as the window list this app reads.
    static func setFrame(_ frame: CGRect, of client: EVEClient) {
        let app = AXUIElementCreateApplication(client.pid)
        guard let window = axWindow(of: app, titled: client.title) else { return }

        var origin = CGPoint(x: frame.origin.x, y: frame.origin.y)
        var size = CGSize(width: frame.width, height: frame.height)
        guard let position = AXValueCreate(.cgPoint, &origin),
              let extent = AXValueCreate(.cgSize, &size) else { return }
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, position)
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, extent)
    }

    static func isMinimized(_ client: EVEClient) -> Bool {
        let app = AXUIElementCreateApplication(client.pid)
        guard let window = axWindow(of: app, titled: client.title) else { return false }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &value)
                == .success else { return false }
        return (value as? Bool) ?? false
    }

    /// Picks the client's game window: the one whose title matches, else the
    /// main window, else whatever the process has.
    private static func axWindow(of app: AXUIElement, titled title: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement], !windows.isEmpty else { return nil }

        for window in windows where axTitle(of: window) == title {
            return window
        }

        var main: CFTypeRef?
        if AXUIElementCopyAttributeValue(app, kAXMainWindowAttribute as CFString, &main) == .success,
           let mainWindow = main, CFGetTypeID(mainWindow) == AXUIElementGetTypeID() {
            return (mainWindow as! AXUIElement)
        }

        return windows.first
    }

    private static func axTitle(of window: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &value)
                == .success else { return nil }
        return value as? String
    }

    private static func setBool(_ element: AXUIElement, _ attribute: String, _ value: Bool) {
        AXUIElementSetAttributeValue(element, attribute as CFString,
                                     value ? kCFBooleanTrue : kCFBooleanFalse)
    }
}
