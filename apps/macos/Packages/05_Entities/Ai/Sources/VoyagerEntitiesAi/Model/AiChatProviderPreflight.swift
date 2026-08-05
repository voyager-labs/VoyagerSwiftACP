import Foundation

public enum AiChatProviderPreflightError: Error, Equatable, Sendable {
    case missingCredential(AiProvider)
    case invalidCredential(provider: AiProvider, expected: ProviderAuthMethod)
    case loweringFailed(AiChatProviderRequestLoweringError)
}

public enum AiChatProviderValidatedCredential: Equatable, Sendable {
    case apiKey(String)
    case oauth(OAuthCredentialFile)
}

public enum AiChatProviderPreflightWarning: Equatable, Sendable {
    case omittedThinkingSelection(provider: AiProvider, selection: AiThinkingSelection, reason: String)
}

public struct AiChatProviderPreflightResult: Equatable, Sendable {
    public let payload: AiChatProviderRequestPayload
    public let credential: AiChatProviderValidatedCredential
    public let warnings: [AiChatProviderPreflightWarning]
    private let originalContext: AiChatRequestContextSnapshot?

    var executionContext: AiChatRequestContextSnapshot {
        originalContext ?? payload.fallbackExecutionContext
    }

    public init(
        payload: AiChatProviderRequestPayload,
        credential: AiChatProviderValidatedCredential,
        warnings: [AiChatProviderPreflightWarning] = [],
    ) {
        self.payload = payload
        self.credential = credential
        self.warnings = warnings
        originalContext = nil
    }

    init(
        payload: AiChatProviderRequestPayload,
        credential: AiChatProviderValidatedCredential,
        originalContext: AiChatRequestContextSnapshot,
        warnings: [AiChatProviderPreflightWarning] = [],
    ) {
        self.payload = payload
        self.credential = credential
        self.warnings = warnings
        self.originalContext = originalContext
    }

    public static func == (lhs: AiChatProviderPreflightResult, rhs: AiChatProviderPreflightResult) -> Bool {
        lhs.payload == rhs.payload
            && lhs.credential == rhs.credential
            && lhs.warnings == rhs.warnings
    }
}

public enum AiChatProviderPreflight {
    public static func prepare(
        _ request: AiChatRequest,
        credential: StoredCredentialPayload?,
    ) throws -> AiChatProviderPreflightResult {
        try prepare(
            context: request.context,
            messages: request.messages,
            credential: credential,
            thinkingCapability: request.context.selectedModel?.thinkingCapability,
            responseContract: request.responseContract,
        )
    }

    public static func prepare(
        context: AiChatRequestContextSnapshot,
        messages: [AiChatMessage],
        credential: StoredCredentialPayload?,
        thinkingCapability: AiModelThinkingCapability?,
        responseContract: AiChatProviderResponseContract? = nil,
    ) throws -> AiChatProviderPreflightResult {
        let validatedCredential = try validateCredential(for: context.provider, credential: credential)
        let (loweredThinking, warnings) = lowerThinking(
            selection: context.selectedThinking,
            provider: context.provider,
            capability: thinkingCapability,
            supportsNone: context.selectedModel?.supportsThinkingNone == true,
        )
        let request = AiChatRequest(context: context, messages: messages, responseContract: responseContract)
        let payload: AiChatProviderRequestPayload
        do {
            payload = try AiChatProviderRequestPayload.lower(request, thinking: loweredThinking)
        } catch let error as AiChatProviderRequestLoweringError {
            throw AiChatProviderPreflightError.loweringFailed(error)
        }
        return AiChatProviderPreflightResult(
            payload: payload,
            credential: validatedCredential,
            originalContext: context,
            warnings: warnings,
        )
    }

    public static func validateCredential(
        for provider: AiProvider,
        credential: StoredCredentialPayload?,
    ) throws -> AiChatProviderValidatedCredential {
        guard let credential else {
            throw AiChatProviderPreflightError.missingCredential(provider)
        }
        switch (provider, credential) {
        case let (.openai, .apiKey(payload)), let (.anthropic, .apiKey(payload)):
            let secret = payload.secret.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !secret.isEmpty else {
                throw AiChatProviderPreflightError.missingCredential(provider)
            }
            return .apiKey(secret)

        case let (.chatgptCodex, .oauth(payload)):
            let accessToken = payload.accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !accessToken.isEmpty else {
                throw AiChatProviderPreflightError.missingCredential(provider)
            }
            return .oauth(payload)

        case (.openai, .oauth), (.anthropic, .oauth):
            throw AiChatProviderPreflightError.invalidCredential(provider: provider, expected: .apiKey)

        case (.chatgptCodex, .apiKey):
            throw AiChatProviderPreflightError.invalidCredential(provider: provider, expected: .oauth)
        }
    }

