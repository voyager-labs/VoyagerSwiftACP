struct OpenAIModelsResponse: Decodable, Sendable {
    let data: [OpenAIModelPayload]
}

struct OpenAIModelPayload: Decodable, Sendable {
    let id: String
}

struct AnthropicModelsResponse: Decodable, Sendable {
    let data: [AnthropicModelPayload]
}

struct AnthropicModelPayload: Decodable, Sendable {
    let id: String
    let displayName: String?
    let capabilities: AnthropicModelCapabilities?

    var thinkingCapability: AiModelThinkingCapability? {
        capabilities?.thinkingCapability
    }

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case capabilities
    }
}

struct AnthropicModelCapabilities: Decodable, Sendable {
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
                (max, AiThinkingEffort.max)
            ]
            .compactMap { support, effort in support?.supported == true ? effort : nil }
        }
    }
}

struct CodexModelsResponse: Decodable, Sendable {
    let models: [CodexModelPayload]

    enum CodingKeys: String, CodingKey {
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

struct CodexModelPayload: Decodable, Sendable {
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
                .supportedReasoningEffortsCamel
            ]
        )
        supportedReasoningLevels = decodedEfforts

        defaultReasoningLevel = try container.decodeFirstPresentEffort(
            forKeys: [
                .defaultReasoningLevel,
                .defaultReasoningEffort,
                .defaultReasoningEffortCamel
            ]
        )
    }
}

struct CodexReasoningEffortPayload: Decodable, Sendable {
    let effortValue: AiThinkingEffort?

    enum CodingKeys: String, CodingKey {
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

extension KeyedDecodingContainer where Key == CodexModelPayload.CodingKeys {
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

extension Array where Element: Hashable {
    func uniquePreservingOrder() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
