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

    public nonisolated init(
        loadModels: @escaping @Sendable (AiProvider, StoredCredentialPayload?) async throws -> [AiProviderModel]
    ) {
        self.loadModels = loadModels
    }
}

extension AiProviderModelListClient: DependencyKey {
    public nonisolated static var liveValue: AiProviderModelListClient {
        live()
    }

    public nonisolated static var testValue: AiProviderModelListClient {
        AiProviderModelListClient(
            loadModels: { provider, _ in
                throw AiProviderModelListError.unsupportedProvider(provider)
            }
        )
    }

    public nonisolated static var previewValue: AiProviderModelListClient {
        AiProviderModelListClient(
            loadModels: { provider, _ in
                throw AiProviderModelListError.unsupportedProvider(provider)
            }
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
                            displayName: payload.displayName ?? payload.modelID,
                            thinkingCapability: payload.thinkingCapability ?? Self.unknownThinkingCapability
                        )
                    }
                case .openai:
                    let secret = try secret(for: provider, credential: credential)
                    let response = try await fetchOpenAIModels(secret: secret, session: session)
                    return response.data.map {
                        makeModel(
                            provider: provider,
                            rawModelID: $0.id,
                            displayName: $0.id,
                            thinkingCapability: Self.unknownThinkingCapability
                        )
                    }
                case .anthropic:
                    let secret = try secret(for: provider, credential: credential)
                    let response = try await fetchAnthropicModels(secret: secret, session: session)
                    return response.data.map {
                        makeModel(
                            provider: provider,
                            rawModelID: $0.id,
                            displayName: $0.displayName ?? $0.id,
                            thinkingCapability: $0.thinkingCapability ?? Self.unknownThinkingCapability
                        )
                    }
                }
            }
        )
    }
}

private extension AiProviderModelListClient {
    static func secret(
        for provider: AiProvider,
        credential: StoredCredentialPayload?
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
        credential: StoredCredentialPayload?
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
        .unknown(reason: AiThinkingUnavailableReason(message: "Thinking capability metadata was not provided by the model API."))
    }

    static func makeModel(
        provider: AiProvider,
        rawModelID: String,
        displayName: String,
        thinkingCapability: AiModelThinkingCapability
    ) -> AiProviderModel {
        AiProviderModel(
            id: AiModelHandle(provider: provider, rawValue: rawModelID),
            provider: provider,
            rawModelID: rawModelID,
            displayName: displayName,
            providerDisplayName: providerDisplayName(for: provider),
            thinkingCapability: thinkingCapability,
            unavailableReason: nil
        )
    }

    static func fetchCodexModels(
        credential: OAuthCredentialFile,
        session: URLSession
    ) async throws -> CodexModelsResponse {
        let request = try makeRequest(
            url: "https://chatgpt.com/backend-api/codex/models?client_version=\(codexClientVersion())",
            provider: .chatgptCodex,
            configure: { request in
                request.setValue("Bearer \(credential.accessToken)", forHTTPHeaderField: "Authorization")
                request.setValue("codex_cli_rs", forHTTPHeaderField: "originator")
                request.setValue("codex_cli_rs/\(codexClientVersion()) (macOS)", forHTTPHeaderField: "User-Agent")
                request.setValue(codexClientVersion(), forHTTPHeaderField: "version")
                if let accountID = credential.chatGPTAccountId, !accountID.isEmpty {
                    request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-ID")
                }
            }
        )
        let data = try await fetchData(for: .chatgptCodex, request: request, session: session)

        do {
            return try JSONDecoder().decode(CodexModelsResponse.self, from: data)
        } catch {
            throw AiProviderModelListError.invalidResponse(.chatgptCodex)
        }
    }

    static func codexClientVersion() -> String {
        let candidateBundles = [Bundle.main, Bundle(identifier: "fm.voyager.Voyager")].compactMap { $0 }
        for bundle in candidateBundles {
            if let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
               !version.isEmpty
            {
                return version
            }
        }
        return "0.0.0"
    }


