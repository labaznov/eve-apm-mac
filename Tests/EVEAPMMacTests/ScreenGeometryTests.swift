import CoreGraphics
import XCTest
@testable import EVEAPMMac

final class ScreenGeometryTests: XCTestCase {
    /// A 2560×1440 display, as macOS reports it: the whole panel, menu bar and
    /// Dock included.
    private let display = CGRect(x: 0, y: 0, width: 2560, height: 1440)
    private let second = CGRect(x: 2560, y: 200, width: 1512, height: 945)
    private let size = CGSize(width: 240, height: 164)

    private func thumbnail(_ x: CGFloat, _ y: CGFloat) -> CGRect {
        CGRect(origin: CGPoint(x: x, y: y), size: size)
    }

    func testAThumbnailInTheMiddleFits() {
        XCTAssertTrue(ScreenGeometry.fits(thumbnail(400, 600), in: [display]))
    }

    func testAThumbnailOverTheDockStillFits() {
        // The Dock takes the bottom 79 points; a position there is one the user
        // chose and must not be taken away.
        XCTAssertTrue(ScreenGeometry.fits(thumbnail(40, 10), in: [display]))
    }

    func testAThumbnailUnderTheMenuBarStillFits() {
        XCTAssertTrue(ScreenGeometry.fits(thumbnail(40, 1440 - 164), in: [display]))
    }

    func testAThumbnailOnTheSecondDisplayFits() {
        XCTAssertTrue(ScreenGeometry.fits(thumbnail(3000, 400), in: [display, second]))
    }

    func testAThumbnailAcrossTwoDisplaysFits() {
        XCTAssertTrue(ScreenGeometry.fits(thumbnail(2450, 400), in: [display, second]))
    }

    func testAThumbnailOnAMonitorThatIsGoneDoesNotFit() {
        XCTAssertFalse(ScreenGeometry.fits(thumbnail(-1900, 300), in: [display]))
    }

    func testAThumbnailHangingMostlyOffAnEdgeDoesNotFit() {
        XCTAssertFalse(ScreenGeometry.fits(thumbnail(2500, 600), in: [display]))
    }

    func testAThumbnailHangingSlightlyOffAnEdgeStillFits() {
        XCTAssertTrue(ScreenGeometry.fits(thumbnail(2380, 600), in: [display]))
    }

    func testNothingFitsWithoutADisplay() {
        XCTAssertFalse(ScreenGeometry.fits(thumbnail(0, 0), in: []))
    }
}
