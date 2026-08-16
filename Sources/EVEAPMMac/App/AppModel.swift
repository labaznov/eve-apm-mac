import AppKit
import Combine

/// Wires the parts together and owns them for the lifetime of the process.
@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    let config: ConfigStore
    let registry: ClientRegistry
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
        controller = ThumbnailController(registry: registry, config: config)
    }

    func start() {
        hotkeys.onAction = { [weak self] action in self?.perform(action) }
        config.$settings
            .map(\.hotkeys)
            .removeDuplicates()
            .sink { [weak self] hotkeys in self?.hotkeys.apply(hotkeys) }
            .store(in: &cancellables)

        controller.start()
        registry.start()
        watchPermissions()
    }

    func perform(_ action: HotkeyAction) {
        switch action {
        case .activate(let character): controller.activate(character: character)
        case .cycleForward: controller.cycle(forward: true)
        case .cycleBackward: controller.cycle(forward: false)
        case .toggleThumbnails: controller.setThumbnailsHidden(!controller.areThumbnailsHidden)
        case .toggleHotkeys: hotkeys.toggleSuspended()
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
