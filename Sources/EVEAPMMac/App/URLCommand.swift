import Foundation

/// What an `eveapm://` link asks the app to do. Parsing lives apart from the
/// app delegate so the link grammar can be tested on its own.
enum URLCommand: Equatable {
    case activate(character: String)
    case suspendHotkeys
    case resumeHotkeys
    case hideThumbnails
    case showThumbnails
    case openSettings

    static let scheme = "eveapm"

    init?(url: URL) {
        guard url.scheme?.lowercased() == Self.scheme, let host = url.host?.lowercased() else {
            return nil
        }
        let argument = url.path
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .removingPercentEncoding ?? ""

        switch (host, argument.lowercased()) {
        case ("character", _) where !argument.isEmpty: self = .activate(character: argument)
        case ("hotkey", "suspend"): self = .suspendHotkeys
        case ("hotkey", "resume"): self = .resumeHotkeys
        case ("thumbnail", "hide"): self = .hideThumbnails
        case ("thumbnail", "show"): self = .showThumbnails
        case ("config", "open"): self = .openSettings
        default: return nil
        }
    }
}
