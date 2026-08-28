import ComposableArchitecture
import Foundation

public enum AiProviderModelListError: Error, Equatable, Sendable {
    case missingCredential(AiProvider)
    case invalidCredential(provider: AiProvider, expected: ProviderAuthMethod)
    case unsupportedProvider(AiProvider)
    case invalidResponse(AiProvider)
    case httpError(provider: AiProvider, statusCode: Int, body: String)
    case networkError(provider: AiProvider, description: String)
}

public struct AiProviderModelListClient: Sendable {
    public var loadModels: @Sendable (AiProvider, StoredCredentialPayload?) async throws -> [AiProviderModel]

    nonisolated public init(
        loadModels: @escaping @Sendable (AiProvider, StoredCredentialPayload?) async throws -> [AiProviderModel],
    ) {
        self.loadModels = loadModels
    }
}

extension AiProviderModelListClient: DependencyKey {
    nonisolated public static var liveValue: AiProviderModelListClient {
        live()
    }

    nonisolated public static var testValue: AiProviderModelListClient {
        AiProviderModelListClient(
            loadModels: { provider, _ in
                throw AiProviderModelListError.unsupportedProvider(provider)
            },
        )
    }

    nonisolated public static var previewValue: AiProviderModelListClient {
        AiProviderModelListClient(
            loadModels: { provider, _ in
                throw AiProviderModelListError.unsupportedProvider(provider)
            },
        )
    }
}

public extension DependencyValues {
    nonisolated var aiProviderModelListClient: AiProviderModelListClient {
        get { self[AiProviderModelListClient.self] }
        set { self[AiProviderModelListClient.self] = newValue }
    }
}

public extension AiProviderModelListClient {
    nonisolated static func live(session: URLSession = .shared) -> AiProviderModelListClient {
        AiProviderModelListClient(
            loadModels: { provider, credential in
                switch provider {
                case .chatgptCodex:
                    let credential = try oauthCredential(for: provider, credential: credential)
                    let response = try await fetchCodexModels(credential: credential, session: session)
                    return response.models.filter(\.isListable).map { payload in
                        makeModel(
                            provider: provider,
                            rawModelID: payload.modelID,
                            displayName: Self.displayName(
                                provider: provider,
                                rawModelID: payload.modelID,
                                providerDisplayName: payload.displayName,
                            ),
                            thinkingCapability: payload.thinkingCapability ?? Self.unknownThinkingCapability,
                            supportsThinkingNone: payload.supportsThinkingNone,
                        )
                    }
                case .openai:
                    let secret = try secret(for: provider, credential: credential)
                    let response = try await fetchOpenAIModels(secret: secret, session: session)
                    return response.data.map { payload in
                        makeModel(
                            provider: provider,
                            rawModelID: payload.id,
                            displayName: Self.displayName(provider: provider, rawModelID: payload.id),
                            thinkingCapability: payload.thinkingCapability ?? Self.unknownThinkingCapability,
                            supportsThinkingNone: payload.supportsThinkingNone,
                        )
                    }
                case .anthropic:
                    let secret = try secret(for: provider, credential: credential)
                    let response = try await fetchAnthropicModels(secret: secret, session: session)
                    return response.data.map {
                        makeModel(
                            provider: provider,
                            rawModelID: $0.id,
                            displayName: Self.displayName(
                                provider: provider,
                                rawModelID: $0.id,
                                providerDisplayName: $0.displayName,
                            ),
                            thinkingCapability: $0.thinkingCapability ?? Self.unknownThinkingCapability,
                            supportsThinkingNone: $0.supportsThinkingNone,
                        )
                    }
                }
            },
        )
    }
}

extension AiProviderModelListClient {
    static let codexCompatibilityVersion = "0.146.0"

    static func secret(
        for provider: AiProvider,
        credential: StoredCredentialPayload?,
    ) throws -> String {
        guard let credential else {
            throw AiProviderModelListError.missingCredential(provider)
        }

        let secret: String
        switch (provider, credential) {
        case let (.openai, .apiKey(payload)), let (.anthropic, .apiKey(payload)):
            secret = payload.secret
        case (.openai, .oauth), (.anthropic, .oauth):
            throw AiProviderModelListError.invalidCredential(provider: provider, expected: .apiKey)
        case (.chatgptCodex, _):
            throw AiProviderModelListError.unsupportedProvider(provider)
        }

        guard !secret.isEmpty else {
            throw AiProviderModelListError.missingCredential(provider)
        }

        return secret
    }

    static func oauthCredential(
        for provider: AiProvider,
        credential: StoredCredentialPayload?,
    ) throws -> OAuthCredentialFile {
        guard let credential else {
            throw AiProviderModelListError.missingCredential(provider)
        }

        switch credential {
        case let .oauth(payload):
            guard !payload.accessToken.isEmpty else {
                throw AiProviderModelListError.missingCredential(provider)
            }
            return payload
        case .apiKey:
            throw AiProviderModelListError.invalidCredential(provider: provider, expected: .oauth)
        }
    }

    static func providerDisplayName(for provider: AiProvider) -> String {
        ProviderDescriptor.descriptor(for: provider)?.displayName ?? provider.rawValue
    }

