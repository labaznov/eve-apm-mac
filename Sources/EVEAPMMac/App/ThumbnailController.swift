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
    private let logs: LogMonitor
    private var thumbnails: [CGWindowID: Thumbnail] = [:]
    private var cancellables = Set<AnyCancellable>()
    private var minimizeTask: Task<Void, Never>?
    private var thumbnailsHidden = false
    /// Published values arrive before the properties behind them settle, so
    /// the controller keeps its own copy of what it was told.
    private var frontmostPID: pid_t?
    private var settings = Settings()

    private var alerts: [String: Alert] = [:]
    private var alertTasks: [String: Task<Void, Never>] = [:]

    init(registry: ClientRegistry, config: ConfigStore, logs: LogMonitor) {
        self.registry = registry
        self.config = config
        self.logs = logs
    }

    func start() {
        settings = config.settings

        registry.$clients
            .sink { [weak self] clients in self?.sync(with: clients) }
            .store(in: &cancellables)

        registry.$frontmostPID
            .removeDuplicates()
            .sink { [weak self] pid in self?.frontmostChanged(to: pid) }
            .store(in: &cancellables)

        config.$settings
            .removeDuplicates()
            .sink { [weak self] settings in self?.apply(settings) }
            .store(in: &cancellables)

        logs.$systems
            .removeDuplicates()
            .sink { [weak self] _ in self?.refreshVisibility() }
            .store(in: &cancellables)

        logs.onAlert = { [weak self] character, alert in self?.raise(alert, for: character) }

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.screensChanged() }
            }
    }

    // MARK: - Alerts

    /// Shows a notice on the character's thumbnail for a while. The point is to
    /// catch the eye on a client the player is not looking at, so by default an
    /// alert on the active client is dropped.
    private func raise(_ alert: Alert, for character: String) {
        let isActive = registry.clients.contains { $0.character == character && $0.pid == frontmostPID }
        guard settings.alertsOnActiveClient || !isActive else { return }

        alerts[character] = alert
        refreshVisibility()

        let duration = settings.alertDuration
        alertTasks[character]?.cancel()
        alertTasks[character] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled, let self else { return }
            alerts[character] = nil
            refreshVisibility()
        }
    }

    private func appearance(for client: EVEClient) -> ThumbnailAppearance {
        let isActive = client.pid == frontmostPID
        let character = client.character
        return ThumbnailAppearance(
            name: settings.showCharacterName ? client.label : nil,
            namePosition: settings.characterNamePosition,
            system: settings.showSystemName ? character.flatMap { logs.systems[$0] } : nil,
            systemPosition: settings.systemNamePosition,
            alert: character.flatMap { alerts[$0] }?.text,
            labelColor: settings.labelColor,
            systemColor: settings.systemNameColor,
            fontSize: settings.labelFontSize,
            labelBackground: settings.overlayBackground ? settings.overlayBackgroundColor : nil,
            border: settings.borderColor(for: client, isActive: isActive),
            borderWidth: settings.borderWidth(isActive: isActive),
            borderStyle: settings.borderStyle(isActive: isActive))
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
        let current = clients.firstIndex { $0.pid == frontmostPID }
        let next = current.map { forward ? ($0 + 1) % clients.count
                                         : ($0 - 1 + clients.count) % clients.count } ?? 0
        activate(clients[next])
    }

    /// Steps through one named group rather than every client. A group is a
    /// list of characters the user wrote down, so it is walked in that order,
    /// skipping the ones that are not running.
    func cycleGroup(named name: String, forward: Bool) {
        guard let group = settings.group(named: name) else {
            Log.error("no cycle group named \(name)")
            return
        }

        var members = group.characters.filter { character in
            registry.clients.contains { $0.character == character }
        }
        if group.includesNotLoggedIn {
            members += registry.clients.filter { $0.character == nil }.map(\.label)
        }

        let current = registry.clients.first { $0.pid == frontmostPID }?.label
        guard let target = CycleOrder.next(in: members, from: current,
                                           forward: forward, loops: group.loops),
              let client = registry.clients.first(where: { $0.label == target }) else {
            Log.info("group \(name): nothing to step to from \(current ?? "nothing") in \(members)")
            return
        }
        Log.info("group \(name): \(current ?? "nothing") -> \(target)")
        activate(client)
    }

    /// True when every running capture has gone quiet, which is what a wedged
    /// window server looks like from here.
    var isCaptureStalled: Bool {
        let running = thumbnails.values.filter(\.stream.isRunning)
        return !running.isEmpty && running.allSatisfy(\.stream.isStalled)
    }

    /// Tears the captures down and builds them again, for use after the window
    /// server has been restarted underneath them.
    func restartCaptures() {
        for id in thumbnails.keys {
            guard let stream = thumbnails[id]?.stream else { continue }
            Task { [weak self] in
                await stream.stop()
                self?.restart(id)
            }
        }
    }

    func setThumbnailsHidden(_ hidden: Bool) {
        thumbnailsHidden = hidden
        refreshVisibility()
    }

    var areThumbnailsHidden: Bool { thumbnailsHidden }

    // MARK: - Lifecycle of panels

    private func sync(with clients: [EVEClient]) {
        frontmostPID = registry.frontmostPID
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
            remember(origin, of: thumbnail.client)
        }
        view.onMoveEnded = { [weak self] in self?.config.flush() }
        view.snapping = { [weak self] frame in
            guard let self else { return frame.origin }
            return Snapping.snap(frame, to: snapTargets(excluding: id),
                                 within: settings.snapDistance)
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
        // A client starts on the login screen and only names its character once
        // one is chosen. That is the moment its remembered position becomes
        // known, so the thumbnail is placed again.
        let characterChanged = thumbnail.client.character != client.character
        thumbnail.client = client
        if characterChanged { thumbnail.isPlaced = false }
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
        let frameRate = settings.frameRate
        Task { await thumbnail.stream.start(window: window, pixelSize: size, frameRate: frameRate) }
    }

    // MARK: - Appearance

    private func apply(_ settings: Settings) {
        self.settings = settings
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
        let width = settings.thumbnailWidth(for: thumbnail.client)
        let height = (width / thumbnail.client.aspectRatio).rounded()
        let panel = thumbnail.panel
        let size = CGSize(width: width, height: height)

        if panel.frame.size != size {
            panel.setContentSize(size)
        }
        if !thumbnail.isPlaced {
            // Before a character is known the thumbnail cascades into a free
            // spot; once it is, it moves to that character's place if it has
            // one and stays put if it does not.
            let fallback = panel.isVisible ? panel.frame.origin
                                           : defaultOrigin(for: panel, index: thumbnails.count - 1)
            place(panel, of: thumbnail.client, size: size, fallback: fallback)
            thumbnail.isPlaced = true
        }
        panel.setAlwaysOnTop(settings.alwaysOnTop)
        panel.alphaValue = settings.opacity
        panel.ignoresMouseEvents = false

        thumbnail.view.isDraggable = !settings.lockPositions
        thumbnail.view.apply(appearance(for: thumbnail.client))

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

    /// Puts a thumbnail where it was left. A remembered position is honoured
    /// untouched as long as it lands on a display attached now; one that does
    /// not is dropped and replaced with a fresh position, which is written back
    /// straight away so the file never holds a place nobody can reach.
    private func place(_ panel: ThumbnailPanel, of client: EVEClient, size: CGSize,
                       fallback: CGPoint) {
        let remembered = client.character.flatMap { settings.positions[$0]?.cgPoint }
        if let remembered, ScreenGeometry.fits(CGRect(origin: remembered, size: size)) {
            panel.setFrameOrigin(remembered)
            return
        }

        if remembered != nil {
            Log.info("dropped an off-screen position for \(client.label)")
        }
        panel.setFrameOrigin(fallback)
        remember(panel.frame.origin, of: client)
    }

    /// Positions are written the moment a thumbnail moves, and pushed to disk
    /// at once, so a crash or a forced quit cannot lose an arrangement.
    private func remember(_ origin: CGPoint, of client: EVEClient) {
        // Only a character earns a remembered place. A client on the login
        // screen is a different process every session, and keying its position
        // on that would fill the file with entries nothing can use again.
        guard let character = client.character else { return }
        let stored = StoredPoint(origin)
        guard settings.positions[character] != stored else { return }
        settings.positions[character] = stored
        config.settings.positions[character] = stored
    }

    /// What a dragged thumbnail lines up against: its neighbours and the usable
    /// area of every display.
    private func snapTargets(excluding id: CGWindowID) -> [CGRect] {
        thumbnails.filter { $0.key != id && $0.value.panel.isVisible }.map(\.value.panel.frame)
            + NSScreen.screens.map(\.visibleFrame)
    }

    /// Re-checks every thumbnail against the displays, for when a monitor is
    /// plugged in or unplugged.
    private func screensChanged() {
        for (id, thumbnail) in thumbnails {
            guard !ScreenGeometry.fits(thumbnail.panel.frame) else { continue }
            thumbnails[id]?.isPlaced = false
            layout(id)
        }
    }

    private func defaultOrigin(for panel: ThumbnailPanel, index: Int) -> CGPoint {
        guard let screen = panel.screen ?? NSScreen.main else { return .zero }
        let step: CGFloat = 24
        return CGPoint(x: screen.visibleFrame.minX + 40 + CGFloat(index) * step,
                       y: screen.visibleFrame.maxY - 40 - panel.frame.height - CGFloat(index) * step)
    }

    private func refreshVisibility() {
        for (id, thumbnail) in thumbnails {
            let isActive = thumbnail.client.pid == frontmostPID
            let visible = !thumbnailsHidden && !(settings.hideActiveThumbnail && isActive)
            if visible {
                if !thumbnail.panel.isVisible { thumbnail.panel.orderFront(nil) }
            } else if thumbnail.panel.isVisible {
                thumbnail.panel.orderOut(nil)
            }
            thumbnail.view.apply(appearance(for: thumbnail.client))
            _ = id
        }
    }

    // MARK: - Auto minimise

    private func frontmostChanged(to pid: pid_t?) {
        frontmostPID = pid
        refreshVisibility()
        scheduleAutoMinimize()
    }

    private func scheduleAutoMinimize() {
        minimizeTask?.cancel()
        guard settings.autoMinimizeEnabled,
              let front = frontmostPID,
              registry.clients.contains(where: { $0.pid == front }) else { return }

        let delay = settings.autoMinimizeDelay
        minimizeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.minimizeInactive(except: front)
        }
    }

    private func minimizeInactive(except front: pid_t) {
        for client in registry.clients where client.pid != front && settings.minimizes(client) {
            WindowActivator.minimize(client)
        }
    }
}
