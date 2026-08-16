import XCTest
@testable import EVEAPMMac

final class WindowsProfileTests: XCTestCase {
    private let sample = """
        [thumbnail]
        width=317
        opacity=80

        [window]
        alwaysOnTop=true
        minimizeInactiveClients=true
        minimizeDelay=4500
        neverMinimizeCharacters=Zar Kai, Qrth Vlaadimir

        [ui]
        hideActiveClientThumbnail=false
        highlightColor=#ff8800

        [overlay]
        showSystemName=false
        characterNameColor=#00ff00

        [hotkey]
        onlyWhenEVEFocused=false

        [thumbnailPositions]
        Zar Kai=@Point(200 100)
        Qrth Vlaadimir=@Point(-32000 -32000)

        [characterBorderColors]
        Zar Kai=#123456
        """

    private func imported(screenHeight: CGFloat = 1440) -> Settings {
        WindowsProfile.settings(fromINI: sample, screenHeight: screenHeight)
    }

    func testThumbnailWidthComesAcross() {
        XCTAssertEqual(imported().thumbnailWidth, 317)
    }

    func testPercentOpacityBecomesAFraction() {
        XCTAssertEqual(imported().opacity, 0.8, accuracy: 0.001)
    }

    func testMillisecondDelayBecomesSeconds() {
        XCTAssertEqual(imported().autoMinimizeDelay, 4.5, accuracy: 0.001)
    }

    func testProtectedCharactersComeAcross() {
        XCTAssertEqual(imported().neverMinimize, ["Zar Kai", "Qrth Vlaadimir"])
    }

    func testHighlightColourBecomesTheActiveBorder() {
        XCTAssertEqual(imported().activeBorderColor,
                       RGBAColor(red: 1, green: 136.0 / 255, blue: 0, alpha: 1))
    }

    func testSwitchedOffOverlayStaysOff() {
        XCTAssertFalse(imported().showSystemName)
    }

    func testPositionIsFlippedOntoTheMacCoordinateSpace() {
        // 1440 tall screen, 100 from the top, a 178 point tall thumbnail.
        XCTAssertEqual(imported().positions["Zar Kai"]?.y, 1440 - 100 - 317 * 9 / 16)
    }

    func testHorizontalPositionIsUnchanged() {
        XCTAssertEqual(imported().positions["Zar Kai"]?.x, 200)
    }

    func testMinimisedWindowPositionIsDropped() {
        XCTAssertNil(imported().positions["Qrth Vlaadimir"])
    }

    func testPerCharacterBorderColourComesAcross() {
        XCTAssertEqual(imported().characterBorderColors["Zar Kai"],
                       RGBAColor(red: 18.0 / 255, green: 52.0 / 255, blue: 86.0 / 255, alpha: 1))
    }

    func testAbsentSettingKeepsTheValueItHadHere() {
        var base = Settings()
        base.frameRate = 7
        XCTAssertEqual(
            WindowsProfile.settings(fromINI: sample, base: base, screenHeight: 1440).frameRate, 7)
    }

    func testEveFocusSettingComesAcross() {
        XCTAssertFalse(imported().hotkeysRequireEVEFocus)
    }

    func testCommentsAndBlankLinesAreIgnored() {
        XCTAssertEqual(INIFile("; a comment\n\n[g]\nk=v").string("g/k"), "v")
    }

    func testPercentEscapedKeyIsDecoded() {
        XCTAssertEqual(INIFile("[thumbnailPositions]\nZar%20Kai=@Point(1 2)")
            .string("thumbnailPositions/Zar Kai"), "@Point(1 2)")
    }

    func testColourWithAnAlphaPairIsRead() {
        XCTAssertEqual(INIFile.colour(fromHex: "#ff112233"),
                       RGBAColor(red: 17.0 / 255, green: 34.0 / 255, blue: 51.0 / 255, alpha: 1))
    }
}
