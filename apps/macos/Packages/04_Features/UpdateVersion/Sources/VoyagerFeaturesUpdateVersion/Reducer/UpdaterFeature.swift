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
            case let .accessGranted(updateStatus, updatesThrough):
                let shouldConfigure = !state.didConfigure
                let shouldStartAtLaunch = !state.didStartAtLaunch
                state.isAccessEligible = true
                state.updateStatus = updateStatus
                state.updatesThrough = updatesThrough
                if shouldConfigure {
                    state.didConfigure = true
                }
                if shouldStartAtLaunch {
                    state.didStartAtLaunch = true
                }
                return .run { _ in
                    await updaterClient.setAccessEligibility(true, updateStatus, updatesThrough)
                    if shouldConfigure {
                        await updaterClient.configure()
                        let enabled = userDefaultsClient.object(SettingsKeys.automaticUpdate) as? Bool ?? false
                        await updaterClient.setAutomaticUpdate(enabled)
                    }
                    if shouldStartAtLaunch {
                        await updaterClient.startAtLaunch()
                    }
                }
            case .accessRevoked:
                guard state.isAccessEligible else { return .none }
                state.isAccessEligible = false
                state.updateStatus = nil
                state.updatesThrough = nil
                return .run { _ in
                    await updaterClient.setAccessEligibility(false, nil, nil)
                }
            case .configureAtLaunch:
                guard state.isAccessEligible, !state.didConfigure else {
                    return .none
                }
                state.didConfigure = true
                return .run { _ in
                    await updaterClient.configure()
                    let enabled = userDefaultsClient.object(SettingsKeys.automaticUpdate) as? Bool ?? false
                    await updaterClient.setAutomaticUpdate(enabled)
                }
            case .startAtLaunch:
                guard state.isAccessEligible, !state.didStartAtLaunch else {
                    return .none
                }
                state.didStartAtLaunch = true
                return .run { _ in
                    await updaterClient.startAtLaunch()
                }
            case .checkForUpdates:
                guard state.isAccessEligible else { return .none }
                return .run { _ in
                    await updaterClient.checkForUpdates()
                }
            case let .setAutomaticUpdate(enabled):
                guard state.isAccessEligible else { return .none }
                return .run { _ in
                    await updaterClient.setAutomaticUpdate(enabled)
                }
            }
        }
    }
}
