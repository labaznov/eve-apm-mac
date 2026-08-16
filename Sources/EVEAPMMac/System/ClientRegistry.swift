import AppKit
import Combine
import ScreenCaptureKit

/// Discovers the running EVE clients and keeps the list current. ScreenCaptureKit
/// has no change notification, so the registry polls, and additionally refreshes
/// the moment an application activates or quits.
@MainActor
final class ClientRegistry: ObservableObject {
    @Published private(set) var clients: [EVEClient] = []
    @Published private(set) var frontmostPID: pid_t?

    /// The ScreenCaptureKit windows behind the published clients, kept so a
    /// capture stream can be built without a second lookup.
    private(set) var windows: [CGWindowID: SCWindow] = [:]

    private let bundleIdentifiers: () -> [String]
    private var pollTimer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var isRefreshing = false
    private var deniedSince: Date?

    /// Windows narrower than this are EVE's own dialogs, not a client.
    private static let minimumWidth: CGFloat = 200

    init(bundleIdentifiers: @escaping () -> [String]) {
        self.bundleIdentifiers = bundleIdentifiers
        frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
    }

    func start(interval: TimeInterval = 1.0) {
        guard pollTimer == nil else { return }

        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification,
                     NSWorkspace.didTerminateApplicationNotification,
                     NSWorkspace.didLaunchApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
                    self?.refreshSoon()
                }
            })
        }

        pollTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshSoon() }
        }
        refreshSoon()
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        for observer in observers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        observers.removeAll()
    }

    func window(for id: CGWindowID) -> SCWindow? {
        windows[id]
    }

    /// Screen Recording can be revoked or still ungranted; the listing is the
    /// only reliable witness of that, so a refusal is logged once and then
    /// retried slowly instead of every poll.
    private func noteDenial(_ error: Error) {
        let now = Date()
        if let since = deniedSince, now.timeIntervalSince(since) < 60 { return }
        deniedSince = now
        Log.error("cannot list windows, Screen Recording is probably not granted: \(error.localizedDescription)")
    }

    private func refreshSoon() {
        guard !isRefreshing else { return }
        isRefreshing = true
        Task { [weak self] in
            await self?.refresh()
            self?.isRefreshing = false
        }
    }

    private func refresh() async {
        let allowed = Set(bundleIdentifiers())
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(
                true, onScreenWindowsOnly: false)
        } catch {
            noteDenial(error)
            if !clients.isEmpty { clients = [] }
            return
        }

        deniedSince = nil

        var found: [EVEClient] = []
        var byID: [CGWindowID: SCWindow] = [:]
        for window in content.windows {
            guard let app = window.owningApplication,
                  allowed.contains(app.bundleIdentifier),
                  window.frame.width >= Self.minimumWidth else { continue }
            let title = window.title ?? "EVE"
            guard ClientTitle.isClientTitle(title) else { continue }

            found.append(EVEClient(windowID: window.windowID,
                                   pid: app.processID,
                                   title: title,
                                   frame: window.frame,
                                   isOnScreen: window.isOnScreen))
            byID[window.windowID] = window
        }

        found.sort { ($0.pid, $0.windowID) < ($1.pid, $1.windowID) }
        windows = byID
        if found != clients {
            if found.count != clients.count {
                Log.info("tracking \(found.count) client(s) of \(content.windows.count) windows")
            }
            clients = found
        }
    }
}
