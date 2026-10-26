import XCTest
@testable import Rambu

final class AlertTests: XCTestCase {
    private func alert(decision: String = "null", callEnded: Bool = false, raisedAt: String = "2026-10-26T12:00:05Z") throws -> FamilyAlert {
        let json = """
        {"id":"a1","sessionId":"s1","parentName":"Ratna","level":"high_risk","signals":["impersonation","secret_code"],
         "evidence":[{"quote":"This is your bank calling.","signals":["impersonation"]},
                     {"quote":"Read it to me now, before the money leaves.","signals":["secret_code","urgency"]},
                     {"quote":"Hurry up.","signals":["urgency"]}],
         "raisedAt":"\(raisedAt)","callEnded":\(callEnded),"decision":\(decision),
         "recipients":[{"id":"d2","name":"Dimas"}]}
        """
        return try APIClient.decoder.decode(FamilyAlert.self, from: Data(json.utf8))
    }

    func testStrongestEvidencePrefersSecretCode() throws {
        let alert = try alert()
        XCTAssertEqual(alert.strongestEvidence?.quote, "Read it to me now, before the money leaves.")
        XCTAssertEqual(alert.latestSignal, .secretCode)
        XCTAssertEqual(alert.caregiverTitle(.en), "Ratna may be getting scammed")
    }

    func testVerdictCopy() throws {
        let scam = try alert(decision: #"{"verdict":"scam","byId":"d2","byName":"Dimas","at":"2026-10-26T12:00:20Z"}"#)
        XCTAssertEqual(scam.verdictSentence(.en), "Dimas says this is a scam. Hang up and call the number on the back of your card.")
        XCTAssertEqual(scam.decisionLine(.en), "Marked as scam by Dimas")
        let safe = try alert(decision: #"{"verdict":"safe","byId":"d2","byName":"Dimas","at":"2026-10-26T12:00:20Z"}"#)
        XCTAssertEqual(safe.verdictSentence(.en), "Dimas checked: this looks safe.")
    }

    func testAnnouncementSpeaksLiveWarningOnceAndSkipsOldOnes() throws {
        let live = try alert()
        let now = ISO8601DateFormatter().date(from: "2026-10-26T12:00:10Z")!
        let warning = SpeechService.announcement(for: live, lang: .en, now: now)
        XCTAssertEqual(warning?.key, "warning-a1-high_risk")
        XCTAssertEqual(warning?.text, "Danger. The caller is asking for a secret code.")

        let old = try alert(callEnded: true)
        XCTAssertNil(SpeechService.announcement(for: old, lang: .en, now: now.addingTimeInterval(3600)))

        let decided = try alert(decision: #"{"verdict":"scam","byId":"d2","byName":"Dimas","at":"2026-10-26T12:00:20Z"}"#)
        XCTAssertEqual(SpeechService.announcement(for: decided, lang: .en, now: now)?.key, "verdict-a1")
    }

    func testParsesRambuPushPayload() {
        let push = RambuPush(userInfo: ["rambu": ["kind": "verdict", "alertId": "a1", "level": "high_risk", "verdict": "scam"]])
        XCTAssertEqual(push?.kind, .verdict)
        XCTAssertEqual(push?.alertId, "a1")
        XCTAssertEqual(push?.level, .highRisk)
        XCTAssertNil(RambuPush(userInfo: ["aps": ["alert": "hi"]]))
    }

    func testHexToken() {
        XCTAssertEqual(Data([0x00, 0xAB, 0x0F]).hexString, "00ab0f")
    }
}
