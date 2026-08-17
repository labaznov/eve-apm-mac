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

/// Where an overlay sits on a thumbnail.
enum OverlayPosition: String, Codable, Sendable, Equatable, CaseIterable {
    case top
    case bottom

    var title: String { self == .top ? "Top" : "Bottom" }
}

/// How a thumbnail's border is drawn.
enum BorderStyle: String, Codable, Sendable, Equatable, CaseIterable {
    case solid
    case dashed
    case dotted

    var title: String { rawValue.capitalized }

    /// The dash pattern a shape layer wants, in points; nil draws a line.
    func dashPattern(width: Double) -> [NSNumber]? {
        switch self {
        case .solid: nil
        case .dashed: [NSNumber(value: width * 3), NSNumber(value: width * 2)]
        case .dotted: [NSNumber(value: max(1, width)), NSNumber(value: max(1, width) * 2)]
        }
    }
}

/// Where a notice sits on a thumbnail.
enum AlertPosition: String, Codable, Sendable, Equatable, CaseIterable {
    case top
    case middle
    case bottom

    var title: String { rawValue.capitalized }
}

/// How the thumbnails of clients with no character yet are arranged.
enum StackMode: String, Codable, Sendable, Equatable, CaseIterable {
    case row
    case column
    case pile

    var title: String {
        switch self {
        case .row: "In a row"
        case .column: "In a column"
        case .pile: "On top of each other"
        }
    }
}

/// A rectangle as it survives a round trip through the settings file.
struct StoredRect: Codable, Sendable, Equatable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    init(_ rect: CGRect) {
        x = rect.origin.x
        y = rect.origin.y
        width = rect.width
        height = rect.height
    }

    var cgRect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
}

/// A named set of characters with shortcuts that step through just them, for
/// the squads a multiboxer switches between as a unit.
struct CycleGroup: Codable, Sendable, Equatable, Hashable, Identifiable {
    var name: String
    var characters: [String] = []
    /// Whether clients still on the login screen take part.
    var includesNotLoggedIn: Bool = false
    /// Whether stepping past the last member returns to the first.
    var loops: Bool = true

    var id: String { name }
}

/// What a global hotkey does when it fires.
enum HotkeyAction: Codable, Sendable, Equatable, Hashable {
    case activate(character: String)
    case cycleForward
    case cycleBackward
    case toggleThumbnails
    case toggleHotkeys
    case switchProfile(name: String)
    case cycleProfileForward
    case cycleProfileBackward
    case cycleGroupForward(group: String)
    case cycleGroupBackward(group: String)

    /// Profile switching has to keep working after the profile changes, so
    /// those shortcuts are held outside any profile.
    var isGlobal: Bool {
        switch self {
        case .switchProfile, .cycleProfileForward, .cycleProfileBackward: true
        default: false
        }
    }
}

/// A global hotkey as the Carbon hotkey API wants it: a virtual key code and a
/// Carbon modifier mask.
struct Hotkey: Codable, Sendable, Equatable, Hashable, Identifiable {
    /// Identity of its own, because a shortcut is edited in place: two rows can
    /// hold the same keys, or none yet, and a list keyed on their contents would
    /// confuse one for the other while they are being recorded.
    var id: UUID
    var keyCode: UInt32
    var modifiers: UInt32
    var action: HotkeyAction

    init(id: UUID = UUID(), keyCode: UInt32, modifiers: UInt32, action: HotkeyAction) {
        self.id = id
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.action = action
    }

