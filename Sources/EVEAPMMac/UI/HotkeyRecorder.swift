import AppKit
import SwiftUI

/// A field that listens for one key press and reports it as a shortcut. Used
/// instead of a text field because a hotkey is a key code, not text.
struct HotkeyRecorder: NSViewRepresentable {
    @Binding var keyCode: UInt32
    @Binding var modifiers: UInt32

    func makeNSView(context: Context) -> RecorderView {
        let view = RecorderView()
        view.onCapture = { code, mask in
            keyCode = code
            modifiers = mask
        }
        return view
    }

    func updateNSView(_ view: RecorderView, context: Context) {
        view.shortcut = keyCode == 0
            ? "Click to record"
            : KeyCombo.description(keyCode: keyCode, modifiers: modifiers)
        view.needsDisplay = true
    }

    final class RecorderView: NSView {
        var onCapture: ((UInt32, UInt32) -> Void)?
        var shortcut = "Click to record" { didSet { needsDisplay = true } }

        private var isRecording = false { didSet { needsDisplay = true } }

        override var acceptsFirstResponder: Bool { true }
        override var intrinsicContentSize: NSSize { NSSize(width: 150, height: 24) }

        override func mouseDown(with event: NSEvent) {
            window?.makeFirstResponder(self)
            isRecording = true
        }

        override func resignFirstResponder() -> Bool {
            isRecording = false
            return true
        }

        override func keyDown(with event: NSEvent) {
            guard isRecording else { return super.keyDown(with: event) }
            isRecording = false
            window?.makeFirstResponder(nil)
            onCapture?(UInt32(event.keyCode),
                       KeyCombo.carbonModifiers(from: event.modifierFlags.rawValue))
        }

        override func draw(_ dirtyRect: NSRect) {
            let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 5, yRadius: 5)
            (isRecording ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
            NSColor.controlBackgroundColor.setFill()
            path.fill()
            path.lineWidth = isRecording ? 2 : 1
            path.stroke()

            let text = isRecording ? "Press a key…" : shortcut
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 12),
                .foregroundColor: NSColor.labelColor
            ]
            let size = (text as NSString).size(withAttributes: attributes)
            (text as NSString).draw(
                at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2),
                withAttributes: attributes)
        }
    }
}
