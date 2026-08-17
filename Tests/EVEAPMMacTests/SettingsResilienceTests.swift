import CoreGraphics
import XCTest
@testable import EVEAPMMac

/// A settings file outlives the build that wrote it and gets edited by hand, so
/// reading one has to give up as little as possible. These are the cases that
/// have cost an arrangement before.
final class SettingsResilienceTests: XCTestCase {
    private func temporaryFile() throws -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("eveapm-read-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory.appendingPathComponent("settings.json")
    }

    private func write(_ json: String, to url: URL) throws {
        try Data(json.utf8).write(to: url)
    }

    // MARK: - A file from an older build

    func testAFileWithoutTheNewestFieldsKeepsItsPositions() throws {
        let url = try temporaryFile()
        try write(#"{"thumbnailWidth": 240, "positions": {"Zar Kai": {"x": 175, "y": 1217}}}"#, to: url)
        XCTAssertEqual(SettingsFile.load(from: url).positions["Zar Kai"]?.y, 1217)
    }

    func testAFileWithOnlyOneFieldKeepsThatField() throws {
        let url = try temporaryFile()
        try write(#"{"thumbnailWidth": 317}"#, to: url)
        XCTAssertEqual(SettingsFile.load(from: url).thumbnailWidth, 317)
    }

    func testAFileWithOnlyOneFieldLeavesTheRestAtItsDefaults() throws {
        let url = try temporaryFile()
        try write(#"{"thumbnailWidth": 317}"#, to: url)
        XCTAssertEqual(SettingsFile.load(from: url).frameRate, Settings().frameRate)
    }

    func testHotkeysFromAFileWithoutIdentitiesAreKept() throws {
        let url = try temporaryFile()
        try write(#"{"hotkeys": [{"keyCode": 124, "modifiers": 0, "action": {"cycleForward": {}}}]}"#,
                  to: url)
        XCTAssertEqual(SettingsFile.load(from: url).hotkeys.first?.keyCode, 124)
    }

    // MARK: - A file edited by hand

    func testOneFieldOfTheWrongTypeDoesNotTakeTheOthersDown() throws {
        let url = try temporaryFile()
        try write(#"{"thumbnailWidth": "wide", "positions": {"Zar Kai": {"x": 10, "y": 20}}}"#,
                  to: url)
        XCTAssertEqual(SettingsFile.load(from: url).positions["Zar Kai"]?.x, 10)
    }

    func testAFieldOfTheWrongTypeFallsBackToItsDefault() throws {
        let url = try temporaryFile()
        try write(#"{"thumbnailWidth": "wide"}"#, to: url)
        XCTAssertEqual(SettingsFile.load(from: url).thumbnailWidth, Settings().thumbnailWidth)
    }

    func testAnUnreadableFieldIsNamed() {
        XCTAssertEqual(SettingsFile.read(Data(#"{"frameRate": "fast"}"#.utf8)).unreadable,
                       ["frameRate"])
    }

    func testAFieldThisBuildDoesNotKnowIsNotComplainedAbout() {
        XCTAssertTrue(SettingsFile.read(Data(#"{"somethingFromTheFuture": 1}"#.utf8))
            .unreadable.isEmpty)
    }

    func testAFieldThisBuildDoesNotKnowLeavesTheRestReadable() {
        XCTAssertEqual(SettingsFile.read(Data(#"{"somethingFromTheFuture": 1, "frameRate": 7}"#.utf8))
            .settings?.frameRate, 7)
    }

    // MARK: - A file that is not JSON at all

    func testAFileThatIsNotJSONYieldsDefaults() throws {
        let url = try temporaryFile()
        try write("{ not json", to: url)
        XCTAssertEqual(SettingsFile.load(from: url), Settings())
    }

    func testAFileThatIsNotJSONIsKeptForInspection() throws {
        let url = try temporaryFile()
        try write("{ not json", to: url)
        _ = SettingsFile.load(from: url)
        let copy = url.deletingPathExtension().appendingPathExtension("broken.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: copy.path))
    }

    func testAFileThatIsNotJSONIsLeftWhereItWas() throws {
        let url = try temporaryFile()
        try write("{ not json", to: url)
        _ = SettingsFile.load(from: url)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "{ not json")
    }

    // MARK: - Everything a full file holds survives

    func testAFullFileSurvivesARoundTrip() throws {
        let url = try temporaryFile()
        var written = Settings()
        written.thumbnailWidth = 271
        written.positions["Zar Kai"] = StoredPoint(CGPoint(x: 12, y: 34))
        written.hotkeys = [Hotkey(keyCode: 18, modifiers: 4096, action: .cycleForward)]
        written.cycleGroups = [CycleGroup(name: "squad", characters: ["Zar Kai"])]
        written.characterThumbnailWidths["Zar Kai"] = 400
        try SettingsFile.save(written, to: url)
        XCTAssertEqual(SettingsFile.load(from: url), written)
    }
}
