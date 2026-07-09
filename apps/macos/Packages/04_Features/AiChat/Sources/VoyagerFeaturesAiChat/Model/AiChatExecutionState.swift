import Foundation
import VoyagerEntitiesAi

public enum AiChatRequestKind: Equatable, Sendable {
    case submit
    case regenerate
}

public enum AiChatHistoryTruncationReason: String, Equatable, Sendable {
    case characterBudgetExceeded
}

public struct AiChatHistoryTruncationMetadata: Equatable, Sendable {
    public let includedMessageCount: Int
    public let excludedMessageCount: Int
    public let budget: Int
    public let truncationReason: AiChatHistoryTruncationReason?

    public init(
        includedMessageCount: Int,
        excludedMessageCount: Int,
        budget: Int,
        truncationReason: AiChatHistoryTruncationReason?,
    ) {
        self.includedMessageCount = includedMessageCount
        self.excludedMessageCount = excludedMessageCount
        self.budget = budget
        self.truncationReason = truncationReason
    }
}

public struct AiChatPreparedRequest: Equatable, Sendable {
    public var prompt: String
    public var messages: [AiChatMessage]
    public var persistenceTranscriptHistory: [AiChatMessage]
    public var assistantReplacementIndex: Int?
    public var historyTruncation: AiChatHistoryTruncationMetadata
    public var requestContextOverride: AiChatLockedRequestContextSnapshot?
    public var requestContextSource: AiChatLockedRequestContextSnapshot?

    public init(
        prompt: String,
        messages: [AiChatMessage],
        persistenceTranscriptHistory: [AiChatMessage]? = nil,
        assistantReplacementIndex: Int?,
        historyTruncation: AiChatHistoryTruncationMetadata,
        requestContextOverride: AiChatLockedRequestContextSnapshot? = nil,
        requestContextSource: AiChatLockedRequestContextSnapshot? = nil,
    ) {
        self.prompt = prompt
        self.messages = messages
        self.persistenceTranscriptHistory = persistenceTranscriptHistory ?? messages
        self.assistantReplacementIndex = assistantReplacementIndex
        self.historyTruncation = historyTruncation
        self.requestContextOverride = requestContextOverride
        self.requestContextSource = requestContextSource
    }
}

public struct AiChatPendingRequestStart: Equatable, Sendable {
    public var resolutionID: UUID
    public var kind: AiChatRequestKind
    public var sessionID: AiChatSessionID
    public var selectedModel: AiProviderModel
    public var selectedRow: AiModelCatalogRow?
    public var selectedThinking: AiThinkingSelection?
    public var customTitle: String?
    public var preparedRequest: AiChatPreparedRequest

    public init(
        resolutionID: UUID,
        kind: AiChatRequestKind,
        sessionID: AiChatSessionID,
        selectedModel: AiProviderModel,
        selectedRow: AiModelCatalogRow?,
        selectedThinking: AiThinkingSelection? = nil,
        customTitle: String? = nil,
        preparedRequest: AiChatPreparedRequest,
    ) {
        self.resolutionID = resolutionID
        self.kind = kind
        self.sessionID = sessionID
        self.selectedModel = selectedModel
        self.selectedRow = selectedRow
        self.selectedThinking = selectedThinking
        self.customTitle = customTitle
        self.preparedRequest = preparedRequest
    }
}

public struct AiChatRequestObservabilitySummary: Equatable, Sendable {
    public let submittedAtMs: Int64
    public let firstDeltaAtMs: Int64?
    public let terminalAtMs: Int64?
    public let chunkCount: Int
    public let terminalFailure: AiChatExecutionFailure?
    public let wasCancelled: Bool

    public var requestDurationMs: Int64? {
        guard let terminalAtMs else { return nil }
        return terminalAtMs - submittedAtMs
    }

    public var timeToFirstDeltaMs: Int64? {
        guard let firstDeltaAtMs else { return nil }
        return firstDeltaAtMs - submittedAtMs
    }

    public init(
        submittedAtMs: Int64,
        firstDeltaAtMs: Int64? = nil,
        terminalAtMs: Int64? = nil,
        chunkCount: Int = 0,
        terminalFailure: AiChatExecutionFailure? = nil,
        wasCancelled: Bool = false,
    ) {
        self.submittedAtMs = submittedAtMs
        self.firstDeltaAtMs = firstDeltaAtMs
        self.terminalAtMs = terminalAtMs
        self.chunkCount = chunkCount
        self.terminalFailure = terminalFailure
        self.wasCancelled = wasCancelled
    }

