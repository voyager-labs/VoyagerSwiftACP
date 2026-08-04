import Foundation

enum AiChatProviderPayloadEmission: Equatable {
    case status(AiChatExecutionActivitySignal)
    case delta(String)
}

private struct OpenAIActivityTransition {
    let kind: AiChatExecutionActivityKind
    let phase: AiChatExecutionActivityPhase
}

struct OpenAIStreamConsumptionState {
    private let requestScope: String
    private var deltas: [String] = []
    private var finalText: String?
    private var activeActivities: Set<AiChatExecutionActivityID> = []

    init(context: AiChatRequestContextSnapshot) {
        requestScope = context.requestID.rawValue.uuidString.lowercased()
    }

    var resolvedText: String? {
        finalText ?? (deltas.isEmpty ? nil : deltas.joined())
    }

    mutating func consume(_ event: OpenAIResponsesStreamEvent) throws -> [AiChatProviderPayloadEmission] {
        var emissions = activityTransition(for: event)
        switch event.type {
        case "response.output_text.delta":
            if let delta = event.delta, !delta.isEmpty {
                deltas.append(delta)
                emissions.append(.delta(delta))
            }
        case "response.output_text.done":
            if let text = event.text, !text.isEmpty { finalText = text }
        case "response.completed":
            if let text = event.resolvedText, !text.isEmpty { finalText = text }
        case "response.failed", "error":
            throw AiChatProviderExecutionClient.openAIStreamFailure(event)
        default:
            break
        }
        return emissions
    }

    private mutating func activityTransition(
        for event: OpenAIResponsesStreamEvent,
    ) -> [AiChatProviderPayloadEmission] {
        guard let transition = Self.activityTransitions[event.type] else { return [] }
        switch transition.phase {
        case .began:
            return beginIfNeeded(event: event, kind: transition.kind)
        case .ended:
            return endIfActive(event: event, kind: transition.kind)
        }
    }

    private static let activityTransitions: [String: OpenAIActivityTransition] = [
        "response.reasoning_text.delta": .init(kind: .thinking, phase: .began),
        "response.reasoning_summary_text.delta": .init(kind: .thinking, phase: .began),
        "response.reasoning_text.done": .init(kind: .thinking, phase: .ended),
        "response.reasoning_summary_text.done": .init(kind: .thinking, phase: .ended),
        "response.web_search_call.in_progress": .init(kind: .searching, phase: .began),
        "response.web_search_call.searching": .init(kind: .searching, phase: .began),
        "response.web_search_call.completed": .init(kind: .searching, phase: .ended),
        "response.file_search_call.in_progress": .init(kind: .searching, phase: .began),
        "response.file_search_call.searching": .init(kind: .searching, phase: .began),
        "response.file_search_call.completed": .init(kind: .searching, phase: .ended),
        "response.code_interpreter_call.in_progress": .init(kind: .toolExecution, phase: .began),
        "response.code_interpreter_call.interpreting": .init(kind: .toolExecution, phase: .began),
        "response.code_interpreter_call.completed": .init(kind: .toolExecution, phase: .ended),
        "response.code_interpreter_call.failed": .init(kind: .toolExecution, phase: .ended),
        "response.mcp_call.in_progress": .init(kind: .toolExecution, phase: .began),
        "response.mcp_call.interpreting": .init(kind: .toolExecution, phase: .began),
        "response.mcp_call.completed": .init(kind: .toolExecution, phase: .ended),
        "response.mcp_call.failed": .init(kind: .toolExecution, phase: .ended),
        "response.output_text.delta": .init(kind: .answerGeneration, phase: .began),
        "response.output_text.done": .init(kind: .answerGeneration, phase: .ended),
    ]

    private mutating func beginIfNeeded(
        event: OpenAIResponsesStreamEvent,
        kind: AiChatExecutionActivityKind,
    ) -> [AiChatProviderPayloadEmission] {
        let activityID = activityID(for: event, kind: kind)
        guard activeActivities.insert(activityID).inserted else { return [] }
        return [.status(signal(activityID: activityID, kind: kind, phase: .began, eventType: event.type))]
    }

    private mutating func endIfActive(
        event: OpenAIResponsesStreamEvent,
        kind: AiChatExecutionActivityKind,
    ) -> [AiChatProviderPayloadEmission] {
        let activityID = activityID(for: event, kind: kind)
        guard activeActivities.remove(activityID) != nil else { return [] }
        return [.status(signal(activityID: activityID, kind: kind, phase: .ended, eventType: event.type))]
    }

