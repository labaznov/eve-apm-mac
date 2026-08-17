import AppKit

/// Decides whether a remembered thumbnail position still makes sense on the
/// displays attached right now. A position from another machine, or from a
/// monitor that has since been unplugged, would otherwise put a thumbnail where
/// nobody can see it.
enum ScreenGeometry {
    /// How much of a thumbnail has to land on a display for the position to
    /// stand. Well under half of one hanging off an edge is still a position the
    /// user chose; a sliver is not.
    static let minimumVisible: CGFloat = 0.6

    /// The whole display area is counted, not the part left over after the menu
    /// bar and the Dock: a floating thumbnail is allowed to sit over either, and
    /// often does.
    static func fits(_ frame: CGRect, in displays: [CGRect]) -> Bool {
        let area = frame.width * frame.height
        guard area > 0, !displays.isEmpty else { return false }

        let visible = displays.reduce(0.0) { total, display in
            let shared = display.intersection(frame)
            return total + (shared.isNull ? 0 : shared.width * shared.height)
        }
        return visible / area >= minimumVisible
    }

    static func fits(_ frame: CGRect) -> Bool {
        fits(frame, in: NSScreen.screens.map(\.frame))
    }
}
