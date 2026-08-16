import Foundation

/// Which of EVE's two log families a line came from. They differ in encoding
/// and in what they are worth reading for.
enum LogKind: Sendable {
    case chat
    case game
}

/// The kinds of notice worth surfacing on a thumbnail the player is not
/// looking at.
enum AlertKind: String, Sendable, Equatable, CaseIterable {
    case fleetInvite
    case followWarp
    case regroup
    case compression
    case decloak
    case conversation
    case crystalBroke
    case miningStopped

    var title: String {
        switch self {
        case .fleetInvite: "Fleet invite"
        case .followWarp: "Following in warp"
        case .regroup: "Regrouping"
        case .compression: "Compressed"
        case .decloak: "Decloaked"
        case .conversation: "Conversation request"
        case .crystalBroke: "Crystal broke"
        case .miningStopped: "Mining stopped"
        }
    }
}

/// One notice raised by a client, ready to be shown on its thumbnail.
struct Alert: Sendable, Equatable {
    let kind: AlertKind
    let text: String
    let time: Date
}

/// What a single log line turned out to mean.
enum LogEvent: Sendable, Equatable {
    case system(name: String, at: Date)
    case alert(Alert)
}
