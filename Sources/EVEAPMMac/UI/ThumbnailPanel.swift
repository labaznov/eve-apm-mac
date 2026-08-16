import AppKit

/// A borderless always-on-top window that never takes focus, so clicking a
/// thumbnail hands focus straight to the EVE client instead of to this app.
final class ThumbnailPanel: NSPanel {
    init(view: ThumbnailView) {
        super.init(contentRect: CGRect(x: 0, y: 0, width: 240, height: 135),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)

        contentView = view
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]
        hidesOnDeactivate = false
        isOpaque = false
        hasShadow = false
        backgroundColor = .clear
        isReleasedWhenClosed = false
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func setAlwaysOnTop(_ onTop: Bool) {
        level = onTop ? .floating : .normal
    }

    /// Nudges the panel back onto a screen after a display change, so a
    /// remembered position on a disconnected monitor does not hide it.
    func ensureOnScreen() {
        guard !NSScreen.screens.contains(where: { $0.visibleFrame.intersects(frame) }),
              let screen = NSScreen.main else { return }
        setFrameOrigin(CGPoint(x: screen.visibleFrame.midX - frame.width / 2,
                               y: screen.visibleFrame.midY - frame.height / 2))
    }
}
