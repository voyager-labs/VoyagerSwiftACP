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
        truncationReason: AiChatHistoryTruncationReason?
    ) {
        self.includedMessageCount = includedMessageCount
        self.excludedMessageCount = excludedMessageCount
        self.budget = budget
        self.truncationReason = truncationReason
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
        wasCancelled: Bool = false
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
            wasCancelled: wasCancelled
        )
    }

    public func recordingTerminal(
        at timestampMs: Int64,
        failure: AiChatExecutionFailure?,
        wasCancelled: Bool
    ) -> Self {
        Self(
            submittedAtMs: submittedAtMs,
            firstDeltaAtMs: firstDeltaAtMs,
            terminalAtMs: timestampMs,
            chunkCount: chunkCount,
            terminalFailure: failure,
            wasCancelled: wasCancelled
        )
    }
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
    public let historyTruncation: AiChatHistoryTruncationMetadata
    public let observabilitySummary: AiChatRequestObservabilitySummary

    public init(
        kind: AiChatRequestKind,
        requestID: AiChatRequestID,
        runID: AiChatRunID,
        context: AiChatRequestContextSnapshot,
        request: AiChatRequest,
        selectedModelHandle: AiModelHandle,
        selectedModelRow: AiModelCatalogRow?,
        assistantReplacementIndex: Int?,
        historyTruncation: AiChatHistoryTruncationMetadata = .init(
            includedMessageCount: 0,
            excludedMessageCount: 0,
            budget: 24_000,
            truncationReason: nil
        ),
        observabilitySummary: AiChatRequestObservabilitySummary = .init(submittedAtMs: 0)
    ) {
        self.kind = kind
        self.requestID = requestID
        self.runID = runID
        self.context = context
        self.request = request
        self.selectedModelHandle = selectedModelHandle
        self.selectedModelRow = selectedModelRow
        self.assistantReplacementIndex = assistantReplacementIndex
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
            selectedModelHandle: selectedModelHandle,
            selectedModelRow: selectedModelRow,
            assistantReplacementIndex: assistantReplacementIndex,
            historyTruncation: historyTruncation,
            observabilitySummary: observabilitySummary.recordingDelta(at: timestampMs)
        )
    }

    public func recordingTerminal(
        at timestampMs: Int64,
        failure: AiChatExecutionFailure?,
        wasCancelled: Bool
    ) -> Self {
        Self(
            kind: kind,
            requestID: requestID,
            runID: runID,
            context: context,
            request: request,
            selectedModelHandle: selectedModelHandle,
            selectedModelRow: selectedModelRow,
            assistantReplacementIndex: assistantReplacementIndex,
            historyTruncation: historyTruncation,
            observabilitySummary: observabilitySummary.recordingTerminal(
                at: timestampMs,
                failure: failure,
                wasCancelled: wasCancelled
            )
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

    public var requestID: AiChatRequestID? { lock?.requestID }
    public var runID: AiChatRunID? { lock?.runID }

    public var isProcessing: Bool {
        if case .processing = self {
            return true
        }
        return false
    }
}
