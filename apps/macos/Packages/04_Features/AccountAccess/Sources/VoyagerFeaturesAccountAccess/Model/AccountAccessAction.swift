import ComposableArchitecture
import Foundation

@CasePathable
public enum AccountAccessAction: CasePathable, Sendable {
    case onAppear
    case retryTapped
    case loginTapped
    case signInHandoffCompleted(SignInHandoffResult)
    case loginCallbackReceived(URL)
    case _handoffExchangeCompleted(Result<AccountSession, AppHandoffExchangeError>)
    case _onAppearSessionRestored(AccountSession?)
    case _loginSessionRestored(Bool)
    case accessStatusResponse(generation: Int, result: Result<AccessStatusResponse, AccessError>)
    case refreshAccessTapped
    case appDidBecomeActive
    case openCheckoutTapped
    case openPricingTapped
    case openAccessHelpTapped
    case openBetaCodeHelpTapped
    case _ttlTimerTicked
    case _refreshTokenResult(Result<AccountSession, AccessError>)
    case _sessionExpiredDetected
    case _fetchRetryScheduled(Int)
    case _cachedSnapshotRestored(AccessStatusSnapshot?)
    case delegate(Delegate)

    @CasePathable
    public enum Delegate: CasePathable, Sendable {
        case unlocked(AccessStatusSnapshot)
    }
}
