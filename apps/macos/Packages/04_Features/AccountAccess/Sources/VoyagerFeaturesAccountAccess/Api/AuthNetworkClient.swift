import ComposableArchitecture
import Foundation
import VoyagerShared

/// `/auth/app-handoff/exchange`, fetchAccessStatus, `/auth/token/refresh` 등
/// auth 네트워크 호출을 담당하는 의존성 클라이언트.
/// sync session은 credential 저장소 경계를 포함하고, reducer에는 민감하지 않은 typed result만 전달한다.
public struct AuthNetworkClient: Sendable {
    public var exchangeHandoff: @Sendable (_ ticket: String, _ state: String, _ context: AppHandoffContext) async throws
        -> AccountSession
    public var fetchAccessStatus: @Sendable () async throws -> AccessStatusResponse
    public var bindDevice: @Sendable (_ request: DeviceBindingRequest) async throws -> DeviceBindingResponse
    public var refreshToken: @Sendable () async throws -> AccountSession
    private var syncSessionOperation: @Sendable (
        _ intent: SessionSyncIntent,
        _ device: DeviceBindingRequest,
        _ requestID: String,
    ) async throws
        -> SessionSyncResult

    public init(
        exchangeHandoff: @escaping @Sendable (
            _ ticket: String,
            _ state: String,
            _ context: AppHandoffContext,
        ) async throws
            -> AccountSession,
        fetchAccessStatus: @escaping @Sendable () async throws -> AccessStatusResponse,
        bindDevice: @escaping @Sendable (_ request: DeviceBindingRequest) async throws -> DeviceBindingResponse = { _ in
            throw DeviceBindingError.notConfigured
        },
        refreshToken: @escaping @Sendable () async throws -> AccountSession,
        syncSession: @escaping @Sendable (_ intent: SessionSyncIntent, _ device: DeviceBindingRequest) async throws
            -> SessionSyncResult = { _, _ in throw SessionSyncError.capabilityMiss },
        syncSessionWithRequestID: (@Sendable (
            _ intent: SessionSyncIntent,
            _ device: DeviceBindingRequest,
            _ requestID: String,
        ) async throws -> SessionSyncResult)? = nil,
    ) {
        self.exchangeHandoff = exchangeHandoff
        self.fetchAccessStatus = fetchAccessStatus
        self.bindDevice = bindDevice
        self.refreshToken = refreshToken
        if let syncSessionWithRequestID {
            syncSessionOperation = syncSessionWithRequestID
        } else {
            syncSessionOperation = { intent, device, _ in
                try await syncSession(intent, device)
            }
        }
    }

    public func syncSession(
        intent: SessionSyncIntent,
        device: DeviceBindingRequest,
    ) async throws -> SessionSyncResult {
        try await syncSession(intent: intent, device: device, requestID: UUID().uuidString)
    }

