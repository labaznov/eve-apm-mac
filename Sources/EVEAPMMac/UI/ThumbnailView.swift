import AppKit
import AVFoundation

/// Everything drawn on one thumbnail besides the capture itself.
struct ThumbnailAppearance: Equatable {
    var name: String?
    var system: String?
    var alert: String?
    var labelColor: RGBAColor
    var border: RGBAColor
    var borderWidth: Double
}

/// The contents of one thumbnail: the live capture, a border, the character
/// name, the system it sits in and whatever just happened to it. Owns the mouse
/// handling too, because a press has to mean either "drag me" or "switch to
/// that client" and only the gesture tells them apart.
final class ThumbnailView: NSView {
    var onActivate: (() -> Void)?
    var onMoved: ((CGPoint) -> Void)?
    var onMoveEnded: (() -> Void)?
    var isDraggable = true

    private let captureLayer: CALayer
    private let nameLayer = CATextLayer()
    private let systemLayer = CATextLayer()
    private let alertLayer = CATextLayer()
    private var dragOrigin: CGPoint?
    private var didDrag = false
    private var shown: ThumbnailAppearance?

    private static let dragThreshold: CGFloat = 3
    private static let lineHeight: CGFloat = 16

    init(captureLayer: CALayer) {
        self.captureLayer = captureLayer
        super.init(frame: .zero)

        wantsLayer = true
        layer?.masksToBounds = true
        layer?.backgroundColor = CGColor(gray: 0, alpha: 1)
        layer?.addSublayer(captureLayer)

        for label in [nameLayer, systemLayer, alertLayer] {
            label.fontSize = 12
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
        systemLayer.foregroundColor = appearance.labelColor.cgColor

        alertLayer.string = appearance.alert
        alertLayer.isHidden = appearance.alert == nil

        layer?.borderColor = appearance.border.cgColor
        layer?.borderWidth = appearance.borderWidth
        layoutLayers()
    }

    override func layout() {
        super.layout()
        layoutLayers()
    }

    private func layoutLayers() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        let inset = layer?.borderWidth ?? 0
        let scale = window?.backingScaleFactor ?? 2
        let width = bounds.width - inset * 2

        captureLayer.frame = bounds.insetBy(dx: inset, dy: inset)
        captureLayer.contentsScale = scale

        for label in [nameLayer, systemLayer, alertLayer] {
            label.contentsScale = scale
        }
        systemLayer.frame = CGRect(x: inset, y: inset + 2, width: width, height: Self.lineHeight)
        nameLayer.frame = CGRect(x: inset, y: bounds.height - inset - Self.lineHeight - 2,
                                 width: width, height: Self.lineHeight)
        alertLayer.frame = CGRect(x: inset, y: (bounds.height - Self.lineHeight * 1.5) / 2,
                                  width: width, height: Self.lineHeight * 1.5)

        CATransaction.commit()
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
        window.setFrameOrigin(CGPoint(x: window.frame.origin.x + delta.x,
                                      y: window.frame.origin.y + delta.y))
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
