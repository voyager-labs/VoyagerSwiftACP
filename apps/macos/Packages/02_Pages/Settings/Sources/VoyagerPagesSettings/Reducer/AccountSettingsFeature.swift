import ComposableArchitecture
import Foundation
import VoyagerFeaturesAccountAccess

@Reducer
public struct AccountSettingsFeature {
    public typealias State = AccountSettingsState
    public typealias Action = AccountSettingsAction

    @Dependency(\.checkoutURLClient)
    var checkoutURLClient

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
            case .retryTapped:
                return .send(.delegate(.retryRequested))
            case .manageAccountTapped:
                return .run { [checkoutURLClient] _ in
                    guard let url = try? checkoutURLClient.accountURL() else { return }
                    checkoutURLClient.openURL(url)
                }
            }
        }
    }
}
