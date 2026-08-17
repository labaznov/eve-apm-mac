import CoreGraphics
import XCTest
@testable import EVEAPMMac

final class StackLayoutTests: XCTestCase {
    private let anchor = CGPoint(x: 1000, y: 1200)
    private let size = CGSize(width: 240, height: 150)

    private func position(_ index: Int, _ mode: StackMode) -> CGPoint {
        StackLayout.position(index: index, mode: mode, anchor: anchor, size: size)
    }

    func testTheFirstOneSitsOnTheAnchor() {
        XCTAssertEqual(position(0, .column), anchor)
    }

    func testARowStepsToTheRight() {
        XCTAssertEqual(position(2, .row).x, 1000 + 2 * (240 + StackLayout.spacing))
    }

    func testARowStaysOnOneLine() {
        XCTAssertEqual(position(2, .row).y, 1200)
    }

    func testAColumnStepsDownTheScreen() {
        XCTAssertEqual(position(2, .column).y, 1200 - 2 * (150 + StackLayout.spacing))
    }

    func testAColumnStaysInOneLine() {
        XCTAssertEqual(position(2, .column).x, 1000)
    }

    func testAPileLeavesThemOnTopOfEachOther() {
        XCTAssertEqual(position(3, .pile), anchor)
    }
}