    public func recordingDelta(at timestampMs: Int64) -> Self {
        Self(
            submittedAtMs: submittedAtMs,
            firstDeltaAtMs: firstDeltaAtMs ?? timestampMs,
            terminalAtMs: terminalAtMs,
            chunkCount: chunkCount + 1,
            terminalFailure: terminalFailure,
            wasCancelled: wasCancelled,
        )
    }

    public func recordingTerminal(
        at timestampMs: Int64,
        failure: AiChatExecutionFailure?,
        wasCancelled: Bool,
    ) -> Self {
        Self(
            submittedAtMs: submittedAtMs,
            firstDeltaAtMs: firstDeltaAtMs,
            terminalAtMs: timestampMs,
            chunkCount: chunkCount,
            terminalFailure: failure,
            wasCancelled: wasCancelled,
        )
    }
}

public struct AiChatRequestLock: Equatable, Sendable {
    public let kind: AiChatRequestKind
    public let requestID: AiChatRequestID
    public let runID: AiChatRunID
    public let context: AiChatRequestContextSnapshot
    public let request: AiChatRequest
    public let persistenceTranscriptHistory: [AiChatMessage]
    public let selectedModelHandle: AiModelHandle
    public let selectedModelRow: AiModelCatalogRow?
    public let assistantReplacementIndex: Int?
    public let customTitle: String?
    public let finalSnapshot: AiChatSessionSnapshot?
    public let historyTruncation: AiChatHistoryTruncationMetadata
    public let observabilitySummary: AiChatRequestObservabilitySummary

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.kind == rhs.kind
            && lhs.requestID == rhs.requestID
            && lhs.runID == rhs.runID
            && lhs.context == rhs.context
            && lhs.request == rhs.request
            && lhs.persistenceTranscriptHistory == rhs.persistenceTranscriptHistory
            && lhs.selectedModelHandle == rhs.selectedModelHandle
            && lhs.selectedModelRow == rhs.selectedModelRow
            && lhs.assistantReplacementIndex == rhs.assistantReplacementIndex
            && lhs.customTitle == rhs.customTitle
            && lhs.historyTruncation == rhs.historyTruncation
            && lhs.observabilitySummary == rhs.observabilitySummary
    }

    public init(
        kind: AiChatRequestKind,
        requestID: AiChatRequestID,
        runID: AiChatRunID,
        context: AiChatRequestContextSnapshot,
        request: AiChatRequest,
        persistenceTranscriptHistory: [AiChatMessage]? = nil,
        selectedModelHandle: AiModelHandle,
        selectedModelRow: AiModelCatalogRow?,
        assistantReplacementIndex: Int?,
        customTitle: String? = nil,
        finalSnapshot: AiChatSessionSnapshot? = nil,
        historyTruncation: AiChatHistoryTruncationMetadata = .init(
            includedMessageCount: 0,
            excludedMessageCount: 0,
            budget: 24000,
            truncationReason: nil,
        ),
        observabilitySummary: AiChatRequestObservabilitySummary = .init(submittedAtMs: 0),
    ) {
        self.kind = kind
        self.requestID = requestID
        self.runID = runID
        self.context = context
        self.request = request
        self.persistenceTranscriptHistory = persistenceTranscriptHistory ?? request.messages
        self.selectedModelHandle = selectedModelHandle
        self.selectedModelRow = selectedModelRow
        self.assistantReplacementIndex = assistantReplacementIndex
        self.customTitle = customTitle
        self.finalSnapshot = finalSnapshot
        self.historyTruncation = historyTruncation
        self.observabilitySummary = observabilitySummary
    }

    public init(
        kind: AiChatRequestKind,
        requestID: AiChatRequestID,
        runID: AiChatRunID,
        context: AiChatRequestContextSnapshot,
        request: AiChatRequest,
        persistenceTranscriptHistory: [AiChatMessage]? = nil,
        selectedModelHandle: AiModelHandle,
        selectedModelRow: AiModelCatalogRow?,
        assistantReplacementIndex: Int?,
        historyTruncation: AiChatHistoryTruncationMetadata = .init(
            includedMessageCount: 0,
            excludedMessageCount: 0,
            budget: 24000,
            truncationReason: nil,
        ),
        observabilitySummary: AiChatRequestObservabilitySummary = .init(submittedAtMs: 0),
    ) {
        self.kind = kind
        self.requestID = requestID
        self.runID = runID
        self.context = context
        self.request = request
        self.persistenceTranscriptHistory = persistenceTranscriptHistory ?? request.messages
        self.selectedModelHandle = selectedModelHandle
        self.selectedModelRow = selectedModelRow
        self.assistantReplacementIndex = assistantReplacementIndex
        customTitle = nil
        finalSnapshot = nil
        self.historyTruncation = historyTruncation
        self.observabilitySummary = observabilitySummary
    }

    public func recordingDelta(at timestampMs: Int64) -> Self {
        Self(
            kind: kind,
            requestID: requestID,
            runID: runID,
            context: context,
            request: request,
            persistenceTranscriptHistory: persistenceTranscriptHistory,
            selectedModelHandle: selectedModelHandle,
            selectedModelRow: selectedModelRow,
            assistantReplacementIndex: assistantReplacementIndex,
            customTitle: customTitle,
            finalSnapshot: finalSnapshot,
            historyTruncation: historyTruncation,
            observabilitySummary: observabilitySummary.recordingDelta(at: timestampMs),
        )
    }

    public func recordingTerminal(
        at timestampMs: Int64,
        failure: AiChatExecutionFailure?,
        wasCancelled: Bool,
    ) -> Self {
        Self(
            kind: kind,
            requestID: requestID,
            runID: runID,
            context: context,
            request: request,
            persistenceTranscriptHistory: persistenceTranscriptHistory,
            selectedModelHandle: selectedModelHandle,
            selectedModelRow: selectedModelRow,
            assistantReplacementIndex: assistantReplacementIndex,
            customTitle: customTitle,
            finalSnapshot: finalSnapshot,
            historyTruncation: historyTruncation,
            observabilitySummary: observabilitySummary.recordingTerminal(
                at: timestampMs,
                failure: failure,
                wasCancelled: wasCancelled,
            ),
        )
    }

    public func recordingFinalSnapshot(_ snapshot: AiChatSessionSnapshot) -> Self {
        Self(
            kind: kind,
            requestID: requestID,
            runID: runID,
            context: context,
            request: request,
            persistenceTranscriptHistory: persistenceTranscriptHistory,
            selectedModelHandle: selectedModelHandle,
            selectedModelRow: selectedModelRow,
            assistantReplacementIndex: assistantReplacementIndex,
            customTitle: customTitle,
            finalSnapshot: snapshot,
            historyTruncation: historyTruncation,
            observabilitySummary: observabilitySummary,
        )
    }

    public func recordingCustomTitle(_ customTitle: String?) -> Self {
        Self(
            kind: kind,
            requestID: requestID,
            runID: runID,
            context: context,
            request: request,
            persistenceTranscriptHistory: persistenceTranscriptHistory,
            selectedModelHandle: selectedModelHandle,
            selectedModelRow: selectedModelRow,
            assistantReplacementIndex: assistantReplacementIndex,
            customTitle: customTitle,
            finalSnapshot: finalSnapshot.map { Self.snapshot($0, customTitle: customTitle) },
            historyTruncation: historyTruncation,
            observabilitySummary: observabilitySummary,
        )
    }

    private static func snapshot(
        _ snapshot: AiChatSessionSnapshot,
        customTitle: String?,
    ) -> AiChatSessionSnapshot {
        AiChatSessionSnapshot(
            sessionID: snapshot.sessionID,
            status: snapshot.status,
            customTitle: customTitle,
            provider: snapshot.provider,
            model: snapshot.model,
            selectedModelRow: snapshot.selectedModelRow,
            selectedThinking: snapshot.selectedThinking,
            transcriptHistory: snapshot.transcriptHistory,
            lastRequestID: snapshot.lastRequestID,
            lastRunID: snapshot.lastRunID,
            lastRequestContext: snapshot.lastRequestContext,
            updatedAtMs: snapshot.updatedAtMs,
        )
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
        case let .processing(lock),
             let .completed(lock),
             let .failed(lock, _),
             let .cancelled(lock),
             let .persistenceRecovery(lock, _):
            lock
        }
    }

    public var requestID: AiChatRequestID? {
        lock?.requestID
    }

    public var runID: AiChatRunID? {
        lock?.runID
    }

    public var isProcessing: Bool {
        if case .processing = self {
            return true
        }
        return false
    }
}

public extension AiChatExecutionPhase {
    var processingSessionID: AiChatSessionID? {
        guard case let .processing(lock) = self else { return nil }
        return lock.context.sessionID
    }
}
