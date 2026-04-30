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
        expiresAt: Date
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

struct CodexTokenResponse: Decodable, Sendable {
    let access_token: String
    let refresh_token: String?
    let id_token: String?
    let expires_in: Int?
    let token_type: String
}

// MARK: - Client

public struct CodexNativeAuthClient: Sendable {
    public var startBrowserLogin: @Sendable () -> AsyncThrowingStream<BrowserLoginState, Error>
    public var startDeviceAuth: @Sendable () async throws -> DeviceAuthChallenge
    public var completeDeviceAuth: @Sendable (_ challenge: DeviceAuthChallenge) async throws -> OAuthCredentialFile
    public var cancelCurrentFlow: @Sendable () async -> Void

    public nonisolated init(
        startBrowserLogin: @escaping @Sendable () -> AsyncThrowingStream<BrowserLoginState, Error>,
        startDeviceAuth: @escaping @Sendable () async throws -> DeviceAuthChallenge,
        completeDeviceAuth: @escaping @Sendable (_ challenge: DeviceAuthChallenge) async throws -> OAuthCredentialFile,
        cancelCurrentFlow: @escaping @Sendable () async -> Void
    ) {
        self.startBrowserLogin = startBrowserLogin
        self.startDeviceAuth = startDeviceAuth
        self.completeDeviceAuth = completeDeviceAuth
        self.cancelCurrentFlow = cancelCurrentFlow
    }
}

// MARK: - DependencyKey

extension CodexNativeAuthClient: DependencyKey {
    public nonisolated static var liveValue: CodexNativeAuthClient {
        CodexNativeAuthClient(
            startBrowserLogin: {
                AsyncThrowingStream { continuation in
                    Task {
                        do {
                            let config = CodexOAuthConfig.default
                            let pkce = PKCE.generate()
                            let state = PKCE.generateState()
                            let authURL = config.authorizeURL(pkceChallenge: pkce.challenge, state: state)

                            continuation.yield(.inProgress)

                            let server = LocalOAuthHTTPServer(
                                port: UInt16(config.redirectPort),
                                expectedPath: config.redirectPath
                            )

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
                                pkce: pkce
                            )

                            let credential = OAuthCredentialFile(
                                accessToken: tokenResponse.access_token,
                                refreshToken: tokenResponse.refresh_token,
                                idToken: tokenResponse.id_token,
                                tokenType: tokenResponse.token_type,
                                scopes: config.scopes,
                                expiresAtMs: Int64(Date().timeIntervalSince1970 * 1000)
                                    + Int64(tokenResponse.expires_in ?? 3600) * 1000,
                                chatGPTAccountId: Self.chatGPTAccountId(from: tokenResponse.id_token)
                            )

                            continuation.yield(.completed(credential))
                            continuation.finish()
                        } catch is CancellationError {
                            continuation.yield(.failed(.cancelled))
                            continuation.finish()
                        } catch let error as OAuthCallbackError {
                            let mapped: CodexNativeAuthError = switch error {
                            case .cancelled: .cancelled
                            case .serverStartFailed where error == .serverStartFailed(
                                "Timeout waiting for OAuth callback"
                            ): .timeout
                            case .accessDenied, .invalidCallback, .serverStartFailed:
                                .networkError(String(describing: error))
                            }
                            continuation.yield(.failed(mapped))
                            continuation.finish()
                        } catch let error as CodexNativeAuthError {
                            continuation.yield(.failed(error))
                            continuation.finish()
                        } catch {
                            continuation.yield(.failed(.networkError(error.localizedDescription)))
                            continuation.finish()
                        }
                    }
                }
            },
            startDeviceAuth: {
                throw CodexNativeAuthError.loginUnavailable
            },
            completeDeviceAuth: { _ in
                throw CodexNativeAuthError.loginUnavailable
            },
            cancelCurrentFlow: {}
        )
    }

    public nonisolated static var testValue: CodexNativeAuthClient {
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
            cancelCurrentFlow: {}
        )
    }

    public nonisolated static var previewValue: CodexNativeAuthClient {
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
                                expiresAtMs: nil
                            )
                        )
                    )
                    continuation.finish()
                }
            },
            startDeviceAuth: {
                DeviceAuthChallenge(
                    userCode: "ABCD-1234",
                    verificationURL: URL(string: "https://chatgpt.com/device")!,
                    pollIntervalMs: 5000,
                    expiresAt: Date().addingTimeInterval(900)
                )
            },
            completeDeviceAuth: { _ in
                OAuthCredentialFile(
                    accessToken: "preview-access-token",
                    refreshToken: "preview-refresh-token",
                    tokenType: "Bearer",
                    scopes: ["profile", "email"],
                    expiresAtMs: nil
                )
            },
            cancelCurrentFlow: {}
        )
    }
}

// MARK: - Live Helpers

extension CodexNativeAuthClient {
    private static func openURL(_ url: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = [url.absoluteString]
        try? process.run()
    }

    private static func exchangeCode(
        config: CodexOAuthConfig,
        code: String,
        pkce: PKCECodes
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

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw CodexNativeAuthError.networkError("Token exchange failed with status \(statusCode)")
        }

        return try JSONDecoder().decode(CodexTokenResponse.self, from: data)
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
