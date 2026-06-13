import ComposableArchitecture
import Foundation
import VoyagerPagesSettings

@ObservableState
public struct SettingsHostState: Equatable {
    public var settings: SettingsState = .init()
    public var notice: String?

    public init() {}
}

@CasePathable
public enum SettingsHostAction: CasePathable, Sendable {
    case settings(SettingsAction)
    case dismissNotice
}

@Reducer
public struct SettingsHostFeature {
    public typealias State = SettingsHostState
    public typealias Action = SettingsHostAction

    public init() {}

    public var body: some Reducer<State, Action> {
        Scope(state: \.settings, action: \.settings) {
            SettingsFeature()
        }

        Reduce { state, action in
            switch action {
            case .settings(.general(.checkForUpdates)):
                state.notice = "Updater is not available in the standalone Settings host."
                return .none

            case .settings(.general(.toggleAutomaticUpdate)):
                state.notice =
                    "Automatic update scheduling is disabled in the standalone Settings host. "
                        + "Preference is still persisted locally."
                return .none

            case .dismissNotice:
                state.notice = nil
                return .none

            case .settings:
                return .none
            }
        }
    }
}
