import ComposableArchitecture
import Foundation

public struct AccountAccessClient: Sendable {
    public var restoreSession: @Sendable () async throws -> AccountSession?
    public var fetchAccessStatus: @Sendable () async throws -> AccessStatusResponse
    public var signOut: @Sendable () async throws -> Void
    public var exchangeAppHandoff: @Sendable (_ ticket: String, _ state: String,
                                              _ context: AppHandoffContext) async throws -> AccountSession

    public nonisolated init(
        restoreSession: @escaping @Sendable () async throws -> AccountSession?,
        fetchAccessStatus: @escaping @Sendable () async throws -> AccessStatusResponse,
        signOut: @escaping @Sendable () async throws -> Void,
        exchangeAppHandoff: @escaping @Sendable (_ ticket: String, _ state: String,
                                                 _ context: AppHandoffContext) async throws -> AccountSession,
    ) {
        self.restoreSession = restoreSession
        self.fetchAccessStatus = fetchAccessStatus
        self.signOut = signOut
        self.exchangeAppHandoff = exchangeAppHandoff
    }

    /// 기존 3-arg 호출 사이트 호환용 convenience init.
    /// exchangeAppHandoff는 notConfigured 에러를 던진다.
    public nonisolated init(
        restoreSession: @escaping @Sendable () async throws -> AccountSession?,
        fetchAccessStatus: @escaping @Sendable () async throws -> AccessStatusResponse,
        signOut: @escaping @Sendable () async throws -> Void,
    ) {
        self.restoreSession = restoreSession
        self.fetchAccessStatus = fetchAccessStatus
        self.signOut = signOut
        exchangeAppHandoff = { _, _, _ in throw AccessError.notConfigured }
    }
}

// MARK: - Mock

public extension AccountAccessClient {
    nonisolated static var mock: AccountAccessClient {
        AccountAccessClient(
            restoreSession: { nil },
            fetchAccessStatus: {
                AccessStatusResponse(status: .coreLicenseActive, entitlements: [.coreLicense])
            },
            signOut: {},
            exchangeAppHandoff: { _, _, _ in throw AccessError.notConfigured },
        )
    }
}

// MARK: - DependencyKey

extension AccountAccessClient: DependencyKey {
    public nonisolated static var liveValue: AccountAccessClient {
        AccountAccessClient(
            restoreSession: { throw AccessError.notConfigured },
            fetchAccessStatus: { throw AccessError.notConfigured },
            signOut: { throw AccessError.notConfigured },
            exchangeAppHandoff: { _, _, _ in throw AccessError.notConfigured },
        )
    }

    public nonisolated static var testValue: AccountAccessClient {
        .mock
    }

    public nonisolated static var previewValue: AccountAccessClient {
        .mock
    }
}

// MARK: - Mock Sign-In State Holder

/// Mock sign-in 세션 상태를 공유하는 sendable state holder.
/// Mock sign-in handoff 성공 시 세션이 설정되고, restoreSession에서 읽는다.
public final class MockSignInState: Sendable {
    private let lock = NSLock()
    private nonisolated(unsafe) var _session: AccountSession?

    public nonisolated init() {}

    public nonisolated var session: AccountSession? {
        lock.lock()
        defer { lock.unlock() }
        return _session
    }

    public nonisolated func setSession(_ session: AccountSession?) {
        lock.lock()
        defer { lock.unlock() }
        _session = session
    }
}

public extension AccountAccessClient {
    /// 공유 MockSignInState로 backed된 mock client.
    /// restoreSession은 signInState.session을 반환한다.
    nonisolated static func mockSignInBacked(by signInState: MockSignInState) -> AccountAccessClient {
        AccountAccessClient(
            restoreSession: { signInState.session },
            fetchAccessStatus: {
                AccessStatusResponse(status: .coreLicenseActive, entitlements: [.coreLicense])
            },
            signOut: { signInState.setSession(nil) },
            exchangeAppHandoff: { _, _, _ in throw AccessError.notConfigured },
        )
    }

    nonisolated static func handoffBacked(
        sessionHolder: MockSignInState,
        exchangeClient: AppHandoffExchangeClient,
        fetchAccessStatus: @escaping @Sendable () async throws -> AccessStatusResponse = {
            throw AccessError.notConfigured
        },
    ) -> AccountAccessClient {
        AccountAccessClient(
            restoreSession: { sessionHolder.session },
            fetchAccessStatus: fetchAccessStatus,
            signOut: { sessionHolder.setSession(nil) },
            exchangeAppHandoff: { ticket, state, context in
                let session = try await exchangeClient.exchange(ticket, state, context)
                sessionHolder.setSession(session)
                return session
            },
        )
    }
}

public extension DependencyValues {
    nonisolated var accountAccessClient: AccountAccessClient {
        get { self[AccountAccessClient.self] }
        set { self[AccountAccessClient.self] = newValue }
    }
}
