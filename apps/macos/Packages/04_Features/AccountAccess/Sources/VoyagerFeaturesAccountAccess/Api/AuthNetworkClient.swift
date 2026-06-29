import ComposableArchitecture
import Foundation
import VoyagerShared

/// `/auth/app-handoff/exchange`, fetchAccessStatus, `/auth/token/refresh` 등
/// auth 네트워크 호출을 담당하는 의존성 클라이언트.
/// 네트워크 요청만 수행하고, 결과 영속성은 호출한 Reducer가 담당한다.
public struct AuthNetworkClient: Sendable {
    public var exchangeHandoff: @Sendable (_ ticket: String, _ state: String, _ context: AppHandoffContext) async throws
        -> AccountSession
    public var fetchAccessStatus: @Sendable () async throws -> AccessStatusResponse
    public var refreshToken: @Sendable () async throws -> AccountSession

    public init(
        exchangeHandoff: @escaping @Sendable (
            _ ticket: String,
            _ state: String,
            _ context: AppHandoffContext,
        ) async throws
            -> AccountSession,
        fetchAccessStatus: @escaping @Sendable () async throws -> AccessStatusResponse,
        refreshToken: @escaping @Sendable () async throws -> AccountSession,
    ) {
        self.exchangeHandoff = exchangeHandoff
        self.fetchAccessStatus = fetchAccessStatus
        self.refreshToken = refreshToken
    }
}

// MARK: - Live

public extension AuthNetworkClient {
    static func live() -> Self {
        AuthNetworkClient(
            exchangeHandoff: { ticket, state, context in
                try await exchangeHandoffLive(ticket: ticket, state: state, context: context)
            },
            fetchAccessStatus: {
                try await fetchAccessStatusLive()
            },
            refreshToken: {
                try await refreshTokenLive()
            },
        )
    }

    // MARK: - Live helpers

    private static func exchangeHandoffLive(
        ticket: String,
        state: String,
        context: AppHandoffContext,
    ) async throws -> AccountSession {
        // extracted from AppHandoffExchangeClient.swift:21-67
        guard let gatewayURLString = EnvironmentLoader.stringValue(forKey: "PUBLIC_GATEWAY_URL")
        else {
            throw AppHandoffExchangeError.networkFailure
        }

        let builder = AppHandoffURLBuilder(
            webBaseURL: EnvironmentLoader.stringValue(forKey: "PUBLIC_WEB_BASE_URL") ?? "",
            gatewayURL: gatewayURLString,
        )

        guard let exchangeURL = builder.exchangeURL else {
            throw AppHandoffExchangeError.networkFailure
        }

        let requestBody: [String: String] = [
            "ticket": ticket,
            "state": state,
            "context": context.rawValue,
        ]

        var request = URLRequest(url: exchangeURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(requestBody)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw AppHandoffExchangeError.networkFailure
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppHandoffExchangeError.networkFailure
        }

        if httpResponse.statusCode == 200 {
            let exchangeResponse = try decodeExchangeSuccessResponse(data)
            guard exchangeResponse.ok else {
                throw AppHandoffExchangeError.decodingFailure
            }
            return try sessionFromExchangeResponse(exchangeResponse)
        }

        // 에러 응답은 code만 추출 (토큰/본문 전체 로깅 금지)
        let errorCode = extractErrorCode(from: data)
        return try throwMappedExchangeError(errorCode)
    }

    private static func fetchAccessStatusLive() async throws -> AccessStatusResponse {
        let store = AccountTokenFileStore.withDefaultHome()
        let file = try await store.read()
        guard let file else { throw AccessError.notConfigured }
        guard let gatewayURLString = EnvironmentLoader.stringValue(forKey: "PUBLIC_GATEWAY_URL")
        else {
            throw AccessError.networkFailure
        }
        guard let base = URL(string: gatewayURLString) else { throw AccessError.networkFailure }
        let accessStatusURL = base.appendingPathComponent("access/status")
        var request = URLRequest(url: accessStatusURL)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(file.accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw AccessError.networkFailure
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AccessError.networkFailure
        }
        if httpResponse.statusCode == 401 {
            throw AccessError.unauthorized
        }
        guard httpResponse.statusCode == 200 else {
            throw AccessError.networkFailure
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(AccessStatusResponse.self, from: data)
    }

    private static func refreshTokenLive() async throws -> AccountSession {
        // extracted from AccountAccessClient.swift:87-128 (excluding write-back)
        let store = AccountTokenFileStore.withDefaultHome()
        let file = try await store.read()
        guard let file else { throw AccessError.notConfigured }
        guard let gatewayURLString = EnvironmentLoader.stringValue(forKey: "PUBLIC_GATEWAY_URL")
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
        if httpResponse.statusCode == 401 {
            throw AccessError.unauthorized
        }
        guard httpResponse.statusCode == 200 else {
            throw AccessError.networkFailure
        }
        let refreshResponse = try JSONDecoder().decode(RefreshSuccessResponse.self, from: data)
        guard refreshResponse.ok, let sessionPayload = refreshResponse.session else {
            throw AccessError.decodingFailure
        }
        return AccountSession(
            accessToken: sessionPayload.accessToken,
            status: .none,
            refreshToken: sessionPayload.refreshToken ?? file.refreshToken,
            expiresAt: sessionPayload.expiresAt.map { Date(timeIntervalSince1970: $0) },
        )
    }
}

// MARK: - DependencyKey

extension AuthNetworkClient: DependencyKey {
    nonisolated public static var liveValue: AuthNetworkClient {
        .live()
    }

    nonisolated public static var testValue: AuthNetworkClient {
        AuthNetworkClient(
            exchangeHandoff: { _, _, _ in throw AccessError.notConfigured },
            fetchAccessStatus: { throw AccessError.notConfigured },
            refreshToken: { throw AccessError.notConfigured },
        )
    }

    nonisolated public static var previewValue: AuthNetworkClient {
        testValue
    }
}

public extension DependencyValues {
    nonisolated var authNetworkClient: AuthNetworkClient {
        get { self[AuthNetworkClient.self] }
        set { self[AuthNetworkClient.self] = newValue }
    }
}
