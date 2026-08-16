import AppKit

/// Decides whether a remembered thumbnail position still makes sense on the
/// displays attached right now. A position from another machine, or from a
/// monitor that has since been unplugged, would otherwise put a thumbnail where
/// nobody can see it.
enum ScreenGeometry {
    static func fits(_ frame: CGRect, in visibleFrames: [CGRect]) -> Bool {
        visibleFrames.contains { $0.contains(frame) }
    }

    static func fits(_ frame: CGRect) -> Bool {
        fits(frame, in: NSScreen.screens.map(\.visibleFrame))
    }
}
