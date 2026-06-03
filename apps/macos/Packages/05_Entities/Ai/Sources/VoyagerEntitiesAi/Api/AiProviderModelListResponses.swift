struct OpenAIModelsResponse: Decodable, Sendable {
    let data: [OpenAIModelPayload]
}

struct OpenAIModelPayload: Decodable, Sendable {
    let id: String
    let supportedReasoningEfforts: [OpenAIReasoningEffortPayload]
    let defaultReasoningEffort: AiThinkingEffort?

    var supportsThinkingNone: Bool {
        if !supportedReasoningEfforts.isEmpty {
            return supportedReasoningEfforts.contains(where: \.supportsNone)
        }
        return OpenAIReasoningCapability.inferredSupportsNone(for: id)
    }

    var thinkingCapability: AiModelThinkingCapability? {
        let decodedEfforts = supportedReasoningEfforts.compactMap(\.effortValue).uniquePreservingOrder()
        if !decodedEfforts.isEmpty {
            return .effort(
                values: decodedEfforts,
                defaultValue: defaultReasoningEffort.flatMap { decodedEfforts.contains($0) ? $0 : nil },
            )
        }

        return OpenAIReasoningCapability.inferred(for: id)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case supportedReasoningEfforts = "supported_reasoning_efforts"
        case supportedReasoningEffortsCamel = "supportedReasoningEfforts"
        case reasoningEfforts = "reasoning_efforts"
        case reasoningEffortsCamel = "reasoningEfforts"
        case defaultReasoningEffort = "default_reasoning_effort"
        case defaultReasoningEffortCamel = "defaultReasoningEffort"
        case reasoningEffort = "reasoning_effort"
        case reasoningEffortCamel = "reasoningEffort"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        supportedReasoningEfforts = try container.decodeFirstPresentOpenAIEfforts(
            forKeys: [
                .supportedReasoningEfforts,
                .supportedReasoningEffortsCamel,
                .reasoningEfforts,
                .reasoningEffortsCamel
            ],
        )
        defaultReasoningEffort = try container.decodeFirstPresentOpenAIEffort(
            forKeys: [
                .defaultReasoningEffort,
                .defaultReasoningEffortCamel,
                .reasoningEffort,
                .reasoningEffortCamel
            ],
        )
    }
}

struct OpenAIReasoningEffortPayload: Decodable, Sendable {
    let effortValue: AiThinkingEffort?
    let supportsNone: Bool

    enum CodingKeys: String, CodingKey {
        case effort
        case reasoningEffort = "reasoning_effort"
        case reasoningEffortCamel = "reasoningEffort"
    }

    init(from decoder: Decoder) throws {
        if let singleValue = try? decoder.singleValueContainer(),
           let rawEffort = try? singleValue.decode(String.self) {
            supportsNone = rawEffort.lowercased() == "none"
            effortValue = AiThinkingEffort(rawValue: rawEffort)
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        for key in [CodingKeys.effort, .reasoningEffort, .reasoningEffortCamel] {
            if let rawEffort = try container.decodeIfPresent(String.self, forKey: key) {
                supportsNone = rawEffort.lowercased() == "none"
                effortValue = AiThinkingEffort(rawValue: rawEffort)
                return
            }
        }
        supportsNone = false
        effortValue = nil
    }
}

enum OpenAIReasoningCapability {
    static func inferredSupportsNone(for modelID: String) -> Bool {
        let normalizedID = modelID.lowercased()
        return normalizedID.hasPrefix("gpt-5.1") || normalizedID.hasPrefix("gpt-5.5")
    }

    static func inferred(for modelID: String) -> AiModelThinkingCapability? {
        let normalizedID = modelID.lowercased()

        if normalizedID.hasPrefix("gpt-5-pro") {
            return .effort(values: [.high], defaultValue: .high)
        }

        if normalizedID.hasPrefix("gpt-5.1") {
            return .effort(values: [.low, .medium, .high], defaultValue: nil)
        }

        if normalizedID.hasPrefix("gpt-5") || isOReasoningModel(normalizedID) {
            return .effort(values: [.minimal, .low, .medium, .high, .xhigh], defaultValue: .medium)
        }

        return nil
    }

    private static func isOReasoningModel(_ modelID: String) -> Bool {
        modelID.hasPrefix("o1")
            || modelID.hasPrefix("o3")
            || modelID.hasPrefix("o4")
    }
}

struct AnthropicModelsResponse: Decodable, Sendable {
    let data: [AnthropicModelPayload]
}

struct AnthropicModelPayload: Decodable, Sendable {
    let id: String
    let displayName: String?
    let capabilities: AnthropicModelCapabilities?

    var supportsThinkingNone: Bool {
        capabilities?.supportsThinkingNone ?? false
    }

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

    var supportsThinkingNone: Bool {
        thinking?.supported == true && thinking?.types?.enabled?.supported == true
    }

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

    var supportsThinkingNone: Bool {
        supportedReasoningLevels.contains(where: \.supportsNone)
            || OpenAIReasoningCapability.inferredSupportsNone(for: modelID)
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
            ],
        )
        supportedReasoningLevels = decodedEfforts

        defaultReasoningLevel = try container.decodeFirstPresentEffort(
            forKeys: [
                .defaultReasoningLevel,
                .defaultReasoningEffort,
                .defaultReasoningEffortCamel
            ],
        )
    }
}

struct CodexReasoningEffortPayload: Decodable, Sendable {
    let effortValue: AiThinkingEffort?
    let supportsNone: Bool

    enum CodingKeys: String, CodingKey {
        case effort
        case reasoningEffort = "reasoning_effort"
        case reasoningEffortCamel = "reasoningEffort"
    }

    init(from decoder: Decoder) throws {
        if let singleValue = try? decoder.singleValueContainer(),
           let rawEffort = try? singleValue.decode(String.self) {
            supportsNone = rawEffort.lowercased() == "none"
            effortValue = AiThinkingEffort(rawValue: rawEffort)
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        for key in [CodingKeys.effort, .reasoningEffort, .reasoningEffortCamel] {
            if let rawEffort = try container.decodeIfPresent(String.self, forKey: key) {
                supportsNone = rawEffort.lowercased() == "none"
                effortValue = AiThinkingEffort(rawValue: rawEffort)
                return
            }
        }
        supportsNone = false
        effortValue = nil
    }
}

extension KeyedDecodingContainer where Key == OpenAIModelPayload.CodingKeys {
    func decodeFirstPresentOpenAIEfforts(forKeys keys: [Key]) throws -> [OpenAIReasoningEffortPayload] {
        for key in keys {
            if let values = try decodeIfPresent([OpenAIReasoningEffortPayload].self, forKey: key) {
                return values
            }
        }
        return []
    }

    func decodeFirstPresentOpenAIEffort(forKeys keys: [Key]) throws -> AiThinkingEffort? {
        for key in keys {
            if let value = try decodeIfPresent(String.self, forKey: key) {
                return AiThinkingEffort(rawValue: value)
            }
        }
        return nil
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
                debugDescription: "Codex model payload is missing a model identifier.",
            ),
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
