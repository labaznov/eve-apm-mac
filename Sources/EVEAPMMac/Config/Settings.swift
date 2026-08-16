import CoreGraphics
import Foundation

/// A colour as it survives a round trip through the settings file, kept free of
/// AppKit so the settings model stays testable.
struct RGBAColor: Codable, Sendable, Equatable, Hashable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    static let activeBorder = RGBAColor(red: 1.0, green: 0.72, blue: 0.15, alpha: 1.0)
    static let inactiveBorder = RGBAColor(red: 0.16, green: 0.17, blue: 0.20, alpha: 1.0)
    static let label = RGBAColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
}

/// A screen position stored per character, in the bottom-left origin coordinate
/// space AppKit uses for window frames.
struct StoredPoint: Codable, Sendable, Equatable {
    var x: Double
    var y: Double

    init(_ point: CGPoint) {
        x = point.x
        y = point.y
    }

    var cgPoint: CGPoint { CGPoint(x: x, y: y) }
}

/// What a global hotkey does when it fires.
enum HotkeyAction: Codable, Sendable, Equatable, Hashable {
    case activate(character: String)
    case cycleForward
    case cycleBackward
    case toggleThumbnails
    case toggleHotkeys
}

/// A global hotkey as the Carbon hotkey API wants it: a virtual key code and a
/// Carbon modifier mask.
struct Hotkey: Codable, Sendable, Equatable, Hashable, Identifiable {
    var keyCode: UInt32
    var modifiers: UInt32
    var action: HotkeyAction

    var id: String { "\(modifiers)-\(keyCode)" }
}

/// Everything the user can change, as it is written to disk.
struct Settings: Codable, Sendable, Equatable {
    var thumbnailWidth: Double = 240
    var opacity: Double = 1.0
    var frameRate: Int = 10
    var alwaysOnTop: Bool = true
    var hideActiveThumbnail: Bool = false
    var lockPositions: Bool = false
    var showCharacterName: Bool = true
    var labelColor: RGBAColor = .label
    var borderWidth: Double = 2
    var activeBorderColor: RGBAColor = .activeBorder
    var inactiveBorderColor: RGBAColor = .inactiveBorder
    var characterBorderColors: [String: RGBAColor] = [:]
    var autoMinimizeEnabled: Bool = false
    var autoMinimizeDelay: Double = 5
    var neverMinimize: [String] = []
    var positions: [String: StoredPoint] = [:]
    var hotkeys: [Hotkey] = []
    var hotkeysRequireEVEFocus: Bool = false

    /// Bundle identifiers whose windows count as EVE clients. Kept editable
    /// because Singularity and third-party launchers ship their own bundles.
    var clientBundleIdentifiers: [String] = ["com.ccpgames.eveonline"]

    static let thumbnailWidthRange: ClosedRange<Double> = 80...800
    static let frameRateRange: ClosedRange<Int> = 1...30
    static let opacityRange: ClosedRange<Double> = 0.2...1.0

    /// Rejects values the UI or a hand-edited file could otherwise push out of
    /// range, so a bad settings file degrades instead of breaking the app.
    func clamped() -> Settings {
        var copy = self
        copy.thumbnailWidth = min(max(thumbnailWidth, Settings.thumbnailWidthRange.lowerBound),
                                  Settings.thumbnailWidthRange.upperBound)
        copy.frameRate = min(max(frameRate, Settings.frameRateRange.lowerBound),
                             Settings.frameRateRange.upperBound)
        copy.opacity = min(max(opacity, Settings.opacityRange.lowerBound),
                           Settings.opacityRange.upperBound)
        copy.borderWidth = min(max(borderWidth, 0), 12)
        copy.autoMinimizeDelay = min(max(autoMinimizeDelay, 0.5), 120)
        return copy
    }

    func borderColor(for client: EVEClient, isActive: Bool) -> RGBAColor {
        if isActive { return activeBorderColor }
        if let character = client.character, let custom = characterBorderColors[character] {
            return custom
        }
        return inactiveBorderColor
    }

    func minimizes(_ client: EVEClient) -> Bool {
        guard autoMinimizeEnabled else { return false }
        guard let character = client.character else { return true }
        return !neverMinimize.contains(character)
    }
}
