import XCTest
@testable import Rambu

final class LangTests: XCTestCase {
    func testPicksCopyForLanguage() {
        XCTAssertEqual(Lang.en.t("Continue", "Lanjut"), "Continue")
        XCTAssertEqual(Lang.id.t("Continue", "Lanjut"), "Lanjut")
    }

    func testSettingsRoundTrip() throws {
        var settings = AppSettings()
        settings.role = .caregiver
        settings.name = "Dimas"
        settings.language = .id
        let data = try JSONEncoder().encode(settings)
        XCTAssertEqual(try JSONDecoder().decode(AppSettings.self, from: data), settings)
    }

    func testFamilyDecodesBackendJSON() throws {
        let json = """
        {"familyId":"f","me":{"id":"a","role":"parent","status":"active","name":"Ratna","relationship":null,"language":"en"},
         "members":[{"id":"a","role":"parent","status":"active","name":"Ratna","relationship":null,"language":"en"},
                    {"id":"b","role":"caregiver","status":"pending","name":"Dimas","relationship":"child","language":"en"}],
         "invite":{"code":"482913","expiresAt":"2026-10-26T10:41:07Z"},"puck":null}
        """
        let family = try APIClient.decoder.decode(Family.self, from: Data(json.utf8))
        XCTAssertEqual(family.pending.map(\.name), ["Dimas"])
        XCTAssertEqual(family.pending.first?.relation, .child)
        XCTAssertTrue(family.caregivers.isEmpty)
    }
}
