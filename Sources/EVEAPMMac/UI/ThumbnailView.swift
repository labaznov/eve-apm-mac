import AppKit
import AVFoundation

/// The contents of one thumbnail: the live capture, a border and the character
/// name. Owns the mouse handling too, because a press has to mean either "drag
/// me" or "switch to that client" and only the gesture tells them apart.
final class ThumbnailView: NSView {
    var onActivate: (() -> Void)?
    var onMoved: ((CGPoint) -> Void)?
    var isDraggable = true

    private let captureLayer: CALayer
    private let labelLayer = CATextLayer()
    private var dragOrigin: CGPoint?
    private var didDrag = false

    private static let dragThreshold: CGFloat = 3

    init(captureLayer: CALayer) {
        self.captureLayer = captureLayer
        super.init(frame: .zero)

        wantsLayer = true
        layer?.masksToBounds = true
        layer?.backgroundColor = CGColor(gray: 0, alpha: 1)
        layer?.addSublayer(captureLayer)

        labelLayer.fontSize = 12
        labelLayer.alignmentMode = .center
        labelLayer.truncationMode = .end
        labelLayer.shadowColor = CGColor(gray: 0, alpha: 1)
        labelLayer.shadowOpacity = 1
        labelLayer.shadowRadius = 2
        labelLayer.shadowOffset = .zero
        layer?.addSublayer(labelLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("ThumbnailView is created in code only")
    }

    override var isFlipped: Bool { true }

    func apply(label: String?, color: RGBAColor, border: RGBAColor, borderWidth: Double) {
        labelLayer.string = label
        labelLayer.isHidden = label == nil
        labelLayer.foregroundColor = color.cgColor
        layer?.borderColor = border.cgColor
        layer?.borderWidth = borderWidth
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
        captureLayer.frame = bounds.insetBy(dx: inset, dy: inset)
        labelLayer.contentsScale = window?.backingScaleFactor ?? 2
        captureLayer.contentsScale = labelLayer.contentsScale
        labelLayer.frame = CGRect(x: inset, y: bounds.height - inset - 18,
                                  width: bounds.width - inset * 2, height: 16)
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
    }

    override func mouseUp(with event: NSEvent) {
        defer { dragOrigin = nil }
        if didDrag {
            if let window { onMoved?(window.frame.origin) }
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
