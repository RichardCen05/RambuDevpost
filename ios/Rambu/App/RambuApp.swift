import SwiftUI

@main
struct RambuApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(\.lang, model.lang)
                .environment(\.locale, model.lang.locale)
                .tint(Brand.teal)
                .fullScreenCover(item: alertRoute) { route in
                    AlertDetailView(alertId: route.id)
                        .environment(model)
                        .environment(\.lang, model.lang)
                        .environment(\.locale, model.lang.locale)
                        .tint(Brand.teal)
                }
                .overlay {
                    // Parent: a caregiver's scam verdict takes over the whole screen until "I hung up".
                    if model.role == .parent, let alert = model.alerts.first, alert.needsHangUp {
                        ScamTakeoverView(alert: alert)
                            .environment(model)
                            .environment(\.lang, model.lang)
                            .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: model.alerts.first?.needsHangUp)
                .onAppear { PushService.shared.attach(model) }
                .task(id: pushReady) {
                    guard pushReady else { return }
                    await PushService.shared.start()
                    if model.role == .parent { LiveActivityService.shared.start(model: model) }
                }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    Task {
                        await model.refreshFamily()
                        await model.refreshAlerts()
                    }
                }
        }
    }

    /// Push and Live Activity tokens are only useful once this phone belongs to a family.
    private var pushReady: Bool { model.settings.onboardingDone && model.isApproved }

    /// Caregivers open the alert from a notification tap or a Home card; parents just see Home.
    private var alertRoute: Binding<AlertRoute?> {
        Binding(
            get: { model.role == .caregiver ? model.openAlertId.map(AlertRoute.init) : nil },
            set: { model.openAlertId = $0?.id }
        )
    }
}

struct AlertRoute: Identifiable, Hashable {
    let id: String
}
