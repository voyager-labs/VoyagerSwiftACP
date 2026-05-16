// swiftlint:disable line_length cyclomatic_complexity
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

    public init(
        payload: AiChatProviderRequestPayload,
        credential: AiChatProviderValidatedCredential,
        warnings: [AiChatProviderPreflightWarning] = []
    ) {
        self.payload = payload
        self.credential = credential
        self.warnings = warnings
    }
}

public enum AiChatProviderPreflight {
    public static func prepare(
        _ request: AiChatRequest,
        credential: StoredCredentialPayload?
    ) throws -> AiChatProviderPreflightResult {
        try prepare(
            context: request.context,
            messages: request.messages,
            credential: credential,
            thinkingCapability: request.context.selectedModel?.thinkingCapability
        )
    }

    public static func prepare(
        context: AiChatRequestContextSnapshot,
        messages: [AiChatMessage],
        credential: StoredCredentialPayload?,
        thinkingCapability: AiModelThinkingCapability?
    ) throws -> AiChatProviderPreflightResult {
        let validatedCredential = try validateCredential(for: context.provider, credential: credential)
        let (loweredThinking, warnings) = lowerThinking(
            selection: context.selectedThinking,
            provider: context.provider,
            capability: thinkingCapability
        )
        let request = AiChatRequest(context: context, messages: messages)
        let payload: AiChatProviderRequestPayload
        do {
            payload = try AiChatProviderRequestPayload.lower(request, thinking: loweredThinking)
        } catch let error as AiChatProviderRequestLoweringError {
            throw AiChatProviderPreflightError.loweringFailed(error)
        }

        return AiChatProviderPreflightResult(
            payload: payload,
            credential: validatedCredential,
            warnings: warnings
        )
    }

    public static func validateCredential(
        for provider: AiProvider,
        credential: StoredCredentialPayload?
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
        capability: AiModelThinkingCapability?
    ) -> (payload: AiChatProviderThinkingPayload?, warnings: [AiChatProviderPreflightWarning]) {
        guard let selection else {
            return (nil, [])
        }

        switch provider {
        case .openai, .chatgptCodex:
            return lowerOpenAIStyleThinking(selection: selection, provider: provider, capability: capability)
        case .anthropic:
            return lowerAnthropicThinking(selection: selection, capability: capability)
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
            if normalized.contains("offline") || normalized.contains("not connected") || normalized.contains("network") {
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
        capability: AiModelThinkingCapability?
    ) -> (payload: AiChatProviderThinkingPayload?, warnings: [AiChatProviderPreflightWarning]) {
        switch selection {
        case .none:
            return (AiChatProviderThinkingPayload.none, [])

        case let .effort(value):
            switch capability {
            case let .effort(values, _), let .adaptive(values, _):
                guard values.contains(value) else {
                    return omittedThinking(provider: provider, selection: selection, reason: "Selected effort is not supported by the model capability.")
                }
                return (.effort(value), [])
            case .unknown, .unsupported, .tokenBudget, nil:
                return omittedThinking(provider: provider, selection: selection, reason: "The model capability does not advertise support for effort-based thinking.")
            }

        case let .tokenBudget(value):
            switch capability {
            case let .tokenBudget(min, max, _):
                guard (min ... max).contains(value) else {
                    return omittedThinking(provider: provider, selection: selection, reason: "Selected token budget is outside the supported range.")
                }
                return (.tokenBudget(value), [])
            case .effort, .adaptive, .unknown, .unsupported, nil:
                return omittedThinking(provider: provider, selection: selection, reason: "The model capability does not advertise token-budget thinking.")
            }
        }
    }

    static func lowerAnthropicThinking(
        selection: AiThinkingSelection,
        capability: AiModelThinkingCapability?
    ) -> (payload: AiChatProviderThinkingPayload?, warnings: [AiChatProviderPreflightWarning]) {
        switch selection {
        case .none:
            switch capability {
            case .effort, .tokenBudget:
                return (.disabled, [])
            case .adaptive, .unknown, .unsupported, nil:
                return omittedThinking(provider: .anthropic, selection: selection, reason: "This model capability does not confirm disabled thinking support.")
            }

        case let .effort(value):
            switch capability {
            case let .effort(values, _):
                guard values.contains(value) else {
                    return omittedThinking(provider: .anthropic, selection: selection, reason: "Selected effort is not supported by the model capability.")
                }
                return (.effort(value), [])
            case let .adaptive(values, defaultValue):
                let effectiveEffort = values.contains(value) ? value : defaultValue
                guard effectiveEffort != nil else {
                    return omittedThinking(provider: .anthropic, selection: selection, reason: "Adaptive-only thinking could not honor the selected effort.")
                }
                return (.adaptive(defaultEffort: effectiveEffort), [
                    .omittedThinkingSelection(
                        provider: .anthropic,
                        selection: selection,
                        reason: "Adaptive-only capability lowered to adaptive/default instead of a direct effort payload."
                    )
                ])
            case .tokenBudget, .unknown, .unsupported, nil:
                return omittedThinking(provider: .anthropic, selection: selection, reason: "The model capability does not advertise effort-based thinking.")
            }

        case let .tokenBudget(value):
            switch capability {
            case let .tokenBudget(min, max, _):
                guard (min ... max).contains(value) else {
                    return omittedThinking(provider: .anthropic, selection: selection, reason: "Selected token budget is outside the supported range.")
                }
                return (.tokenBudget(value), [])
            case let .adaptive(_, defaultValue):
                return (.adaptive(defaultEffort: defaultValue), [
                    .omittedThinkingSelection(
                        provider: .anthropic,
                        selection: selection,
                        reason: "Adaptive-only capability omitted manual token budget and fell back to adaptive/default."
                    )
                ])
            case .effort, .unknown, .unsupported, nil:
                return omittedThinking(provider: .anthropic, selection: selection, reason: "The model capability does not advertise manual token-budget thinking.")
            }
        }
    }

    static func omittedThinking(
        provider: AiProvider,
        selection: AiThinkingSelection,
        reason: String
    ) -> (payload: AiChatProviderThinkingPayload?, warnings: [AiChatProviderPreflightWarning]) {
        (
            nil,
            [.omittedThinkingSelection(provider: provider, selection: selection, reason: reason)]
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
    }
}

// swiftlint:enable line_length cyclomatic_complexity
