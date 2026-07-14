import ComposableArchitecture
import Foundation
import VoyagerEntitiesAppPreferences
import VoyagerShared

@Reducer
public struct UpdaterFeature: Sendable {
    public typealias State = UpdaterState
    public typealias Action = UpdaterAction

    @Dependency(\.updaterClient)
    var updaterClient
    @Dependency(\.userDefaultsClient)
    var userDefaultsClient

    public init() {}

    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .configureAtLaunch:
                if state.didConfigure {
                    return .none
                }
                state.didConfigure = true
                return .run { _ in
                    await updaterClient.configure()
                    let enabled = await userDefaultsClient.object(SettingsKeys.automaticUpdate) as? Bool ?? false
                    await updaterClient.setAutomaticUpdate(enabled)
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
