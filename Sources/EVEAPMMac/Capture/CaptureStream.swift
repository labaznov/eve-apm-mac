import AVFoundation
import CoreMedia
import ScreenCaptureKit

/// A live mirror of one EVE client window, rendered into a layer. This is the
/// macOS answer to the DWM thumbnail the Windows original registers: the window
/// server keeps sending frames even while the window sits behind others.
@MainActor
final class CaptureStream {
    let layer = AVSampleBufferDisplayLayer()

    private var stream: SCStream?
    private var output: FrameOutput?
    private let queue = DispatchQueue(label: "com.github.labaznov.eveapmmac.capture",
                                      qos: .userInitiated)
    private(set) var isRunning = false
    private(set) var lastFrameAt: Date?
    private var startedAt: Date?
    var onFailure: (() -> Void)?

    /// True when the stream was accepted but the window server has gone quiet.
    /// A minimised client also stops producing frames, so this is a hint rather
    /// than a fault on its own.
    var isStalled: Bool {
        guard isRunning, let since = lastFrameAt ?? startedAt else { return false }
        return Date().timeIntervalSince(since) > Self.stallAfter
    }

    private static let stallAfter: TimeInterval = 10

    init() {
        layer.videoGravity = .resizeAspect
        layer.backgroundColor = CGColor(gray: 0, alpha: 1)
    }

    func start(window: SCWindow, pixelSize: CGSize, frameRate: Int) async {
        await stop()

        let filter = SCContentFilter(desktopIndependentWindow: window)
        let configuration = Self.configuration(pixelSize: pixelSize, frameRate: frameRate)
        let output = FrameOutput { [weak self] buffer in
            Task { @MainActor in self?.display(buffer.value) }
        }
        let delegate = StreamDelegate { [weak self] error in
            Task { @MainActor in self?.handleFailure(error) }
        }

        do {
            let stream = SCStream(filter: filter, configuration: configuration, delegate: delegate)
            try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: queue)
            try await stream.startCapture()
            self.stream = stream
            self.output = output
            self.delegate = delegate
            startedAt = Date()
            lastFrameAt = nil
            isRunning = true
        } catch {
            Log.error("cannot capture window \(window.windowID): \(error.localizedDescription)")
            isRunning = false
            onFailure?()
        }
    }

    func stop() async {
        guard let stream else { return }
        self.stream = nil
        output = nil
        delegate = nil
        isRunning = false
        try? await stream.stopCapture()
    }

    func reconfigure(pixelSize: CGSize, frameRate: Int) async {
        guard let stream else { return }
        do {
            try await stream.updateConfiguration(
                Self.configuration(pixelSize: pixelSize, frameRate: frameRate))
        } catch {
            Log.error("cannot update capture configuration: \(error.localizedDescription)")
        }
    }

    private var delegate: StreamDelegate?

    private static func configuration(pixelSize: CGSize, frameRate: Int) -> SCStreamConfiguration {
        let configuration = SCStreamConfiguration()
        configuration.width = max(2, Int(pixelSize.width.rounded()) & ~1)
        configuration.height = max(2, Int(pixelSize.height.rounded()) & ~1)
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(max(1, frameRate)))
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.showsCursor = false
        configuration.queueDepth = 3
        configuration.scalesToFit = true
        configuration.capturesAudio = false
        return configuration
    }

    private func display(_ buffer: CMSampleBuffer) {
        guard Self.isCompleteFrame(buffer) else { return }
        lastFrameAt = Date()
        let renderer = layer.sampleBufferRenderer
        if renderer.status == .failed {
            renderer.flush()
        }
        renderer.enqueue(buffer)
    }

    private func handleFailure(_ error: Error) {
        Log.error("capture stopped: \(error.localizedDescription)")
        isRunning = false
        stream = nil
        output = nil
        delegate = nil
        onFailure?()
    }

    /// ScreenCaptureKit also emits frames marked idle or blank when nothing
    /// changed; showing those would wipe the thumbnail.
    private static func isCompleteFrame(_ buffer: CMSampleBuffer) -> Bool {
        guard buffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(buffer,
                                                                        createIfNecessary: false)
                  as? [[SCStreamFrameInfo: Any]],
              let raw = attachments.first?[.status] as? Int,
              let status = SCFrameStatus(rawValue: raw) else { return false }
        return status == .complete
    }
}

/// Carries a sample buffer from the capture queue to the main actor. Core Media
/// buffers are reference types Apple has not marked sendable, and handing one
/// over intact is exactly what the renderer needs.
private struct FrameBox: @unchecked Sendable {
    let value: CMSampleBuffer
}

private final class FrameOutput: NSObject, SCStreamOutput {
    private let handler: @Sendable (FrameBox) -> Void

    init(handler: @escaping @Sendable (FrameBox) -> Void) {
        self.handler = handler
    }

    func stream(_ stream: SCStream,
                didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of type: SCStreamOutputType) {
        guard type == .screen else { return }
        setDisplayImmediately(sampleBuffer)
        handler(FrameBox(value: sampleBuffer))
    }

    /// The renderer has no timebase of its own, so every frame is marked for
    /// immediate display instead of being scheduled against a clock.
    private func setDisplayImmediately(_ buffer: CMSampleBuffer) {
        guard let array = CMSampleBufferGetSampleAttachmentsArray(buffer, createIfNecessary: true),
              CFArrayGetCount(array) > 0 else { return }
        let raw = CFArrayGetValueAtIndex(array, 0)
        let attachments = unsafeBitCast(raw, to: CFMutableDictionary.self)
        CFDictionarySetValue(attachments,
                             Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                             Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
    }
}

private final class StreamDelegate: NSObject, SCStreamDelegate {
    private let onError: @Sendable (Error) -> Void

    init(onError: @escaping @Sendable (Error) -> Void) {
        self.onError = onError
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        onError(error)
    }
}