    /// Files written before shortcuts carried an identity are still read; those
    /// entries are given one as they come in.
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        keyCode = try values.decode(UInt32.self, forKey: .keyCode)
        modifiers = try values.decode(UInt32.self, forKey: .modifiers)
        action = try values.decode(HotkeyAction.self, forKey: .action)
    }
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
    var hotkeysRequireEVEFocus: Bool = true
    /// Fire a shortcut even when further modifiers are held, so a key the game
    /// also uses with Ctrl or Alt still reaches this app.
    var wildcardHotkeys: Bool = false
    var cycleGroups: [CycleGroup] = []

    /// A width of its own for named characters; the rest use `thumbnailWidth`.
    var characterThumbnailWidths: [String: Double] = [:]
    /// How near an edge a dragged thumbnail snaps to it. Zero switches it off.
    var snapDistance: Double = 8

    var labelFontSize: Double = 12
    var characterNamePosition: OverlayPosition = .bottom
    var systemNamePosition: OverlayPosition = .top
    var systemNameColor: RGBAColor = .label
    var overlayBackground: Bool = false
    var overlayBackgroundColor: RGBAColor = RGBAColor(red: 0, green: 0, blue: 0, alpha: 0.5)
    var activeBorderStyle: BorderStyle = .solid
    var inactiveBorderStyle: BorderStyle = .solid
    var inactiveBorderWidth: Double = 2

    /// Bundle identifiers whose windows count as EVE clients. Kept editable
    /// because Singularity and third-party launchers ship their own bundles.
    var clientBundleIdentifiers: [String] = ["com.ccpgames.eveonline"]

    /// Take the thumbnails away while another application is in front, so they
    /// do not sit over the work they are not part of.
    var hideThumbnailsWhenEVEUnfocused: Bool = false
    /// How long the other application has to stay in front before that happens,
    /// so a glance at another window does not make everything flicker.
    var eveFocusDebounce: Double = 0.4
    /// Characters whose thumbnail is never shown.
    var hiddenCharacters: [String] = []
    /// Characters that "Quit EVE Clients" leaves running.
    var neverClose: [String] = []

    var showNotLoggedInClients: Bool = true
    var notLoggedInBadge: Bool = true
    var notLoggedInStack: StackMode = .column
    /// Where that stack starts; nothing means near the top left of the screen.
    var notLoggedInAnchor: StoredPoint?

    var alertColor: RGBAColor = RGBAColor(red: 1.0, green: 0.72, blue: 0.15, alpha: 1.0)
    var alertPosition: AlertPosition = .middle

    /// Put a client's own window back where it was when its character logs in.
    var rememberClientWindows: Bool = false
    var clientWindowFrames: [String: StoredRect] = [:]

    /// Seconds without a mining tick before mining counts as stopped.
    var miningTimeout: Double = 30

    /// Switch as the button goes down rather than when it comes up.
    var switchOnMouseDown: Bool = false
    /// Drag thumbnails with the right button, leaving the left one to switch.
    var dragWithRightButton: Bool = false

    var showSystemName: Bool = true
    var monitorChatLogs: Bool = true
    var monitorGameLogs: Bool = true
    var alertsEnabled: Bool = true
    var alertsOnActiveClient: Bool = false
    var alertDuration: Double = 6
    var mutedAlerts: [String] = []

    /// Empty means the place EVE writes its logs by default.
    var chatLogDirectory: String = ""
    var gameLogDirectory: String = ""

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
        copy.alertDuration = min(max(alertDuration, 1), 60)
        copy.positions = positions.filter { !Settings.isProcessKey($0.key) }
        copy.inactiveBorderWidth = min(max(inactiveBorderWidth, 0), 12)
        copy.snapDistance = min(max(snapDistance, 0), 60)
        copy.labelFontSize = min(max(labelFontSize, 8), 32)
        copy.eveFocusDebounce = min(max(eveFocusDebounce, 0), 10)
        copy.miningTimeout = min(max(miningTimeout, 5), 600)
        copy.characterThumbnailWidths = characterThumbnailWidths.mapValues {
            min(max($0, Settings.thumbnailWidthRange.lowerBound),
                Settings.thumbnailWidthRange.upperBound)
        }
        return copy
    }

    /// Earlier builds saved a position for a client that had no character yet,
    /// under a key made from its process. Those keys never match anything again
    /// and are dropped on the way in.
    static func isProcessKey(_ key: String) -> Bool {
        guard key.hasPrefix("Client ") else { return false }
        let rest = key.dropFirst("Client ".count)
        return !rest.isEmpty && rest.allSatisfy(\.isNumber)
    }

    func shows(_ alert: AlertKind) -> Bool {
        alertsEnabled && !mutedAlerts.contains(alert.rawValue)
    }

    /// Where EVE keeps its logs, unless the user pointed elsewhere.
    static func defaultLogDirectory(_ kind: LogKind) -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/EVE/logs", isDirectory: true)
            .appendingPathComponent(kind == .chat ? "Chatlogs" : "Gamelogs", isDirectory: true)
    }

    func logDirectory(_ kind: LogKind) -> URL {
        let configured = kind == .chat ? chatLogDirectory : gameLogDirectory
        guard !configured.isEmpty else { return Settings.defaultLogDirectory(kind) }
        return URL(fileURLWithPath: (configured as NSString).expandingTildeInPath, isDirectory: true)
    }

    func thumbnailWidth(for client: EVEClient) -> Double {
        client.character.flatMap { characterThumbnailWidths[$0] } ?? thumbnailWidth
    }

    func borderStyle(isActive: Bool) -> BorderStyle {
        isActive ? activeBorderStyle : inactiveBorderStyle
    }

    func borderWidth(isActive: Bool) -> Double {
        isActive ? borderWidth : inactiveBorderWidth
    }

    func shows(_ client: EVEClient) -> Bool {
        if let character = client.character { return !hiddenCharacters.contains(character) }
        return showNotLoggedInClients
    }

    func closes(_ character: String?) -> Bool {
        guard let character else { return true }
        return !neverClose.contains(character)
    }

    func group(named name: String) -> CycleGroup? {
        cycleGroups.first { $0.name == name }
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
