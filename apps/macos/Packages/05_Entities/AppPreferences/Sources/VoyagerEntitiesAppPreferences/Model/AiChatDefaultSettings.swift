import Foundation

public struct PersistedAIProviderSelection: Codable, Equatable, Hashable, Sendable {
    public var rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public struct PersistedAIModelSelection: Codable, Equatable, Hashable, Sendable {
    public var providerRawValue: String
    public var modelRawValue: String

    public init(providerRawValue: String, modelRawValue: String) {
        self.providerRawValue = providerRawValue
        self.modelRawValue = modelRawValue
    }
}

public enum PersistedAIThinkingSelection: Codable, Equatable, Hashable, Sendable {
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

public struct AiChatDefaultSettings: Codable, Equatable, Sendable {
    public static let `default` = AiChatDefaultSettings(
        provider: nil,
        model: nil,
        thinking: .providerDefault,
    )

    public var provider: PersistedAIProviderSelection?
    public var model: PersistedAIModelSelection?
    public var thinking: PersistedAIThinkingSelection

    public init(
        provider: PersistedAIProviderSelection?,
        model: PersistedAIModelSelection?,
        thinking: PersistedAIThinkingSelection,
    ) {
        self.provider = provider
        self.model = model
        self.thinking = thinking
    }
}
