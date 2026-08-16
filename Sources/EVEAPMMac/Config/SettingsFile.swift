import Foundation

/// Reads and writes JSON documents. A missing or unreadable file yields nothing
/// rather than an error, because losing one must not stop the app from
/// starting.
enum JSONFile {
    static func load<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    static func save(_ value: some Encodable, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(value).write(to: url, options: .atomic)
    }
}

/// The settings document, which always loads into something usable.
enum SettingsFile {
    static func load(from url: URL) -> Settings {
        (JSONFile.load(Settings.self, from: url) ?? Settings()).clamped()
    }

    static func save(_ settings: Settings, to url: URL) throws {
        try JSONFile.save(settings, to: url)
    }
}

/// What the app remembers outside any profile: which profile is in use and the
/// shortcuts that switch between them.
struct AppState: Codable, Sendable, Equatable {
    var currentProfile: String = ProfileLayout.defaultProfile
    var globalHotkeys: [Hotkey] = []
}

/// Where the settings live on disk. A `settings.json` sitting next to the app
/// wins over the one in Application Support, so a copy of the app can be
/// carried around with its settings beside it.
struct ProfileLayout: Sendable {
    static let defaultProfile = "default"
    static let portableFileName = "settings.json"

    let root: URL
    let isPortable: Bool

    init(root: URL, isPortable: Bool = false) {
        self.root = root
        self.isPortable = isPortable
    }

    /// Picks the folder to work in: beside the app when a settings file is
    /// there, otherwise the usual place under the user's Library.
    init() {
        let beside = ProfileLayout.besideTheApp()
        if FileManager.default.fileExists(
            atPath: beside.appendingPathComponent(ProfileLayout.portableFileName).path) {
            self.init(root: beside, isPortable: true)
        } else {
            self.init(root: ProfileLayout.applicationSupport())
        }
    }

    static func applicationSupport() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("EVE-APM-Mac", isDirectory: true)
    }

    static func besideTheApp() -> URL {
        Bundle.main.bundleURL.deletingLastPathComponent()
    }

    var profilesDirectory: URL { root.appendingPathComponent("profiles", isDirectory: true) }
    var stateURL: URL { root.appendingPathComponent("state.json") }
    var legacySettingsURL: URL { root.appendingPathComponent(ProfileLayout.portableFileName) }

    /// In a portable folder the file the user put there is the default profile
    /// itself, so it keeps its name and its place.
    func profileURL(_ name: String) -> URL {
        let clean = ProfileLayout.sanitize(name)
        if isPortable, clean == ProfileLayout.defaultProfile { return legacySettingsURL }
        return profilesDirectory.appendingPathComponent("\(clean).json")
    }

    /// A profile name becomes a file name, so anything that would break a path
    /// is folded away.
    static func sanitize(_ name: String) -> String {
        let cleaned = name
            .components(separatedBy: CharacterSet(charactersIn: "/\\:."))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        return cleaned.isEmpty ? defaultProfile : cleaned
    }

    func names() -> [String] {
        let contents = try? FileManager.default.contentsOfDirectory(
            at: profilesDirectory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        var found = Set((contents ?? [])
            .filter { $0.pathExtension == "json" }
            .map { $0.deletingPathExtension().lastPathComponent })
        if isPortable {
            found.insert(ProfileLayout.defaultProfile)
        }
        return found.isEmpty ? [ProfileLayout.defaultProfile] : found.sorted()
    }

    /// Moves a pre-profile settings file into the default profile, so an
    /// upgrade keeps the arrangement the user already had.
    func migrateLegacySettings() {
        guard !isPortable else { return }
        let manager = FileManager.default
        let target = profileURL(ProfileLayout.defaultProfile)
        guard manager.fileExists(atPath: legacySettingsURL.path),
              !manager.fileExists(atPath: target.path) else { return }
        try? manager.createDirectory(at: profilesDirectory, withIntermediateDirectories: true)
        try? manager.moveItem(at: legacySettingsURL, to: target)
        Log.info("migrated settings into the default profile")
    }
}
