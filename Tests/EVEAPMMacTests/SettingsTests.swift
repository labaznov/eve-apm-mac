import CoreGraphics
import XCTest
@testable import EVEAPMMac

final class SettingsTests: XCTestCase {
    private func client(character: String?) -> EVEClient {
        EVEClient(windowID: 4711,
                  pid: 8123,
                  title: character.map { "EVE - \($0)" } ?? "EVE",
                  frame: CGRect(x: 17, y: 43, width: 1720, height: 1080),
                  isOnScreen: true)
    }

    func testClampingPullsAnOversizedThumbnailBackIntoRange() {
        var settings = Settings()
        settings.thumbnailWidth = 9000
        XCTAssertEqual(settings.clamped().thumbnailWidth, Settings.thumbnailWidthRange.upperBound)
    }

    func testClampingLiftsAFrameRateOfZero() {
        var settings = Settings()
        settings.frameRate = 0
        XCTAssertEqual(settings.clamped().frameRate, Settings.frameRateRange.lowerBound)
    }

    func testActiveClientGetsTheActiveBorderColour() {
        var settings = Settings()
        settings.characterBorderColors["Zar Kai"] = RGBAColor(red: 1, green: 0, blue: 0, alpha: 1)
        XCTAssertEqual(settings.borderColor(for: client(character: "Zar Kai"), isActive: true),
                       settings.activeBorderColor)
    }

    func testCharacterColourWinsOverTheInactiveDefault() {
        var settings = Settings()
        let red = RGBAColor(red: 1, green: 0, blue: 0, alpha: 1)
        settings.characterBorderColors["Zar Kai"] = red
        XCTAssertEqual(settings.borderColor(for: client(character: "Zar Kai"), isActive: false), red)
    }

    func testProtectedCharacterIsNotMinimised() {
        var settings = Settings()
        settings.autoMinimizeEnabled = true
        settings.neverMinimize = ["Zar Kai"]
        XCTAssertFalse(settings.minimizes(client(character: "Zar Kai")))
    }

    func testNothingIsMinimisedWhileTheFeatureIsOff() {
        XCTAssertFalse(Settings().minimizes(client(character: "Qrth Vlaadimir")))
    }

    func testAPositionSavedAgainstAProcessIsDropped() {
        var settings = Settings()
        settings.positions["Client 28720"] = StoredPoint(CGPoint(x: 10, y: 20))
        XCTAssertTrue(settings.clamped().positions.isEmpty)
    }

    func testACharacterPositionSurvivesTheCleanup() {
        var settings = Settings()
        settings.positions["Zar Kai"] = StoredPoint(CGPoint(x: 10, y: 20))
        XCTAssertEqual(settings.clamped().positions["Zar Kai"]?.x, 10)
    }

    func testACharacterNamedLikeAProcessKeyIsKept() {
        var settings = Settings()
        settings.positions["Client Nine"] = StoredPoint(CGPoint(x: 10, y: 20))
        XCTAssertNotNil(settings.clamped().positions["Client Nine"])
    }

    func testAHiddenCharacterIsNotShown() {
        var settings = Settings()
        settings.hiddenCharacters = ["Zar Kai"]
        XCTAssertFalse(settings.shows(client(character: "Zar Kai")))
    }

    func testACharacterNotOnTheHiddenListIsShown() {
        var settings = Settings()
        settings.hiddenCharacters = ["Zar Kai"]
        XCTAssertTrue(settings.shows(client(character: "Qrth Vlaadimir")))
    }

    func testAClientWithNoCharacterFollowsItsOwnSetting() {
        var settings = Settings()
        settings.showNotLoggedInClients = false
        XCTAssertFalse(settings.shows(client(character: nil)))
    }

    func testAProtectedCharacterIsNotClosed() {
        var settings = Settings()
        settings.neverClose = ["Zar Kai"]
        XCTAssertFalse(settings.closes("Zar Kai"))
    }

    func testAnyOtherCharacterIsClosed() {
        var settings = Settings()
        settings.neverClose = ["Zar Kai"]
        XCTAssertTrue(settings.closes("Qrth Vlaadimir"))
    }

    func testAClientWithNoCharacterIsClosed() {
        XCTAssertTrue(Settings().closes(nil))
    }

    func testClientWithoutCharacterIsMinimised() {
        var settings = Settings()
        settings.autoMinimizeEnabled = true
        settings.neverMinimize = ["Zar Kai"]
        XCTAssertTrue(settings.minimizes(client(character: nil)))
    }
}
