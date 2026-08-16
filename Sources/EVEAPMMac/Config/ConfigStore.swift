import AppKit
import Combine
import Foundation

/// Holds the live settings, the set of profiles they are grouped into, and
/// pushes both to disk. Writes are coalesced because dragging a thumbnail
/// changes a stored position on every frame.
@MainActor
final class ConfigStore: ObservableObject {
    @Published var settings: Settings {
        didSet {
            guard settings != oldValue else { return }
            scheduleSave()
        }
    }

    @Published private(set) var currentProfile: String
    @Published private(set) var profiles: [String]

    /// Shortcuts that switch profiles, kept outside the profiles so they keep
    /// working after a switch.
    @Published var globalHotkeys: [Hotkey] {
        didSet {
            guard globalHotkeys != oldValue else { return }
            writeState()
        }
    }

    private let layout: ProfileLayout
    private var saveTask: Task<Void, Never>?

    init(layout: ProfileLayout = ProfileLayout()) {
        self.layout = layout
        layout.migrateLegacySettings()

        let state = JSONFile.load(AppState.self, from: layout.stateURL) ?? AppState()
        let available = layout.names()
        let selected = available.contains(state.currentProfile)
            ? state.currentProfile
            : available[0]

        profiles = available
        currentProfile = selected
        globalHotkeys = state.globalHotkeys
        settings = SettingsFile.load(from: layout.profileURL(selected))
    }

    // MARK: - Profiles

    func switchTo(_ name: String) {
        let target = ProfileLayout.sanitize(name)
        guard target != currentProfile else { return }
        if !profiles.contains(target) {
            // A profile file can appear from outside the app, and a link may
            // name it before this store has looked.
            profiles = layout.names()
        }
        guard profiles.contains(target) else {
            Log.error("no profile named \(target)")
            return
        }
        flush()
        currentProfile = target
        settings = SettingsFile.load(from: layout.profileURL(target))
        writeState()
        Log.info("switched to profile \(target)")
    }

    func cycleProfile(forward: Bool) {
        guard profiles.count > 1, let index = profiles.firstIndex(of: currentProfile) else { return }
        let step = forward ? 1 : profiles.count - 1
        switchTo(profiles[(index + step) % profiles.count])
    }

    /// Creates a profile and switches to it. Copying the current one is the
    /// useful default: a profile is normally a variation of what is on screen.
    func createProfile(named name: String, copyingCurrent: Bool = true) {
        let target = ProfileLayout.sanitize(name)
        guard !profiles.contains(target) else { return }
        flush()

        var fresh = copyingCurrent ? settings : Settings()
        if !copyingCurrent { fresh.clientBundleIdentifiers = settings.clientBundleIdentifiers }
        try? SettingsFile.save(fresh, to: layout.profileURL(target))

        profiles = layout.names()
        currentProfile = target
        settings = fresh
        writeState()
    }

    func deleteProfile(_ name: String) {
        let target = ProfileLayout.sanitize(name)
        guard profiles.count > 1, profiles.contains(target) else { return }
        try? FileManager.default.removeItem(at: layout.profileURL(target))
        profiles = layout.names()
        if currentProfile == target {
            currentProfile = profiles[0]
            settings = SettingsFile.load(from: layout.profileURL(currentProfile))
        }
        writeState()
    }

    /// Takes settings from elsewhere — an imported Windows profile — and makes
    /// them a profile of their own, leaving the current one alone.
    func adopt(_ settings: Settings, asProfile name: String) {
        let target = ProfileLayout.sanitize(name)
        if profiles.contains(target) {
            switchTo(target)
            self.settings = settings
            flush()
        } else {
            createProfile(named: target, copyingCurrent: false)
            self.settings = settings
            flush()
        }
    }

    var activeProfilePath: String {
        layout.profileURL(currentProfile).path
    }

    func revealInFinder() {
        let url = layout.profileURL(currentProfile)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: - Persistence

    func flush() {
        saveTask?.cancel()
        saveTask = nil
        write()
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.write()
        }
    }

    private func write() {
        do {
            try SettingsFile.save(settings, to: layout.profileURL(currentProfile))
        } catch {
            Log.error("cannot write settings: \(error.localizedDescription)")
        }
    }

    private func writeState() {
        do {
            try JSONFile.save(AppState(currentProfile: currentProfile, globalHotkeys: globalHotkeys),
                              to: layout.stateURL)
        } catch {
            Log.error("cannot write app state: \(error.localizedDescription)")
        }
    }
}
