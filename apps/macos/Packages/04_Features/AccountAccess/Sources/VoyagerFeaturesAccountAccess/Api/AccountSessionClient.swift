import ComposableArchitecture
import Foundation

// MARK: - Client Struct

public struct AccountSessionClient: Sendable {
    public var read: @Sendable () async throws -> AccountSession?
    public var persist: @Sendable (_ session: AccountSession) async throws -> Void
    public var delete: @Sendable () async throws -> Void

    nonisolated public init(
        read: @escaping @Sendable () async throws -> AccountSession?,
        persist: @escaping @Sendable (AccountSession) async throws -> Void,
        delete: @escaping @Sendable () async throws -> Void,
    ) {
        self.read = read
        self.persist = persist
        self.delete = delete
    }
}

// MARK: - Live Factory

extension AccountSessionClient {
    static func live(store: AccountTokenFileStore) -> Self {
        AccountSessionClient(
            read: {
                let file = try await store.read()
                guard let file else { return nil }
                let expiresAt = Date(
                    timeIntervalSince1970: TimeInterval(file.accessTokenExpiresAtMs) / 1000,
                )
                if expiresAt <= Date() { return nil }
                return AccountTokenSessionMapper.tokensFileToSession(file)
            },
            persist: { session in
                if let tokensFile = AccountTokenSessionMapper.sessionToTokensFile(session) {
                    try await store.write(tokensFile)
                }
            },
            delete: {
                try await store.delete()
            },
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
            read: { nil },
            persist: { _ in },
            delete: {},
        )
    }

    nonisolated public static var previewValue: AccountSessionClient {
        testValue
    }
}

// MARK: - Dependency Values

public extension DependencyValues {
    nonisolated var accountSessionClient: AccountSessionClient {
        get { self[AccountSessionClient.self] }
        set { self[AccountSessionClient.self] = newValue }
    }
}
