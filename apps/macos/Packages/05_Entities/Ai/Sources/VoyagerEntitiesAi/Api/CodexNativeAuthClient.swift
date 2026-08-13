import ComposableArchitecture
import Foundation

// MARK: - Supporting Models

public struct DeviceAuthChallenge: Equatable, Sendable {
    public let userCode: String
    public let verificationURL: URL
    public let pollIntervalMs: Int
    public let expiresAt: Date

    public init(
        userCode: String,
        verificationURL: URL,
        pollIntervalMs: Int,
        expiresAt: Date,
    ) {
        self.userCode = userCode
        self.verificationURL = verificationURL
        self.pollIntervalMs = pollIntervalMs
        self.expiresAt = expiresAt
    }
}

public enum BrowserLoginState: Equatable, Sendable {
    case inProgress
    case completed(OAuthCredentialFile)
    case failed(CodexNativeAuthError)
}

struct CodexTokenResponse: Decodable {
    let access_token: String
    let refresh_token: String?
    let id_token: String?
    let expires_in: Int?
    let token_type: String
}

private struct OAuthErrorResponse: Decodable {
    let error: String
}

public enum CodexCredentialRefreshError: Error, Equatable, Sendable {
    case missingRefreshToken
    case invalidGrant
    case unauthorized(statusCode: Int)
    case transport
    case server(statusCode: Int)
    case invalidResponse
    case cancelled
}

private final class CodexBrowserLoginFlow: @unchecked Sendable {
    private let lock = NSLock()
    private var task: Task<Void, Never>?
    private var server: LocalOAuthHTTPServer?
    private var generation = 0

    func start(server: LocalOAuthHTTPServer, operation: @escaping @Sendable () async -> Void) -> Int {
        cancel()

        lock.lock()
        generation += 1
        let currentGeneration = generation
        self.server = server
        let task = Task {
            await operation()
            finish(generation: currentGeneration)
        }
        self.task = task
        lock.unlock()

        return currentGeneration
    }

    func cancel() {
        lock.lock()
        generation += 1
        let currentTask = task
        let currentServer = server
        task = nil
        server = nil
        lock.unlock()

        currentServer?.cancel()
        currentTask?.cancel()
    }

    func cancel(generation expectedGeneration: Int) {
        lock.lock()
        guard generation == expectedGeneration else {
            lock.unlock()
            return
        }

        generation += 1
        let currentTask = task
        let currentServer = server
        task = nil
        server = nil
        lock.unlock()

        currentServer?.cancel()
        currentTask?.cancel()
    }

    private func finish(generation finishedGeneration: Int) {
        lock.lock()
        if generation == finishedGeneration {
            task = nil
            server = nil
        }
        lock.unlock()
    }
}

// MARK: - Client

public struct CodexNativeAuthClient: Sendable {
    public static func classifyRefreshHTTPFailure(
        statusCode: Int,
        body: Data,
    ) -> CodexCredentialRefreshError {
        guard statusCode == 400,
              let payload = try? JSONDecoder().decode(OAuthErrorResponse.self, from: body),
              payload.error == "invalid_grant"
        else {
            return .transport
        }
        return .invalidGrant
    }

    public var startBrowserLogin: @Sendable () -> AsyncThrowingStream<BrowserLoginState, Error>
    public var startDeviceAuth: @Sendable () async throws -> DeviceAuthChallenge
    public var completeDeviceAuth: @Sendable (_ challenge: DeviceAuthChallenge) async throws -> OAuthCredentialFile
    public var cancelCurrentFlow: @Sendable () async -> Void
    public var refreshCredential: @Sendable (OAuthCredentialFile) async throws -> OAuthCredentialFile

    nonisolated public init(
        startBrowserLogin: @escaping @Sendable () -> AsyncThrowingStream<BrowserLoginState, Error>,
        startDeviceAuth: @escaping @Sendable () async throws -> DeviceAuthChallenge,
        completeDeviceAuth: @escaping @Sendable (_ challenge: DeviceAuthChallenge) async throws -> OAuthCredentialFile,
        cancelCurrentFlow: @escaping @Sendable () async -> Void,
        refreshCredential: @escaping @Sendable (OAuthCredentialFile) async throws -> OAuthCredentialFile = { _ in
            throw CodexNativeAuthError.loginUnavailable
        },
    ) {
        self.startBrowserLogin = startBrowserLogin
        self.startDeviceAuth = startDeviceAuth
        self.completeDeviceAuth = completeDeviceAuth
        self.cancelCurrentFlow = cancelCurrentFlow
        self.refreshCredential = refreshCredential
    }
}

// MARK: - DependencyKey

extension CodexNativeAuthClient: DependencyKey {
    nonisolated public static var liveValue: CodexNativeAuthClient {
        .live()
    }

