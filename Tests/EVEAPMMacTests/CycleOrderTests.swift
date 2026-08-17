import XCTest
@testable import EVEAPMMac

final class CycleOrderTests: XCTestCase {
    private let squad = ["Zar Kai", "Qrth Vlaadimir", "Sable Quint"]

    func testSteppingForwardTakesTheNextMember() {
        XCTAssertEqual(CycleOrder.next(in: squad, from: "Zar Kai", forward: true, loops: true),
                       "Qrth Vlaadimir")
    }

    func testSteppingBackwardTakesThePreviousMember() {
        XCTAssertEqual(CycleOrder.next(in: squad, from: "Sable Quint", forward: false, loops: true),
                       "Qrth Vlaadimir")
    }

    func testTheEndWrapsRoundWhenTheCycleLoops() {
        XCTAssertEqual(CycleOrder.next(in: squad, from: "Sable Quint", forward: true, loops: true),
                       "Zar Kai")
    }

    func testTheStartWrapsRoundWhenTheCycleLoops() {
        XCTAssertEqual(CycleOrder.next(in: squad, from: "Zar Kai", forward: false, loops: true),
                       "Sable Quint")
    }

    func testTheEndHoldsWhenTheCycleDoesNotLoop() {
        XCTAssertNil(CycleOrder.next(in: squad, from: "Sable Quint", forward: true, loops: false))
    }

    func testAnOutsiderEntersAtTheStart() {
        XCTAssertEqual(CycleOrder.next(in: squad, from: "Stranger", forward: true, loops: false),
                       "Zar Kai")
    }

    func testNothingInFrontEntersAtTheEndGoingBackwards() {
        XCTAssertEqual(CycleOrder.next(in: squad, from: nil, forward: false, loops: true),
                       "Sable Quint")
    }

    func testAnEmptyCycleHasNoNext() {
        XCTAssertNil(CycleOrder.next(in: [], from: nil, forward: true, loops: true))
    }

    func testACycleOfOneStaysOnIt() {
        XCTAssertEqual(CycleOrder.next(in: ["Zar Kai"], from: "Zar Kai", forward: true, loops: true),
                       "Zar Kai")
    }
}
