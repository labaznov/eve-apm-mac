import Foundation

/// Turns one line of an EVE log into an event. Everything about the log
/// grammar lives here, so the file watching around it stays free of regular
/// expressions.
enum LogParser {
    static func event(from rawLine: String, kind: LogKind, now: Date = Date()) -> LogEvent? {
        let line = clean(rawLine)
        guard line.count > 24 else { return nil }
        let time = timestamp(in: line) ?? now

        switch kind {
        case .chat:
            guard let system = capture(localChannel, in: line, group: 1) else { return nil }
            return .system(name: sanitize(system), at: time)
        case .game:
            return gameEvent(in: line, at: time)
        }
    }

    /// Cheap rejection of the overwhelming majority of lines, so the parser
    /// only sees candidates.
    static func isInteresting(_ line: String, kind: LogKind) -> Bool {
        switch kind {
        case .chat:
            return line.contains("EVE System")
        case .game:
            return line.contains("(notify)") || line.contains("(question)")
                || line.contains("(None)")
        }
    }

    /// The listener named in a log file's header block, which is the only place
    /// a log states whose client wrote it.
    static func listener(inHeader header: String) -> String? {
        guard let name = capture(listenerLine, in: header, group: 1) else { return nil }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }

    // MARK: - Game log

    private static func gameEvent(in line: String, at time: Date) -> LogEvent? {
        if let system = capture(jump, in: line, group: 1) {
            return .system(name: sanitize(system), at: time)
        }
        if let system = capture(conduit, in: line, group: 1) {
            return .system(name: sanitize(system), at: time)
        }
        if let inviter = capture(fleetInvite, in: line, group: 1) {
            return alert(.fleetInvite, "Fleet invite from \(inviter)", time)
        }
        if let leader = capture(followWarp, in: line, group: 1) {
            return alert(.followWarp, "Following \(leader)", time)
        }
        if let target = capture(regroup, in: line, group: 1) {
            return alert(.regroup, "Regrouping to \(target)", time)
        }
        if let groups = captures(compression, in: line), groups.count > 2 {
            let item = groups[2].hasSuffix(".") ? String(groups[2].dropLast()) : groups[2]
            return alert(.compression, "Compressed \(groups[1])x \(item)", time)
        }
        if let source = capture(decloak, in: line, group: 1) {
            return alert(.decloak, "Decloaked by \(source)", time)
        }
        if let pilot = capture(conversation, in: line, group: 1) {
            return alert(.conversation, "Conversation from \(pilot)", time)
        }
        if let crystal = capture(crystalBroke, in: line, group: 1) {
            return alert(.crystalBroke, "Crystal broke: \(crystal)", time)
        }
        if matches(asteroidDepleted, line) {
            return alert(.miningStopped, "Asteroid depleted", time)
        }
        if matches(cargoFull, line) {
            return alert(.miningStopped, "Cargo hold full", time)
        }
        return nil
    }

    private static func alert(_ kind: AlertKind, _ text: String, _ time: Date) -> LogEvent {
        .alert(Alert(kind: kind, text: text, time: time))
    }

    // MARK: - Text handling

    /// Chat log lines carry a byte order mark of their own and end in CR.
    private static func clean(_ line: String) -> String {
        var text = line
        if text.first == "\u{FEFF}" { text.removeFirst() }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func sanitize(_ system: String) -> String {
        var text = replacing(htmlTag, in: system, with: "")
        text = replacing(whitespaceRun, in: text, with: " ")
            .trimmingCharacters(in: .whitespaces)
        while let last = text.last, last == "." || last == "," {
            text.removeLast()
            text = text.trimmingCharacters(in: .whitespaces)
        }
        return text
    }

    static func timestamp(in line: String) -> Date? {
        guard let text = capture(timestampPrefix, in: line, group: 1) else { return nil }
        return eveTime.date(from: text)
    }

    private static let eveTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy.MM.dd HH:mm:ss"
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    // MARK: - Patterns

    private static let timestampPrefix = regex(#"^\[\s*(\d{4}\.\d{2}\.\d{2}\s+\d{2}:\d{2}:\d{2})\s*\]"#)
    private static let listenerLine = regex(#"(?m)^\s*Listener:\s*(.+?)\s*$"#)
    private static let localChannel = regex(#"EVE System\s*>\s*Channel changed to Local\s*:\s*(.+)$"#)
    private static let jump = regex(#"\(None\)\s*Jumping from\s+.+?\s+to\s+(.+)$"#)
    private static let conduit = regex(#"\(notify\)\s*A Conduit Field activated by .+ jumps you to\s+(.+)$"#)
    private static let fleetInvite = regex(#"\(question\)\s*<a href="[^"]+">([^<]+)</a>\s*wants you to join their fleet"#)
    private static let followWarp = regex(#"\(notify\)\s*Following\s+(.+?)\s+in warp"#)
    private static let regroup = regex(#"\(notify\)\s*Regrouping to\s+(.+?)(?:\.|$)"#)
    private static let compression = regex(#"\(notify\)\s*Successfully compressed\s+.+?\s+into\s+(\d+)\s+(.+)$"#)
    private static let decloak = regex(#"\(notify\)\s*Your cloak deactivates due to proximity to (?:a nearby )?(.+?)\."#)
    private static let conversation = regex(#"\(None\)\s*<a href=["']?showinfo:[^>"']+["']?>([^<]+)</a>\s*is inviting you to a conversation"#)
    private static let crystalBroke = regex(#"\(notify\)\s*.+?\s+deactivates due to the destruction of the\s+(.+?)\s+it was fitted with"#)
    private static let asteroidDepleted = regex(#"\(notify\)\s*.+?\s+deactivates as it finds the resource it was harvesting a pale shadow of its former glory"#)
    private static let cargoFull = regex(#"\(notify\)\s*Your\s+.+?\s+has completed operations\.\s+Ship's cargo hold is full"#)
    private static let htmlTag = regex("<[^>]*>")
    private static let whitespaceRun = regex(#"\s+"#)

    private static func regex(_ pattern: String) -> NSRegularExpression {
        // The patterns are literals in this file; a failure here is a typo, not
        // a runtime condition.
        try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }

    private static func captures(_ pattern: NSRegularExpression, in text: String) -> [String]? {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = pattern.firstMatch(in: text, range: range) else { return nil }
        return (0..<match.numberOfRanges).map { index in
            guard let range = Range(match.range(at: index), in: text) else { return "" }
            return String(text[range]).trimmingCharacters(in: .whitespaces)
        }
    }

    private static func capture(_ pattern: NSRegularExpression, in text: String,
                                group: Int) -> String? {
        guard let groups = captures(pattern, in: text), groups.count > group,
              !groups[group].isEmpty else { return nil }
        return groups[group]
    }

    private static func matches(_ pattern: NSRegularExpression, _ text: String) -> Bool {
        captures(pattern, in: text) != nil
    }

    private static func replacing(_ pattern: NSRegularExpression, in text: String,
                                  with template: String) -> String {
        pattern.stringByReplacingMatches(
            in: text, range: NSRange(text.startIndex..<text.endIndex, in: text),
            withTemplate: template)
    }
}
