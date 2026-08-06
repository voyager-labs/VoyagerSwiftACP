import ComposableArchitecture
import Foundation

public enum AccountSessionRestoration: Equatable, Sendable {
    case available(session: AccountSession)
    case missing
}

public struct AccountAccessHandoffClaimCompletion: Equatable, Sendable {
    public let ticket: String
    public let state: String
    public let context: AppHandoffContext
    public let scope: AccountAccessHandoffScope
    public let generation: UInt64
    public let claimed: Bool

    public init(
        ticket: String,
        state: String,
        context: AppHandoffContext,
        scope: AccountAccessHandoffScope,
        generation: UInt64,
        claimed: Bool,
    ) {
        self.ticket = ticket
        self.state = state
        self.context = context
        self.scope = scope
        self.generation = generation
        self.claimed = claimed
    }
}

public struct AccountAccessHandoffCompletion: Equatable, Sendable {
    public let expiresAt: Date?
    public let sessionBindingID: UUID

    public init(expiresAt: Date?, sessionBindingID: UUID) {
        self.expiresAt = expiresAt
        self.sessionBindingID = sessionBindingID
    }
}

public struct AccountAccessSessionSyncActivationCompletion: Equatable, Sendable {
    public let requestGeneration: UInt64
    public let binding: UUID?
    public let intent: SessionSyncIntent
    public let reason: SyncReason

    public init(
        requestGeneration: UInt64,
        binding: UUID?,
        intent: SessionSyncIntent,
        reason: SyncReason,
    ) {
        self.requestGeneration = requestGeneration
        self.binding = binding
        self.intent = intent
        self.reason = reason
    }
}

@CasePathable
public enum AccountAccessAction: CasePathable, Sendable {
    case onAppear
    case retryTapped
    case loginTapped(context: AppHandoffContext, scope: AccountAccessHandoffScope)
    case cancelSignIn
    case signInHandoffCompleted(
        SignInHandoffResult,
        transaction: AccountAccessHandoffTransaction,
        generation: UInt64,
    )
    case loginCallbackReceived(URL)
    case _handoffCallbackTimedOut(state: String)
    case _handoffClaimCompleted(AccountAccessHandoffClaimCompletion)
    case _handoffCommitAuthorized(state: String, generation: UInt64, session: AccountSession)
    case _handoffExchangeCompleted(
        state: String,
        generation: UInt64,
        result: Result<AccountAccessHandoffCompletion, AppHandoffExchangeError>,
    )
    case _handoffPersistenceRollbackFailed(generation: UInt64)
    case _onAppearSessionRestored(AccountSessionRestoration)
    case _loginSessionRestored(AccountSessionRestoration)
    case sessionSyncRequested(intent: SessionSyncIntent, reason: SyncReason)
    case _sessionSyncActivationCompleted(AccountAccessSessionSyncActivationCompletion)
    case _sessionSyncCompleted(
        generation: UInt64,
        binding: UUID? = nil,
        result: Result<SessionSyncResult, SessionSyncError>,
    )
    case appDidBecomeActive
    case revalidatePersistedSession(generation: Int, reason: SyncReason = .foreground)
    case _persistedSessionRevalidated(
        generation: Int,
        reason: SyncReason = .foreground,
        result: PersistedSessionRevalidationResult,
    )
    case _refreshDeadlineReached(generation: UInt64)
    case _sessionExpiredDetected
    case signOut
    case appWillTerminate

    public enum PersistedSessionRevalidationResult: Equatable, Sendable {
        case valid(session: AccountSession)
        case missing
        case storageUnavailable
    }
}
