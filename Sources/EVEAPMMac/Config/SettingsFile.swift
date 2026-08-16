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

/// Where the settings live on disk.
struct ProfileLayout: Sendable {
    static let defaultProfile = "default"

    let root: URL

    init(root: URL = ProfileLayout.applicationSupport()) {
        self.root = root
    }

    static func applicationSupport() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("EVE-APM-Mac", isDirectory: true)
    }

    var profilesDirectory: URL { root.appendingPathComponent("profiles", isDirectory: true) }
    var stateURL: URL { root.appendingPathComponent("state.json") }
    var legacySettingsURL: URL { root.appendingPathComponent("settings.json") }

    func profileURL(_ name: String) -> URL {
        profilesDirectory.appendingPathComponent("\(ProfileLayout.sanitize(name)).json")
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
        let found = (contents ?? [])
            .filter { $0.pathExtension == "json" }
            .map { $0.deletingPathExtension().lastPathComponent }
            .sorted()
        return found.isEmpty ? [ProfileLayout.defaultProfile] : found
    }

    /// Moves a pre-profile settings file into the default profile, so an
    /// upgrade keeps the arrangement the user already had.
    func migrateLegacySettings() {
        let manager = FileManager.default
        let target = profileURL(ProfileLayout.defaultProfile)
        guard manager.fileExists(atPath: legacySettingsURL.path),
              !manager.fileExists(atPath: target.path) else { return }
        try? manager.createDirectory(at: profilesDirectory, withIntermediateDirectories: true)
        try? manager.moveItem(at: legacySettingsURL, to: target)
        Log.info("migrated settings into the default profile")
    }
}
