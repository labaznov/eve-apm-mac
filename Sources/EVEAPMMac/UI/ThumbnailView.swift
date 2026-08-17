import AppKit
import AVFoundation

/// Everything drawn on one thumbnail besides the capture itself.
struct ThumbnailAppearance: Equatable {
    var name: String?
    var namePosition: OverlayPosition = .bottom
    var system: String?
    var systemPosition: OverlayPosition = .top
    var alert: String?
    var labelColor: RGBAColor
    var systemColor: RGBAColor = .label
    var fontSize: Double = 12
    /// A plate behind the labels, for a thumbnail of a bright scene.
    var labelBackground: RGBAColor?
    var border: RGBAColor
    var borderWidth: Double
    var borderStyle: BorderStyle = .solid
}

/// The contents of one thumbnail: the live capture, a border, the character
/// name, the system it sits in and whatever just happened to it. Owns the mouse
/// handling too, because a press has to mean either "drag me" or "switch to
/// that client" and only the gesture tells them apart.
final class ThumbnailView: NSView {
    var onActivate: (() -> Void)?
    var onMoved: ((CGPoint) -> Void)?
    var onMoveEnded: (() -> Void)?
    /// Asked where a dragged thumbnail should actually land, so it can line up
    /// with its neighbours.
    var snapping: ((CGRect) -> CGPoint)?
    var isDraggable = true

    private let captureLayer: CALayer
    private let borderLayer = CAShapeLayer()
    private let nameLayer = CATextLayer()
    private let systemLayer = CATextLayer()
    private let alertLayer = CATextLayer()
    private var dragOrigin: CGPoint?
    private var didDrag = false
    private var shown: ThumbnailAppearance?

    private static let dragThreshold: CGFloat = 3

    init(captureLayer: CALayer) {
        self.captureLayer = captureLayer
        super.init(frame: .zero)

        wantsLayer = true
        layer?.masksToBounds = true
        layer?.backgroundColor = CGColor(gray: 0, alpha: 1)
        layer?.addSublayer(captureLayer)

        borderLayer.fillColor = nil
        layer?.addSublayer(borderLayer)

        for label in [nameLayer, systemLayer, alertLayer] {
            label.alignmentMode = .center
            label.truncationMode = .end
            label.shadowColor = CGColor(gray: 0, alpha: 1)
            label.shadowOpacity = 1
            label.shadowRadius = 2
            label.shadowOffset = .zero
            layer?.addSublayer(label)
        }
        alertLayer.backgroundColor = CGColor(gray: 0, alpha: 0.65)
        alertLayer.foregroundColor = CGColor(srgbRed: 1, green: 0.72, blue: 0.15, alpha: 1)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("ThumbnailView is created in code only")
    }

    override var isFlipped: Bool { true }

    func apply(_ appearance: ThumbnailAppearance) {
        guard appearance != shown else { return }
        shown = appearance

        nameLayer.string = appearance.name
        nameLayer.isHidden = appearance.name == nil
        nameLayer.foregroundColor = appearance.labelColor.cgColor

        systemLayer.string = appearance.system
        systemLayer.isHidden = appearance.system == nil
        systemLayer.foregroundColor = appearance.systemColor.cgColor

        alertLayer.string = appearance.alert
        alertLayer.isHidden = appearance.alert == nil

        for label in [nameLayer, systemLayer] {
            label.fontSize = appearance.fontSize
            label.backgroundColor = appearance.labelBackground?.cgColor
        }
        alertLayer.fontSize = appearance.fontSize

        // The stroke sits on the boundary, so half of it falls outside a clipped
        // layer; doubling the width leaves the asked-for thickness visible.
        borderLayer.strokeColor = appearance.border.cgColor
        borderLayer.lineWidth = appearance.borderWidth * 2
        borderLayer.lineDashPattern = appearance.borderStyle.dashPattern(width: appearance.borderWidth)
        borderLayer.isHidden = appearance.borderWidth <= 0

        layoutLayers()
    }

    override func layout() {
        super.layout()
        layoutLayers()
    }

    private func layoutLayers() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        let appearance = shown
        let inset = appearance?.borderWidth ?? 0
        let scale = window?.backingScaleFactor ?? 2
        let lineHeight = ((appearance?.fontSize ?? 12) * 1.4).rounded()
        let width = bounds.width - inset * 2

        captureLayer.frame = bounds.insetBy(dx: inset, dy: inset)
        captureLayer.contentsScale = scale

        borderLayer.frame = bounds
        borderLayer.path = CGPath(rect: bounds, transform: nil)

        for label in [nameLayer, systemLayer, alertLayer] {
            label.contentsScale = scale
        }
        nameLayer.frame = row(at: appearance?.namePosition ?? .bottom,
                              inset: inset, width: width, height: lineHeight)
        systemLayer.frame = row(at: appearance?.systemPosition ?? .top,
                                inset: inset, width: width, height: lineHeight)
        alertLayer.frame = CGRect(x: inset, y: (bounds.height - lineHeight * 1.5) / 2,
                                  width: width, height: lineHeight * 1.5)

        // Both labels asked for the same edge; one steps aside.
        if !nameLayer.isHidden, !systemLayer.isHidden,
           appearance?.namePosition == appearance?.systemPosition {
            nameLayer.frame.origin.y += appearance?.namePosition == .top ? lineHeight : -lineHeight
        }

        CATransaction.commit()
    }

    private func row(at position: OverlayPosition, inset: CGFloat,
                     width: CGFloat, height: CGFloat) -> CGRect {
        let y = position == .top ? inset + 2 : bounds.height - inset - height - 2
        return CGRect(x: inset, y: y, width: width, height: height)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func mouseDown(with event: NSEvent) {
        dragOrigin = NSEvent.mouseLocation
        didDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDraggable, let origin = dragOrigin, let window else { return }
        let location = NSEvent.mouseLocation
        let delta = CGPoint(x: location.x - origin.x, y: location.y - origin.y)
        guard didDrag || hypot(delta.x, delta.y) > Self.dragThreshold else { return }

        didDrag = true
        dragOrigin = location
        let moved = CGRect(origin: CGPoint(x: window.frame.origin.x + delta.x,
                                           y: window.frame.origin.y + delta.y),
                           size: window.frame.size)
        window.setFrameOrigin(snapping?(moved) ?? moved.origin)
        onMoved?(window.frame.origin)
    }

    override func mouseUp(with event: NSEvent) {
        defer { dragOrigin = nil }
        if didDrag {
            if let window { onMoved?(window.frame.origin) }
            onMoveEnded?()
        } else {
            onActivate?()
        }
    }
}

extension RGBAColor {
    var cgColor: CGColor {
        CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }

    var nsColor: NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }

    init(_ color: NSColor) {
        let converted = color.usingColorSpace(.sRGB) ?? .white
        self.init(red: Double(converted.redComponent),
                  green: Double(converted.greenComponent),
                  blue: Double(converted.blueComponent),
                  alpha: Double(converted.alphaComponent))
    }
}
