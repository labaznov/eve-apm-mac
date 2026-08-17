import CoreGraphics
import XCTest
@testable import EVEAPMMac

final class SnappingTests: XCTestCase {
    private let neighbour = CGRect(x: 100, y: 400, width: 240, height: 150)

    func testANearbyLeftEdgeLinesUp() {
        let dragged = CGRect(x: 104, y: 200, width: 240, height: 150)
        XCTAssertEqual(Snapping.snap(dragged, to: [neighbour], within: 8).x, 100)
    }

    func testAThumbnailStacksUnderneathItsNeighbour() {
        let dragged = CGRect(x: 100, y: 253, width: 240, height: 150)
        XCTAssertEqual(Snapping.snap(dragged, to: [neighbour], within: 8).y, 250)
    }

    func testAnEdgeFurtherOffThanTheDistanceIsLeftAlone() {
        let dragged = CGRect(x: 120, y: 200, width: 240, height: 150)
        XCTAssertEqual(Snapping.snap(dragged, to: [neighbour], within: 8).x, 120)
    }

    func testTheNearestOfSeveralEdgesWins() {
        let other = CGRect(x: 90, y: 400, width: 240, height: 150)
        let dragged = CGRect(x: 97, y: 200, width: 240, height: 150)
        XCTAssertEqual(Snapping.snap(dragged, to: [neighbour, other], within: 8).x, 100)
    }

    func testSnappingOffLeavesThePositionUntouched() {
        let dragged = CGRect(x: 101, y: 200, width: 240, height: 150)
        XCTAssertEqual(Snapping.snap(dragged, to: [neighbour], within: 0).x, 101)
    }

    func testWithoutNeighboursThePositionIsUntouched() {
        let dragged = CGRect(x: 101, y: 203, width: 240, height: 150)
        XCTAssertEqual(Snapping.snap(dragged, to: [], within: 8), CGPoint(x: 101, y: 203))
    }

    func testTheRightEdgeCanMeetANeighboursLeftEdge() {
        let dragged = CGRect(x: -145, y: 200, width: 240, height: 150)
        XCTAssertEqual(Snapping.snap(dragged, to: [neighbour], within: 8).x, -140)
    }
}
