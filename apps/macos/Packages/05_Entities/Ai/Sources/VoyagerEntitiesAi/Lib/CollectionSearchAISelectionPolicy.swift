import Foundation

public struct CollectionSearchAIThinkingOption: Identifiable, Equatable, Sendable {
    public let selection: AiThinkingSelection?
    public let title: String

    public var id: String {
        selection.map(CollectionSearchAISelectionPolicy.thinkingLabel(for:)) ?? "provider-default"
    }

    public init(selection: AiThinkingSelection?, title: String) {
        self.selection = selection
        self.title = title
    }
}

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
        guard let selectedThinking, let model else { return nil }

        switch (selectedThinking, model.thinkingCapability) {
        case (.none, .effort), (.none, .adaptive), (.none, .tokenBudget), (.none, .unknown):
            return model.supportsThinkingNone ? selectedThinking : nil
        case let (.effort(value), .effort(values, _)):
            return values.contains(value) ? selectedThinking : nil
        case let (.effort(value), .adaptive(values, _)):
            return values.contains(value) ? selectedThinking : nil
        case let (.tokenBudget(value), .tokenBudget(min, max, _)):
            return (min ... max).contains(value) ? selectedThinking : nil
        case (.effort, .unknown), (.tokenBudget, .unknown):
            return selectedThinking
        case (.none, .unsupported), (.effort, .tokenBudget), (.tokenBudget, .effort), (.tokenBudget, .adaptive),
             (.effort, .unsupported), (.tokenBudget, .unsupported):
            return nil
        }
    }

    public static func thinkingOptions(for model: AiProviderModel?) -> [CollectionSearchAIThinkingOption] {
        guard let model else { return [] }

        let defaults = defaultOptions(supportsNone: model.supportsThinkingNone)
        switch model.thinkingCapability {
        case let .effort(values, _):
            return defaults + values.map { effortOption($0) }
        case let .adaptive(effortValues, _):
            return defaults + effortValues.map { effortOption($0) }
        case let .tokenBudget(min, max, defaultValue):
            return defaults + budgetValues(min: min, max: max, defaultValue: defaultValue).map { tokenBudgetOption($0) }
        case .unsupported, .unknown:
            return []
        }
    }

    public static func defaultThinkingLabel(for capability: AiModelThinkingCapability) -> String {
        switch capability {
        case .unsupported, .unknown:
            "Thinking unavailable"
        case .effort, .adaptive, .tokenBudget:
            "default"
        }
    }

    public static func thinkingLabel(for selection: AiThinkingSelection) -> String {
        switch selection {
        case .none:
            "none"
        case let .effort(value):
            switch value {
            case .minimal:
                "minimal"
            case .low:
                "low"
            case .medium:
                "medium"
            case .high:
                "high"
            case .xhigh:
                "x-high"
            case .max:
                "max"
            }
        case let .tokenBudget(value):
            "\(value) tokens"
        }
    }

    private static func defaultOptions(supportsNone: Bool) -> [CollectionSearchAIThinkingOption] {
        var options = [CollectionSearchAIThinkingOption(selection: nil, title: "Provider default")]
        if supportsNone {
            options.append(CollectionSearchAIThinkingOption(
                selection: AiThinkingSelection.none,
                title: thinkingLabel(for: .none),
            ))
        }
        return options
    }

    private static func effortOption(_ effort: AiThinkingEffort) -> CollectionSearchAIThinkingOption {
        CollectionSearchAIThinkingOption(selection: .effort(effort), title: thinkingLabel(for: .effort(effort)))
    }

    private static func tokenBudgetOption(_ value: Int) -> CollectionSearchAIThinkingOption {
        CollectionSearchAIThinkingOption(selection: .tokenBudget(value), title: thinkingLabel(for: .tokenBudget(value)))
    }

    private static func budgetValues(min: Int, max: Int, defaultValue: Int?) -> [Int] {
        var values: [Int] = [min]
        if let defaultValue, defaultValue != min, defaultValue != max {
            values.append(defaultValue)
        }
        if max != min {
            values.append(max)
        }
        return values
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
