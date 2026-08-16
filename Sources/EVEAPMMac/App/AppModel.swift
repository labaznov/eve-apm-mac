import AppKit
import Combine

/// Wires the parts together and owns them for the lifetime of the process.
@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    let config: ConfigStore
    let registry: ClientRegistry
    let logs = LogMonitor()
    let controller: ThumbnailController
    let hotkeys = HotkeyManager()

    @Published private(set) var hasScreenRecording = Permissions.hasScreenRecording
    @Published private(set) var hasAccessibility = Permissions.hasAccessibility

    private var cancellables = Set<AnyCancellable>()
    private var permissionTimer: Timer?
    private var configuredHotkeys: [Hotkey] = []

    private init() {
        let config = ConfigStore()
        let registry = ClientRegistry(bundleIdentifiers: { config.settings.clientBundleIdentifiers })
        self.config = config
        self.registry = registry
        controller = ThumbnailController(registry: registry, config: config, logs: logs)
    }

    func start() {
        Log.info("starting with screen recording \(hasScreenRecording), accessibility \(hasAccessibility)")

        hotkeys.onAction = { [weak self] action in self?.perform(action) }
        Publishers.CombineLatest3(config.$settings.map(\.hotkeys),
                                  config.$globalHotkeys,
                                  config.$settings.map(\.hotkeysRequireEVEFocus))
            .removeDuplicates { $0 == $1 }
            .sink { [weak self] hotkeys, global, _ in
                self?.configuredHotkeys = hotkeys + global
                self?.refreshHotkeyRegistration()
            }
            .store(in: &cancellables)

        watchFrontmostApplication()

        config.$settings
            .removeDuplicates()
            .sink { [weak self] settings in self?.logs.apply(settings) }
            .store(in: &cancellables)

        controller.start()
        registry.start()
        logs.start()
        watchPermissions()
    }

    func perform(_ action: HotkeyAction) {
        guard isHotkeyContext else { return }

        switch action {
        case .activate(let character): controller.activate(character: character)
        case .cycleForward: controller.cycle(forward: true)
        case .cycleBackward: controller.cycle(forward: false)
        case .toggleThumbnails: controller.setThumbnailsHidden(!controller.areThumbnailsHidden)
        case .toggleHotkeys: toggleHotkeySuspension()
        case .switchProfile(let name): config.switchTo(name)
        case .cycleProfileForward: config.cycleProfile(forward: true)
        case .cycleProfileBackward: config.cycleProfile(forward: false)
        }
    }

    /// Every EVE client the app is tracking, one entry per process.
    var runningClients: [NSRunningApplication] {
        let pids = Set(registry.clients.map(\.pid))
        return pids.compactMap { NSRunningApplication(processIdentifier: $0) }
    }

    /// Asks each client to quit the way the Quit menu item would, so the game
    /// closes its session itself rather than being killed under it.
    @discardableResult
    func quitAllClients() -> Int {
        let clients = runningClients
        for client in clients {
            client.terminate()
        }
        Log.info("asked \(clients.count) client(s) to quit")
        return clients.count
    }

    func toggleHotkeySuspension() {
        hotkeys.toggleSuspended()
        refreshHotkeyRegistration()
    }

    func setHotkeysSuspended(_ suspended: Bool) {
        suspended ? hotkeys.suspend() : hotkeys.resume()
        refreshHotkeyRegistration()
    }

    /// A registered shortcut is swallowed system-wide, so restricting shortcuts
    /// to EVE cannot mean ignoring them when they fire: they are unregistered
    /// while another application is in front, and the key reaches that
    /// application untouched.
    private func refreshHotkeyRegistration() {
        hotkeys.apply(isHotkeyContext && !hotkeys.isSuspended ? configuredHotkeys : [])
    }

    private func watchFrontmostApplication() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification,
                     NSWorkspace.didTerminateApplicationNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshHotkeyRegistration() }
            }
        }
    }

    private var isHotkeyContext: Bool {
        guard config.settings.hotkeysRequireEVEFocus else { return true }
        guard let bundle = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else {
            return false
        }
        return config.settings.clientBundleIdentifiers.contains(bundle)
    }

    /// The grants can be given while the app runs, and there is no notification
    /// for either of them, so both are polled while any is missing.
    private func watchPermissions() {
        refreshPermissions()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshPermissions() }
        }
    }

    private func refreshPermissions() {
        let screen = Permissions.hasScreenRecording
        let accessibility = Permissions.hasAccessibility
        if screen != hasScreenRecording { hasScreenRecording = screen }
        if accessibility != hasAccessibility { hasAccessibility = accessibility }
        if screen && accessibility {
            permissionTimer?.invalidate()
            permissionTimer = nil
        }
    }
}
