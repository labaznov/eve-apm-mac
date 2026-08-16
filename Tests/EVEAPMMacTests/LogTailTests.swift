import XCTest
@testable import EVEAPMMac

final class LogTailTests: XCTestCase {
    private func temporaryFile(_ name: String) throws -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("eveapm-tail-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory.appendingPathComponent(name)
    }

    private func append(_ text: String, to url: URL, encoding: String.Encoding) throws {
        let data = text.data(using: encoding)!
        if FileManager.default.fileExists(atPath: url.path) {
            let handle = try FileHandle(forWritingTo: url)
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.close()
        } else {
            try data.write(to: url)
        }
    }

    func testReadsTheLinesAlreadyInAGameLog() throws {
        let url = try temporaryFile("gamelog.txt")
        try append("[ 1 ] first\n[ 2 ] second\n", to: url, encoding: .utf8)
        var tail = LogTail(url: url, kind: .game, character: "Zar Kai")
        XCTAssertEqual(tail.readLines(), ["[ 1 ] first", "[ 2 ] second"])
    }

    func testHoldsBackALineThatHasNoBreakYet() throws {
        let url = try temporaryFile("gamelog.txt")
        try append("[ 1 ] first\n[ 2 ] unter", to: url, encoding: .utf8)
        var tail = LogTail(url: url, kind: .game, character: "Zar Kai")
        XCTAssertEqual(tail.readLines(), ["[ 1 ] first"])
    }

    func testCompletesAHeldLineOnTheNextRead() throws {
        let url = try temporaryFile("gamelog.txt")
        try append("[ 2 ] unter", to: url, encoding: .utf8)
        var tail = LogTail(url: url, kind: .game, character: "Zar Kai")
        _ = tail.readLines()
        try append("minated\n", to: url, encoding: .utf8)
        XCTAssertEqual(tail.readLines(), ["[ 2 ] unterminated"])
    }

    func testReadsUtf16ChatLogLines() throws {
        let url = try temporaryFile("Local_1.txt")
        try append("\u{FEFF}[ 1 ] Rook Talvane > BBB-222 clr\r\n", to: url, encoding: .utf16LittleEndian)
        var tail = LogTail(url: url, kind: .chat, character: "Zar Kai")
        XCTAssertEqual(tail.readLines(), ["\u{FEFF}[ 1 ] Rook Talvane > BBB-222 clr"])
    }

    func testResumesAfterAnOddByteLandsInTheMiddleOfACharacter() throws {
        let url = try temporaryFile("Local_1.txt")
        let line = "[ 1 ] EVE System > Channel changed to Local : AAA-111\r\n"
        let bytes = line.data(using: .utf16LittleEndian)!
        try bytes.prefix(9).write(to: url)
        var tail = LogTail(url: url, kind: .chat, character: "Zar Kai")
        _ = tail.readLines()
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: bytes.dropFirst(9))
        try handle.close()
        XCTAssertEqual(tail.readLines(), ["[ 1 ] EVE System > Channel changed to Local : AAA-111"])
    }

    func testNothingNewYieldsNoLines() throws {
        let url = try temporaryFile("gamelog.txt")
        try append("[ 1 ] first\n", to: url, encoding: .utf8)
        var tail = LogTail(url: url, kind: .game, character: "Zar Kai")
        _ = tail.readLines()
        XCTAssertEqual(tail.readLines(), [])
    }

    func testATruncatedFileIsReadFromItsStart() throws {
        let url = try temporaryFile("gamelog.txt")
        try append("[ 1 ] first\n[ 2 ] second\n", to: url, encoding: .utf8)
        var tail = LogTail(url: url, kind: .game, character: "Zar Kai")
        _ = tail.readLines()
        try Data("[ 3 ] third\n".utf8).write(to: url)
        XCTAssertEqual(tail.readLines(), ["[ 3 ] third"])
    }

    func testSeekingToTheEndSkipsWhatIsAlreadyThere() throws {
        let url = try temporaryFile("gamelog.txt")
        try append("[ 1 ] first\n", to: url, encoding: .utf8)
        var tail = LogTail(url: url, kind: .game, character: "Zar Kai")
        tail.seekToEnd()
        XCTAssertEqual(tail.readLines(), [])
    }
}
