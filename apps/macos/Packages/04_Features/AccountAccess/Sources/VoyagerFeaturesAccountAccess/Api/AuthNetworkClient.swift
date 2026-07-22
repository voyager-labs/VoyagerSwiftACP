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
        let appEnv = EnvironmentLoader.detectAppEnv()
        return AuthNetworkClient(
            exchangeHandoff: { ticket, state, context in
                try await exchangeHandoffLive(ticket: ticket, state: state, context: context, appEnv: appEnv)
            },
            fetchAccessStatus: {
                try await fetchAccessStatusLive(appEnv: appEnv)
            },
            bindDevice: { request in
                try await bindDeviceLive(request, appEnv: appEnv)
            },
            refreshToken: {
                let store = AccountTokenFileStore.withDefaultHome(appEnv: appEnv)
                let refreshed = try await refreshTokenLive(store: store)
                return refreshed.session
            },
            syncSessionWithRequestID: { intent, device, requestID in
                try await syncSessionLive(intent: intent, device: device, requestID: requestID, appEnv: appEnv)
            },
        )
    }

    // MARK: - Live helpers

    private static func exchangeHandoffLive(
        ticket: String,
        state: String,
        context: AppHandoffContext,
        appEnv _: EnvironmentLoader.AppEnv,
    ) async throws -> AccountSession {
        // extracted from AppHandoffExchangeClient.swift:21-67
        guard let gatewayURLString = EnvironmentLoader.stringValue(forKey: "PUBLIC_GATEWAY_URL"),
              let gatewayURL = GatewayEnvironment(rawValue: gatewayURLString).baseURL
        else {
            throw AppHandoffExchangeError.networkFailure
        }

        let builder = AppHandoffURLBuilder(
            webBaseURL: EnvironmentLoader.stringValue(forKey: "PUBLIC_WEB_BASE_URL") ?? "",
            gatewayURL: gatewayURL.absoluteString,
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
            guard let mappedError = exchangeError(for: error) else {
                throw CancellationError()
            }
            throw mappedError
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

    private static func fetchAccessStatusLive(appEnv: EnvironmentLoader.AppEnv) async throws -> AccessStatusResponse {
        let store = AccountTokenFileStore.withDefaultHome(appEnv: appEnv)
        let file = try await store.read()
        guard let file else { throw AccessError.notConfigured }
        guard let gatewayURLString = EnvironmentLoader.stringValue(forKey: "PUBLIC_GATEWAY_URL"),
              let base = GatewayEnvironment(rawValue: gatewayURLString).baseURL
        else { throw AccessError.networkFailure }
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
        return try decodeAccessStatusResponse(data)
    }

    private static func bindDeviceLive(_ bindingRequest: DeviceBindingRequest,
                                       appEnv: EnvironmentLoader.AppEnv) async throws -> DeviceBindingResponse
    {
        let store = AccountTokenFileStore.withDefaultHome(appEnv: appEnv)
        let file = try await store.read()
        guard let file else { throw DeviceBindingError.notConfigured }
        guard let gatewayURLString = EnvironmentLoader.stringValue(forKey: "PUBLIC_GATEWAY_URL"),
              let base = GatewayEnvironment(rawValue: gatewayURLString).baseURL
        else { throw DeviceBindingError.networkFailure }
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
        guard let file = try await store.read() else { throw AccessError.notConfigured }
        return try await refreshTokenLive(file: file)
    }

    private static func refreshTokenLive(
        file: AccountTokensFile,
    ) async throws -> (session: AccountSession, source: AccountTokensFile) {
        // extracted from AccountAccessClient.swift:87-128 (excluding write-back)
        guard let gatewayURLString = EnvironmentLoader.stringValue(forKey: "PUBLIC_GATEWAY_URL"),
              let base = GatewayEnvironment(rawValue: gatewayURLString).baseURL
        else { throw AccessError.networkFailure }
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
        let refreshResponse = try decodeRefreshSuccessResponse(data)
        guard refreshResponse.ok, let sessionPayload = refreshResponse.session else {
            throw AccessError.decodingFailure
        }
        return (
            session: AccountSession(
                accessToken: sessionPayload.accessToken,
                status: .none,
                refreshToken: sessionPayload.refreshToken ?? file.refreshToken,
                expiresAt: sessionPayload.expiresAt.map { Date(timeIntervalSince1970: $0) },
                sessionBindingID: file.sessionBindingID ?? UUID(),
            ),
            source: file,
        )
    }

    private static func syncSessionLive(
        intent: SessionSyncIntent,
        device: DeviceBindingRequest,
        requestID: String,
        appEnv: EnvironmentLoader.AppEnv,
    ) async throws -> SessionSyncResult {
        let store = AccountTokenFileStore.withDefaultHome(appEnv: appEnv)
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
              let baseURL = GatewayEnvironment(rawValue: gatewayURLString).baseURL
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
            return try await legacySessionSync(intent: intent, device: device, store: store, appEnv: appEnv)
        }
        throw syncError
    }

    internal static func sessionSyncResult(
        data: Data,
        intent: SessionSyncIntent,
        source: AccountTokensFile,
        store: AccountTokenFileStore,
    ) async throws -> SessionSyncResult {
        let decoded: SessionSyncResponse
        do {
            decoded = try gatewayJSONDecoder().decode(SessionSyncResponse.self, from: data)
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
        } catch let error where isCancellationError(error) {
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
        case 400, 413, 429:
            .invalidResponse(statusCode)
        case 500 ... 599:
            .upstream(statusCode)
        default:
            .invalidResponse(statusCode)
        }
    }

    private static func legacySessionSync(
        intent: SessionSyncIntent,
        device: DeviceBindingRequest,
        store: AccountTokenFileStore,
        appEnv: EnvironmentLoader.AppEnv,
    ) async throws -> SessionSyncResult {
        let refreshedSession: AccountSession? = if intent == .refresh {
            try await refreshLegacySession(store: store)
        } else {
            nil
        }

        let access: AccessStatusResponse
        do {
            access = try await fetchAccessStatusLive(appEnv: appEnv)
        } catch let error where isCancellationError(error) {
            throw CancellationError()
        } catch {
            throw legacySessionSyncError(for: error)
        }

        let outcome: SessionSyncDeviceBindingOutcome = if access.toAccessStatus().isActive {
            try await legacyDeviceBindingOutcome(for: device, appEnv: appEnv)
        } else {
            .notAttempted
        }
        return legacySessionSyncResult(
            intent: intent,
            access: access,
            outcome: outcome,
            refreshedSession: refreshedSession,
        )
    }

    static func legacySessionSyncResult(
        intent: SessionSyncIntent,
        access: AccessStatusResponse,
        outcome: SessionSyncDeviceBindingOutcome,
        refreshedSession: AccountSession?,
    ) -> SessionSyncResult {
        SessionSyncResult(
            sessionStatus: intent == .refresh ? .rotated : .unchanged,
            syncStatus: .complete,
            accessStatus: access,
            deviceBindingOutcome: outcome,
            connectedDeviceAvailability: .unavailable,
            sessionExpiresAt: refreshedSession?.expiresAt,
        )
    }

    private static func refreshLegacySession(store: AccountTokenFileStore) async throws -> AccountSession {
        let source = try await legacyRefreshSource(store: store)
        let refreshed = try await legacyRefreshedSession(source: source)
        return try await persistLegacyRefreshedSession(refreshed, store: store)
    }

    private static func legacyRefreshSource(store: AccountTokenFileStore) async throws -> AccountTokensFile {
        do {
            guard let stored = try await store.read() else { throw AccessError.notConfigured }
            return stored
        } catch let error where isCancellationError(error) {
            throw CancellationError()
        } catch let error as AccessError {
            throw legacySessionSyncError(for: error)
        } catch {
            throw SessionSyncError.storageFailure
        }
    }

    private static func legacyRefreshedSession(
        source: AccountTokensFile,
    ) async throws -> (session: AccountSession, source: AccountTokensFile) {
        do {
            return try await refreshTokenLive(file: source)
        } catch let error where isCancellationError(error) {
            throw CancellationError()
        } catch {
            throw legacySessionSyncError(for: error)
        }
    }

    internal static func persistLegacyRefreshedSession(
        _ refreshed: (session: AccountSession, source: AccountTokensFile),
        store: AccountTokenFileStore,
    ) async throws -> AccountSession {
        guard let tokens = AccountTokenSessionMapper.sessionToTokensFile(refreshed.session, now: Date()),
              let persistedSession = AccountTokenSessionMapper.tokensFileToSession(tokens)
        else {
            throw SessionSyncError.storageFailure
        }

        do {
            let didReplace = try await store.replaceIfCurrentMatches(tokens, expected: refreshed.source)
            guard didReplace else { throw SessionSyncError.storageFailure }
        } catch let error where isCancellationError(error) {
            throw CancellationError()
        } catch let error as SessionSyncError {
            throw error
        } catch {
            throw SessionSyncError.storageFailure
        }
        return persistedSession
    }

    private static func legacyDeviceBindingOutcome(
        for device: DeviceBindingRequest,
        appEnv: EnvironmentLoader.AppEnv,
    ) async throws -> SessionSyncDeviceBindingOutcome {
        do {
            _ = try await bindDeviceLive(device, appEnv: appEnv)
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
            sessionBindingID: previous.sessionBindingID,
        )
    }
}

