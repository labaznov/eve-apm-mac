import CoreGraphics
import Foundation

/// One EVE Online client the app tracks: the system window it mirrors, the
/// process behind it and the character currently logged into it.
struct EVEClient: Identifiable, Sendable, Equatable {
    let windowID: CGWindowID
    let pid: pid_t
    let title: String
    let frame: CGRect
    let isOnScreen: Bool

    var id: CGWindowID { windowID }
    var character: String? { ClientTitle.character(from: title) }

    /// What the thumbnail is labelled with, and the key positions are stored
    /// under. Clients without a character keep an identity of their own so
    /// their thumbnails stay apart.
    var label: String { character ?? "Client \(pid)" }

    var aspectRatio: CGFloat {
        frame.height > 0 ? frame.width / frame.height : 16.0 / 9.0
    }
}
