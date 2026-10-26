import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if model.settings.onboardingDone, let role = model.role {
                MainTabs(role: role)
            } else {
                switch model.role {
                case .parent: ParentOnboarding()
                case .caregiver: CaregiverOnboarding()
                case nil: WelcomeView()
                }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: model.role)
        .animation(.easeInOut(duration: 0.25), value: model.settings.onboardingDone)
        .task { await model.refreshFamily() }
    }
}
