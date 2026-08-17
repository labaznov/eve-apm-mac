import Combine
import Foundation

/// Follows the log files EVE writes, so thumbnails can show which system a
/// character sits in and what just happened to it. EVE names its logs after the
/// session rather than the character, so each file's header is read once to
/// learn whose it is.
@MainActor
final class LogMonitor: ObservableObject {
    /// Character name to the solar system it was last seen in.
    @Published private(set) var systems: [String: String] = [:]

    var onAlert: ((String, Alert) -> Void)?

    private var settings = Settings()
    private var tails: [URL: LogTail] = [:]
    private var seenAt: [String: Date] = [:]
    private var pollTimer: Timer?
    private var scanTimer: Timer?
    /// One watchdog per character that is mining, so the moment the ticks stop
    /// can be reported.
    private var miningWatchdogs: [String: Task<Void, Never>] = [:]
    private var isRunning = false

    private static let activePoll: TimeInterval = 0.5
    private static let idlePoll: TimeInterval = 1.0
    private static let scanInterval: TimeInterval = 30
    private static let maximumAge: TimeInterval = 24 * 3600
    /// How far back a freshly discovered log is read, enough to find the
    /// current system without wading through a whole day of chatter.
    private static let catchUpBytes: UInt64 = 512 * 1024

    func start() {
        guard !isRunning else { return }
        isRunning = true
        scan()
        scanTimer = Timer.scheduledTimer(withTimeInterval: Self.scanInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.scan() }
        }
        schedulePoll(after: Self.idlePoll)
    }

    func stop() {
        isRunning = false
        pollTimer?.invalidate()
        scanTimer?.invalidate()
        pollTimer = nil
        scanTimer = nil
        tails.removeAll()
        for watchdog in miningWatchdogs.values { watchdog.cancel() }
        miningWatchdogs.removeAll()
    }

    func apply(_ settings: Settings) {
        let directoriesChanged = settings.chatLogDirectory != self.settings.chatLogDirectory
            || settings.gameLogDirectory != self.settings.gameLogDirectory
        let monitoringChanged = settings.monitorChatLogs != self.settings.monitorChatLogs
            || settings.monitorGameLogs != self.settings.monitorGameLogs
        self.settings = settings

        guard isRunning else { return }
        if directoriesChanged || monitoringChanged {
            tails.removeAll()
            systems.removeAll()
            seenAt.removeAll()
            scan()
        }
    }

    func system(for character: String) -> String? {
        systems[character]
    }

    // MARK: - Discovery

    private func scan() {
        var wanted: [URL: LogTail] = [:]
        if settings.monitorChatLogs {
            collect(kind: .chat, prefix: "Local_", into: &wanted)
        }
        if settings.monitorGameLogs {
            collect(kind: .game, prefix: nil, into: &wanted)
        }

        for (url, tail) in wanted where tails[url] == nil {
            var fresh = tail
            fresh.start(fromLast: Self.catchUpBytes)
            consume(fresh.readLines(), from: fresh, raisingAlerts: false)
            tails[url] = fresh
        }
        for url in tails.keys where wanted[url] == nil {
            tails.removeValue(forKey: url)
        }
    }

    /// Picks the newest log per character, since every client session starts a
    /// file of its own and only the last one is still being written.
    private func collect(kind: LogKind, prefix: String?, into wanted: inout [URL: LogTail]) {
        var newest: [String: (url: URL, date: Date)] = [:]
        let cutoff = Date().addingTimeInterval(-Self.maximumAge)

        for url in files(in: settings.logDirectory(kind), prefix: prefix) {
            guard let modified = modificationDate(of: url), modified > cutoff else { continue }
            guard let character = character(of: url, kind: kind) else { continue }
            if let known = newest[character], known.date >= modified { continue }
            newest[character] = (url, modified)
        }

        for (character, entry) in newest {
            wanted[entry.url] = LogTail(url: entry.url, kind: kind, character: character)
        }
    }

    private func files(in directory: URL, prefix: String?) -> [URL] {
        let contents = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles])
        return (contents ?? []).filter { url in
            url.pathExtension.lowercased() == "txt"
                && (prefix.map { url.lastPathComponent.hasPrefix($0) } ?? true)
        }
    }

    private func modificationDate(of url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    private func character(of url: URL, kind: LogKind) -> String? {
        if let tail = tails[url] { return tail.character }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let head = try? handle.read(upToCount: 4096) else { return nil }

        let encoding: String.Encoding = kind == .chat ? .utf16LittleEndian : .utf8
        var data = head
        if encoding == .utf16LittleEndian, data.count % 2 != 0 { data.removeLast() }
        guard let text = String(data: data, encoding: encoding) else { return nil }
        return LogParser.listener(inHeader: text)
    }

    // MARK: - Polling

    private func schedulePoll(after interval: TimeInterval) {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
    }

    private func poll() {
        guard isRunning else { return }
        var sawActivity = false
        for url in tails.keys {
            guard var tail = tails[url] else { continue }
            let lines = tail.readLines()
            tails[url] = tail
            if !lines.isEmpty {
                sawActivity = true
                consume(lines, from: tail, raisingAlerts: true)
            }
        }
        schedulePoll(after: sawActivity ? Self.activePoll : Self.idlePoll)
    }

    private func consume(_ lines: [String], from tail: LogTail, raisingAlerts: Bool) {
        for line in lines where LogParser.isInteresting(line, kind: tail.kind) {
            guard let event = LogParser.event(from: line, kind: tail.kind) else { continue }
            switch event {
            case .system(let name, let at):
                record(system: name, for: tail.character, at: at)
            case .alert(let alert):
                guard raisingAlerts, settings.shows(alert.kind) else { continue }
                if alert.kind == .miningStopped { stopWatchingMining(tail.character) }
                onAlert?(tail.character, alert)
            case .miningTick(let at):
                guard raisingAlerts else { continue }
                watchMining(tail.character, since: at)
            }
        }
    }

    /// EVE writes a line for every mining cycle. Nothing marks the end of a
    /// session, so the end is the silence after the last one.
    private func watchMining(_ character: String, since: Date) {
        miningWatchdogs[character]?.cancel()
        let timeout = settings.miningTimeout
        miningWatchdogs[character] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(timeout))
            guard !Task.isCancelled, let self, settings.shows(.miningIdle) else { return }
            miningWatchdogs[character] = nil
            onAlert?(character, Alert(kind: .miningIdle,
                                      text: "No mining for \(Int(timeout))s", time: Date()))
        }
    }

    private func stopWatchingMining(_ character: String) {
        miningWatchdogs[character]?.cancel()
        miningWatchdogs[character] = nil
    }

    /// Chat and game logs report the same jump, and a catch-up read replays old
    /// ones, so only a report newer than the last one counts.
    private func record(system: String, for character: String, at time: Date) {
        guard !system.isEmpty else { return }
        if let seen = seenAt[character], seen > time { return }
        seenAt[character] = time
        guard systems[character] != system else { return }
        systems[character] = system
    }
}
