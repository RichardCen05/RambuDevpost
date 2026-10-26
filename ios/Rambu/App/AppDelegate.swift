import UIKit
import UserNotifications

/// Receives the APNs device token and wires up notification handling before the first scene appears,
/// so a tap that launched the app is not missed.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = PushService.shared
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let hex = deviceToken.hexString
        Task { @MainActor in PushService.shared.didReceive(apnsToken: hex) }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // Simulator or missing entitlement: the app still works by polling.
        print("Rambu: remote notifications unavailable: \(error.localizedDescription)")
    }
}

extension Data {
    /// APNs and ActivityKit tokens are sent to the backend as lowercase hex.
    var hexString: String { map { String(format: "%02x", $0) }.joined() }
}
