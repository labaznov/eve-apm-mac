import CoreGraphics

/// Arranges the thumbnails of clients that have no character yet. They cannot be
/// remembered by name, so instead of scattering them they are gathered at one
/// spot in the order they were found.
enum StackLayout {
    static let spacing: CGFloat = 10

    static func position(index: Int, mode: StackMode, anchor: CGPoint, size: CGSize) -> CGPoint {
        switch mode {
        case .row:
            CGPoint(x: anchor.x + CGFloat(index) * (size.width + spacing), y: anchor.y)
        case .column:
            // Downwards on screen, which is decreasing y in this coordinate space.
            CGPoint(x: anchor.x, y: anchor.y - CGFloat(index) * (size.height + spacing))
        case .pile:
            anchor
        }
    }
}
