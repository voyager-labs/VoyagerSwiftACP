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
    public let supportsThinkingNone: Bool
    public let unavailableReason: AiModelUnavailableReason?

    public init(
        id: AiModelHandle,
        provider: AiProvider,
        rawModelID: String,
        displayName: String,
        providerDisplayName: String,
        thinkingCapability: AiModelThinkingCapability,
        supportsThinkingNone: Bool = false,
        unavailableReason: AiModelUnavailableReason? = nil,
    ) {
        self.id = id
        self.provider = provider
        self.rawModelID = rawModelID
        self.displayName = displayName
        self.providerDisplayName = providerDisplayName
        self.thinkingCapability = thinkingCapability
        self.supportsThinkingNone = supportsThinkingNone
        self.unavailableReason = unavailableReason
    }
}

public enum AiModelDisplayNameFormatter {
    private enum ClaudeFamily: String {
        case opus
        case sonnet
        case haiku

        var displayName: String {
            switch self {
            case .opus:
                "Opus"
            case .sonnet:
                "Sonnet"
            case .haiku:
                "Haiku"
            }
        }
    }

    public static func displayName(
        provider: AiProvider,
        rawModelID: String,
        providerDisplayName: String? = nil,
    ) -> String {
        if let canonicalName = canonicalName(for: rawModelID, provider: provider) {
            return canonicalName
        }

        if let trimmedDisplayName = providerDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !trimmedDisplayName.isEmpty {
            return trimmedDisplayName
        }

        return rawModelID
    }

    private static func canonicalName(for rawModelID: String, provider: AiProvider) -> String? {
        switch provider {
        case .chatgptCodex, .openai:
            openAIModelName(for: rawModelID)
        case .anthropic:
            anthropicModelName(for: rawModelID)
        }
    }

    private static func openAIModelName(for rawModelID: String) -> String? {
        let normalizedID = rawModelID.lowercased()

        if normalizedID.hasPrefix("gpt-") {
            return gptModelName(for: normalizedID)
        }

        if isOSeriesModelID(normalizedID) {
            return normalizedID
        }

        return nil
    }

    private static func gptModelName(for normalizedID: String) -> String {
        let parts = normalizedID.split(separator: "-").map(String.init)
        guard parts.first == "gpt" else { return normalizedID }
        let suffix = parts.dropFirst()

        guard let version = suffix.first else { return "GPT" }
        let variants = suffix.dropFirst().map(formatOpenAIVariant)
        return (["GPT-\(version)"] + variants).joined(separator: " ")
    }

    private static func formatOpenAIVariant(_ value: String) -> String {
        value.split(separator: "_")
            .flatMap { $0.split(separator: "-") }
            .map { component in
                switch component {
                case "api", "tts":
                    component.uppercased()
                default:
                    component.prefix(1).uppercased() + component.dropFirst()
                }
            }
            .joined(separator: " ")
    }

    private static func isOSeriesModelID(_ normalizedID: String) -> Bool {
        guard normalizedID.first == "o" else { return false }
        let suffix = normalizedID.dropFirst()
        return suffix.first?.isNumber == true
    }

    private static func anthropicModelName(for rawModelID: String) -> String? {
        let normalizedID = rawModelID.lowercased()
        guard normalizedID.hasPrefix("claude-") else { return nil }
        let parts = normalizedID.split(separator: "-").map(String.init)
        guard parts.count >= 4 else { return nil }

        if let generationName = claudeGenerationName(from: parts) {
            return generationName
        }

        if let legacyName = legacyClaudeName(from: parts) {
            return legacyName
        }

        return nil
    }

    private static func claudeGenerationName(from parts: [String]) -> String? {
        guard parts.count >= 4,
              let family = ClaudeFamily(rawValue: parts[1]),
              parts[2].allSatisfy(\.isNumber),
              parts[3].allSatisfy(\.isNumber) else { return nil }

        return "Claude \(family.displayName) \(parts[2]).\(parts[3])"
    }

    private static func legacyClaudeName(from parts: [String]) -> String? {
        guard parts.count >= 5,
              parts[1].allSatisfy(\.isNumber),
              parts[2].allSatisfy(\.isNumber),
              let family = ClaudeFamily(rawValue: parts[3]) else { return nil }

        return "Claude \(family.displayName) \(parts[1]).\(parts[2])"
    }
}
