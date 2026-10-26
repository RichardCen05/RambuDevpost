import ActivityKit
import Foundation

/// Parent phone only. The backend starts and updates the call's Live Activity by push, so this service
/// just hands it the two tokens ActivityKit gives us: the push-to-start token, and each activity's update token.
@MainActor
final class LiveActivityService {
    static let shared = LiveActivityService()

    private var started = false
    private var observed: Set<String> = []
    private var tasks: [Task<Void, Never>] = []

    func start(model: AppModel) {
        guard !started else { return }
        started = true

        tasks.append(Task { [weak model] in
            for await data in Activity<RambuCallAttributes>.pushToStartTokenUpdates {
                await model?.registerPush(liveActivityStartToken: data.hexString)
            }
        })

        tasks.append(Task { [weak self, weak model] in
            for await activity in Activity<RambuCallAttributes>.activityUpdates {
                guard let model else { return }
                self?.observe(activity, model: model)
            }
        })

        for activity in Activity<RambuCallAttributes>.activities {
            observe(activity, model: model)
        }
    }

    private func observe(_ activity: Activity<RambuCallAttributes>, model: AppModel) {
        guard observed.insert(activity.id).inserted else { return }
        tasks.append(Task { [weak model] in
            for await data in activity.pushTokenUpdates {
                await model?.registerPush(liveActivityUpdateToken: data.hexString)
            }
        })
    }
}
