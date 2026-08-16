import CoreGraphics
import Foundation

/// Reads a profile written by the Windows EVE-APM Preview. That application
/// stores its profiles as Qt INI files rather than JSON, one file per profile
/// under `profiles\`, so bringing settings across means translating the file
/// rather than reading it as-is.
///
/// Only the settings this application also has are carried over; the rest is
/// left behind rather than guessed at.
enum WindowsProfile {
    /// Windows parks minimised windows here, and the original stores that as a
    /// position; it would put a thumbnail nowhere.
    private static let minimizedMarker = -32000.0

    /// - Parameters:
    ///   - text: contents of a Windows `<profile>.ini`.
    ///   - base: settings to fill in, so anything absent keeps its value here.
    ///   - screenHeight: height of the display the positions were saved
    ///     against, needed because Windows measures from the top of the screen
    ///     and macOS from the bottom.
    static func settings(fromINI text: String, base: Settings = Settings(),
                         screenHeight: CGFloat) -> Settings {
        let ini = INIFile(text)
        var settings = base

        if let width = ini.double("thumbnail/width") { settings.thumbnailWidth = width }
        if let opacity = ini.double("thumbnail/opacity") {
            // The original stores a percentage in some builds and a fraction in
            // others; both are accepted rather than picking one and being wrong.
            settings.opacity = opacity > 1 ? opacity / 100 : opacity
        }
        if let onTop = ini.bool("window/alwaysOnTop") { settings.alwaysOnTop = onTop }
        if let locked = ini.bool("position/lockPositions") { settings.lockPositions = locked }
        if let hide = ini.bool("ui/hideActiveClientThumbnail") { settings.hideActiveThumbnail = hide }
        if let colour = ini.colour("ui/highlightColor") { settings.activeBorderColor = colour }

        if let minimize = ini.bool("window/minimizeInactiveClients") {
            settings.autoMinimizeEnabled = minimize
        }
        if let delay = ini.double("window/minimizeDelay") {
            // Windows keeps the delay in milliseconds.
            settings.autoMinimizeDelay = delay > 120 ? delay / 1000 : delay
        }
        if let never = ini.list("window/neverMinimizeCharacters") { settings.neverMinimize = never }

        if let show = ini.bool("overlay/showCharacterName") { settings.showCharacterName = show }
        if let show = ini.bool("overlay/showSystemName") { settings.showSystemName = show }
        if let colour = ini.colour("overlay/characterNameColor") { settings.labelColor = colour }

        if let chat = ini.bool("chatlog/enableMonitoring") { settings.monitorChatLogs = chat }
        if let game = ini.bool("gamelog/enableMonitoring") { settings.monitorGameLogs = game }
        if let alerts = ini.bool("combatMessages/enabled") { settings.alertsEnabled = alerts }
        if let duration = ini.double("combatMessages/duration") {
            settings.alertDuration = duration > 60 ? duration / 1000 : duration
        }
        if let focused = ini.bool("hotkey/onlyWhenEVEFocused") {
            settings.hotkeysRequireEVEFocus = focused
        }

        settings.positions = positions(in: ini, height: settings.thumbnailWidth * 9 / 16,
                                       screenHeight: screenHeight)
            .merging(settings.positions) { imported, _ in imported }
        for (character, colour) in ini.colours(inGroup: "characterBorderColors") {
            settings.characterBorderColors[character] = colour
        }

        return settings.clamped()
    }

    private static func positions(in ini: INIFile, height: CGFloat,
                                  screenHeight: CGFloat) -> [String: StoredPoint] {
        var result: [String: StoredPoint] = [:]
        for (character, value) in ini.entries(inGroup: "thumbnailPositions") {
            guard let point = qtPoint(value),
                  point.x != minimizedMarker, point.y != minimizedMarker else { continue }
            // Windows counts down from the top of the screen, AppKit up from
            // the bottom, and the anchor moves from the top edge of the
            // thumbnail to its bottom edge.
            result[character] = StoredPoint(CGPoint(x: point.x,
                                                    y: screenHeight - point.y - height))
        }
        return result
    }

    /// Qt writes points as `@Point(x y)`.
    private static func qtPoint(_ value: String) -> CGPoint? {
        guard value.hasPrefix("@Point(") , value.hasSuffix(")") else { return nil }
        let numbers = value.dropFirst("@Point(".count).dropLast()
            .split(separator: " ")
            .compactMap { Double($0) }
        guard numbers.count == 2 else { return nil }
        return CGPoint(x: numbers[0], y: numbers[1])
    }
}

/// The slice of the INI format Qt writes: `[group]` headers, `key=value` lines,
/// `;` and `#` comments, and percent escapes in keys that hold non-ASCII.
struct INIFile {
    private(set) var values: [String: String] = [:]

    init(_ text: String) {
        var group = ""
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix(";") || line.hasPrefix("#") { continue }
            if line.hasPrefix("["), line.hasSuffix("]") {
                group = String(line.dropFirst().dropLast())
                continue
            }
            guard let separator = line.firstIndex(of: "=") else { continue }
            let key = String(line[line.startIndex..<separator]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: separator)...])
                .trimmingCharacters(in: .whitespaces)
            let decoded = key.removingPercentEncoding ?? key
            values[group.isEmpty ? decoded : "\(group)/\(decoded)"] = value
        }
    }

    func string(_ key: String) -> String? {
        values[key].map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\"")) }
    }

    func double(_ key: String) -> Double? {
        string(key).flatMap(Double.init)
    }

    func bool(_ key: String) -> Bool? {
        guard let text = string(key)?.lowercased() else { return nil }
        if ["true", "1", "yes"].contains(text) { return true }
        if ["false", "0", "no"].contains(text) { return false }
        return nil
    }

    func list(_ key: String) -> [String]? {
        guard let text = string(key) else { return nil }
        return text.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    func colour(_ key: String) -> RGBAColor? {
        string(key).flatMap(INIFile.colour(fromHex:))
    }

    func entries(inGroup group: String) -> [(String, String)] {
        values.compactMap { key, value in
            guard key.hasPrefix(group + "/") else { return nil }
            return (String(key.dropFirst(group.count + 1)), value)
        }
    }

    func colours(inGroup group: String) -> [(String, RGBAColor)] {
        entries(inGroup: group).compactMap { key, value in
            INIFile.colour(fromHex: value).map { (key, $0) }
        }
    }

    /// Qt writes colours as `#rrggbb`, sometimes with an alpha pair in front.
    static func colour(fromHex text: String) -> RGBAColor? {
        var digits = text.trimmingCharacters(in: CharacterSet(charactersIn: "\"# "))
        if digits.count == 8 { digits = String(digits.dropFirst(2)) }
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        return RGBAColor(red: Double((value >> 16) & 0xFF) / 255,
                         green: Double((value >> 8) & 0xFF) / 255,
                         blue: Double(value & 0xFF) / 255,
                         alpha: 1)
    }
}
