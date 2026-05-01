import VoyagerEntitiesAi

public enum AiChatRequestKind: Equatable, Sendable {
    case submit
    case regenerate
}

public struct AiChatRequestLock: Equatable, Sendable {
    public let kind: AiChatRequestKind
    public let requestID: AiChatRequestID
    public let runID: AiChatRunID
    public let context: AiChatRequestContextSnapshot
    public let request: AiChatRequest
    public let selectedModelHandle: AiModelHandle
    public let selectedModelRow: AiModelCatalogRow?
    public let assistantReplacementIndex: Int?

    public init(
        kind: AiChatRequestKind,
        requestID: AiChatRequestID,
        runID: AiChatRunID,
        context: AiChatRequestContextSnapshot,
        request: AiChatRequest,
        selectedModelHandle: AiModelHandle,
        selectedModelRow: AiModelCatalogRow?,
        assistantReplacementIndex: Int?
    ) {
        self.kind = kind
        self.requestID = requestID
        self.runID = runID
        self.context = context
        self.request = request
        self.selectedModelHandle = selectedModelHandle
        self.selectedModelRow = selectedModelRow
        self.assistantReplacementIndex = assistantReplacementIndex
    }
}

public enum AiChatExecutionPhase: Equatable, Sendable {
    case idle
    case processing(AiChatRequestLock)
    case completed(AiChatRequestLock)
    case failed(AiChatRequestLock, AiChatExecutionFailure)
    case cancelled(AiChatRequestLock)
    case persistenceRecovery(AiChatRequestLock, AiChatExecutionFailure)

    public var lock: AiChatRequestLock? {
        switch self {
        case .idle:
            nil
        case let .processing(lock), let .completed(lock), let .failed(lock, _), let .cancelled(lock), let .persistenceRecovery(lock, _):
            lock
        }
    }

    public var requestID: AiChatRequestID? { lock?.requestID }
    public var runID: AiChatRunID? { lock?.runID }

    public var isProcessing: Bool {
        if case .processing = self {
            return true
        }
        return false
    }
}
