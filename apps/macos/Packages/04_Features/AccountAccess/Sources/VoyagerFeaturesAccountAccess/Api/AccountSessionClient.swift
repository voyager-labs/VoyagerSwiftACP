import ComposableArchitecture
import Foundation

// MARK: - Client Struct

public struct AccountSessionClient: Sendable {
    public var read: @Sendable (_ now: Date) async throws -> AccountSession?
    public var persist: @Sendable (_ session: AccountSession) async throws -> Void
    public var prepareHandoffPersistence: @Sendable (_ session: AccountSession) async throws -> AccountSession
    public var commitHandoffPersistence: @Sendable (_ expectedSession: AccountSession) async throws -> Void
    public var delete: @Sendable (_ reason: AccountSessionEndReason) async throws -> Void
    public var discardPersistedSession: @Sendable (_ expectedSession: AccountSession) async throws -> Void

    /// .accountSessionDidEnd notification userInfo key for the end reason.
    public static let sessionEndReasonUserInfoKey = "accountSessionEndReason"

    nonisolated public init(
        read: @escaping @Sendable (Date) async throws -> AccountSession?,
        persist: @escaping @Sendable (AccountSession) async throws -> Void,
        delete: @escaping @Sendable (_ reason: AccountSessionEndReason) async throws -> Void,
    ) {
        self.init(
            read: read,
            persist: persist,
            prepareHandoffPersistence: { session in
                try await persist(session)
                guard let persistedSession = try await read(Date()) else {
                    throw AccountSessionPersistenceError.verificationFailed
                }
                return persistedSession
            },
            commitHandoffPersistence: { _ in },
            delete: delete,
            discardPersistedSession: { _ in
                throw AccountSessionPersistenceError.discardUnavailable
            },
        )
    }

    nonisolated public init(
        read: @escaping @Sendable (Date) async throws -> AccountSession?,
        persist: @escaping @Sendable (AccountSession) async throws -> Void,
        delete: @escaping @Sendable (_ reason: AccountSessionEndReason) async throws -> Void,
        discardPersistedSession: @escaping @Sendable (_ expectedSession: AccountSession) async throws -> Void,
    ) {
        self.init(
            read: read,
            persist: persist,
            prepareHandoffPersistence: { session in
                try await persist(session)
                guard let persistedSession = try await read(Date()) else {
                    throw AccountSessionPersistenceError.verificationFailed
                }
                return persistedSession
            },
            commitHandoffPersistence: { _ in },
            delete: delete,
            discardPersistedSession: discardPersistedSession,
        )
    }

    nonisolated public init(
        read: @escaping @Sendable (Date) async throws -> AccountSession?,
        persist: @escaping @Sendable (AccountSession) async throws -> Void,
        prepareHandoffPersistence: @escaping @Sendable (AccountSession) async throws -> AccountSession,
        commitHandoffPersistence: @escaping @Sendable (AccountSession) async throws -> Void,
        delete: @escaping @Sendable (_ reason: AccountSessionEndReason) async throws -> Void,
        discardPersistedSession: @escaping @Sendable (_ expectedSession: AccountSession) async throws -> Void,
    ) {
        self.read = read
        self.persist = persist
        self.prepareHandoffPersistence = prepareHandoffPersistence
        self.commitHandoffPersistence = commitHandoffPersistence
        self.delete = delete
        self.discardPersistedSession = discardPersistedSession
    }
}

enum AccountSessionPersistenceError: Error, Equatable {
    case missingRefreshToken
    case discardUnavailable
    case verificationFailed
}

// MARK: - Live Factory

extension AccountSessionClient {
    static func live(store: AccountTokenFileStore) -> Self {
        let discardPersistedSession: @Sendable (AccountSession) async throws -> Void = { session in
            try await store.discard(expectedSession: session)
        }
        return AccountSessionClient(
            read: { now in
                let file = try await store.read()
                guard let file else { return nil }
                let expiresAt = Date(
                    timeIntervalSince1970: TimeInterval(file.accessTokenExpiresAtMs) / 1000,
                )
                guard var session = AccountTokenSessionMapper.tokensFileToSession(file) else { return nil }
                if expiresAt > now { return session }
                guard !file.refreshToken.isEmpty,
                      file.refreshTokenExpiresAtMs > Int64(now.timeIntervalSince1970 * 1000)
                else { return nil }
                session.status = .none
                return session
            },
            persist: { session in
                guard let tokensFile = AccountTokenSessionMapper.sessionToTokensFile(session, now: Date()) else {
                    throw AccountSessionPersistenceError.missingRefreshToken
                }
                try await store.write(tokensFile)
            },
            prepareHandoffPersistence: { session in
                guard let tokensFile = AccountTokenSessionMapper.sessionToTokensFile(session, now: Date()) else {
                    throw AccountSessionPersistenceError.missingRefreshToken
                }
                let preparedFile = try await store.prepareHandoffWrite(tokensFile)
                guard let preparedSession = AccountTokenSessionMapper.tokensFileToSession(preparedFile) else {
                    throw AccountSessionPersistenceError.verificationFailed
                }
                return preparedSession
            },
            commitHandoffPersistence: { session in
                try await store.commitHandoffWrite(expectedSession: session)
            },
            delete: { reason in
                try await store.delete()
                NotificationCenter.default.post(
                    name: .accountSessionDidEnd,
                    object: nil,
                    userInfo: [
                        AccountSessionClient.sessionEndReasonUserInfoKey: reason.rawValue,
                    ],
                )
            },
            discardPersistedSession: discardPersistedSession,
        )
    }
}

// MARK: - DependencyKey

extension AccountSessionClient: DependencyKey {
    nonisolated public static var liveValue: AccountSessionClient {
        .live(store: AccountTokenFileStore.withDefaultHome())
    }

    nonisolated public static var testValue: AccountSessionClient {
        AccountSessionClient(
            read: { _ in nil },
            persist: { _ in },
            delete: { _ in },
        )
    }

    nonisolated public static var previewValue: AccountSessionClient {
        testValue
    }
}

// MARK: - Notification

public extension Notification.Name {
    static let accountSessionDidEnd = Notification.Name("accountSessionDidEnd")
}

// MARK: - Dependency Values

public extension DependencyValues {
    nonisolated var accountSessionClient: AccountSessionClient {
        get { self[AccountSessionClient.self] }
        set { self[AccountSessionClient.self] = newValue }
    }
}
