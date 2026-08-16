import AppKit
import Combine
import ScreenCaptureKit

/// Keeps one thumbnail panel alive per EVE client and applies the settings to
/// all of them: this is where discovery, capture, layout and the switching
/// behaviour meet.
@MainActor
final class ThumbnailController {
    private struct Thumbnail {
        let panel: ThumbnailPanel
        let view: ThumbnailView
        let stream: CaptureStream
        var client: EVEClient
        var pixelSize: CGSize
        var isPlaced: Bool
    }

    private let registry: ClientRegistry
    private let config: ConfigStore
    private var thumbnails: [CGWindowID: Thumbnail] = [:]
    private var cancellables = Set<AnyCancellable>()
    private var minimizeTask: Task<Void, Never>?
    private var thumbnailsHidden = false

    init(registry: ClientRegistry, config: ConfigStore) {
        self.registry = registry
        self.config = config
    }

    func start() {
        registry.$clients
            .sink { [weak self] clients in self?.sync(with: clients) }
            .store(in: &cancellables)

        registry.$frontmostPID
            .removeDuplicates()
            .sink { [weak self] _ in self?.frontmostChanged() }
            .store(in: &cancellables)

        config.$settings
            .removeDuplicates()
            .sink { [weak self] settings in self?.apply(settings) }
            .store(in: &cancellables)
    }

    // MARK: - Commands

    func activate(_ client: EVEClient) {
        WindowActivator.activate(client)
    }

    func activate(character: String) {
        guard let client = registry.clients.first(where: { $0.character == character }) else { return }
        activate(client)
    }

    func cycle(forward: Bool) {
        let clients = registry.clients
        guard !clients.isEmpty else { return }
        let current = clients.firstIndex { $0.pid == registry.frontmostPID }
        let next = current.map { forward ? ($0 + 1) % clients.count
                                         : ($0 - 1 + clients.count) % clients.count } ?? 0
        activate(clients[next])
    }

    func setThumbnailsHidden(_ hidden: Bool) {
        thumbnailsHidden = hidden
        refreshVisibility()
    }

    var areThumbnailsHidden: Bool { thumbnailsHidden }

    // MARK: - Lifecycle of panels

    private func sync(with clients: [EVEClient]) {
        let live = Set(clients.map(\.windowID))
        for id in thumbnails.keys where !live.contains(id) {
            remove(id)
        }
        for client in clients {
            if thumbnails[client.windowID] == nil {
                add(client)
            } else {
                update(client)
            }
        }
        refreshVisibility()
    }

    private func add(_ client: EVEClient) {
        let stream = CaptureStream()
        let view = ThumbnailView(captureLayer: stream.layer)
        let panel = ThumbnailPanel(view: view)
        let id = client.windowID

        view.onActivate = { [weak self] in
            guard let self, let thumbnail = thumbnails[id] else { return }
            activate(thumbnail.client)
        }
        view.onMoved = { [weak self] origin in
            guard let self, let thumbnail = thumbnails[id] else { return }
            config.settings.positions[thumbnail.client.label] = StoredPoint(origin)
        }
        stream.onFailure = { [weak self] in
            Task { @MainActor in self?.restart(id) }
        }

        thumbnails[id] = Thumbnail(panel: panel, view: view, stream: stream,
                                   client: client, pixelSize: .zero, isPlaced: false)
        layout(id)
        panel.orderFront(nil)
        startCapture(id)
    }

    private func remove(_ id: CGWindowID) {
        guard let thumbnail = thumbnails.removeValue(forKey: id) else { return }
        thumbnail.panel.orderOut(nil)
        Task { await thumbnail.stream.stop() }
    }

    private func update(_ client: EVEClient) {
        guard var thumbnail = thumbnails[client.windowID] else { return }
        let aspectChanged = abs(thumbnail.client.aspectRatio - client.aspectRatio) > 0.01
        thumbnail.client = client
        thumbnails[client.windowID] = thumbnail
        layout(client.windowID)
        if aspectChanged {
            startCapture(client.windowID)
        }
    }

    private func restart(_ id: CGWindowID) {
        guard thumbnails[id] != nil else { return }
        startCapture(id)
    }

