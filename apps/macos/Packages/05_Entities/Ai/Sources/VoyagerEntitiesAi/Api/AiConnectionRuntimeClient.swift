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
        adapterName: String
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
        resolveAdapter: @escaping @Sendable (AiProvider, StoredCredentialPayload?) -> AiAdapterDescriptor?
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

                return await Self.performSmokeRequest(
                    provider: provider,
                    secret: secret,
                    session: session
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
            }
        )
    }

    private static func performSmokeRequest(
        provider: AiProvider,
        secret: String,
        session: URLSession
    ) async -> AiProviderVerificationResult {
        let url: String
        var request: URLRequest

        switch provider {
        case .openai, .chatgptCodex:
            url = "https://api.openai.com/v1/chat/completions"
            guard let requestURL = URL(string: url) else {
                return .invalid(.verificationFailed)
            }
            request = URLRequest(url: requestURL)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
            request.timeoutInterval = 30
            let body: [String: Any] = [
                "model": "gpt-4o-mini",
                "messages": [["role": "user", "content": "Hi"]],
                "max_tokens": 5,
            ]
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        case .anthropic:
            url = "https://api.anthropic.com/v1/messages"
            guard let requestURL = URL(string: url) else {
                return .invalid(.verificationFailed)
            }
            request = URLRequest(url: requestURL)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(secret, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            request.timeoutInterval = 30
            let body: [String: Any] = [
                "model": "claude-sonnet-4-20250514",
                "messages": [["role": "user", "content": "Hi"]],
                "max_tokens": 5,
            ]
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
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
            switch error.code {
            case .timedOut, .networkConnectionLost:
                return .networkError
            case .cancelled:
                return .invalid(.verificationFailed)
            default:
                return .networkError
            }
        } catch {
            return .networkError
        }
    }

    public static func mapHTTPError(_ error: AiHTTPError) -> AiProviderVerificationResult {
        switch error {
        case let .httpError(statusCode, body):
            switch statusCode {
            case 200 ... 299: .valid
            case 401: .invalid(.invalidAPIKey)
            case 403:
                if let code = extractErrorCode(from: body) {
                    switch code {
                    case "expired_api_key": .invalid(.expired)
                    default: .invalid(.invalidAPIKey)
                    }
                } else {
                    .invalid(.invalidAPIKey)
                }
            case 429: .invalid(.verificationFailed)
            case 500 ... 599: .networkError
            default: .invalid(.verificationFailed)
            }
        case .networkError: .networkError
        case .timeout: .networkError
        case .invalidURL: .invalid(.verificationFailed)
        case .cancelled: .invalid(.verificationFailed)
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