    static func fetchOpenAIModels(
        secret: String,
        session: URLSession
    ) async throws -> OpenAIModelsResponse {
        let request = try makeRequest(
            url: "https://api.openai.com/v1/models",
            provider: .openai,
            configure: { request in
                request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
            }
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
        session: URLSession
    ) async throws -> AnthropicModelsResponse {
        let request = try makeRequest(
            url: "https://api.anthropic.com/v1/models",
            provider: .anthropic,
            configure: { request in
                request.setValue(secret, forHTTPHeaderField: "x-api-key")
                request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            }
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
        configure: (inout URLRequest) -> Void
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
        session: URLSession
    ) async throws -> Data {
        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw AiProviderModelListError.networkError(
                    provider: provider,
                    description: "Non-HTTP response"
                )
            }

            guard (200 ... 299).contains(httpResponse.statusCode) else {
                let body = String(data: data, encoding: .utf8) ?? ""
                throw AiProviderModelListError.httpError(
                    provider: provider,
                    statusCode: httpResponse.statusCode,
                    body: body
                )
            }

            return data
        } catch let error as AiProviderModelListError {
            throw error
        } catch let error as URLError {
            throw AiProviderModelListError.networkError(
                provider: provider,
                description: error.localizedDescription
            )
        } catch {
            throw AiProviderModelListError.networkError(
                provider: provider,
                description: error.localizedDescription
            )
        }
    }
}

private struct OpenAIModelsResponse: Decodable, Sendable {
    let data: [OpenAIModelPayload]
}

private struct OpenAIModelPayload: Decodable, Sendable {
    let id: String
}

private struct AnthropicModelsResponse: Decodable, Sendable {
    let data: [AnthropicModelPayload]
}

private struct AnthropicModelPayload: Decodable, Sendable {
    let id: String
    let displayName: String?
    let capabilities: AnthropicModelCapabilities?

    var thinkingCapability: AiModelThinkingCapability? {
        capabilities?.thinkingCapability
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case capabilities
    }
}

private struct AnthropicModelCapabilities: Decodable, Sendable {
    let thinking: Thinking?
    let effort: Effort?

    var thinkingCapability: AiModelThinkingCapability? {
        guard thinking?.supported == true else { return nil }
        let effortValues = effort?.supportedValues ?? []
        if effort?.supported == true, !effortValues.isEmpty {
            return .effort(values: effortValues, defaultValue: nil)
        }
        if thinking?.types?.adaptive?.supported == true {
            return .adaptive(effortValues: effortValues, defaultValue: nil)
        }
        return nil
    }

    struct Thinking: Decodable, Sendable {
        let supported: Bool
        let types: Types?
    }

    struct Types: Decodable, Sendable {
        let adaptive: Support?
        let enabled: Support?
    }

    struct Support: Decodable, Sendable {
        let supported: Bool
    }

    struct Effort: Decodable, Sendable {
        let supported: Bool
        let low: Support?
        let medium: Support?
        let high: Support?
        let xhigh: Support?
        let max: Support?

        var supportedValues: [AiThinkingEffort] {
            [
                (low, AiThinkingEffort.low),
                (medium, AiThinkingEffort.medium),
                (high, AiThinkingEffort.high),
                (xhigh, AiThinkingEffort.xhigh),
                (max, AiThinkingEffort.max),
            ]
                .compactMap { support, effort in support?.supported == true ? effort : nil }
        }
    }
}


private struct CodexModelsResponse: Decodable, Sendable {
    let models: [CodexModelPayload]

    private enum CodingKeys: String, CodingKey {
        case models
        case data
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        models = try container.decodeIfPresent([CodexModelPayload].self, forKey: .models)
            ?? container.decodeIfPresent([CodexModelPayload].self, forKey: .data)
            ?? []
    }
}

private struct CodexModelPayload: Decodable, Sendable {
    let modelID: String
    let displayName: String?
    let visibility: String?
    let hidden: Bool
    let supportedReasoningLevels: [CodexReasoningEffortPayload]
    let defaultReasoningLevel: AiThinkingEffort?

    var isListable: Bool {
        !hidden && visibility?.lowercased() != "none"
    }

