import Foundation

/// Reads the character name out of an EVE Online client window title. The
/// client titles its window "EVE" until a character is selected and
/// "EVE - <character>" afterwards, so an absent name means the client sits on
/// the login or character selection screen.
enum ClientTitle {
    private static let separator = " - "
    private static let prefix = "EVE"

    static func character(from title: String) -> String? {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix(prefix) else { return nil }

        let remainder = trimmed
            .dropFirst(prefix.count)
            .trimmingCharacters(in: .whitespaces)
        guard remainder.hasPrefix("-") else { return nil }

        let name = remainder.dropFirst().trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : name
    }

    static func isClientTitle(_ title: String) -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        return trimmed == prefix || trimmed.hasPrefix(prefix + separator)
    }
}