    private func activityID(
        for event: OpenAIResponsesStreamEvent,
        kind: AiChatExecutionActivityKind,
    ) -> AiChatExecutionActivityID {
        if let providerID = event.itemID ?? event.item?.id, !providerID.isEmpty {
            return AiChatExecutionActivityID(rawValue: providerID)
        }
        let index = event.outputIndex ?? 0
        return AiChatExecutionActivityID(rawValue: "\(requestScope):openai:\(kind.rawValue):\(index)")
    }
}

struct AnthropicActivityState {
    private let requestScope: String
    private var activitiesByIndex: [Int: (AiChatExecutionActivityID, AiChatExecutionActivityKind)] = [:]
    private var serverActivitiesByID: [String: AiChatExecutionActivityKind] = [:]

    init(context: AiChatRequestContextSnapshot) {
        requestScope = context.requestID.rawValue.uuidString.lowercased()
    }

    mutating func consume(_ event: AnthropicStreamEvent) -> [AiChatProviderPayloadEmission] {
        switch event.type {
        case "content_block_start":
            start(event)
        case "content_block_stop":
            stop(event)
        default:
            []
        }
    }

    private mutating func start(_ event: AnthropicStreamEvent) -> [AiChatProviderPayloadEmission] {
        guard let block = event.contentBlock else { return [] }
        if block.type.hasSuffix("_tool_result"), let toolUseID = block.toolUseID,
           let kind = serverActivitiesByID.removeValue(forKey: toolUseID)
        {
            return [
                .status(signal(
                    activityID: AiChatExecutionActivityID(rawValue: toolUseID),
                    kind: kind,
                    phase: .ended,
                    eventType: event.type,
                )),
            ]
        }
        guard let index = event.index else { return [] }
        let kind: AiChatExecutionActivityKind? = switch block.type {
        case "thinking":
            .thinking
        case "text":
            .answerGeneration
        case "server_tool_use":
            isAnthropicSearchTool(block.name) ? .searching : .toolExecution
        default:
            nil
        }
        guard let kind else { return [] }
        let activityID = AiChatExecutionActivityID(rawValue: block.id ?? "\(requestScope):anthropic:block:\(index)")
        activitiesByIndex[index] = (activityID, kind)
        if block.type == "server_tool_use", let id = block.id { serverActivitiesByID[id] = kind }
        return [.status(signal(activityID: activityID, kind: kind, phase: .began, eventType: event.type))]
    }

    private mutating func stop(_ event: AnthropicStreamEvent) -> [AiChatProviderPayloadEmission] {
        guard let index = event.index, let activity = activitiesByIndex.removeValue(forKey: index) else { return [] }
        if serverActivitiesByID[activity.0.rawValue] != nil { return [] }
        return [
            .status(signal(
                activityID: activity.0,
                kind: activity.1,
                phase: .ended,
                eventType: event.type,
            )),
        ]
    }
}

func signal(
    activityID: AiChatExecutionActivityID,
    kind: AiChatExecutionActivityKind,
    phase: AiChatExecutionActivityPhase,
    eventType: String,
    origin: AiChatExecutionEvidenceOrigin = .providerWire,
    boundaryEventTypes: [String] = [],
) -> AiChatExecutionActivitySignal {
    AiChatExecutionActivitySignal(
        activityID: activityID,
        kind: kind,
        phase: phase,
        evidence: AiChatExecutionActivityEvidence(
            origin: origin,
            providerEventType: eventType,
            boundaryEventTypes: boundaryEventTypes,
        ),
    )
}

private func isAnthropicSearchTool(_ name: String?) -> Bool {
    guard let name = name?.lowercased() else { return false }
    return name.contains("web_search") || name.contains("search")
}

enum CodexAppServerItemKind: Equatable {
    case reasoning
    case webSearch
    case commandExecution
    case mcpToolCall
    case agentMessage(phase: String?)
}

enum CodexAppServerTurnStatus: String, Equatable {
    case completed
    case interrupted
    case failed
    case inProgress
}

enum CodexAppServerEvent: Equatable {
    case turnStarted(turnID: String, providerEventType: String)
    case turnCompleted(
        turnID: String,
        status: CodexAppServerTurnStatus,
        failure: AiChatExecutionFailure?,
        providerEventType: String,
    )
    case itemStarted(id: String, kind: CodexAppServerItemKind, providerEventType: String)
    case itemCompleted(id: String, kind: CodexAppServerItemKind, providerEventType: String)
    case agentMessageDelta(itemID: String, delta: String)
    case reasoningDelta(itemID: String)
    case error(turnID: String, willRetry: Bool, providerEventType: String)
}

