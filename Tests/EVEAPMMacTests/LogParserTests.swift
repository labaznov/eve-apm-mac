import XCTest
@testable import EVEAPMMac

final class LogParserTests: XCTestCase {
    private let epoch = Date(timeIntervalSince1970: 0)

    private func system(_ line: String, _ kind: LogKind) -> String? {
        guard case .system(let name, _)? = LogParser.event(from: line, kind: kind, now: epoch) else {
            return nil
        }
        return name
    }

    private func alert(_ line: String) -> Alert? {
        guard case .alert(let alert)? = LogParser.event(from: line, kind: .game, now: epoch) else {
            return nil
        }
        return alert
    }

    func testLocalChannelLineReportsTheSystem() {
        XCTAssertEqual(
            system("\u{FEFF}[ 2026.08.16 21:46:27 ] EVE System > Channel changed to Local : AAA-111\r",
                   .chat),
            "AAA-111")
    }

    func testLineCarriesTheLogTimestampInEVETime() {
        XCTAssertEqual(
            LogParser.timestamp(in: "[ 2026.08.16 21:46:27 ] EVE System > Channel changed to Local : AAA-111"),
            DateComponents(calendar: Calendar(identifier: .gregorian),
                           timeZone: TimeZone(identifier: "UTC"),
                           year: 2026, month: 8, day: 16,
                           hour: 21, minute: 46, second: 27).date)
    }

    func testPlayerChatIsNotASystemChange() {
        XCTAssertNil(system("[ 2026.08.16 21:47:19 ] Ahpa66HD > TPAR-G is clear", .chat))
    }

    func testJumpReportsTheDestinationSystem() {
        XCTAssertEqual(
            system("[ 2026.08.16 22:03:11 ] (None) Jumping from CCC-333 to DDD-444", .game),
            "DDD-444")
    }

    func testConduitJumpReportsTheDestinationSystem() {
        XCTAssertEqual(
            system("[ 2026.08.16 22:03:11 ] (notify) A Conduit Field activated by Zar Kai jumps you to J000000.",
                   .game),
            "J000000")
    }

    func testFleetInviteNamesTheInviter() {
        XCTAssertEqual(
            alert("[ 2026.08.16 22:04:00 ] (question) <a href=\"showinfo:1377//95465499\">Qrth Vlaadimir</a> wants you to join their fleet")?.text,
            "Fleet invite from Qrth Vlaadimir")
    }

    func testFollowWarpIsAnAlert() {
        XCTAssertEqual(
            alert("[ 2026.08.16 22:04:31 ] (notify) Following Zar Kai in warp to 300 km")?.kind,
            .followWarp)
    }

    func testRegroupDropsTheTrailingStop() {
        XCTAssertEqual(
            alert("[ 2026.08.16 22:05:02 ] (notify) Regrouping to Zar Kai.")?.text,
            "Regrouping to Zar Kai")
    }

    func testCompressionCountsTheOutput() {
        XCTAssertEqual(
            alert("[ 2026.08.16 22:06:44 ] (notify) Successfully compressed Bright Spodumain into 37 Compressed Bright Spodumain.")?.text,
            "Compressed 37x Compressed Bright Spodumain")
    }

    func testDecloakNamesTheSource() {
        XCTAssertEqual(
            alert("[ 2026.08.16 22:07:10 ] (notify) Your cloak deactivates due to proximity to a nearby Large Collidable Object.")?.text,
            "Decloaked by Large Collidable Object")
    }

    func testConversationRequestNamesThePilot() {
        XCTAssertEqual(
            alert("[ 2026.08.16 22:08:00 ] (None) <a href=showinfo:1377//90001>Rook Talvane</a> is inviting you to a conversation.")?.text,
            "Conversation from Rook Talvane")
    }

    func testBrokenCrystalNamesTheCrystal() {
        XCTAssertEqual(
            alert("[ 2026.08.16 22:09:00 ] (notify) Modulated Deep Core Miner II deactivates due to the destruction of the Spodumain Mining Crystal II it was fitted with.")?.text,
            "Crystal broke: Spodumain Mining Crystal II")
    }

    func testDepletedAsteroidStopsMining() {
        XCTAssertEqual(
            alert("[ 2026.08.16 22:10:00 ] (notify) Ice Harvester II deactivates as it finds the resource it was harvesting a pale shadow of its former glory.")?.kind,
            .miningStopped)
    }

    func testFullCargoStopsMining() {
        XCTAssertEqual(
            alert("[ 2026.08.16 22:11:00 ] (notify) Your Mining Laser has completed operations. Ship's cargo hold is full.")?.kind,
            .miningStopped)
    }

    func testUnremarkableGameLineHasNoEvent() {
        XCTAssertNil(LogParser.event(
            from: "[ 2026.08.16 21:46:24 ] (hint) Attempting to join a channel",
            kind: .game, now: epoch))
    }

    func testChatterIsSkippedBeforeParsing() {
        XCTAssertFalse(LogParser.isInteresting("[ 2026.08.16 21:47:19 ] Ahpa66HD > TPAR-G", kind: .chat))
    }

    func testSystemLineIsWorthParsing() {
        XCTAssertTrue(LogParser.isInteresting("[ .. ] EVE System > Channel changed to Local : AAA-111",
                                              kind: .chat))
    }

    func testHeaderNamesTheListener() {
        let header = """
                  Channel ID:      local
                  Channel Name:    Local
                  Listener:        Vex Aldrin
                  Session started: 2026.08.16 21:46:24
            """
        XCTAssertEqual(LogParser.listener(inHeader: header), "Vex Aldrin")
    }

    func testHeaderWithoutListenerNamesNobody() {
        XCTAssertNil(LogParser.listener(inHeader: "  Channel Name:    Local"))
    }

    func testSystemNameLosesMarkupAndPunctuation() {
        XCTAssertEqual(LogParser.sanitize("<b>J000000</b> ,"), "J000000")
    }
}
