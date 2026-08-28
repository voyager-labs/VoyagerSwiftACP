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
            case .launchReady:
                let shouldConfigure = !state.didConfigure
                let shouldStartAtLaunch = !state.didStartAtLaunch
                if shouldConfigure {
                    state.didConfigure = true
                }
                if shouldStartAtLaunch {
                    state.didStartAtLaunch = true
                }
                return .run { _ in
                    if shouldConfigure {
                        await updaterClient.configure()
                        let enabled = userDefaultsClient.object(SettingsKeys.automaticUpdate) as? Bool ?? false
                        await updaterClient.setAutomaticUpdate(enabled)
                    }
                    if shouldStartAtLaunch {
                        await updaterClient.startAtLaunch()
                    }
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