enum CodexAppServerParsingError: Error, Equatable {
    case malformedKnownEvent(String)
}

struct CodexActivityState {
    private let requestScope: String
    private var retryActivity: (AiChatExecutionActivityID, String)?

    init(context: AiChatRequestContextSnapshot) {
        requestScope = context.requestID.rawValue.uuidString.lowercased()
    }

    mutating func consume(_ event: CodexAppServerEvent) -> [AiChatProviderPayloadEmission] {
        var result = endRetryIfNeeded(before: event)
        result.append(contentsOf: emissions(for: event))
        return result
    }

    private mutating func endRetryIfNeeded(
        before event: CodexAppServerEvent,
    ) -> [AiChatProviderPayloadEmission] {
        guard case let .itemStarted(_, _, eventType) = event,
              let (activityID, beginEventType) = retryActivity
        else { return [] }
        retryActivity = nil
        return [retryEnd(activityID: activityID, beginEventType: beginEventType, eventType: eventType)]
    }

    private mutating func emissions(for event: CodexAppServerEvent) -> [AiChatProviderPayloadEmission] {
        switch event {
        case let .itemStarted(id, kind, eventType):
            itemStatus(id: id, itemKind: kind, phase: .began, eventType: eventType)
        case let .itemCompleted(id, kind, eventType):
            itemStatus(id: id, itemKind: kind, phase: .ended, eventType: eventType)
        case let .agentMessageDelta(_, delta):
            delta.isEmpty ? [] : [.delta(delta)]
        case let .error(turnID, willRetry, eventType):
            beginRetry(turnID: turnID, willRetry: willRetry, eventType: eventType)
        case let .turnCompleted(_, _, _, eventType):
            endRetry(at: eventType)
        case .turnStarted, .reasoningDelta:
            []
        }
    }

    private func itemStatus(
        id: String,
        itemKind: CodexAppServerItemKind,
        phase: AiChatExecutionActivityPhase,
        eventType: String,
    ) -> [AiChatProviderPayloadEmission] {
        guard let kind = activityKind(for: itemKind) else { return [] }
        return [
            .status(signal(
                activityID: AiChatExecutionActivityID(rawValue: id),
                kind: kind,
                phase: phase,
                eventType: eventType,
            )),
        ]
    }

    private mutating func beginRetry(
        turnID: String,
        willRetry: Bool,
        eventType: String,
    ) -> [AiChatProviderPayloadEmission] {
        guard willRetry, retryActivity == nil else { return [] }
        let activityID = AiChatExecutionActivityID(rawValue: "\(requestScope):codex:retry:\(turnID)")
        retryActivity = (activityID, eventType)
        return [
            .status(signal(
                activityID: activityID,
                kind: .retrying,
                phase: .began,
                eventType: eventType,
            )),
        ]
    }

    private mutating func endRetry(at eventType: String) -> [AiChatProviderPayloadEmission] {
        guard let (activityID, beginEventType) = retryActivity else { return [] }
        retryActivity = nil
        return [retryEnd(activityID: activityID, beginEventType: beginEventType, eventType: eventType)]
    }

    private func retryEnd(
        activityID: AiChatExecutionActivityID,
        beginEventType: String,
        eventType: String,
    ) -> AiChatProviderPayloadEmission {
        .status(signal(
            activityID: activityID,
            kind: .retrying,
            phase: .ended,
            eventType: eventType,
            origin: .voyagerClient,
            boundaryEventTypes: [beginEventType, eventType],
        ))
    }

    private func activityKind(for itemKind: CodexAppServerItemKind) -> AiChatExecutionActivityKind? {
        switch itemKind {
        case .reasoning:
            .thinking
        case .webSearch:
            .searching
        case .commandExecution, .mcpToolCall:
            .toolExecution
        case .agentMessage:
            .answerGeneration
        }
    }
}

final class CodexActivityStateBox: @unchecked Sendable {
    private let lock = NSLock()
    private var state: CodexActivityState

    init(context: AiChatRequestContextSnapshot) {
        state = CodexActivityState(context: context)
    }

    func consume(_ event: CodexAppServerEvent) -> [AiChatProviderPayloadEmission] {
        lock.lock()
        defer { lock.unlock() }
        return state.consume(event)
    }
}