    static var unknownThinkingCapability: AiModelThinkingCapability {
        .unknown(
            reason: AiThinkingUnavailableReason(
                message: "Thinking capability metadata was not provided by the model API.",
            ),
        )
    }

    static func displayName(
        provider: AiProvider,
        rawModelID: String,
        providerDisplayName: String? = nil,
    ) -> String {
        AiModelDisplayNameFormatter.displayName(
            provider: provider,
            rawModelID: rawModelID,
            providerDisplayName: providerDisplayName,
        )
    }

    static func makeModel(
        provider: AiProvider,
        rawModelID: String,
        displayName: String,
        thinkingCapability: AiModelThinkingCapability,
        supportsThinkingNone: Bool = false,
    ) -> AiProviderModel {
        AiProviderModel(
            id: AiModelHandle(provider: provider, rawValue: rawModelID),
            provider: provider,
            rawModelID: rawModelID,
            displayName: displayName,
            providerDisplayName: providerDisplayName(for: provider),
            thinkingCapability: thinkingCapability,
            supportsThinkingNone: supportsThinkingNone,
            unavailableReason: nil,
        )
    }

    static func fetchCodexModels(
        credential: OAuthCredentialFile,
        session: URLSession,
    ) async throws -> CodexModelsResponse {
        let clientVersion = codexCompatibilityVersion
        let request = try makeRequest(
            url: "https://chatgpt.com/backend-api/codex/models?client_version=\(clientVersion)",
            provider: .chatgptCodex,
            configure: { request in
                request.setValue("Bearer \(credential.accessToken)", forHTTPHeaderField: "Authorization")
                request.setValue("codex_cli_rs", forHTTPHeaderField: "originator")
                request.setValue(codexUserAgent(clientVersion: clientVersion), forHTTPHeaderField: "User-Agent")
                request.setValue(clientVersion, forHTTPHeaderField: "version")
                if let accountID = credential.chatGPTAccountId, !accountID.isEmpty {
                    request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-ID")
                }
            },
        )
        let data = try await fetchData(for: .chatgptCodex, request: request, session: session)

        do {
            return try JSONDecoder().decode(CodexModelsResponse.self, from: data)
        } catch {
            throw AiProviderModelListError.invalidResponse(.chatgptCodex)
        }
    }

    static func codexUserAgent(clientVersion: String) -> String {
        let operatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion
        let osVersion = [
            operatingSystemVersion.majorVersion,
            operatingSystemVersion.minorVersion,
            operatingSystemVersion.patchVersion,
        ]
        .map(String.init)
        .joined(separator: ".")
        return "codex_cli_rs/\(clientVersion) (macOS \(osVersion); \(architectureName()))"
    }

    static func architectureName() -> String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "unknown"
        #endif
    }

    static func fetchOpenAIModels(
        secret: String,
        session: URLSession,
    ) async throws -> OpenAIModelsResponse {
        let request = try makeRequest(
            url: "https://api.openai.com/v1/models",
            provider: .openai,
            configure: { request in
                request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
            },
        )
        let data = try await fetchData(for: .openai, request: request, session: session)

        do {
            return try JSONDecoder().decode(OpenAIModelsResponse.self, from: data)
        } catch {
            throw AiProviderModelListError.invalidResponse(.openai)
        }
    }

    static func fetchAnthropicModels(
        secret: String,
        session: URLSession,
    ) async throws -> AnthropicModelsResponse {
        let request = try makeRequest(
            url: "https://api.anthropic.com/v1/models",
            provider: .anthropic,
            configure: { request in
                request.setValue(secret, forHTTPHeaderField: "x-api-key")
                request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            },
        )
        let data = try await fetchData(for: .anthropic, request: request, session: session)

        do {
            return try JSONDecoder().decode(AnthropicModelsResponse.self, from: data)
        } catch {
            throw AiProviderModelListError.invalidResponse(.anthropic)
        }
    }

    static func makeRequest(
        url: String,
        provider: AiProvider,
        configure: (inout URLRequest) -> Void,
    ) throws -> URLRequest {
        guard let requestURL = URL(string: url) else {
            throw AiProviderModelListError.invalidResponse(provider)
        }

        var request = URLRequest(url: requestURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        configure(&request)
        return request
    }

    static func fetchData(
        for provider: AiProvider,
        request: URLRequest,
        session: URLSession,
    ) async throws -> Data {
        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw AiProviderModelListError.networkError(
                    provider: provider,
                    description: "Non-HTTP response",
                )
            }

            guard (200 ... 299).contains(httpResponse.statusCode) else {
                let body = String(data: data, encoding: .utf8) ?? ""
                throw AiProviderModelListError.httpError(
                    provider: provider,
                    statusCode: httpResponse.statusCode,
                    body: body,
                )
            }

            return data
        } catch let error as AiProviderModelListError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch let error as URLError {
            throw AiProviderModelListError.networkError(
                provider: provider,
                description: error.localizedDescription,
            )
        } catch {
            throw AiProviderModelListError.networkError(
                provider: provider,
                description: error.localizedDescription,
            )
        }
    }
}