    var thinkingCapability: AiModelThinkingCapability? {
        let efforts = supportedReasoningLevels.compactMap(\.effortValue).uniquePreservingOrder()
        guard !efforts.isEmpty else { return nil }
        let defaultValue = defaultReasoningLevel.flatMap { efforts.contains($0) ? $0 : nil } ?? efforts.first ?? .medium
        return .effort(values: efforts, defaultValue: defaultValue)
    }

    enum CodingKeys: String, CodingKey {
        case slug
        case id
        case model
        case name
        case displayName
        case displayNameSnake = "display_name"
        case hidden
        case visibility
        case supportedReasoningLevels = "supported_reasoning_levels"
        case supportedReasoningEfforts = "supported_reasoning_efforts"
        case supportedReasoningEffortsCamel = "supportedReasoningEfforts"
        case defaultReasoningLevel = "default_reasoning_level"
        case defaultReasoningEffort = "default_reasoning_effort"
        case defaultReasoningEffortCamel = "defaultReasoningEffort"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        modelID = try container.decodeFirstPresentString(forKeys: [.slug, .model, .id, .name])
        displayName = try container.decodeFirstPresentStringIfPresent(forKeys: [.displayNameSnake, .displayName])
        let decodedVisibility = try container.decodeIfPresent(String.self, forKey: .visibility)
        hidden = try container.decodeIfPresent(Bool.self, forKey: .hidden) ?? false
        visibility = decodedVisibility
        let decodedEfforts = try container.decodeFirstPresentEfforts(
            forKeys: [
                .supportedReasoningLevels,
                .supportedReasoningEfforts,
                .supportedReasoningEffortsCamel,
            ]
        )
        supportedReasoningLevels = decodedEfforts

        defaultReasoningLevel = try container.decodeFirstPresentEffort(
            forKeys: [
                .defaultReasoningLevel,
                .defaultReasoningEffort,
                .defaultReasoningEffortCamel,
            ]
        )
    }
}

private struct CodexReasoningEffortPayload: Decodable, Sendable {
    let effortValue: AiThinkingEffort?

    private enum CodingKeys: String, CodingKey {
        case effort
        case reasoningEffort = "reasoning_effort"
        case reasoningEffortCamel = "reasoningEffort"
    }

    init(from decoder: Decoder) throws {
        if let singleValue = try? decoder.singleValueContainer(),
           let rawEffort = try? singleValue.decode(AiThinkingEffort.self) {
            effortValue = rawEffort
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        effortValue = try container.decodeIfPresent(AiThinkingEffort.self, forKey: .effort)
            ?? container.decodeIfPresent(AiThinkingEffort.self, forKey: .reasoningEffort)
            ?? container.decodeIfPresent(AiThinkingEffort.self, forKey: .reasoningEffortCamel)
    }
}

private extension KeyedDecodingContainer where Key == CodexModelPayload.CodingKeys {
    func decodeFirstPresentString(forKeys keys: [Key]) throws -> String {
        for key in keys {
            if let value = try decodeIfPresent(String.self, forKey: key), !value.isEmpty {
                return value
            }
        }
        throw DecodingError.keyNotFound(
            keys[0],
            DecodingError.Context(
                codingPath: codingPath,
                debugDescription: "Codex model payload is missing a model identifier."
            )
        )
    }

    func decodeFirstPresentStringIfPresent(forKeys keys: [Key]) throws -> String? {
        for key in keys {
            if let value = try decodeIfPresent(String.self, forKey: key), !value.isEmpty {
                return value
            }
        }
        return nil
    }

    func decodeFirstPresentEfforts(forKeys keys: [Key]) throws -> [CodexReasoningEffortPayload] {
        for key in keys {
            if let values = try decodeIfPresent([CodexReasoningEffortPayload].self, forKey: key) {
                return values
            }
        }
        return []
    }

    func decodeFirstPresentEffort(forKeys keys: [Key]) throws -> AiThinkingEffort? {
        for key in keys {
            if let value = try decodeIfPresent(AiThinkingEffort.self, forKey: key) {
                return value
            }
        }
        return nil
    }
}

private extension Array where Element: Hashable {
    func uniquePreservingOrder() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
