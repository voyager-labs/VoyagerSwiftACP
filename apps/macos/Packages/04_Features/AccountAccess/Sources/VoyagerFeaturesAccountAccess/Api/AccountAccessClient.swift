import ComposableArchitecture
import Foundation

public struct AccountAccessClient: Sendable {
    public var restoreSession: @Sendable () async throws -> AccountSession?
    public var fetchAccessStatus: @Sendable () async throws -> AccessStatusResponse
    public var signOut: @Sendable () async throws -> Void
    public var exchangeAppHandoff: @Sendable (_ ticket: String, _ state: String,
                                              _ context: AppHandoffContext) async throws -> AccountSession
    public var refreshToken: @Sendable () async throws -> AccountSession

    nonisolated public init(
        restoreSession: @escaping @Sendable () async throws -> AccountSession?,
        fetchAccessStatus: @escaping @Sendable () async throws -> AccessStatusResponse,
        signOut: @escaping @Sendable () async throws -> Void,
        exchangeAppHandoff: @escaping @Sendable (_ ticket: String, _ state: String,
                                                 _ context: AppHandoffContext) async throws -> AccountSession,
        refreshToken: @escaping @Sendable () async throws -> AccountSession,
    ) {
        self.restoreSession = restoreSession
        self.fetchAccessStatus = fetchAccessStatus
        self.signOut = signOut
        self.exchangeAppHandoff = exchangeAppHandoff
        self.refreshToken = refreshToken
    }

    /// 기존 3-arg 호출 사이트 호환용 convenience init.
    /// exchangeAppHandoff와 refreshToken은 notConfigured 에러를 던진다.
    nonisolated public init(
        restoreSession: @escaping @Sendable () async throws -> AccountSession?,
        fetchAccessStatus: @escaping @Sendable () async throws -> AccessStatusResponse,
        signOut: @escaping @Sendable () async throws -> Void,
    ) {
        self.restoreSession = restoreSession
        self.fetchAccessStatus = fetchAccessStatus
        self.signOut = signOut
        exchangeAppHandoff = { _, _, _ in throw AccessError.notConfigured }
        refreshToken = { throw AccessError.notConfigured }
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
            refreshToken: { throw AccessError.notConfigured },
        )
    }
}

// MARK: - DependencyKey

extension AccountAccessClient: DependencyKey {
    nonisolated public static var liveValue: AccountAccessClient {
        let store = AccountTokenFileStore.withDefaultHome()
        return AccountAccessClient(
            restoreSession: {
                let file = try await store.read()
                guard let file else { return nil }
                let expiresAt = Date(
                    timeIntervalSince1970: TimeInterval(file.accessTokenExpiresAtMs) / 1000,
                )
                if expiresAt <= Date() {
                    return nil
                }
                return AccountTokenSessionMapper.tokensFileToSession(file)
            },
            fetchAccessStatus: { throw AccessError.notConfigured },
            signOut: {
                try await store.delete()
            },
            exchangeAppHandoff: { ticket, state, context in
                // AppHandoffExchangeClient.liveValue로 교환 요청 → 성공 시 토큰 저장
                let session = try await AppHandoffExchangeClient.liveValue.exchange(ticket, state, context)
                if let tokensFile = AccountTokenSessionMapper.sessionToTokensFile(session) {
                    try await store.write(tokensFile)
                }
                return session
            },
            refreshToken: {
                let file = try await store.read()
                guard let file else { throw AccessError.notConfigured }
                guard let gatewayURLString = ProcessInfo.processInfo.environment["PUBLIC_GATEWAY_URL"],
                      !gatewayURLString.isEmpty
                else {
                    throw AccessError.networkFailure
                }
                guard let base = URL(string: gatewayURLString) else { throw AccessError.networkFailure }
                let refreshURL = base.appendingPathComponent("auth/token/refresh")
                var request = URLRequest(url: refreshURL)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                let requestBody: [String: String] = ["refresh_token": file.refreshToken]
                request.httpBody = try JSONEncoder().encode(requestBody)
                let (data, response): (Data, URLResponse)
                do {
                    (data, response) = try await URLSession.shared.data(for: request)
                } catch {
                    throw AccessError.networkFailure
                }
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw AccessError.networkFailure
                }
                guard httpResponse.statusCode == 200 else {
                    throw AccessError.networkFailure
                }
                let refreshResponse = try JSONDecoder().decode(RefreshSuccessResponse.self, from: data)
                guard refreshResponse.ok, let sessionPayload = refreshResponse.session else {
                    throw AccessError.decodingFailure
                }
                let newSession = AccountSession(
                    accessToken: sessionPayload.accessToken,
                    status: .none,
                    refreshToken: sessionPayload.refreshToken ?? file.refreshToken,
                    expiresAt: sessionPayload.expiresAt.map { Date(timeIntervalSince1970: $0) },
                )
                if let tokensFile = AccountTokenSessionMapper.sessionToTokensFile(newSession) {
                    try await store.write(tokensFile)
                }
                return newSession
            },
        )
    }

    nonisolated public static var testValue: AccountAccessClient {
        .mock
    }

    nonisolated public static var previewValue: AccountAccessClient {
        .mock
    }
}

// MARK: - Refresh Response Decoding

/// POST /auth/token/refresh 성공 응답 디코딩 구조.
/// exchange 성공 응답과 동일한 { ok, session } 스키마를 사용한다.
private struct RefreshSuccessResponse: Decodable {
    let ok: Bool
    let session: RefreshSessionPayload?
}

private struct RefreshSessionPayload: Decodable {
    let accessToken: String
    let refreshToken: String?
    let expiresAt: Double?

    private enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresAt = "expires_at"
    }
}

// MARK: - Mock Sign-In State Holder

/// Mock sign-in 세션 상태를 공유하는 sendable state holder.
/// Mock sign-in handoff 성공 시 세션이 설정되고, restoreSession에서 읽는다.
public final class MockSignInState: Sendable {
    private let lock = NSLock()
    nonisolated(unsafe) private var _session: AccountSession?

    nonisolated public init() {}

    nonisolated public var session: AccountSession? {
        lock.lock()
        defer { lock.unlock() }
        return _session
    }

    nonisolated public func setSession(_ session: AccountSession?) {
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
            refreshToken: { throw AccessError.notConfigured },
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
            refreshToken: { throw AccessError.notConfigured },
        )
    }
}

public extension DependencyValues {
    nonisolated var accountAccessClient: AccountAccessClient {
        get { self[AccountAccessClient.self] }
        set { self[AccountAccessClient.self] = newValue }
    }
}
