import Foundation

public enum AiProviderVerificationResult: Equatable, Sendable {
    case valid
    case invalid(ProviderStatusReason)
    case unsupportedProvider
    case networkError
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
    public var resolveAdapter: @Sendable (AiProvider, StoredCredentialPayload?) -> AiAdapterDescriptor?

    public init(
        verifyProvider: @escaping @Sendable (AiProvider, StoredCredentialPayload?) async
            -> AiProviderVerificationResult,
        resolveAdapter: @escaping @Sendable (AiProvider, StoredCredentialPayload?) -> AiAdapterDescriptor?,
    ) {
        self.verifyProvider = verifyProvider
        self.resolveAdapter = resolveAdapter
    }
}

extension AiConnectionRuntimeClient {
    public static func live(session: URLSession = .shared) -> AiConnectionRuntimeClient {
        AiConnectionRuntimeClient(
            verifyProvider: { provider, credential in
                guard let credential else {
                    return .invalid(.missingCredential)
                }

                let secret: String = switch credential {
                case let .apiKey(payload): payload.secret
                case let .oauth(payload): payload.accessToken
                }

                guard !secret.isEmpty else {
                    return .invalid(.invalidAPIKey)
                }

                if provider == .chatgptCodex {
                    return .valid
                }

                return await Self.performSmokeRequest(
                    provider: provider,
                    secret: secret,
                    session: session,
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
