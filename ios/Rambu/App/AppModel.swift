import Foundation
import Observation
import SwiftUI

/// What this phone remembers between launches (everything shared lives on the backend).
struct AppSettings: Codable, Equatable {
    var role: Role?
    var name: String = ""
    var relationship: Relationship = .child
    var language: Lang = .deviceDefault
    var serverURL: String = AppSettings.defaultServer
    var onboardingDone = false
    var readAloud = true

    static let defaultServer = "http://127.0.0.1:8001"
    private static let key = "rambu.settings"

    static func load() -> AppSettings {
        guard let data = UserDefaults.standard.data(forKey: key),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data) else { return AppSettings() }
        return settings
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: Self.key) }
    }
}

@MainActor
@Observable
final class AppModel {
    var settings: AppSettings {
        didSet { settings.save() }
    }
    private(set) var token: String?
    var family: Family?
    var alerts: [FamilyAlert] = []
    var history: [CallRecord] = []
    /// Set when a notification is tapped; the caregiver UI opens this alert.
    var openAlertId: String?
    /// False while the last request to the backend failed to connect.
    var serverReachable = true
    var errorMessage: String?

    init() {
        settings = AppSettings.load()
        token = Keychain.load()
        if ProcessInfo.processInfo.environment["RAMBU_RESET"] == "1" { resetLocal() }
        if let server = ProcessInfo.processInfo.environment["RAMBU_SERVER"] { settings.serverURL = server }
    }

    var lang: Lang { settings.language }
    var role: Role? { settings.role }
    var isLinked: Bool { token != nil }
    var isApproved: Bool { family?.me.status == "active" }

    var api: APIClient {
        APIClient(baseURL: URL(string: settings.serverURL) ?? URL(string: AppSettings.defaultServer)!, token: token)
    }

    // MARK: Setup

    func createFamily() async throws {
        let reply: CreateFamilyResponse = try await api.post(
            "/api/families", ["name": settings.name, "language": settings.language.rawValue]
        )
        store(token: reply.deviceToken)
        await refreshFamily()
    }

    func join(code: String) async throws {
        let reply: JoinResponse = try await api.post("/api/families/join", [
            "code": code,
            "name": settings.name,
            "relationship": settings.relationship.rawValue,
            "language": settings.language.rawValue,
        ])
        store(token: reply.deviceToken)
        await refreshFamily()
    }

    func renewInvite() async {
        do {
            let _: Invite = try await api.post("/api/families/invite")
            await refreshFamily()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func allow(_ member: Member) async {
        do {
            family = try await api.post("/api/family/members/\(member.id)/allow")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshFamily() async {
        guard token != nil else { return }
        do {
            family = try await api.get("/api/family")
            serverReachable = true
            errorMessage = nil
        } catch let error as APIError {
            serverReachable = !error.isUnreachable
            errorMessage = error.isUnreachable ? nil : error.detail
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Alerts and history

    func refreshAlerts() async {
        guard isApproved else { return }
        if let alerts: [FamilyAlert] = try? await api.get("/api/alerts") { self.alerts = alerts }
    }

    func refreshHistory() async {
        guard isApproved else { return }
        if let history: [CallRecord] = try? await api.get("/api/history") { self.history = history }
    }

    func callDetail(_ id: String) async -> CallRecord? {
        try? await api.get("/api/history/\(id)")
    }

    /// Caregiver verdict. The first answer in the family wins; a later one gets the existing decision back.
    func decide(_ alert: FamilyAlert, scam: Bool) async -> DecisionResult? {
        do {
            let result: DecisionResult = try await api.post("/api/alerts/\(alert.id)/decision", ["verdict": scam ? "scam" : "safe"])
            if let index = alerts.firstIndex(where: { $0.id == alert.id }) { alerts[index] = result.alert }
            return result
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    /// Parent: "I hung up" — stops the repeated alarm on the backend and closes the takeover.
    func acknowledge(_ alert: FamilyAlert) async {
        do {
            let updated: FamilyAlert = try await api.post("/api/alerts/\(alert.id)/acknowledge")
            if let index = alerts.firstIndex(where: { $0.id == alert.id }) { alerts[index] = updated }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Push

    func registerPush(apnsToken: String? = nil, liveActivityStartToken: String? = nil, liveActivityUpdateToken: String? = nil) async {
        guard token != nil else { return }
        var body = ["environment": Self.apnsEnvironment]
        if let apnsToken { body["apnsToken"] = apnsToken }
        if let liveActivityStartToken { body["liveActivityStartToken"] = liveActivityStartToken }
        if let liveActivityUpdateToken { body["liveActivityUpdateToken"] = liveActivityUpdateToken }
        try? await api.put("/api/devices/me/push", body)
    }

    /// Xcode builds use the APNs sandbox.
    static var apnsEnvironment: String {
        #if DEBUG
        "sandbox"
        #else
        "production"
        #endif
    }

    // MARK: Settings

    func setLanguage(_ lang: Lang) {
        settings.language = lang
        guard token != nil else { return }
        Task { try? await api.put("/api/devices/me", ["language": lang.rawValue]) }
    }

    func setName(_ name: String) {
        settings.name = name
        guard token != nil, !name.isEmpty else { return }
        Task { try? await api.put("/api/devices/me", ["name": name]) }
    }

    func setRelationship(_ relationship: Relationship) {
        settings.relationship = relationship
        guard token != nil else { return }
        Task { try? await api.put("/api/devices/me", ["relationship": relationship.rawValue]) }
    }

    func finishOnboarding() {
        settings.onboardingDone = true
    }

    /// Forget this phone's role and family (development and "start over").
    func resetLocal() {
        Keychain.delete()
        token = nil
        family = nil
        let server = settings.serverURL
        settings = AppSettings()
        settings.serverURL = server
    }

    private func store(token: String) {
        Keychain.save(token)
        self.token = token
    }
}
