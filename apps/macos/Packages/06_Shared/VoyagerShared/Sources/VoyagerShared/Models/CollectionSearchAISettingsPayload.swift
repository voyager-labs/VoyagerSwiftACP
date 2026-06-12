import Foundation

public nonisolated struct CollectionSearchAISettingsPayload: Codable, Equatable, Sendable {
    public let provider: CollectionSearchAIProviderPreferencePayload
    public let model: CollectionSearchAIModelPreferencePayload
    public let thinking: CollectionSearchAIThinkingPreferencePayload

    public init(
        provider: CollectionSearchAIProviderPreferencePayload,
        model: CollectionSearchAIModelPreferencePayload,
        thinking: CollectionSearchAIThinkingPreferencePayload,
    ) {
        self.provider = provider
        self.model = model
        self.thinking = thinking
    }
}

public nonisolated enum CollectionSearchAIProviderPreferencePayload: Equatable, Hashable, Sendable, Codable {
    case auto
    case specific(String)

    private enum CodingKeys: String, CodingKey {
        case kind
        case provider
    }

    private enum Kind: String, Codable {
        case auto
        case specific
    }

    public var rawValue: String? {
        switch self {
        case .auto:
            nil
        case let .specific(provider):
            provider
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .auto:
            self = .auto
        case .specific:
            self = try .specific(container.decode(String.self, forKey: .provider))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .auto:
            try container.encode(Kind.auto, forKey: .kind)
        case let .specific(provider):
            try container.encode(Kind.specific, forKey: .kind)
            try container.encode(provider, forKey: .provider)
        }
    }
}

public nonisolated enum CollectionSearchAIModelPreferencePayload: Equatable, Hashable, Sendable, Codable {
    case auto
    case specific(provider: String, model: String)

    private enum CodingKeys: String, CodingKey {
        case kind
        case provider
        case model
    }

    private enum Kind: String, Codable {
        case auto
        case specific
    }

    public var providerRawValue: String? {
        switch self {
        case .auto:
            nil
        case let .specific(provider, _):
            provider
        }
    }

    public var modelRawValue: String? {
        switch self {
        case .auto:
            nil
        case let .specific(_, model):
            model
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .auto:
            self = .auto
        case .specific:
            self = try .specific(
                provider: container.decode(String.self, forKey: .provider),
                model: container.decode(String.self, forKey: .model),
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .auto:
            try container.encode(Kind.auto, forKey: .kind)
        case let .specific(provider, model):
            try container.encode(Kind.specific, forKey: .kind)
            try container.encode(provider, forKey: .provider)
            try container.encode(model, forKey: .model)
        }
    }
}

public nonisolated enum CollectionSearchAIThinkingPreferencePayload: Equatable, Hashable, Sendable, Codable {
    case providerDefault
    case none
    case effort(String)
    case tokenBudget(Int)

    private enum CodingKeys: String, CodingKey {
        case kind
        case value
    }

    private enum Kind: String, Codable {
        case providerDefault
        case none
        case effort
        case tokenBudget
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .providerDefault:
            self = .providerDefault
        case .none:
            self = .none
        case .effort:
            self = try .effort(container.decode(String.self, forKey: .value))
        case .tokenBudget:
            self = try .tokenBudget(container.decode(Int.self, forKey: .value))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .providerDefault:
            try container.encode(Kind.providerDefault, forKey: .kind)
        case .none:
            try container.encode(Kind.none, forKey: .kind)
        case let .effort(value):
            try container.encode(Kind.effort, forKey: .kind)
            try container.encode(value, forKey: .value)
        case let .tokenBudget(value):
            try container.encode(Kind.tokenBudget, forKey: .kind)
            try container.encode(value, forKey: .value)
        }
    }
}