    public static func live(session: URLSession = .shared) -> CodexNativeAuthClient {
        let browserLoginFlow = CodexBrowserLoginFlow()

        return CodexNativeAuthClient(
            startBrowserLogin: {
                browserLoginStream(flow: browserLoginFlow, session: session)
            },
            startDeviceAuth: {
                throw CodexNativeAuthError.loginUnavailable
            },
            completeDeviceAuth: { _ in
                throw CodexNativeAuthError.loginUnavailable
            },
            cancelCurrentFlow: {
                browserLoginFlow.cancel()
            },
            refreshCredential: { credential in
                let response = try await refreshToken(
                    config: .default,
                    refreshToken: credential.refreshToken,
                    session: session,
                )
                return OAuthCredentialFile(
                    accessToken: response.access_token,
                    refreshToken: response.refresh_token ?? credential.refreshToken,
                    idToken: response.id_token ?? credential.idToken,
                    tokenType: response.token_type,
                    scopes: CodexOAuthConfig.default.scopes,
                    expiresAtMs: Int64(Date().timeIntervalSince1970 * 1000) + Int64(response.expires_in ?? 3600) * 1000,
                    chatGPTAccountId: Self.chatGPTAccountId(from: response.id_token) ?? credential.chatGPTAccountId,
                )
            },
        )
    }

    nonisolated public static var testValue: CodexNativeAuthClient {
        CodexNativeAuthClient(
            startBrowserLogin: {
                AsyncThrowingStream { continuation in
                    continuation.yield(.failed(.loginUnavailable))
                    continuation.finish()
                }
            },
            startDeviceAuth: {
                throw CodexNativeAuthError.loginUnavailable
            },
            completeDeviceAuth: { _ in
                throw CodexNativeAuthError.loginUnavailable
            },
            cancelCurrentFlow: {},
            refreshCredential: { _ in throw CodexNativeAuthError.loginUnavailable },
        )
    }

    nonisolated public static var previewValue: CodexNativeAuthClient {
        CodexNativeAuthClient(
            startBrowserLogin: {
                AsyncThrowingStream { continuation in
                    continuation.yield(.inProgress)
                    continuation.yield(
                        .completed(
                            OAuthCredentialFile(
                                accessToken: "preview-access-token",
                                refreshToken: "preview-refresh-token",
                                tokenType: "Bearer",
                                scopes: ["profile", "email"],
                                expiresAtMs: nil,
                            ),
                        ),
                    )
                    continuation.finish()
                }
            },
            startDeviceAuth: {
                DeviceAuthChallenge(
                    userCode: "ABCD-1234",
                    verificationURL: {
                        guard let url = URL(string: "https://chatgpt.com/device") else {
                            fatalError("Invalid hardcoded device URL")
                        }
                        return url
                    }(),
                    pollIntervalMs: 5000,
                    expiresAt: Date().addingTimeInterval(900),
                )
            },
            completeDeviceAuth: { _ in
                OAuthCredentialFile(
                    accessToken: "preview-access-token",
                    refreshToken: "preview-refresh-token",
                    tokenType: "Bearer",
                    scopes: ["profile", "email"],
                    expiresAtMs: nil,
                )
            },
            cancelCurrentFlow: {},
            refreshCredential: { credential in credential },
        )
    }
}

// MARK: - Live Helpers

extension CodexNativeAuthClient {
    private static func browserLoginStream(
        flow: CodexBrowserLoginFlow,
        session: URLSession,
    ) -> AsyncThrowingStream<BrowserLoginState, Error> {
        AsyncThrowingStream { continuation in
            let config = CodexOAuthConfig.default
            let server = LocalOAuthHTTPServer(
                port: UInt16(config.redirectPort),
                expectedPath: config.redirectPath,
            )
            let generation = flow.start(server: server) {
                await runBrowserLogin(
                    continuation: continuation,
                    config: config,
                    server: server,
                    session: session,
                )
            }
            continuation.onTermination = { @Sendable _ in
                flow.cancel(generation: generation)
            }
        }
    }

    private static func runBrowserLogin(
        continuation: AsyncThrowingStream<BrowserLoginState, Error>.Continuation,
        config: CodexOAuthConfig,
        server: LocalOAuthHTTPServer,
        session: URLSession,
    ) async {
        do {
            try Task.checkCancellation()
            let pkce = PKCE.generate()
            let state = PKCE.generateState()
            let authURL = config.authorizeURL(pkceChallenge: pkce.challenge, state: state)
            continuation.yield(.inProgress)
            openURL(authURL)
            let callback = try await server.startAndWait(timeout: 300)
            guard callback.state == state else {
                continuation.yield(.failed(.callbackMismatch))
                continuation.finish()
                return
            }
            let tokenResponse = try await exchangeCode(
                config: config,
                code: callback.code,
                pkce: pkce,
                session: session,
            )
            continuation.yield(.completed(oAuthCredential(from: tokenResponse, config: config)))
            continuation.finish()
        } catch is CancellationError {
            continuation.yield(.failed(.cancelled))
            continuation.finish()
        } catch let error as URLError where error.code == .cancelled {
            continuation.yield(.failed(.cancelled))
            continuation.finish()
        } catch let error as OAuthCallbackError {
            continuation.yield(.failed(mapCallbackError(error)))
            continuation.finish()
        } catch let error as CodexNativeAuthError {
            continuation.yield(.failed(error))
            continuation.finish()
        } catch {
            continuation.yield(.failed(.networkError(error.localizedDescription)))
            continuation.finish()
        }
    }

