import Network
import SwiftUI
import UIKit
import UserNotifications

/// Whether this phone has a usable internet path right now.
@MainActor
@Observable
final class NetworkStatus {
    static let shared = NetworkStatus()

    private(set) var isOnline = true
    private let monitor = NWPathMonitor()

    private init() {
        monitor.pathUpdateHandler = { path in
            let online = path.status == .satisfied
            Task { @MainActor in NetworkStatus.shared.isOnline = online }
        }
        monitor.start(queue: DispatchQueue(label: "rambu.network"))
    }
}

/// Notification permission as Profile and the banners show it.
enum NotificationAccess {
    case unknown, on, off, notAsked

    static func current() async -> NotificationAccess {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return .on
        case .denied: return .off
        case .notDetermined: return .notAsked
        @unknown default: return .unknown
        }
    }

    /// Asks the first time; after a refusal only the Settings app can turn it back on.
    static func turnOn() async -> NotificationAccess {
        if await current() == .notAsked {
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            return await current()
        }
        openAppSettings()
        return await current()
    }

    static func openAppSettings() {
        let link = URL(string: UIApplication.openNotificationSettingsURLString) ?? URL(string: UIApplication.openSettingsURLString)
        if let link { UIApplication.shared.open(link) }
    }
}

/// Yellow banners on parent Home for anything that stops protection.
struct ParentIssueBanners: View {
    @Environment(AppModel.self) private var model
    @Environment(\.lang) private var lang
    @Environment(\.scenePhase) private var scenePhase
    @State private var network = NetworkStatus.shared
    @State private var notifications: NotificationAccess = .unknown
    @State private var showServer = false

    var body: some View {
        VStack(spacing: 10) {
            if notifications == .off || notifications == .notAsked {
                Banner(
                    symbol: "bell.slash.fill",
                    title: lang.t("Notifications are off", "Notifikasi mati"),
                    detail: lang.t("You won't see warnings during a call.", "Anda tidak akan melihat peringatan saat menelepon."),
                    action: lang.t("Turn on", "Nyalakan"),
                    onAction: { Task { notifications = await NotificationAccess.turnOn() } }
                )
            }
            if !network.isOnline {
                Banner(
                    symbol: "wifi.slash",
                    title: lang.t("No internet", "Tidak ada internet"),
                    detail: lang.t("Caregivers cannot be notified yet.", "Pengawas belum bisa diberi tahu.")
                )
            } else if !model.serverReachable {
                Banner(
                    symbol: "server.rack",
                    title: lang.t("Can't reach the Rambu server", "Server Rambu tidak terjangkau"),
                    detail: lang.t("Calls can't be checked right now.", "Panggilan belum bisa diperiksa sekarang."),
                    action: lang.t("Check", "Cek"),
                    onAction: { showServer = true }
                )
            }
            if model.family?.puck?.online == false {
                Banner(
                    symbol: "circle.slash",
                    title: lang.t("Puck is offline", "Puck tidak terhubung"),
                    detail: lang.t("Calls aren't checked. Check the puck's cable and Wi-Fi.",
                                   "Panggilan tidak diperiksa. Cek kabel dan Wi-Fi puck.")
                )
            }
        }
        .task { notifications = await NotificationAccess.current() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { notifications = await NotificationAccess.current() } }
        }
        .sheet(isPresented: $showServer) { ServerSheet() }
    }
}
