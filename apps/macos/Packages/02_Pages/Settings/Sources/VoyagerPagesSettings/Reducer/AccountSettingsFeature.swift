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
        Scope(state: \.access, action: \.access) {
            AccountAccessFeature()
        }

        Reduce { state, action in
            switch action {
            case .access(.delegate(.signedOut)):
                state.isShowingSignOutConfirmation = false
                return .none

            case .access(.delegate(.unlocked)):
                return .none

            case .access:
                return .none

            case .signOutTapped:
                state.isShowingSignOutConfirmation = true
                return .none

            case .signOutConfirmed:
                state.isShowingSignOutConfirmation = false
                return .send(.access(.signOut))

            case .signOutCancelled:
                state.isShowingSignOutConfirmation = false
                return .none

            case .manageAccountTapped:
                let checkoutURLClient = checkoutURLClient
                return .run { _ in
                    guard let url = try? checkoutURLClient.accountURL() else { return }
                    checkoutURLClient.openURL(url)
                }

            case .openAccountURLCompleted:
                return .none
            }
        }
    }
}