    private static func mapCallbackError(_ error: OAuthCallbackError) -> CodexNativeAuthError {
        switch error {
        case .cancelled:
            .cancelled
        case .serverStartFailed where error == .serverStartFailed("Timeout waiting for OAuth callback"):
            .timeout
        case .accessDenied, .invalidCallback, .serverStartFailed:
            .networkError(String(describing: error))
        }
    }

    private static func oAuthCredential(
        from response: CodexTokenResponse,
        config: CodexOAuthConfig,
    ) -> OAuthCredentialFile {
        OAuthCredentialFile(
            accessToken: response.access_token,
            refreshToken: response.refresh_token,
            idToken: response.id_token,
            tokenType: response.token_type,
            scopes: config.scopes,
            expiresAtMs: Int64(Date().timeIntervalSince1970 * 1000)
                + Int64(response.expires_in ?? 3600) * 1000,
            chatGPTAccountId: chatGPTAccountId(from: response.id_token),
        )
    }

    private static func openURL(_ url: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = [url.absoluteString]
        try? process.run()
    }

    private static func exchangeCode(
        config: CodexOAuthConfig,
        code: String,
        pkce: PKCECodes,
        session: URLSession,
    ) async throws -> CodexTokenResponse {
        var request = URLRequest(url: config.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "redirect_uri", value: config.redirectURI),
            URLQueryItem(name: "client_id", value: config.clientId),
            URLQueryItem(name: "code_verifier", value: pkce.verifier),
        ]
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw CodexNativeAuthError.networkError("Token exchange failed with status \(statusCode)")
        }

        return try JSONDecoder().decode(CodexTokenResponse.self, from: data)
    }

    private static func refreshToken(
        config: CodexOAuthConfig,
        refreshToken: String?,
        session: URLSession,
    ) async throws -> CodexTokenResponse {
        guard let refreshToken, !refreshToken.isEmpty else {
            throw CodexCredentialRefreshError.missingRefreshToken
        }
        var request = URLRequest(url: config.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "grant_type", value: "refresh_token"),
            URLQueryItem(name: "refresh_token", value: refreshToken),
            URLQueryItem(name: "client_id", value: config.clientId),
        ]
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)
        let (data, response) = try await refreshResponse(for: request, session: session)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CodexCredentialRefreshError.transport
        }
        switch httpResponse.statusCode {
        case 200:
            break
        case 401, 403:
            throw CodexCredentialRefreshError.unauthorized(statusCode: httpResponse.statusCode)
        case 400:
            throw Self.classifyRefreshHTTPFailure(statusCode: 400, body: data)
        case 500 ... 599:
            throw CodexCredentialRefreshError.server(statusCode: httpResponse.statusCode)
        default:
            throw CodexCredentialRefreshError.transport
        }
        do {
            return try JSONDecoder().decode(CodexTokenResponse.self, from: data)
        } catch {
            throw CodexCredentialRefreshError.invalidResponse
        }
    }

    private static func refreshResponse(
        for request: URLRequest,
        session: URLSession,
    ) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch is CancellationError {
            throw CodexCredentialRefreshError.cancelled
        } catch let error as URLError where error.code == .cancelled {
            throw CodexCredentialRefreshError.cancelled
        } catch {
            throw CodexCredentialRefreshError.transport
        }
    }

    static func chatGPTAccountId(from idToken: String?) -> String? {
        guard let idToken else { return nil }
        let parts = idToken.split(separator: ".")
        guard parts.count >= 2 else { return nil }

        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = payload.count % 4
        if remainder > 0 {
            payload.append(String(repeating: "=", count: 4 - remainder))
        }

        guard let data = Data(base64Encoded: payload),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let auth = object["https://api.openai.com/auth"] as? [String: Any]
        else { return nil }

        return auth["chatgpt_account_id"] as? String
    }
}

public extension DependencyValues {
    nonisolated var codexNativeAuthClient: CodexNativeAuthClient {
        get { self[CodexNativeAuthClient.self] }
        set { self[CodexNativeAuthClient.self] = newValue }
    }
}
