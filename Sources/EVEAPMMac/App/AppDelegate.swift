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
        item.button?.image = menuBarIcon()
        item.menu = buildMenu()
        statusItem = item
    }

    /// The bee, reduced to a template so the menu bar tints it to match the
    /// bar it sits in. Falls back to a symbol if the resource is missing.
    private func menuBarIcon() -> NSImage? {
        guard let url = Bundle.main.url(forResource: "MenuBarIcon", withExtension: "png"),
              let image = NSImage(contentsOf: url) else {
            return NSImage(systemSymbolName: "rectangle.on.rectangle",
                           accessibilityDescription: "EVE-APM Mac")
        }
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        image.accessibilityDescription = "EVE-APM Mac"
        return image
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

        let profiles = NSMenuItem(title: "Profile", action: nil, keyEquivalent: "")
        profiles.submenu = NSMenu()
        menu.addItem(profiles)

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
        case .switchProfile(let name): model.config.switchTo(name)
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
    @objc private func chooseProfile(_ item: NSMenuItem) {
        AppModel.shared.config.switchTo(item.title)
    }

    /// The profiles are listed when the menu opens, because one can be added
    /// from the settings window or by dropping a file in at any time.
    @MainActor
    private func refreshProfiles(in menu: NSMenu) {
        let config = AppModel.shared.config
        menu.removeAllItems()
        for name in config.profiles {
            let item = menu.addItem(withTitle: name, action: #selector(chooseProfile(_:)),
                                    keyEquivalent: "")
            item.target = self
            item.state = name == config.currentProfile ? .on : .off
        }
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
            if let profiles = menu.item(at: 3)?.submenu {
                refreshProfiles(in: profiles)
            }
        }
    }
}
