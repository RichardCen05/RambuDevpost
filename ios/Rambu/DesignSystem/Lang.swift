import SwiftUI

/// App language. Copy lives next to the view that shows it, as an English/Indonesian pair:
/// `lang.t("Continue", "Lanjut")`. Switching in Profile re-renders everything at once,
/// without restarting the app or touching the family or history.
enum Lang: String, Codable, CaseIterable, Sendable {
    case en, id

    static var deviceDefault: Lang {
        Locale.preferredLanguages.first?.hasPrefix("id") == true ? .id : .en
    }

    var name: String { self == .en ? "English" : "Bahasa Indonesia" }
    var locale: Locale { Locale(identifier: self == .en ? "en_US" : "id_ID") }

    func t(_ english: String, _ indonesian: String) -> String {
        self == .en ? english : indonesian
    }
}

private struct LangKey: EnvironmentKey {
    static let defaultValue: Lang = .en
}

extension EnvironmentValues {
    var lang: Lang {
        get { self[LangKey.self] }
        set { self[LangKey.self] = newValue }
    }
}

enum Relationship: String, Codable, CaseIterable, Sendable {
    case child, grandchild, relative

    func label(_ lang: Lang) -> String {
        switch self {
        case .child: lang.t("Child", "Anak")
        case .grandchild: lang.t("Grandchild", "Cucu")
        case .relative: lang.t("Relative", "Kerabat")
        }
    }
}

enum Signal: String, Codable, CaseIterable, Sendable {
    case impersonation, urgency, secretCode = "secret_code", transfer, remoteApp = "remote_app"

    /// Short name for caregivers.
    func title(_ lang: Lang) -> String {
        switch self {
        case .impersonation: lang.t("Claims to be an institution", "Mengaku dari lembaga")
        case .urgency: lang.t("Pressure to act now", "Desakan waktu")
        case .secretCode: lang.t("Asks for an OTP or PIN", "Meminta kode OTP atau PIN")
        case .transfer: lang.t("Asks for a money transfer", "Meminta transfer uang")
        case .remoteApp: lang.t("Asks to install an app", "Menyuruh pasang aplikasi")
        }
    }

    /// Plain sentence for the parent while the call is still going.
    func headline(_ lang: Lang) -> String {
        switch self {
        case .impersonation: lang.t("The caller claims to be an institution", "Penelepon mengaku dari lembaga")
        case .urgency: lang.t("The caller is pressuring you", "Penelepon mendesak Anda")
        case .secretCode: lang.t("The caller is asking for a secret code", "Penelepon meminta kode rahasia")
        case .transfer: lang.t("The caller is asking for a transfer", "Penelepon meminta transfer")
        case .remoteApp: lang.t("The caller wants you to install an app", "Penelepon menyuruh pasang aplikasi")
        }
    }

    var symbol: String {
        switch self {
        case .impersonation: "building.columns.fill"
        case .urgency: "timer"
        case .secretCode: "key.fill"
        case .transfer: "banknote.fill"
        case .remoteApp: "arrow.down.app.fill"
        }
    }
}

extension Risk {
    func label(_ lang: Lang) -> String {
        switch self {
        case .low: lang.t("Safe", "Aman")
        case .needsReview: lang.t("Worth a look", "Perlu dicek")
        case .highRisk: lang.t("Danger", "Bahaya")
        }
    }

    var symbol: String {
        switch self {
        case .low: "checkmark.circle.fill"
        case .needsReview: "exclamationmark.triangle.fill"
        case .highRisk: "exclamationmark.octagon.fill"
        }
    }
}