    private func startCapture(_ id: CGWindowID) {
        guard let thumbnail = thumbnails[id],
              let window = registry.window(for: id) else { return }
        let size = thumbnail.pixelSize
        let frameRate = config.settings.frameRate
        Task { await thumbnail.stream.start(window: window, pixelSize: size, frameRate: frameRate) }
    }

    // MARK: - Appearance

    private func apply(_ settings: Settings) {
        for id in thumbnails.keys {
            layout(id)
        }
        refreshVisibility()
        scheduleAutoMinimize()
    }

    /// Resizes and repaints one thumbnail. The origin is only imposed the first
    /// time a panel appears, so a poll of the client list never yanks a panel
    /// out from under the pointer.
    private func layout(_ id: CGWindowID) {
        guard var thumbnail = thumbnails[id] else { return }
        let settings = config.settings
        let width = settings.thumbnailWidth
        let height = (width / thumbnail.client.aspectRatio).rounded()
        let panel = thumbnail.panel
        let size = CGSize(width: width, height: height)

        if panel.frame.size != size {
            panel.setContentSize(size)
        }
        if !thumbnail.isPlaced {
            let origin = settings.positions[thumbnail.client.label]?.cgPoint
                ?? defaultOrigin(for: panel, index: thumbnails.count - 1)
            panel.setFrameOrigin(origin)
            thumbnail.isPlaced = true
        }
        panel.ensureOnScreen()
        panel.setAlwaysOnTop(settings.alwaysOnTop)
        panel.alphaValue = settings.opacity
        panel.ignoresMouseEvents = false

        let isActive = thumbnail.client.pid == registry.frontmostPID
        thumbnail.view.isDraggable = !settings.lockPositions
        thumbnail.view.apply(label: settings.showCharacterName ? thumbnail.client.label : nil,
                             color: settings.labelColor,
                             border: settings.borderColor(for: thumbnail.client, isActive: isActive),
                             borderWidth: settings.borderWidth)

        let scale = panel.screen?.backingScaleFactor ?? 2
        let pixelSize = CGSize(width: width * scale, height: height * scale)
        if pixelSize != thumbnail.pixelSize {
            thumbnail.pixelSize = pixelSize
            thumbnails[id] = thumbnail
            let stream = thumbnail.stream
            let frameRate = settings.frameRate
            Task {
                if stream.isRunning {
                    await stream.reconfigure(pixelSize: pixelSize, frameRate: frameRate)
                }
            }
        } else {
            thumbnails[id] = thumbnail
        }
    }

    private func defaultOrigin(for panel: ThumbnailPanel, index: Int) -> CGPoint {
        guard let screen = panel.screen ?? NSScreen.main else { return .zero }
        let step: CGFloat = 24
        return CGPoint(x: screen.visibleFrame.minX + 40 + CGFloat(index) * step,
                       y: screen.visibleFrame.maxY - 40 - panel.frame.height - CGFloat(index) * step)
    }

    private func refreshVisibility() {
        let settings = config.settings
        for (id, thumbnail) in thumbnails {
            let isActive = thumbnail.client.pid == registry.frontmostPID
            let visible = !thumbnailsHidden && !(settings.hideActiveThumbnail && isActive)
            if visible {
                if !thumbnail.panel.isVisible { thumbnail.panel.orderFront(nil) }
            } else if thumbnail.panel.isVisible {
                thumbnail.panel.orderOut(nil)
            }
            thumbnail.view.apply(label: settings.showCharacterName ? thumbnail.client.label : nil,
                                 color: settings.labelColor,
                                 border: settings.borderColor(for: thumbnail.client, isActive: isActive),
                                 borderWidth: settings.borderWidth)
            _ = id
        }
    }

    // MARK: - Auto minimise

    private func frontmostChanged() {
        refreshVisibility()
        scheduleAutoMinimize()
    }

    private func scheduleAutoMinimize() {
        minimizeTask?.cancel()
        let settings = config.settings
        guard settings.autoMinimizeEnabled,
              let front = registry.frontmostPID,
              registry.clients.contains(where: { $0.pid == front }) else { return }

        let delay = settings.autoMinimizeDelay
        minimizeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.minimizeInactive(except: front)
        }
    }

    private func minimizeInactive(except front: pid_t) {
        let settings = config.settings
        for client in registry.clients where client.pid != front && settings.minimizes(client) {
            WindowActivator.minimize(client)
        }
    }
}
