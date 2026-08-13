import Foundation

public enum AiProviderVerificationResult: Equatable, Sendable {
    case valid
    case invalid(ProviderStatusReason)
    case unsupportedProvider
    case networkError
}

public struct AiProviderVerificationOutcome: Equatable, Sendable {
    public let result: AiProviderVerificationResult
    public let sourceCredential: StoredCredentialPayload?
    public let effectiveCredential: StoredCredentialPayload?

    public init(
        result: AiProviderVerificationResult,
        sourceCredential: StoredCredentialPayload?,
        effectiveCredential: StoredCredentialPayload?,
    ) {
        self.result = result
        self.sourceCredential = sourceCredential
        self.effectiveCredential = effectiveCredential
    }
}

public struct AiAdapterDescriptor: Equatable, Sendable {
    public let provider: AiProvider
    public let adapterName: String

    public init(
        provider: AiProvider,
        adapterName: String,
    ) {
        self.provider = provider
        self.adapterName = adapterName
    }
}

public struct AiConnectionRuntimeClient: Sendable {
    public var verifyProvider: @Sendable (AiProvider, StoredCredentialPayload?) async
        -> AiProviderVerificationResult
    public var verifyProviderWithCredential: (@Sendable (AiProvider, StoredCredentialPayload?) async throws
        -> AiProviderVerificationOutcome)?
    public var resolveAdapter: @Sendable (AiProvider, StoredCredentialPayload?) -> AiAdapterDescriptor?

    public init(
        verifyProvider: @escaping @Sendable (AiProvider, StoredCredentialPayload?) async
            -> AiProviderVerificationResult,
        verifyProviderWithCredential: (@Sendable (AiProvider, StoredCredentialPayload?) async throws
            -> AiProviderVerificationOutcome)? = nil,
        resolveAdapter: @escaping @Sendable (AiProvider, StoredCredentialPayload?) -> AiAdapterDescriptor?,
    ) {
        self.verifyProvider = verifyProvider
        self.verifyProviderWithCredential = verifyProviderWithCredential
        self.resolveAdapter = resolveAdapter
    }
}

extension AiConnectionRuntimeClient {
    public static func live(
        session: URLSession = .shared,
        refreshCredential: (@Sendable (OAuthCredentialFile) async throws -> OAuthCredentialFile)? = nil,
    ) -> AiConnectionRuntimeClient {
        let refreshCredential = refreshCredential ?? CodexNativeAuthClient.live(session: session).refreshCredential
        return AiConnectionRuntimeClient(
            verifyProvider: { provider, credential in
                await Self.verifyStatus(provider: provider, credential: credential, session: session)
            },
            verifyProviderWithCredential: { provider, credential in
                try await Self.verifyWithEffectiveCredential(
                    provider: provider,
                    credential: credential,
                    session: session,
                    refreshCredential: refreshCredential,
                )
            },
            resolveAdapter: { provider, credential in
                guard credential != nil else { return nil }
                switch provider {
                case .openai:
                    return AiAdapterDescriptor(provider: .openai, adapterName: "OpenAIAdapter")
                case .chatgptCodex:
                    return AiAdapterDescriptor(provider: .chatgptCodex, adapterName: "OpenAIAdapter")
                case .anthropic:
                    return AiAdapterDescriptor(provider: .anthropic, adapterName: "AnthropicAdapter")
                }
            },
        )
    }

    private static func verifyWithEffectiveCredential(
        provider: AiProvider,
        credential: StoredCredentialPayload?,
        session: URLSession,
        refreshCredential: @escaping @Sendable (OAuthCredentialFile) async throws -> OAuthCredentialFile,
    ) async throws -> AiProviderVerificationOutcome {
        guard let credential else {
            return AiProviderVerificationOutcome(
                result: .invalid(.missingCredential),
                sourceCredential: nil,
                effectiveCredential: nil,
            )
        }
        guard provider == .chatgptCodex else {
            return await AiProviderVerificationOutcome(
                result: verifyStatus(provider: provider, credential: credential, session: session),
                sourceCredential: credential,
                effectiveCredential: credential,
            )
        }
        guard case let .oauth(oauth) = credential, !oauth.accessToken.isEmpty else {
            return AiProviderVerificationOutcome(
                result: .invalid(.credentialKindMismatch),
                sourceCredential: credential,
                effectiveCredential: credential,
            )
        }
        let effectiveCredential = try await refreshedCredential(
            oauth,
            source: credential,
            refreshCredential: refreshCredential,
        )
        guard case let .success(effective) = effectiveCredential else {
            return effectiveCredential.failure
        }
        return try await verifyModels(
            provider: provider,
            sourceCredential: credential,
            effectiveCredential: effective,
            session: session,
        )
    }

    private static func verifyModels(
        provider: AiProvider,
        sourceCredential: StoredCredentialPayload,
        effectiveCredential: StoredCredentialPayload,
        session: URLSession,
    ) async throws -> AiProviderVerificationOutcome {
        do {
            let models = try await AiProviderModelListClient.live(session: session).loadModels(
                provider,
                effectiveCredential,
            )
            return AiProviderVerificationOutcome(
                result: models.isEmpty ? .invalid(.verificationFailed) : .valid,
                sourceCredential: sourceCredential,
                effectiveCredential: effectiveCredential,
            )
        } catch let error as AiProviderModelListError {
            return AiProviderVerificationOutcome(
                result: mapModelListError(error),
                sourceCredential: sourceCredential,
                effectiveCredential: effectiveCredential,
            )
        } catch {
            guard !isCancellation(error) else { throw CancellationError() }
            return AiProviderVerificationOutcome(
                result: .networkError,
                sourceCredential: sourceCredential,
                effectiveCredential: effectiveCredential,
            )
        }
    }

