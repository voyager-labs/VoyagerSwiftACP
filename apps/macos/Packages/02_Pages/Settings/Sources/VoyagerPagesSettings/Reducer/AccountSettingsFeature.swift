import ComposableArchitecture
import Foundation
import VoyagerFeaturesAccountAccess

@Reducer
public struct AccountSettingsFeature {
    public typealias State = AccountSettingsState
    public typealias Action = AccountSettingsAction

    public init() {}

    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .delegate:
                return .none
            case .signInTapped:
                guard !state.presentation.hasAccountSession else { return .none }
                return .send(.delegate(.signInRequested))
            case .signOutTapped:
                state.isShowingSignOutConfirmation = true
                return .none
            case .signOutConfirmed:
                state.isShowingSignOutConfirmation = false
                return .send(.delegate(.signOutRequested))
            case .signOutCancelled:
                state.isShowingSignOutConfirmation = false
                return .none
            }
        }
    }
}
