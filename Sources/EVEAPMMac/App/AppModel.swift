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
        Publishers.CombineLatest(config.$settings.map(\.hotkeys), config.$globalHotkeys)
            .map { $0 + $1 }
            .removeDuplicates()
            .sink { [weak self] hotkeys in self?.hotkeys.apply(hotkeys) }
            .store(in: &cancellables)

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
        switch action {
        case .activate(let character): controller.activate(character: character)
        case .cycleForward: controller.cycle(forward: true)
        case .cycleBackward: controller.cycle(forward: false)
        case .toggleThumbnails: controller.setThumbnailsHidden(!controller.areThumbnailsHidden)
        case .toggleHotkeys: hotkeys.toggleSuspended()
        case .switchProfile(let name): config.switchTo(name)
        case .cycleProfileForward: config.cycleProfile(forward: true)
        case .cycleProfileBackward: config.cycleProfile(forward: false)
        }
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
