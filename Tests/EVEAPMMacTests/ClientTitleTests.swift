import XCTest
@testable import EVEAPMMac

final class ClientTitleTests: XCTestCase {
    func testReadsCharacterFromClientTitle() {
        XCTAssertEqual(ClientTitle.character(from: "EVE - Qrth Vlaadimir"), "Qrth Vlaadimir")
    }

    func testReadsCharacterWhoseNameContainsTheSeparator() {
        XCTAssertEqual(ClientTitle.character(from: "EVE - Zar - Kai"), "Zar - Kai")
    }

    func testTitleWithoutCharacterHasNoCharacter() {
        XCTAssertNil(ClientTitle.character(from: "EVE"))
    }

    func testDanglingSeparatorHasNoCharacter() {
        XCTAssertNil(ClientTitle.character(from: "EVE -   "))
    }

    func testForeignWindowHasNoCharacter() {
        XCTAssertNil(ClientTitle.character(from: "EVEning News - Safari"))
    }

    func testBareClientTitleIsRecognised() {
        XCTAssertTrue(ClientTitle.isClientTitle("  EVE  "))
    }

    func testUnrelatedTitleIsNotAClientTitle() {
        XCTAssertFalse(ClientTitle.isClientTitle("EVEmon 4.1"))
    }
}
