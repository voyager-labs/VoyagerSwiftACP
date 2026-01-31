import ComposableArchitecture
import Foundation

@Reducer
struct UpdaterFeature {
    @Dependency(\.updaterClient)
    var updaterClient

    typealias State = UpdaterState
    typealias Action = UpdaterAction

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .configureAtLaunch:
                if state.didConfigure {
                    return .none
                }
                state.didConfigure = true
                return .run { _ in
                    await updaterClient.configure()
                }
            case .startAtLaunch:
                if state.didStartAtLaunch {
                    return .none
                }
                state.didStartAtLaunch = true
                return .run { _ in
                    await updaterClient.startAtLaunch()
                }
            case .checkForUpdates:
                return .run { _ in
                    await updaterClient.checkForUpdates()
                }
            case let .setAutomaticUpdate(enabled):
                return .run { _ in
                    await updaterClient.setAutomaticUpdate(enabled)
                }
            }
        }
    }
}
