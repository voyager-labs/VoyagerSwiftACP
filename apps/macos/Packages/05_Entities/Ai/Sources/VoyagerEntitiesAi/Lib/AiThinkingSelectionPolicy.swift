public struct AiThinkingOption: Identifiable, Equatable, Sendable {
    public let selection: AiThinkingSelection?
    public let title: String

    public var id: String {
        selection.map(AiThinkingSelectionPolicy.label(for:)) ?? "provider-default"
    }

    public init(selection: AiThinkingSelection?, title: String) {
        self.selection = selection
        self.title = title
    }
}

public enum AiThinkingSelectionPolicy {
    public static func normalize(
        _ selection: AiThinkingSelection?,
        capability: AiModelThinkingCapability,
        supportsNone: Bool,
    ) -> AiThinkingSelection? {
        guard let selection else { return nil }
        if case let .tokenBudget(min, max, _) = capability, min > max { return nil }

        switch (selection, capability) {
        case (.none, .effort), (.none, .adaptive), (.none, .tokenBudget), (.none, .unknown):
            return supportsNone ? selection : nil
        case let (.effort(value), .effort(values, _)):
            return values.contains(value) ? selection : nil
        case let (.effort(value), .adaptive(values, _)):
            return values.contains(value) ? selection : nil
        case let (.tokenBudget(value), .tokenBudget(min, max, _)):
            return min <= value && value <= max ? selection : nil
        case (.effort, .unknown), (.tokenBudget, .unknown):
            return selection
        case (.none, .unsupported), (.effort, .tokenBudget), (.tokenBudget, .effort), (.tokenBudget, .adaptive),
             (.effort, .unsupported), (.tokenBudget, .unsupported):
            return nil
        }
    }

    public static func options(
        capability: AiModelThinkingCapability,
        supportsNone: Bool,
    ) -> [AiThinkingOption] {
        let defaults = defaultOptions(supportsNone: supportsNone)
        switch capability {
        case let .effort(values, _):
            return defaults + values.map { effortOption($0) }
        case let .adaptive(effortValues, _):
            return defaults + effortValues.map { effortOption($0) }
        case let .tokenBudget(min, max, defaultValue):
            guard min <= max else { return [] }
            return defaults + budgetValues(min: min, max: max, defaultValue: defaultValue).map { tokenBudgetOption($0) }
        case .unsupported, .unknown:
            return []
        }
    }

    public static func defaultLabel(for capability: AiModelThinkingCapability) -> String {
        switch capability {
        case .unsupported, .unknown:
            "Thinking unavailable"
        case .effort, .adaptive, .tokenBudget:
            "default"
        }
    }

    public static func label(for selection: AiThinkingSelection) -> String {
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

    private static func defaultOptions(supportsNone: Bool) -> [AiThinkingOption] {
        var options = [AiThinkingOption(selection: nil, title: "Provider default")]
        if supportsNone {
            options.append(AiThinkingOption(selection: AiThinkingSelection.none, title: label(for: .none)))
        }
        return options
    }

    private static func effortOption(_ effort: AiThinkingEffort) -> AiThinkingOption {
        AiThinkingOption(selection: .effort(effort), title: label(for: .effort(effort)))
    }

    private static func tokenBudgetOption(_ value: Int) -> AiThinkingOption {
        AiThinkingOption(selection: .tokenBudget(value), title: label(for: .tokenBudget(value)))
    }

    private static func budgetValues(min: Int, max: Int, defaultValue: Int?) -> [Int] {
        var values = [min]
        if let defaultValue, min <= defaultValue, defaultValue <= max, defaultValue != min, defaultValue != max {
            values.append(defaultValue)
        }
        if max != min {
            values.append(max)
        }
        return values
    }
}
