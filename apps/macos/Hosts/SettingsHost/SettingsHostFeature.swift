import ComposableArchitecture
import Foundation
import VoyagerFeaturesAccountAccess
import VoyagerPagesSettings

@ObservableState
public struct SettingsHostState: Equatable {
    public var settings: SettingsState = .init()
    public var accountAccess: AccountAccessFeature.State = .init()
    public var isAccountAccessBootstrapPending = true

    public init() {}

    /// preset-derived Settings 초기 상태 주입용. Host는 child internals를 직접 건드리지 않고
    /// `SettingsState.hostPreset(for:)` 팩토리에서 만들어진 인스턴스만 받는다.
    public init(settings: SettingsState) {
        self.settings = settings
        accountAccess = Self.makeAccountAccessState(from: settings.accountSettings.presentation)
        isAccountAccessBootstrapPending = false
    }

    private static func makeAccountAccessState(
        from presentation: AccountAccessPresentation,
    ) -> AccountAccessFeature.State {
        var accountAccess = AccountAccessFeature.State()
        accountAccess.hasAccountSession = presentation.hasAccountSession
        accountAccess.isSignInInProgress = presentation.isSignInInProgress
        accountAccess.didSignInFail = presentation.didSignInFail
        return accountAccess
    }
}

@CasePathable
public enum SettingsHostAction: CasePathable, Sendable {
    case settings(SettingsAction)
    case accountAccess(AccountAccessFeature.Action)
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
        Scope(state: \.accountAccess, action: \.accountAccess) {
            AccountAccessFeature()
        }
        Reduce { state, action in
            switch action {
            case .settings(.delegate(.account(.signInRequested))):
                guard !state.accountAccess.hasAccountSession else { return .none }
                return .send(.accountAccess(.loginTapped(context: .paywall, scope: .settings)))

            case .settings(.delegate(.account(.signOutRequested))):
                return .send(.accountAccess(.signOut))

            case .settings(.onAppear):
                guard state.isAccountAccessBootstrapPending else { return .none }
                state.isAccountAccessBootstrapPending = false
                return .send(.accountAccess(.onAppear))

            case .accountAccess:
                return .send(.settings(.accountAccessPresentationUpdated(
                    makeAccountAccessPresentation(state.accountAccess),
                )))

            default:
                return .none
            }
        }
    }

    private func makeAccountAccessPresentation(
        _ accountAccess: AccountAccessFeature.State,
    ) -> AccountAccessPresentation {
        AccountAccessPresentation(
            hasAccountSession: accountAccess.hasAccountSession,
            isSignInInProgress: accountAccess.isSignInInProgress,
            didSignInFail: accountAccess.didSignInFail,
        )
    }
}
