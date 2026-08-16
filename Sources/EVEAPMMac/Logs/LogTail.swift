import Foundation

/// Follows one log file, handing back whole lines as EVE appends them. Chat
/// logs are UTF-16 and game logs are UTF-8, and a read can land mid-character,
/// so the unconsumed bytes are carried over to the next read.
struct LogTail {
    let url: URL
    let kind: LogKind
    let character: String
    private(set) var offset: UInt64 = 0
    private var pending = Data()

    init(url: URL, kind: LogKind, character: String) {
        self.url = url
        self.kind = kind
        self.character = character
    }

    var encoding: String.Encoding {
        kind == .chat ? .utf16LittleEndian : .utf8
    }

    mutating func seekToEnd() {
        offset = (try? FileHandle(forReadingFrom: url).seekToEnd()) ?? 0
        pending.removeAll()
    }

    /// Begins reading a set distance from the end, so a long-running session's
    /// log is caught up with without replaying all of it.
    mutating func start(fromLast bytes: UInt64) {
        let size = (try? FileHandle(forReadingFrom: url).seekToEnd()) ?? 0
        var start = size > bytes ? size - bytes : 0
        // UTF-16 characters are two bytes wide from the start of the file, and
        // an odd offset would decode the rest of it as nonsense.
        if encoding == .utf16LittleEndian { start -= start % 2 }
        offset = start
        pending.removeAll()
    }

    /// Reads whatever was appended since the last call. A file that shrank was
    /// replaced by a new session, so reading restarts from its beginning.
    mutating func readLines() -> [String] {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? handle.close() }

        let size = (try? handle.seekToEnd()) ?? 0
        if size < offset {
            offset = 0
            pending.removeAll()
        }
        guard size > offset else { return [] }

        try? handle.seek(toOffset: offset)
        guard let fresh = try? handle.readToEnd(), !fresh.isEmpty else { return [] }
        offset = size
        pending.append(fresh)

        return takeCompleteLines()
    }

    private mutating func takeCompleteLines() -> [String] {
        var usable = pending
        if encoding == .utf16LittleEndian, usable.count % 2 != 0 {
            usable.removeLast()
        }
        // A carriage return and its line feed form one character in Swift, so
        // the break is found by kind rather than by comparing to "\n".
        guard let text = String(data: usable, encoding: encoding),
              let lastBreak = text.lastIndex(where: \.isNewline) else { return [] }

        let complete = String(text[text.startIndex...lastBreak])
        pending.removeFirst(byteCount(of: complete))

        return complete
            .split(whereSeparator: \.isNewline)
            .map(String.init)
    }

    private func byteCount(of text: String) -> Int {
        encoding == .utf16LittleEndian ? text.utf16.count * 2 : text.utf8.count
    }
}
