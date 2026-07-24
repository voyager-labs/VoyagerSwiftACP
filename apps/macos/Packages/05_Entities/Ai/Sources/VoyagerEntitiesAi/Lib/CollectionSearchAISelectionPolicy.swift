import Foundation

public typealias CollectionSearchAIThinkingOption = AiThinkingOption

public enum CollectionSearchAISelectionPolicy {
    public static func supportsQueryConversion(_ model: AiProviderModel) -> Bool {
        guard model.unavailableReason == nil else { return false }

        let normalizedID = model.rawModelID.lowercased()
        switch model.provider {
        case .openai:
            guard isOpenAIStructuredTextCandidate(normalizedID) else { return false }
            return normalizedID.hasPrefix("gpt-4o")
                || normalizedID.hasPrefix("gpt-4.1")
                || normalizedID.hasPrefix("gpt-5")
                || normalizedID.hasPrefix("o1")
                || normalizedID.hasPrefix("o3")
                || normalizedID.hasPrefix("o4")
        case .anthropic:
            return normalizedID.hasPrefix("claude-")
        case .chatgptCodex:
            return true
        }
    }

    public static func normalizeSelectedThinking(
        _ selectedThinking: AiThinkingSelection?,
        for model: AiProviderModel?,
    ) -> AiThinkingSelection? {
        guard let model else { return nil }
        return AiThinkingSelectionPolicy.normalize(
            selectedThinking,
            capability: model.thinkingCapability,
            supportsNone: model.supportsThinkingNone,
        )
    }

    public static func thinkingOptions(for model: AiProviderModel?) -> [CollectionSearchAIThinkingOption] {
        guard let model else { return [] }
        return AiThinkingSelectionPolicy.options(
            capability: model.thinkingCapability,
            supportsNone: model.supportsThinkingNone,
        )
    }

    public static func defaultThinkingLabel(for capability: AiModelThinkingCapability) -> String {
        AiThinkingSelectionPolicy.defaultLabel(for: capability)
    }

    public static func thinkingLabel(for selection: AiThinkingSelection) -> String {
        AiThinkingSelectionPolicy.label(for: selection)
    }

    private static func isOpenAIStructuredTextCandidate(_ normalizedID: String) -> Bool {
        let unsupportedMarkers = [
            "audio",
            "search",
            "transcribe",
            "transcription",
            "tts",
            "moderation",
            "embedding",
            "realtime",
            "whisper",
        ]
        return unsupportedMarkers.contains { normalizedID.contains($0) } == false
    }
}
