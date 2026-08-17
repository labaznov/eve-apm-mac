import CoreGraphics

/// Pulls a dragged thumbnail into line with its neighbours and the edges of the
/// screen, so a row of thumbnails ends up actually straight.
enum Snapping {
    /// - Parameters:
    ///   - frame: where the thumbnail is being dragged to.
    ///   - targets: frames to line up with — other thumbnails, and the usable
    ///     area of each display.
    ///   - distance: how near an edge has to be before it pulls. Zero switches
    ///     snapping off.
    /// - Returns: the origin to use, which is the one passed in when nothing is
    ///   near enough.
    static func snap(_ frame: CGRect, to targets: [CGRect], within distance: CGFloat) -> CGPoint {
        guard distance > 0, !targets.isEmpty else { return frame.origin }

        var origin = frame.origin
        if let dx = pull(low: frame.minX, high: frame.maxX,
                         edges: targets.flatMap { [$0.minX, $0.maxX] }, within: distance) {
            origin.x += dx
        }
        if let dy = pull(low: frame.minY, high: frame.maxY,
                         edges: targets.flatMap { [$0.minY, $0.maxY] }, within: distance) {
            origin.y += dy
        }
        return origin
    }

    /// The smallest move that brings either edge of the thumbnail onto one of
    /// the edges around it.
    private static func pull(low: CGFloat, high: CGFloat,
                             edges: [CGFloat], within distance: CGFloat) -> CGFloat? {
        var best: CGFloat?
        for edge in edges {
            for offset in [edge - low, edge - high] where abs(offset) <= distance {
                if best == nil || abs(offset) < abs(best!) { best = offset }
            }
        }
        return best
    }
}
