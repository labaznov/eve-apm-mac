import CoreGraphics
import XCTest
@testable import EVEAPMMac

final class ScreenGeometryTests: XCTestCase {
    private let laptop = CGRect(x: 0, y: 0, width: 1512, height: 945)
    private let external = CGRect(x: 1512, y: 200, width: 2560, height: 1415)

    func testAThumbnailInsideADisplayFits() {
        XCTAssertTrue(ScreenGeometry.fits(CGRect(x: 40, y: 700, width: 240, height: 148),
                                          in: [laptop, external]))
    }

    func testAThumbnailOnTheSecondDisplayFits() {
        XCTAssertTrue(ScreenGeometry.fits(CGRect(x: 3000, y: 900, width: 240, height: 148),
                                          in: [laptop, external]))
    }

    func testAThumbnailOffEveryDisplayDoesNotFit() {
        XCTAssertFalse(ScreenGeometry.fits(CGRect(x: -1900, y: 300, width: 240, height: 148),
                                           in: [laptop, external]))
    }

    func testAThumbnailHangingOverAnEdgeDoesNotFit() {
        XCTAssertFalse(ScreenGeometry.fits(CGRect(x: 1400, y: 40, width: 240, height: 148),
                                           in: [laptop]))
    }

    func testNothingFitsWithoutADisplay() {
        XCTAssertFalse(ScreenGeometry.fits(CGRect(x: 0, y: 0, width: 10, height: 10), in: []))
    }
}
