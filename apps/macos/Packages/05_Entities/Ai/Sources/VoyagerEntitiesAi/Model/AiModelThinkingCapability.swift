import Foundation

public struct AiThinkingUnavailableReason: Equatable, Sendable, Hashable, Codable {
    public let message: String

    public init(message: String) {
        self.message = message
    }
}

public enum AiThinkingEffort: String, Equatable, Sendable, CaseIterable, Codable {
    case minimal
    case low
    case medium
    case high
    case xhigh
    case max
}

public enum AiThinkingSelection: Equatable, Sendable, Hashable, Codable {
    case effort(AiThinkingEffort)
    case tokenBudget(Int)
}

public enum AiModelThinkingCapability: Equatable, Sendable, Hashable, Codable {
    case unsupported(reason: AiThinkingUnavailableReason)
    case unknown(reason: AiThinkingUnavailableReason)
    case effort(values: [AiThinkingEffort], defaultValue: AiThinkingEffort?)
    case tokenBudget(min: Int, max: Int, defaultValue: Int?)
    case adaptive(effortValues: [AiThinkingEffort], defaultValue: AiThinkingEffort?)
}
