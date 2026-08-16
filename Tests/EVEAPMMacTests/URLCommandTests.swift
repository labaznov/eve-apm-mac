import XCTest
@testable import EVEAPMMac

final class URLCommandTests: XCTestCase {
    func testActivatesCharacterFromLink() {
        XCTAssertEqual(URLCommand(url: URL(string: "eveapm://character/Qrth%20Vlaadimir")!),
                       .activate(character: "Qrth Vlaadimir"))
    }

    func testSuspendsHotkeysFromLink() {
        XCTAssertEqual(URLCommand(url: URL(string: "eveapm://hotkey/suspend")!), .suspendHotkeys)
    }

    func testHidesThumbnailsFromLink() {
        XCTAssertEqual(URLCommand(url: URL(string: "EVEAPM://Thumbnail/Hide")!), .hideThumbnails)
    }

    func testOpensSettingsFromLink() {
        XCTAssertEqual(URLCommand(url: URL(string: "eveapm://config/open")!), .openSettings)
    }

    func testCharacterLinkWithoutNameIsRejected() {
        XCTAssertNil(URLCommand(url: URL(string: "eveapm://character/")!))
    }

    func testForeignSchemeIsRejected() {
        XCTAssertNil(URLCommand(url: URL(string: "eveonline://character/Zar")!))
    }

    func testUnknownVerbIsRejected() {
        XCTAssertNil(URLCommand(url: URL(string: "eveapm://hotkey/explode")!))
    }
}
