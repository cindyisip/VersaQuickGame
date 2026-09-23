import XCTest
@testable import QuickGameCore

final class GameRulesTests: XCTestCase {
    func testCompletedScoreRules() {
        XCTAssertTrue(GameRules.validScore(a: 11, b: 9, target: 11, winBy: 2))
        XCTAssertTrue(GameRules.validScore(a: 12, b: 10, target: 11, winBy: 2))
        XCTAssertFalse(GameRules.validScore(a: 11, b: 10, target: 11, winBy: 2))
        XCTAssertFalse(GameRules.validScore(a: 12, b: 9, target: 11, winBy: 2))
        XCTAssertFalse(GameRules.validScore(a: -1, b: 11, target: 11, winBy: 2))
        XCTAssertTrue(GameRules.validScore(a: 10, b: 11, target: 11, winBy: 1))
        XCTAssertFalse(GameRules.validScore(a: 12, b: 11, target: 11, winBy: 1))
    }
    func testInvitationOnlyAcceptsExpectedWebsiteOrExplicitAppScheme() {
        let token = String(repeating: "a", count: 64)
        XCTAssertEqual(GameRules.invitationToken(from: URL(string: "https://qg.example.com/join/#\(token)")!, expectedHost: "qg.example.com"), token)
        XCTAssertNil(GameRules.invitationToken(from: URL(string: "https://unrelated.example.com/join/#\(token)")!, expectedHost: "qg.example.com"))
        XCTAssertNil(GameRules.invitationToken(from: URL(string: "https://qg.example.com/other/#\(token)")!, expectedHost: "qg.example.com"))
        XCTAssertNil(GameRules.invitationToken(from: URL(string: "https://qg.example.com/join/#short")!, expectedHost: "qg.example.com"))
    }
    func testDecodingGuestInvitationAndOpponentPerspective() throws {
        let payload = #"""
        {"id":"game","host_name":"Cindy","place":"HUB","court":"3","starts_at":"2026-09-23T12:30:00.000+00:00","target":11,"scoring":"sideout","win_by":2,"score_a":11,"score_b":8,"revision":1,"participants":[
          {"id":"p0","slot":0,"nickname":"Cindy","display_name":"Cindy","account_id":"host","is_me":false,"claimed":true},
          {"id":"p1","slot":1,"nickname":"Anna","display_name":"Guest - Anna","is_me":false,"claimed":false},
          {"id":"p2","slot":2,"nickname":"Mike","display_name":"Mike","account_id":"opponent","is_me":true,"claimed":true},
          {"id":"p3","slot":3,"nickname":"Jo","display_name":"Guest - Jo","is_me":false,"claimed":false}],
          "claims":[],"my_claim":null,"confirmed_by_me":false,"confirmation_count":0}
        """#
        let game = try JSONDecoder().decode(Game.self, from: Data(payload.utf8))
        XCTAssertNil(game.host_id) // Anonymous invitation payloads omit this field.
        XCTAssertEqual(game.won(userID: "opponent"), false)
        XCTAssertEqual(game.won(userID: "host"), true)
        XCTAssertNil(game.won(userID: "unrelated"))
        XCTAssertNotEqual(game.startDate, .distantPast)
        let summary = Stats.from([game], userID: "opponent")
        XCTAssertEqual(summary.losses, 1)
        XCTAssertEqual(summary.loss_percent, 100)
        XCTAssertEqual(Stats.from([game], userID: "unrelated").games, 0)
    }
    func testMonthAndYearComparisonsUseAdjacentCalendarPeriods() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let f = ISO8601DateFormatter()
        let febNow = f.date(from: "2025-02-27T15:00:00Z")!
        let feb = try XCTUnwrap(PlayerPeriod.thisMonth.windows(customFrom: febNow, through: febNow, now: febNow, calendar: calendar))
        XCTAssertEqual(f.string(from: feb.current.start), "2025-02-01T00:00:00Z")
        XCTAssertEqual(f.string(from: feb.current.end), "2025-02-28T00:00:00Z")
        XCTAssertEqual(f.string(from: feb.previous.start), "2025-01-01T00:00:00Z")
        XCTAssertEqual(f.string(from: feb.previous.end), "2025-01-28T00:00:00Z")
        let today = f.date(from: "2026-09-23T12:00:00Z")!
        let year = try XCTUnwrap(PlayerPeriod.thisYear.windows(customFrom: today, through: today, now: today, calendar: calendar))
        XCTAssertEqual(f.string(from: year.current.end), "2026-09-24T00:00:00Z")
        XCTAssertEqual(f.string(from: year.previous.end), "2025-09-24T00:00:00Z")
        let custom = try XCTUnwrap(PlayerPeriod.custom.windows(customFrom: f.date(from: "2026-09-01T20:00:00Z")!, through: f.date(from: "2026-09-03T01:00:00Z")!, calendar: calendar))
        XCTAssertEqual(f.string(from: custom.current.end), "2026-09-04T00:00:00Z")
        XCTAssertEqual(f.string(from: custom.previous.start), "2026-08-29T00:00:00Z")
    }
}
