import AppKit
import SwiftUI

/// Starts the app, owns the menu bar item and routes `eveapm://` links.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        MainActor.assumeIsolated {
            buildStatusItem()
            AppModel.shared.start()
            requestMissingPermissions()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { AppModel.shared.config.flush() }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        MainActor.assumeIsolated {
            for url in urls {
                guard let command = URLCommand(url: url) else {
                    Log.error("unknown link \(url.absoluteString)")
                    continue
                }
                handle(command)
            }
        }
    }

    // MARK: - Menu bar

    @MainActor
    private func buildStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "rectangle.on.rectangle",
                                     accessibilityDescription: "EVE-APM Mac")
        item.menu = buildMenu()
        statusItem = item
    }

    @MainActor
    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self

        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
            .target = self
        menu.addItem(withTitle: "Hide Thumbnails", action: #selector(toggleThumbnails), keyEquivalent: "")
            .target = self
        menu.addItem(withTitle: "Suspend Hotkeys", action: #selector(toggleHotkeys), keyEquivalent: "")
            .target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return menu
    }

    @MainActor
    private func handle(_ command: URLCommand) {
        let model = AppModel.shared
        switch command {
        case .activate(let character): model.controller.activate(character: character)
        case .suspendHotkeys: model.hotkeys.suspend()
        case .resumeHotkeys: model.hotkeys.resume()
        case .hideThumbnails: model.controller.setThumbnailsHidden(true)
        case .showThumbnails: model.controller.setThumbnailsHidden(false)
        case .openSettings: openSettings()
        }
    }

    // MARK: - Actions

    @MainActor
    @objc private func openSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 520, height: 560),
                                  styleMask: [.titled, .closable, .miniaturizable],
                                  backing: .buffered,
                                  defer: false)
            window.title = "EVE-APM Mac"
            window.contentViewController = NSHostingController(
                rootView: SettingsView().environmentObject(AppModel.shared))
            window.center()
            window.isReleasedWhenClosed = false
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @MainActor
    @objc private func toggleThumbnails() {
        let controller = AppModel.shared.controller
        controller.setThumbnailsHidden(!controller.areThumbnailsHidden)
    }

    @MainActor
    @objc private func toggleHotkeys() {
        AppModel.shared.hotkeys.toggleSuspended()
    }

    @MainActor
    private func requestMissingPermissions() {
        if !Permissions.hasScreenRecording { Permissions.requestScreenRecording() }
        if !Permissions.hasAccessibility { Permissions.requestAccessibility() }
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        MainActor.assumeIsolated {
            let model = AppModel.shared
            menu.item(at: 1)?.title = model.controller.areThumbnailsHidden
                ? "Show Thumbnails" : "Hide Thumbnails"
            menu.item(at: 2)?.title = model.hotkeys.isSuspended
                ? "Resume Hotkeys" : "Suspend Hotkeys"
        }
    }
}
