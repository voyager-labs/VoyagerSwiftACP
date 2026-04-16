import Foundation

/// Bridges settings-facing TCA dependency clients to the adapter layer for
/// provider verification. Plain service (not a TCA DependencyKey) — Foundation
/// clients own TCA integration; this provides adapter resolution and error mapping.
///
/// Provider mapping: `.openai` → OpenAIAdapter, `.chatgptCodex` → OpenAIAdapter,
/// `.anthropic` → AnthropicAdapter.
public struct AIConnectionRuntimeClient: Sendable {
    public var verifyProvider: @Sendable (AIProvider, StoredCredentialPayload?) async -> AIProviderVerificationResult
    public var resolveAdapter: @Sendable (AIProvider, StoredCredentialPayload?) -> AIAdapterDescriptor?

    public init(
        verifyProvider: @escaping @Sendable (AIProvider, StoredCredentialPayload?) async
            -> AIProviderVerificationResult,
        resolveAdapter: @escaping @Sendable (AIProvider, StoredCredentialPayload?) -> AIAdapterDescriptor?,
    ) {
        self.verifyProvider = verifyProvider
        self.resolveAdapter = resolveAdapter
    }
}

public struct AIAdapterDescriptor: Equatable, Sendable {
    public let provider: AIProvider
    public let providerID: AIProviderID
    public let adapterName: String
    public let capabilities: AIProviderCapability

    public init(
        provider: AIProvider,
        providerID: AIProviderID,
        adapterName: String,
        capabilities: AIProviderCapability,
    ) {
        self.provider = provider
        self.providerID = providerID
        self.adapterName = adapterName
        self.capabilities = capabilities
    }
}

// MARK: - Live Implementation

public extension AIConnectionRuntimeClient {
    static func live(
        httpClient: AIHTTPClient = AIHTTPClient(),
    ) -> AIConnectionRuntimeClient {
        AIConnectionRuntimeClient(
            verifyProvider: { provider, credential in
                guard let credential else {
                    return .invalid(.missingCredential)
                }

                let secret: String = switch credential {
                case let .apiKey(payload):
                    payload.secret
                case let .oauth(payload):
                    payload.accessToken
                }

                guard !secret.isEmpty else {
                    return .invalid(.invalidAPIKey)
                }

                switch provider {
                case .openai:
                    let config = OpenAIConfiguration(apiKey: secret, defaultModel: AIModelID("gpt-4o-mini"))
                    let adapter = OpenAIAdapter(configuration: config, httpClient: httpClient)
                    return await Self.performVerification(adapter: adapter)

                case .chatgptCodex:
                    let config = OpenAIConfiguration(
                        apiKey: secret,
                        defaultModel: AIModelID("gpt-4o-mini"),
                    )
                    let adapter = OpenAIAdapter(configuration: config, httpClient: httpClient)
                    return await Self.performVerification(adapter: adapter)

                case .anthropic:
                    let config = AnthropicConfiguration(
                        apiKey: secret,
                        defaultModel: AIModelID("claude-sonnet-4-20250514"),
                    )
                    let adapter = AnthropicAdapter(configuration: config, httpClient: httpClient)
                    return await Self.performVerification(adapter: adapter)
                }
            },
            resolveAdapter: { provider, credential in
                switch provider {
                case .openai:
                    guard credential != nil else { return nil }
                    return AIAdapterDescriptor(
                        provider: .openai,
                        providerID: .openai,
                        adapterName: "OpenAIAdapter",
                        capabilities: OpenAICapabilities.standard,
                    )

                case .chatgptCodex:
                    guard credential != nil else { return nil }
                    return AIAdapterDescriptor(
                        provider: .chatgptCodex,
                        providerID: .chatgptCodex,
                        adapterName: "OpenAIAdapter",
                        capabilities: OpenAICapabilities.standard,
                    )

                case .anthropic:
                    guard credential != nil else { return nil }
                    return AIAdapterDescriptor(
                        provider: .anthropic,
                        providerID: .anthropic,
                        adapterName: "AnthropicAdapter",
                        capabilities: AnthropicCapabilities.standard,
                    )
                }
            },
        )
    }

    private static func performVerification(
        adapter: some _AIAdapterVerifiable,
    ) async -> AIProviderVerificationResult {
        do {
            _ = try await adapter.generate(
                messages: [AIMessage.user("Hi")],
                model: nil,
                tools: [],
                temperature: nil,
                maxTokens: 5,
            )
            return .valid
        } catch let error as AIHTTPError {
            return mapHTTPError(error)
        } catch {
            return .invalid(.verificationFailed)
        }
    }

    /// Maps `AIHTTPError` to settings-facing `AIProviderVerificationResult`.
    /// No vendor-specific error types leak beyond this point.
    static func mapHTTPError(_ error: AIHTTPError) -> AIProviderVerificationResult {
        switch error {
        case let .httpError(statusCode, _):
            switch statusCode {
            case 401: .invalid(.invalidAPIKey)
            case 403: .invalid(.expired)
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
}

protocol _AIAdapterVerifiable: Sendable {
    func generate(
        messages: [AIMessage],
        model: AIModelID?,
        tools: [AIToolDefinition],
        temperature: Double?,
        maxTokens: Int?,
    ) async throws -> AIGenerationResult
}

extension OpenAIAdapter: _AIAdapterVerifiable {}
extension OpenAICompatibleAdapter: _AIAdapterVerifiable {}
extension AnthropicAdapter: _AIAdapterVerifiable {}
