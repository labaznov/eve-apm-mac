import CoreGraphics
import XCTest
@testable import EVEAPMMac

final class SettingsFileTests: XCTestCase {
    private func temporaryFile() throws -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("eveapm-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory.appendingPathComponent("settings.json")
    }

    func testMissingFileYieldsDefaults() throws {
        XCTAssertEqual(SettingsFile.load(from: try temporaryFile()), Settings())
    }

    func testSettingsSurviveARoundTrip() throws {
        let url = try temporaryFile()
        var written = Settings()
        written.thumbnailWidth = 317
        written.hotkeys = [Hotkey(keyCode: 122, modifiers: 4096, action: .activate(character: "Zar Kai"))]
        written.positions["Zar Kai"] = StoredPoint(CGPoint(x: -1440, y: 823))
        written.mutedAlerts = [AlertKind.compression.rawValue]
        try SettingsFile.save(written, to: url)
        XCTAssertEqual(SettingsFile.load(from: url), written)
    }

    func testCorruptFileYieldsDefaults() throws {
        let url = try temporaryFile()
        try Data("{ not json".utf8).write(to: url)
        XCTAssertEqual(SettingsFile.load(from: url), Settings())
    }

    func testOutOfRangeFileIsClampedOnLoad() throws {
        let url = try temporaryFile()
        var written = Settings()
        written.opacity = 7.5
        try SettingsFile.save(written, to: url)
        XCTAssertEqual(SettingsFile.load(from: url).opacity, Settings.opacityRange.upperBound)
    }

    func testMutedAlertIsNotShown() {
        var settings = Settings()
        settings.mutedAlerts = [AlertKind.decloak.rawValue]
        XCTAssertFalse(settings.shows(.decloak))
    }

    func testDisablingAlertsSilencesEveryKind() {
        var settings = Settings()
        settings.alertsEnabled = false
        XCTAssertFalse(settings.shows(.fleetInvite))
    }

    func testChatLogDirectoryDefaultsToWhereEVEWritesIt() {
        XCTAssertEqual(Settings().logDirectory(.chat).lastPathComponent, "Chatlogs")
    }

    func testConfiguredLogDirectoryExpandsATilde() {
        var settings = Settings()
        settings.gameLogDirectory = "~/EVE/Gamelogs"
        XCTAssertFalse(settings.logDirectory(.game).path.contains("~"))
    }
}