    public static func lowerThinking(
        selection: AiThinkingSelection?,
        provider: AiProvider,
        capability: AiModelThinkingCapability?,
        supportsNone: Bool = false,
    ) -> (payload: AiChatProviderThinkingPayload?, warnings: [AiChatProviderPreflightWarning]) {
        guard let selection else {
            return (nil, [])
        }
        switch provider {
        case .openai, .chatgptCodex:
            return lowerOpenAIStyleThinking(
                selection: selection,
                provider: provider,
                capability: capability,
                supportsNone: supportsNone,
            )
        case .anthropic:
            return lowerAnthropicThinking(selection: selection, capability: capability, supportsNone: supportsNone)
        }
    }
}

public enum AiChatProviderExecutionFailureMapper {
    public static func map(_ error: AiHTTPError) -> AiChatExecutionFailure {
        switch error {
        case let .httpError(statusCode, body):
            return mapHTTPStatus(statusCode, body: body)
        case let .networkError(description):
            let normalized = description.lowercased()
            if normalized.contains("offline") || normalized.contains("not connected") || normalized
                .contains("network")
            {
                return .network
            }
            return .transportError
        case .timeout:
            return .network
        case .cancelled:
            return .cancelled
        case .invalidURL:
            return .transportError
        }
    }
}

private extension AiChatProviderPreflight {
    static func lowerOpenAIStyleThinking(
        selection: AiThinkingSelection,
        provider: AiProvider,
        capability: AiModelThinkingCapability?,
        supportsNone: Bool,
    ) -> (payload: AiChatProviderThinkingPayload?, warnings: [AiChatProviderPreflightWarning]) {
        switch selection {
        case .none:
            guard supportsNone else {
                return omittedThinking(
                    provider: provider,
                    selection: selection,
                    reason: "This model does not advertise support for reasoning none.",
                )
            }
            return (AiChatProviderThinkingPayload.none, [])

        case let .effort(value):
            switch capability {
            case let .effort(values, _), let .adaptive(values, _):
                guard values.contains(value) else {
                    return omittedThinking(
                        provider: provider,
                        selection: selection,
                        reason: "Selected effort is not supported by the model capability.",
                    )
                }
                return (.effort(value), [])
            case .unknown, .unsupported, .tokenBudget, nil:
                return omittedThinking(
                    provider: provider,
                    selection: selection,
                    reason: "The model capability does not advertise support for effort-based thinking.",
                )
            }

        case let .tokenBudget(value):
            switch capability {
            case let .tokenBudget(min, max, _):
                guard min <= value, value <= max else {
                    return omittedThinking(
                        provider: provider,
                        selection: selection,
                        reason: "Selected token budget is outside the supported range.",
                    )
                }
                return (.tokenBudget(value), [])
            case .effort, .adaptive, .unknown, .unsupported, nil:
                return omittedThinking(
                    provider: provider,
                    selection: selection,
                    reason: "The model capability does not advertise token-budget thinking.",
                )
            }
        }
    }

    static func lowerAnthropicThinking(
        selection: AiThinkingSelection,
        capability: AiModelThinkingCapability?,
        supportsNone: Bool,
    ) -> (payload: AiChatProviderThinkingPayload?, warnings: [AiChatProviderPreflightWarning]) {
        switch selection {
        case .none:
            lowerAnthropicNoneThinking(selection: selection, capability: capability, supportsNone: supportsNone)
        case let .effort(value):
            lowerAnthropicEffortThinking(value: value, selection: selection, capability: capability)
        case let .tokenBudget(value):
            lowerAnthropicTokenBudgetThinking(value: value, selection: selection, capability: capability)
        }
    }

    static func lowerAnthropicNoneThinking(
        selection: AiThinkingSelection,
        capability: AiModelThinkingCapability?,
        supportsNone: Bool,
    ) -> (payload: AiChatProviderThinkingPayload?, warnings: [AiChatProviderPreflightWarning]) {
        guard supportsNone else {
            return omittedThinking(
                provider: .anthropic,
                selection: selection,
                reason: "This model does not advertise support for disabling thinking.",
            )
        }
        switch capability {
        case .effort, .tokenBudget:
            return (.disabled, [])
        case .adaptive, .unknown, .unsupported, nil:
            return omittedThinking(
                provider: .anthropic,
                selection: selection,
                reason: "This model capability does not confirm disabled thinking support.",
            )
        }
    }

    static func lowerAnthropicEffortThinking(
        value: AiThinkingEffort,
        selection: AiThinkingSelection,
        capability: AiModelThinkingCapability?,
    ) -> (payload: AiChatProviderThinkingPayload?, warnings: [AiChatProviderPreflightWarning]) {
        switch capability {
        case let .effort(values, _):
            lowerAnthropicDirectEffort(value: value, values: values, selection: selection)
        case let .adaptive(values, defaultValue):
            lowerAnthropicAdaptiveEffort(
                value: value,
                values: values,
                defaultValue: defaultValue,
                selection: selection,
            )
        case .tokenBudget, .unknown, .unsupported, nil:
            omittedThinking(
                provider: .anthropic,
                selection: selection,
                reason: "The model capability does not advertise effort-based thinking.",
            )
        }
    }