    public func syncSession(
        intent: SessionSyncIntent,
        device: DeviceBindingRequest,
        requestID: String,
    ) async throws -> SessionSyncResult {
        try await syncSessionOperation(intent, device, requestID)
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
            bindDevice: { request in
                try await bindDeviceLive(request)
            },
            refreshToken: {
                let store = AccountTokenFileStore.withDefaultHome()
                let refreshed = try await refreshTokenLive(store: store)
                return refreshed.session
            },
            syncSessionWithRequestID: { intent, device, requestID in
                try await syncSessionLive(intent: intent, device: device, requestID: requestID)
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
            if isCancellationError(error) { throw CancellationError() }
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

    private static func bindDeviceLive(_ bindingRequest: DeviceBindingRequest) async throws -> DeviceBindingResponse {
        let store = AccountTokenFileStore.withDefaultHome()
        let file = try await store.read()
        guard let file else { throw DeviceBindingError.notConfigured }
        guard let gatewayURLString = EnvironmentLoader.stringValue(forKey: "PUBLIC_GATEWAY_URL")
        else {
            throw DeviceBindingError.networkFailure
        }
        guard let base = URL(string: gatewayURLString) else { throw DeviceBindingError.networkFailure }
        let bindingURL = base.appendingPathComponent("access/device-bindings")
        var request = URLRequest(url: bindingURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(file.accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(bindingRequest)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            if isCancellationError(error) { throw CancellationError() }
            throw DeviceBindingError.networkFailure
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DeviceBindingError.networkFailure
        }
        if (200 ..< 300).contains(httpResponse.statusCode) {
            let bindingResponse: DeviceBindingResponse
            do {
                bindingResponse = try JSONDecoder().decode(DeviceBindingResponse.self, from: data)
            } catch {
                throw DeviceBindingError.decodingFailure
            }
            guard bindingResponse.ok else { throw DeviceBindingError.decodingFailure }
            return bindingResponse
        }

        let errorCode = extractErrorCode(from: data)
        throw mappedDeviceBindingError(statusCode: httpResponse.statusCode, code: errorCode)
    }

    private static func refreshTokenLive(
        store: AccountTokenFileStore,
    ) async throws -> (session: AccountSession, source: AccountTokensFile) {
        // extracted from AccountAccessClient.swift:87-128 (excluding write-back)
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
            if isCancellationError(error) { throw CancellationError() }
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
        return (
            session: AccountSession(
                accessToken: sessionPayload.accessToken,
                status: .none,
                refreshToken: sessionPayload.refreshToken ?? file.refreshToken,
                expiresAt: sessionPayload.expiresAt.map { Date(timeIntervalSince1970: $0) },
            ),
            source: file,
        )
    }

    private static func syncSessionLive(
        intent: SessionSyncIntent,
        device: DeviceBindingRequest,
        requestID: String,
    ) async throws -> SessionSyncResult {
        let store = AccountTokenFileStore.withDefaultHome()
        let file: AccountTokensFile
        do {
            guard let storedFile = try await store.read() else { throw SessionSyncError.storageFailure }
            file = storedFile
        } catch let error as SessionSyncError {
            throw error
        } catch {
            throw SessionSyncError.storageFailure
        }

        guard let gatewayURLString = EnvironmentLoader.stringValue(forKey: "PUBLIC_GATEWAY_URL"),
              let baseURL = URL(string: gatewayURLString)
        else {
            throw SessionSyncError.upstream(0)
        }

        var request = URLRequest(url: baseURL.appendingPathComponent("auth/session/sync"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if intent == .validate {
            request.setValue("Bearer \(file.accessToken)", forHTTPHeaderField: "Authorization")
        }
        let body = SessionSyncRequest(
            mode: intent,
            requestID: requestID,
            deviceID: device.deviceId,
            deviceName: device.deviceName,
            appVersion: device.appVersion,
            osVersion: device.osVersion,
            refreshToken: intent == .refresh ? file.refreshToken : nil,
        )
        request.httpBody = try JSONEncoder().encode(body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            if isCancellationError(error) { throw CancellationError() }
            throw SessionSyncError.upstream(0)
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SessionSyncError.upstream(0)
        }

        if httpResponse.statusCode == 200 {
            return try await sessionSyncResult(data: data, intent: intent, source: file, store: store)
        }

        guard let syncError = sessionSyncError(for: httpResponse.statusCode) else {
            return try await legacySessionSync(intent: intent, device: device, store: store)
        }
        throw syncError
    }

    private static func sessionSyncResult(
        data: Data,
        intent: SessionSyncIntent,
        source: AccountTokensFile,
        store: AccountTokenFileStore,
    ) async throws -> SessionSyncResult {
        let decoded: SessionSyncResponse
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            decoded = try decoder.decode(SessionSyncResponse.self, from: data)
        } catch {
            throw SessionSyncError.upstream(200)
        }
        if intent == .refresh, decoded.session.status == .rotated {
            let rotated = try rotatedTokensFile(from: decoded.session, replacing: source)
            try await replaceRotatedTokens(rotated, expected: source, store: store)
        }
        return decoded.result()
    }

    private static func replaceRotatedTokens(
        _ tokens: AccountTokensFile,
        expected source: AccountTokensFile,
        store: AccountTokenFileStore,
    ) async throws {
        do {
            let didReplace = try await store.replaceIfCurrentMatches(tokens, expected: source)
            guard didReplace else { throw SessionSyncError.storageFailure }
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as SessionSyncError {
            throw error
        } catch {
            throw SessionSyncError.storageFailure
        }
    }

    static func sessionSyncError(for statusCode: Int) -> SessionSyncError? {
        switch statusCode {
        case 404, 405:
            nil
        case 401:
            .invalidCredential
        default:
            .upstream(statusCode)
        }
    }

    private static func legacySessionSync(
        intent: SessionSyncIntent,
        device: DeviceBindingRequest,
        store: AccountTokenFileStore,
    ) async throws -> SessionSyncResult {
        if intent == .refresh {
            try await refreshLegacySession(store: store)
        }

        let access: AccessStatusResponse
        do {
            access = try await fetchAccessStatusLive()
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as AccessError where error == .unauthorized {
            throw SessionSyncError.invalidCredential
        } catch {
            throw SessionSyncError.capabilityMiss
        }

        let outcome: SessionSyncDeviceBindingOutcome = if access.toAccessStatus().isActive {
            try await legacyDeviceBindingOutcome(for: device)
        } else {
            .notAttempted
        }
        return SessionSyncResult(
            sessionStatus: intent == .refresh ? .rotated : .unchanged,
            syncStatus: .complete,
            accessStatus: access,
            deviceBindingOutcome: outcome,
            connectedDeviceAvailability: .unavailable,
        )
    }

    private static func refreshLegacySession(store: AccountTokenFileStore) async throws {
        do {
            let refreshed = try await refreshTokenLive(store: store)
            guard let tokens = AccountTokenSessionMapper.sessionToTokensFile(refreshed.session) else {
                throw SessionSyncError.storageFailure
            }
            let didReplace = try await store.replaceIfCurrentMatches(tokens, expected: refreshed.source)
            guard didReplace else { throw SessionSyncError.storageFailure }
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as SessionSyncError {
            throw error
        } catch let error as AccessError where error == .unauthorized {
            throw SessionSyncError.invalidCredential
        } catch {
            throw SessionSyncError.capabilityMiss
        }
    }

    private static func legacyDeviceBindingOutcome(
        for device: DeviceBindingRequest,
    ) async throws -> SessionSyncDeviceBindingOutcome {
        do {
            _ = try await bindDeviceLive(device)
            return .bound
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as DeviceBindingError {
            if let syncError = legacySessionSyncError(for: error) {
                throw syncError
            }
            return error == .seatCapacityExceeded ? .deviceLimitReached : .notAttempted
        } catch {
            return .notAttempted
        }
    }

    private static func rotatedTokensFile(
        from session: SessionSyncResponse.Session,
        replacing previous: AccountTokensFile,
    ) throws -> AccountTokensFile {
        guard let accessToken = session.accessToken,
              let refreshToken = session.refreshToken,
              let expiresAt = session.expiresAt
        else {
            throw SessionSyncError.storageFailure
        }
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let expiresAtMs = expiresAt * 1000
        return AccountTokensFile(
            updatedAtMs: now,
            accessToken: accessToken,
            accessTokenExpiresAtMs: expiresAtMs,
            accessTokenExpiresIn: session.expiresIn ?? max(0, expiresAtMs - now),
            refreshToken: refreshToken,
            refreshTokenExpiresAtMs: (session.refreshTokenExpiresAt ?? previous.refreshTokenExpiresAtMs / 1000) * 1000,
        )
    }
}

extension AuthNetworkClient {
    static func isCancellationError(_ error: Error) -> Bool {
        error is CancellationError || (error as? URLError)?.code == .cancelled
    }

    static func legacySessionSyncError(for deviceBindingError: DeviceBindingError) -> SessionSyncError? {
        switch deviceBindingError {
        case .unauthorized:
            .invalidCredential
        default:
            nil
        }
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
            bindDevice: { _ in throw DeviceBindingError.notConfigured },
            refreshToken: { throw AccessError.notConfigured },
            syncSession: { _, _ in throw SessionSyncError.capabilityMiss },
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
