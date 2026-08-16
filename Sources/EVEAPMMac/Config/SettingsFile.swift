import Foundation

/// Reads and writes the settings JSON. A missing or unreadable file yields
/// defaults rather than an error, because losing a settings file must not stop
/// the app from starting.
enum SettingsFile {
    static let fileName = "settings.json"

    static func directory(
        appSupport: URL = FileManager.default.urls(for: .applicationSupportDirectory,
                                                   in: .userDomainMask)[0]
    ) -> URL {
        appSupport.appendingPathComponent("EVE-APM-Mac", isDirectory: true)
    }

    static func load(from directory: URL) -> Settings {
        let url = directory.appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: url),
              let settings = try? decoder.decode(Settings.self, from: data) else {
            return Settings()
        }
        return settings.clamped()
    }

    static func save(_ settings: Settings, to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try encoder.encode(settings)
        try data.write(to: directory.appendingPathComponent(fileName), options: .atomic)
    }

    private static var decoder: JSONDecoder { JSONDecoder() }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