    static func lowerAnthropicDirectEffort(
        value: AiThinkingEffort,
        values: [AiThinkingEffort],
        selection: AiThinkingSelection,
    ) -> (payload: AiChatProviderThinkingPayload?, warnings: [AiChatProviderPreflightWarning]) {
        guard values.contains(value) else {
            return omittedThinking(
                provider: .anthropic,
                selection: selection,
                reason: "Selected effort is not supported by the model capability.",
            )
        }
        return (.effort(value), [])
    }

    static func lowerAnthropicAdaptiveEffort(
        value: AiThinkingEffort,
        values: [AiThinkingEffort],
        defaultValue: AiThinkingEffort?,
        selection: AiThinkingSelection,
    ) -> (payload: AiChatProviderThinkingPayload?, warnings: [AiChatProviderPreflightWarning]) {
        let effectiveEffort = values.contains(value) ? value : defaultValue
        guard effectiveEffort != nil else {
            return omittedThinking(
                provider: .anthropic,
                selection: selection,
                reason: "Adaptive-only thinking could not honor the selected effort.",
            )
        }
        return (.adaptive(defaultEffort: effectiveEffort), [
            .omittedThinkingSelection(
                provider: .anthropic,
                selection: selection,
                reason: "Adaptive capability lowered effort selection to adaptive/default.",
            ),
        ])
    }

    static func lowerAnthropicTokenBudgetThinking(
        value: Int,
        selection: AiThinkingSelection,
        capability: AiModelThinkingCapability?,
    ) -> (payload: AiChatProviderThinkingPayload?, warnings: [AiChatProviderPreflightWarning]) {
        switch capability {
        case let .tokenBudget(min, max, _):
            lowerAnthropicManualBudget(value: value, min: min, max: max, selection: selection)
        case let .adaptive(_, defaultValue):
            (.adaptive(defaultEffort: defaultValue), [
                .omittedThinkingSelection(
                    provider: .anthropic,
                    selection: selection,
                    reason: "Adaptive capability omitted manual token budget.",
                ),
            ])
        case .effort, .unknown, .unsupported, nil:
            omittedThinking(
                provider: .anthropic,
                selection: selection,
                reason: "The model capability does not advertise manual token-budget thinking.",
            )
        }
    }

    static func lowerAnthropicManualBudget(
        value: Int,
        min: Int,
        max: Int,
        selection: AiThinkingSelection,
    ) -> (payload: AiChatProviderThinkingPayload?, warnings: [AiChatProviderPreflightWarning]) {
        guard min <= value, value <= max else {
            return omittedThinking(
                provider: .anthropic,
                selection: selection,
                reason: "Selected token budget is outside the supported range.",
            )
        }
        return (.tokenBudget(value), [])
    }

    static func omittedThinking(
        provider: AiProvider,
        selection: AiThinkingSelection,
        reason: String,
    ) -> (payload: AiChatProviderThinkingPayload?, warnings: [AiChatProviderPreflightWarning]) {
        (
            nil,
            [.omittedThinkingSelection(provider: provider, selection: selection, reason: reason)],
        )
    }
}

private extension AiChatProviderExecutionFailureMapper {
    static func mapHTTPStatus(_ statusCode: Int, body: String) -> AiChatExecutionFailure {
        switch statusCode {
        case 401, 403:
            return .authentication
        case 402:
            return .quotaExceeded
        case 429:
            return bodySuggestsQuotaOrBilling(body) ? .quotaExceeded : .rateLimited
        case 500 ... 599:
            return .network
        case 404:
            return .modelUnavailable
        default:
            if bodySuggestsMissingModel(body) {
                return .modelUnavailable
            }
            if bodySuggestsQuotaOrBilling(body) {
                return .quotaExceeded
            }
            return statusCode >= 400 ? .invalidRequest : .unknown
        }
    }

    static func bodySuggestsMissingModel(_ body: String) -> Bool {
        let normalized = body.lowercased()
        guard normalized.contains("model") else { return false }
        return normalized.contains("not found")
            || normalized.contains("does not exist")
            || normalized.contains("unavailable")
            || normalized.contains("unknown")
    }

    static func bodySuggestsQuotaOrBilling(_ body: String) -> Bool {
        let normalized = body.lowercased()
        return normalized.contains("credit")
            || normalized.contains("credits")
            || normalized.contains("quota")
            || normalized.contains("billing")
            || normalized.contains("balance")
            || normalized.contains("insufficient_quota")
            || normalized.contains("payment")
            || normalized.contains("usage limit")
            || normalized.contains("limit reached")
            || normalized.contains("monthly limit")
            || normalized.contains("daily limit")
            || normalized.contains("spending limit")
            || normalized.contains("plan limit")
            || normalized.contains("current quota")
            || normalized.contains("billing details")
            || normalized.contains("maximum monthly spend")
            || normalized.contains("monthly budget")
            || normalized.contains("hard limit")
            || normalized.contains("soft limit")
            || normalized.contains("usage cap")
            || normalized.contains("insufficient funds")
            || normalized.contains("upgrade")
            || normalized.contains("subscription")
    }
}
