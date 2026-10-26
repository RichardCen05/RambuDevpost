import UIKit
import UserNotifications

/// The custom `rambu` key the backend puts in every alert push.
struct RambuPush: Equatable, Sendable {
    enum Kind: String, Sendable { case warning, verdict, locked, ended }

    let kind: Kind?
    let alertId: String?
    let level: Risk?
    let verdict: String?

    init?(userInfo: [AnyHashable: Any]) {
        guard let payload = userInfo["rambu"] as? [String: Any] else { return nil }
        kind = (payload["kind"] as? String).flatMap(Kind.init(rawValue:))
        alertId = payload["alertId"] as? String
        level = (payload["level"] as? String).flatMap(Risk.init(rawValue:))
        verdict = payload["verdict"] as? String
    }
}

/// Notification permission, APNs registration, and what happens when a Rambu push arrives or is tapped.
final class PushService: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = PushService()

    @MainActor private weak var model: AppModel?
    @MainActor private var latestToken: String?
    @MainActor private var started = false

    @MainActor
    func attach(_ model: AppModel) {
        self.model = model
    }

    /// Called once the phone is onboarded and approved: asks for permission and registers with APNs.
    /// Registering again on every launch makes iOS hand the token back, which re-sends it to the backend.
    @MainActor
    func start() async {
        guard !started else { return }
        started = true
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge, .timeSensitive])) ?? false
        if !granted { print("Rambu: notifications not allowed") }
        UIApplication.shared.registerForRemoteNotifications()
    }

    @MainActor
    func didReceive(apnsToken: String) {
        latestToken = apnsToken
        guard let model else { return }
        Task { await model.registerPush(apnsToken: apnsToken) }
    }

    // MARK: UNUserNotificationCenterDelegate

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let push = RambuPush(userInfo: notification.request.content.userInfo)
        if push != nil {
            Task { @MainActor in await self.refreshAfterPush() }
        }
        completionHandler([.banner, .sound, .list])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let alertId = RambuPush(userInfo: response.notification.request.content.userInfo)?.alertId
        Task { @MainActor in
            if let alertId { self.model?.openAlertId = alertId }
            await self.refreshAfterPush()
        }
        completionHandler()
    }

    @MainActor
    private func refreshAfterPush() async {
        guard let model else { return }
        await model.refreshFamily()
        await model.refreshAlerts()
        SpeechService.shared.announceParentUpdates(model)
    }
}