extension AuthNetworkClient {
    static func isCancellationError(_ error: Error) -> Bool {
        error is CancellationError || (error as? URLError)?.code == .cancelled
    }

    static func exchangeError(for error: Error) -> AppHandoffExchangeError? {
        isCancellationError(error) ? nil : .networkFailure
    }

    static func legacySessionSyncError(for error: Error) -> SessionSyncError {
        switch error {
        case let error as SessionSyncError:
            error
        case let error as AccessError:
            switch error {
            case .unauthorized:
                .invalidCredential
            case .notConfigured:
                .capabilityMiss
            case .networkFailure, .decodingFailure, .unknownGatewayCode:
                .upstream(0)
            }
        case let error as DeviceBindingError:
            switch error {
            case .unauthorized:
                .invalidCredential
            case .notConfigured:
                .capabilityMiss
            default:
                .upstream(0)
            }
        default:
            .upstream(0)
        }
    }

    static func legacySessionSyncError(for deviceBindingError: DeviceBindingError) -> SessionSyncError? {
        switch deviceBindingError {
        case .unauthorized:
            .invalidCredential
        case .notConfigured:
            .capabilityMiss
        default:
            nil
        }
    }

    static func decodeAccessStatusResponse(_ data: Data) throws -> AccessStatusResponse {
        do {
            return try gatewayJSONDecoder().decode(AccessStatusResponse.self, from: data)
        } catch {
            throw AccessError.decodingFailure
        }
    }

    static func gatewayJSONDecoder() -> JSONDecoder {
        let fractionalFormatter = gatewayDateFormatter("yyyy-MM-dd'T'HH:mm:ss.SSSSSSSSS'Z'")
        let wholeSecondFormatter = gatewayDateFormatter("yyyy-MM-dd'T'HH:mm:ss'Z'")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            guard value.range(
                of: #"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z$"#,
                options: .regularExpression,
            ) != nil,
                let date = fractionalFormatter.date(from: value) ?? wholeSecondFormatter.date(from: value)
            else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Gateway date must be a valid RFC3339 UTC timestamp.",
                )
            }
            return date
        }
        return decoder
    }

    private static func gatewayDateFormatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = format
        formatter.isLenient = false
        return formatter
    }

    static func decodeRefreshSuccessResponse(_ data: Data) throws -> RefreshSuccessResponse {
        do {
            return try JSONDecoder().decode(RefreshSuccessResponse.self, from: data)
        } catch {
            throw AccessError.decodingFailure
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
