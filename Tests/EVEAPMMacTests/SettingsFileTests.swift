import CoreGraphics
import XCTest
@testable import EVEAPMMac

final class SettingsFileTests: XCTestCase {
    private func temporaryDirectory() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("eveapm-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testMissingFileYieldsDefaults() throws {
        XCTAssertEqual(SettingsFile.load(from: try temporaryDirectory()), Settings())
    }

    func testSettingsSurviveARoundTrip() throws {
        let directory = try temporaryDirectory()
        var written = Settings()
        written.thumbnailWidth = 317
        written.hotkeys = [Hotkey(keyCode: 122, modifiers: 4096, action: .activate(character: "Zar Kai"))]
        written.positions["Zar Kai"] = StoredPoint(CGPoint(x: -1440, y: 823))
        try SettingsFile.save(written, to: directory)
        XCTAssertEqual(SettingsFile.load(from: directory), written)
    }

    func testCorruptFileYieldsDefaults() throws {
        let directory = try temporaryDirectory()
        try Data("{ not json".utf8)
            .write(to: directory.appendingPathComponent(SettingsFile.fileName))
        XCTAssertEqual(SettingsFile.load(from: directory), Settings())
    }

    func testOutOfRangeFileIsClampedOnLoad() throws {
        let directory = try temporaryDirectory()
        var written = Settings()
        written.opacity = 7.5
        try SettingsFile.save(written, to: directory)
        XCTAssertEqual(SettingsFile.load(from: directory).opacity, Settings.opacityRange.upperBound)
    }
}
