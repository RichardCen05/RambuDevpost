import XCTest
@testable import Rambu

final class CallFormatTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Jakarta")!
        return calendar
    }()

    private func date(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso)!
    }

    func testTodayAndYesterday() {
        let now = date("2026-10-26T12:00:00Z")  // 19:00 in Jakarta
        let today = date("2026-10-26T07:03:00Z")  // 14:03
        let yesterday = date("2026-10-25T07:03:00Z")
        XCTAssertEqual(CallFormat.when(today, lang: .en, now: now, calendar: calendar), "Today, 14:03")
        XCTAssertEqual(CallFormat.when(today, lang: .id, now: now, calendar: calendar), "Hari ini, 14:03")
        XCTAssertEqual(CallFormat.when(yesterday, lang: .en, now: now, calendar: calendar), "Yesterday, 14:03")
        XCTAssertEqual(CallFormat.when(yesterday, lang: .id, now: now, calendar: calendar), "Kemarin, 14:03")
    }

    func testOlderDateShowsDayAndMonth() {
        let now = date("2026-10-26T12:00:00Z")
        let older = date("2026-10-20T02:30:00Z")  // 09:30 in Jakarta
        XCTAssertEqual(CallFormat.when(older, lang: .en, now: now, calendar: calendar), "20 Oct, 09:30")
        XCTAssertEqual(CallFormat.when(older, lang: .id, now: now, calendar: calendar), "20 Okt, 09:30")
    }

    func testDuration() {
        XCTAssertEqual(CallFormat.duration(62, lang: .en), "1 min 2 sec")
        XCTAssertEqual(CallFormat.duration(62, lang: .id), "1 mnt 2 dtk")
        XCTAssertEqual(CallFormat.duration(45, lang: .en), "45 sec")
        XCTAssertEqual(CallFormat.duration(120, lang: .en), "2 min")
        XCTAssertEqual(CallFormat.duration(nil, lang: .en), "")
    }

    func testCallRecordDecodesAndReadsAsCouldNotAssess() throws {
        let json = """
        {"id":"s1","startedAt":"2026-10-26T12:00:00Z","endedAt":null,"durationSeconds":null,"status":"failed",
         "level":"low","signals":[],"evidence":[],"decision":null,"failureReason":"server","transcript":null}
        """
        let record = try APIClient.decoder.decode(CallRecord.self, from: Data(json.utf8))
        XCTAssertTrue(record.couldNotAssess)
        XCTAssertEqual(record.mascot, "mascot-rest")
        XCTAssertEqual(record.title(.en), "Call not checked")
    }
}
