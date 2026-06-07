import Foundation
import VoyagerShared

public enum AiChatProviderRequestLoweringError: Error, Equatable, Sendable {
    case modelProviderMismatch(requestProvider: AiProvider, modelProvider: AiProvider)
    case missingModelID(AiProvider)
}

public struct AiChatProviderMessage: Equatable, Sendable, Codable {
    public let role: AiChatMessageRole
    public let content: String

    public init(role: AiChatMessageRole, content: String) {
        self.role = role
        self.content = content
    }
}

public struct AiChatProviderContextBundle: Equatable, Sendable, Codable {
    public let sessionID: AiChatSessionID?
    public let requestID: AiChatRequestID
    public let runID: AiChatRunID
    public let requestContext: AiChatLockedRequestContextSnapshot
    public let promptSummary: String?
    public let submittedAtMs: Int64?

    public init(
        sessionID: AiChatSessionID?,
        requestID: AiChatRequestID,
        runID: AiChatRunID,
        requestContext: AiChatLockedRequestContextSnapshot,
        promptSummary: String?,
        submittedAtMs: Int64?,
    ) {
        self.sessionID = sessionID
        self.requestID = requestID
        self.runID = runID
        self.requestContext = requestContext
        self.promptSummary = promptSummary
        self.submittedAtMs = submittedAtMs
    }

    public var currentContext: AiChatCurrentContextSnapshot {
        requestContext.currentContext
    }
}

public enum AiChatProviderThinkingPayload: Equatable, Sendable, Codable {
    case none
    case disabled
    case effort(AiThinkingEffort)
    case tokenBudget(Int)
    case adaptive(defaultEffort: AiThinkingEffort?)
}

public struct AiChatProviderRequestPayload: Equatable, Sendable, Codable {
    public let provider: AiProvider
    public let rawModelID: String
    public let messages: [AiChatProviderMessage]
    public let context: AiChatProviderContextBundle
    public let thinking: AiChatProviderThinkingPayload?
    public let responseContract: AiChatProviderResponseContract?

    public init(
        provider: AiProvider,
        rawModelID: String,
        messages: [AiChatProviderMessage],
        context: AiChatProviderContextBundle,
        thinking: AiChatProviderThinkingPayload?,
        responseContract: AiChatProviderResponseContract? = nil,
    ) {
        self.provider = provider
        self.rawModelID = rawModelID
        self.messages = messages
        self.context = context
        self.thinking = thinking
        self.responseContract = responseContract
    }

    public static func lower(_ request: AiChatRequest) throws -> AiChatProviderRequestPayload {
        try lower(request, thinking: lowerThinking(request.context.selectedThinking))
    }

    public var currentContext: AiChatCurrentContextSnapshot {
        context.requestContext.currentContext
    }

    var fallbackExecutionContext: AiChatRequestContextSnapshot {
        AiChatRequestContextSnapshot(
            sessionID: context.sessionID,
            requestID: context.requestID,
            runID: context.runID,
            provider: provider,
            model: AiModelHandle(provider: provider, rawValue: rawModelID),
            selectedModel: nil,
            selectedThinking: nil,
            sessionStatus: .idle,
            currentContext: context.currentContext,
            requestContext: context.requestContext,
            promptSummary: context.promptSummary,
            submittedAtMs: context.submittedAtMs,
        )
    }

    public static func lower(
        _ request: AiChatRequest,
        thinking: AiChatProviderThinkingPayload?,
    ) throws -> AiChatProviderRequestPayload {
        let resolvedModelProvider = request.context.selectedModel?.provider ?? request.context.model.provider
        guard request.context.provider == resolvedModelProvider else {
            throw AiChatProviderRequestLoweringError.modelProviderMismatch(
                requestProvider: request.context.provider,
                modelProvider: resolvedModelProvider,
            )
        }

        let rawModelID = (request.context.selectedModel?.rawModelID ?? request.context.model.rawValue)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawModelID.isEmpty else {
            throw AiChatProviderRequestLoweringError.missingModelID(request.context.provider)
        }

        return AiChatProviderRequestPayload(
            provider: request.context.provider,
            rawModelID: rawModelID,
            messages: request.messages.map {
                AiChatProviderMessage(role: $0.role, content: $0.content)
            },
            context: AiChatProviderContextBundle(
                sessionID: request.context.sessionID,
                requestID: request.context.requestID,
                runID: request.context.runID,
                requestContext: request.context.requestContext,
                promptSummary: request.context.promptSummary,
                submittedAtMs: request.context.submittedAtMs,
            ),
            thinking: thinking,
            responseContract: request.responseContract,
        )
    }

    private static func lowerThinking(_ selection: AiThinkingSelection?) -> AiChatProviderThinkingPayload? {
        switch selection {
        case nil:
            nil
        case .some(.none):
            AiChatProviderThinkingPayload.none
        case let .some(.effort(value)):
            .effort(value)
        case let .some(.tokenBudget(value)):
            .tokenBudget(value)
        }
    }
}

public struct AiChatProviderResponseContract: Equatable, Sendable, Codable {
    public let name: String
    public let schema: [String: JSONValue]
    public let strict: Bool

    public init(
        name: String,
        schema: [String: JSONValue],
        strict: Bool = true,
    ) {
        self.name = name
        self.schema = schema
        self.strict = strict
    }
}