    private enum RefreshResult {
        case success(StoredCredentialPayload)
        case failure(AiProviderVerificationOutcome)
        var failure: AiProviderVerificationOutcome {
            guard case let .failure(value) = self else { fatalError("Unexpected refresh success") }
            return value
        }
    }

    private static func refreshedCredential(
        _ oauth: OAuthCredentialFile,
        source: StoredCredentialPayload,
        refreshCredential: @escaping @Sendable (OAuthCredentialFile) async throws -> OAuthCredentialFile,
    ) async throws -> RefreshResult {
        guard isExpired(oauth) else { return .success(source) }
        do {
            return try await .success(.oauth(refreshCredential(oauth)))
        } catch let error as CodexCredentialRefreshError {
            return try .failure(AiProviderVerificationOutcome(
                result: mapRefreshError(error),
                sourceCredential: source,
                effectiveCredential: source,
            ))
        } catch {
            guard !isCancellation(error) else { throw CancellationError() }
            return .failure(AiProviderVerificationOutcome(
                result: .networkError,
                sourceCredential: source,
                effectiveCredential: source,
            ))
        }
    }

    private static func isCancellation(_ error: Error) -> Bool {
        error is CancellationError || (error as? URLError)?.code == .cancelled
    }

    private static func verifyStatus(
        provider: AiProvider,
        credential: StoredCredentialPayload?,
        session: URLSession,
    ) async -> AiProviderVerificationResult {
        guard let credential else { return .invalid(.missingCredential) }
        let secret: String = switch credential {
        case let .apiKey(payload): payload.secret
        case let .oauth(payload): payload.accessToken
        }
        guard !secret.isEmpty else { return .invalid(.invalidAPIKey) }
        if provider == .chatgptCodex { return .valid }
        return await performSmokeRequest(provider: provider, secret: secret, session: session)
    }

    static func mapModelListError(_ error: AiProviderModelListError) -> AiProviderVerificationResult {
        switch error {
        case .missingCredential: .invalid(.missingCredential)
        case .invalidCredential: .invalid(.credentialKindMismatch)
        case .unsupportedProvider: .unsupportedProvider
        case .invalidResponse: .invalid(.verificationFailed)
        case let .httpError(provider, statusCode, _):
            switch statusCode {
            case 401, 403:
                if provider == .chatgptCodex {
                    .invalid(.expired)
                } else {
                    .invalid(.invalidAPIKey)
                }
            case 500 ... 599: .networkError
            default: .invalid(.verificationFailed)
            }
        case .networkError: .networkError
        }
    }

    public static func mapRefreshError(_ error: CodexCredentialRefreshError) throws -> AiProviderVerificationResult {
        switch error {
        case .missingRefreshToken, .invalidGrant, .unauthorized:
            .invalid(.expired)
        case .transport, .server, .invalidResponse:
            .networkError
        case .cancelled:
            throw CancellationError()
        }
    }

    private static func isExpired(_ credential: OAuthCredentialFile) -> Bool {
        guard let expiresAtMs = credential.expiresAtMs else { return true }
        return expiresAtMs <= Int64(Date().timeIntervalSince1970 * 1000)
    }

    private static func performSmokeRequest(
        provider: AiProvider,
        secret: String,
        session: URLSession,
    ) async -> AiProviderVerificationResult {
        let url: String
        var request: URLRequest

        switch provider {
        case .openai:
            url = "https://api.openai.com/v1/models"
            guard let requestURL = URL(string: url) else {
                return .invalid(.verificationFailed)
            }
            request = URLRequest(url: requestURL)
            request.httpMethod = "GET"
            request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
            request.timeoutInterval = 30

        case .chatgptCodex:
            return .valid

        case .anthropic:
            url = "https://api.anthropic.com/v1/models"
            guard let requestURL = URL(string: url) else {
                return .invalid(.verificationFailed)
            }
            request = URLRequest(url: requestURL)
            request.httpMethod = "GET"
            request.setValue(secret, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            request.timeoutInterval = 30
        }

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return .networkError
            }
            let body = String(data: data, encoding: .utf8) ?? ""
            let error = AiHTTPError.httpError(statusCode: httpResponse.statusCode, body: body)
            return Self.mapHTTPError(error)
        } catch let error as URLError {
            if error.code == .cancelled {
                return .invalid(.verificationFailed)
            }
            return .networkError
        } catch {
            return .networkError
        }
    }

    public static func mapHTTPError(_ error: AiHTTPError) -> AiProviderVerificationResult {
        switch error {
        case let .httpError(statusCode, body):
            mapHTTPStatusCode(statusCode, body: body)
        case .networkError, .timeout:
            .networkError
        case .invalidURL, .cancelled:
            .invalid(.verificationFailed)
        }
    }

    private static func mapHTTPStatusCode(_ statusCode: Int, body: String) -> AiProviderVerificationResult {
        switch statusCode {
        case 200 ... 299: return .valid
        case 401: return .invalid(.invalidAPIKey)
        case 403:
            if extractErrorCode(from: body) == "expired_api_key" {
                return .invalid(.expired)
            }
            return .invalid(.invalidAPIKey)
        case 429: return .invalid(.verificationFailed)
        case 500 ... 599: return .networkError
        default: return .invalid(.verificationFailed)
        }
    }

    private static func extractErrorCode(from body: String) -> String? {
        guard let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = json["error"] as? [String: Any],
              let code = error["code"] as? String
        else { return nil }
        return code
    }
}
