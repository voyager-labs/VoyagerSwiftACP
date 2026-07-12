import ComposableArchitecture
import Foundation

public enum AccountSessionRestoration: Equatable, Sendable {
    case available(sessionExpiresAt: Date?)
    case missing
}

@CasePathable
public enum AccountAccessAction: CasePathable, Sendable {
    case onAppear
    case retryTapped
    case loginTapped
    case cancelSignIn
    case signInHandoffCompleted(SignInHandoffResult)
    case loginCallbackReceived(URL)
    case _handoffCallbackTimedOut(state: String)
    case _handoffClaimCompleted(ticket: String, state: String, context: AppHandoffContext, claimed: Bool)
    case _handoffExchangeCompleted(state: String, result: Result<Date?, AppHandoffExchangeError>)
    case _onAppearSessionRestored(AccountSessionRestoration)
    case _loginSessionRestored(AccountSessionRestoration)
    case sessionSyncRequested(intent: SessionSyncIntent, reason: SyncReason)
    case _sessionSyncCompleted(
        generation: UInt64,
        result: Result<SessionSyncResult, SessionSyncError>,
    )
    case accessStatusResponse(generation: Int, result: Result<AccessStatusResponse, AccessError>)
    case deviceBindingResponse(
        generation: Int,
        snapshot: AccessStatusSnapshot,
        result: Result<DeviceBindingResponse, DeviceBindingError>,
    )
    case refreshAccessTapped
    case appDidBecomeActive
    case revalidatePersistedSession(generation: Int)
    case _persistedSessionRevalidated(
        generation: Int,
        result: PersistedSessionRevalidationResult,
    )
    case openCheckoutTapped
    case openPricingTapped
    case openAccountTapped
    case openAccessHelpTapped
    case openBetaCodeHelpTapped
    case _webURLResult(Result<Void, AccessError>)
    case _refreshDeadlineReached(generation: UInt64)
    case _sessionExpiredDetected
    case _fetchRetryScheduled(Int)
    case _cachedSnapshotRestored(AccessStatusSnapshot?)
    case hydrateLaunchSnapshot(AccessStatusSnapshot)
    case hydrateAccessFailure(error: AccessError, sessionExpiresAt: Date?)
    case signOut
    case appWillTerminate
    case delegate(Delegate)

    @CasePathable
    public enum Recovery: Equatable, Sendable {
        case sessionRequired
        case snapshot(AccessStatusSnapshot)
        case accessFailure(error: AccessError, sessionExpiresAt: Date?)
        case deviceBindingFailure(snapshot: AccessStatusSnapshot, error: DeviceBindingError)
    }

    public enum PersistedSessionRevalidationResult: Equatable, Sendable {
        case valid(sessionExpiresAt: Date)
        case missing
        case storageUnavailable
    }

    @CasePathable
    public enum Delegate: CasePathable, Sendable {
        case unlocked(AccessStatusSnapshot)
        case recoveryRequired(Recovery)
        case signedOut
    }
}
