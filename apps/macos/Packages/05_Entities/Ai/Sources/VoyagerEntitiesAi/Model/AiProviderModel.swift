import Foundation

public struct AiModelUnavailableReason: Equatable, Sendable, Hashable, Codable {
    public let message: String

    public init(message: String) {
        self.message = message
    }
}

public struct AiProviderModel: Equatable, Sendable, Hashable, Codable, Identifiable {
    public let id: AiModelHandle
    public let provider: AiProvider
    public let rawModelID: String
    public let displayName: String
    public let providerDisplayName: String
    public let thinkingCapability: AiModelThinkingCapability
    public let unavailableReason: AiModelUnavailableReason?

    public init(
        id: AiModelHandle,
        provider: AiProvider,
        rawModelID: String,
        displayName: String,
        providerDisplayName: String,
        thinkingCapability: AiModelThinkingCapability,
        unavailableReason: AiModelUnavailableReason? = nil
    ) {
        self.id = id
        self.provider = provider
        self.rawModelID = rawModelID
        self.displayName = displayName
        self.providerDisplayName = providerDisplayName
        self.thinkingCapability = thinkingCapability
        self.unavailableReason = unavailableReason
    }
}
