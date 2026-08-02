import AppKit
import ComposableArchitecture
import Foundation
import VoyagerEntitiesAi
import VoyagerEntitiesCollection
import VoyagerEntitiesEntry
import VoyagerFeaturesAiChat
import VoyagerFeaturesComposer
import VoyagerFeaturesContentPageNavigation
import VoyagerFeaturesEntryOperations
import VoyagerShared

func refreshAiChatFailureFromBackgroundIfNeeded(
    context: AiChatRequestContextSnapshot,
    backgroundAiChat: AiChatFeature.State,
    state: inout FileManagerWindowState,
    skipsActiveContent: Bool = false,
    skipsActiveInspector: Bool = false,
) {
    guard context.sessionID != nil else { return }

    if !skipsActiveContent,
       state.content.aiChat.canRefreshFailureFromBackground(context: context)
    {
        state.content.aiChat.applyBackgroundFailure(context: context, backgroundAiChat: backgroundAiChat)
        state.syncActiveTabContentState()
    }

    for tabID in state.tabContentStates.keys {
        guard tabID != state.contentTabs.activeTabID else { continue }
        guard state.tabContentStates[tabID]?.aiChat.canRefreshFailureFromBackground(context: context) == true
        else { continue }
        state.tabContentStates[tabID]?.aiChat.applyBackgroundFailure(
            context: context,
            backgroundAiChat: backgroundAiChat,
        )
    }

    if !skipsActiveInspector,
       state.inspector.aiChat.canRefreshFailureFromBackground(context: context)
    {
        state.inspector.aiChat.applyBackgroundFailure(context: context, backgroundAiChat: backgroundAiChat)
        state.syncActiveTabInspectorState()
    }

    for tabID in state.tabInspectorStates.keys {
        guard tabID != state.contentTabs.activeTabID else { continue }
        guard state.tabInspectorStates[tabID]?.aiChat.canRefreshFailureFromBackground(context: context) == true
        else { continue }
        state.tabInspectorStates[tabID]?.aiChat.applyBackgroundFailure(
            context: context,
            backgroundAiChat: backgroundAiChat,
        )
    }
}

func refreshAiChatRecoveryFromBackgroundIfNeeded(
    lock: AiChatRequestLock,
    backgroundAiChat: AiChatFeature.State,
    state: inout FileManagerWindowState,
    skipsActiveContent: Bool = false,
    skipsActiveInspector: Bool = false,
) {
    guard lock.context.sessionID != nil else { return }

    if !skipsActiveContent,
       state.content.aiChat.canRefreshRecoveryFromBackground(lock: lock)
    {
        state.content.aiChat.applyBackgroundRecovery(lock: lock, backgroundAiChat: backgroundAiChat)
        state.syncActiveTabContentState()
    }

    for tabID in state.tabContentStates.keys {
        guard tabID != state.contentTabs.activeTabID else { continue }
        guard state.tabContentStates[tabID]?.aiChat.canRefreshRecoveryFromBackground(lock: lock) == true
        else { continue }
        state.tabContentStates[tabID]?.aiChat.applyBackgroundRecovery(
            lock: lock,
            backgroundAiChat: backgroundAiChat,
        )
    }

    if !skipsActiveInspector,
       state.inspector.aiChat.canRefreshRecoveryFromBackground(lock: lock)
    {
        state.inspector.aiChat.applyBackgroundRecovery(lock: lock, backgroundAiChat: backgroundAiChat)
        state.syncActiveTabInspectorState()
    }

    for tabID in state.tabInspectorStates.keys {
        guard tabID != state.contentTabs.activeTabID else { continue }
        guard state.tabInspectorStates[tabID]?.aiChat.canRefreshRecoveryFromBackground(lock: lock) == true
        else { continue }
        state.tabInspectorStates[tabID]?.aiChat.applyBackgroundRecovery(
            lock: lock,
            backgroundAiChat: backgroundAiChat,
        )
    }
}

func refreshAiChatSnapshotsFromBackgroundIfNeeded(
    summary: AiChatSessionSummary,
    snapshot: AiChatSessionSnapshot? = nil,
    backgroundAiChat: AiChatFeature.State,
    state: inout FileManagerWindowState,
    skipsActiveContent: Bool = false,
    skipsActiveInspector: Bool = false,
) {
    if !skipsActiveContent,
       state.content.aiChat.canRefreshFromBackground(summary: summary, snapshot: snapshot)
    {
        state.content.aiChat.applyBackgroundSnapshot(
            summary: summary,
            snapshot: snapshot,
            backgroundAiChat: backgroundAiChat,
        )
        state.syncActiveTabContentState()
    }

    for tabID in state.tabContentStates.keys {
        guard tabID != state.contentTabs.activeTabID else { continue }
        guard state.tabContentStates[tabID]?.aiChat
            .canRefreshFromBackground(summary: summary, snapshot: snapshot) == true
        else {
            continue
        }
        state.tabContentStates[tabID]?.aiChat.applyBackgroundSnapshot(
            summary: summary,
            snapshot: snapshot,
            backgroundAiChat: backgroundAiChat,
        )
    }

    if !skipsActiveInspector,
       state.inspector.aiChat.canRefreshFromBackground(summary: summary, snapshot: snapshot)
    {
        state.inspector.aiChat.applyBackgroundSnapshot(
            summary: summary,
            snapshot: snapshot,
            backgroundAiChat: backgroundAiChat,
        )
        state.syncActiveTabInspectorState()
    }

    for tabID in state.tabInspectorStates.keys {
        guard tabID != state.contentTabs.activeTabID else { continue }
        guard state.tabInspectorStates[tabID]?.aiChat
            .canRefreshFromBackground(summary: summary, snapshot: snapshot) == true
        else {
            continue
        }
        state.tabInspectorStates[tabID]?.aiChat.applyBackgroundSnapshot(
            summary: summary,
            snapshot: snapshot,
            backgroundAiChat: backgroundAiChat,
        )
    }
}

extension AiChatFeature.State {
    func canRefreshRecoveryFromBackground(lock: AiChatRequestLock) -> Bool {
        guard sessionID == lock.context.sessionID,
              pendingRequestStart == nil
        else { return false }
        guard executionPhase.isProcessing else { return true }
        return executionPhase.matchesOwner(requestID: lock.requestID, runID: lock.runID)
    }

    mutating func applyBackgroundRecovery(
        lock: AiChatRequestLock,
        backgroundAiChat: AiChatFeature.State,
    ) {
        guard let matchingPhase = backgroundAiChat.backgroundExecutionPhases[lock.requestID]?
            .matchingRecoveryFollowUp(lock: lock)
            ?? backgroundAiChat.executionPhase.matchingRecoveryFollowUp(lock: lock)
        else { return }

        if let finalSnapshot = matchingPhase.lock?.finalSnapshot ?? lock.finalSnapshot {
            applyBackgroundRecoveryFinalSnapshot(finalSnapshot)
        } else if let lock = matchingPhase.lock {
            applyBackgroundLockPayload(lock)
        }
        executionPhase = matchingPhase
        streamingAssistantDraft = nil
        lockedModelHandle = nil
        if case let .persistenceRecovery(_, failure) = matchingPhase {
            lastExecutionFailure = failure
        } else {
            lastExecutionFailure = nil
        }
    }

    mutating func applyBackgroundRecoveryFinalSnapshot(_ snapshot: AiChatSessionSnapshot) {
        sessionID = snapshot.sessionID
        sessionStatus = snapshot.status
        currentSessionCustomTitle = snapshot.customTitle
        transcriptHistory = snapshot.transcriptHistory
        transcriptAutoScrollVersion += 1
        lastRequestContext = snapshot.lastRequestContext
        lastRequestContextModelHandle = snapshot.model
        selectedModelHandle = snapshot.model
        selectedThinking = snapshot.selectedThinking
    }

    mutating func applyBackgroundLockPayload(_ lock: AiChatRequestLock) {
        transcriptHistory = lock.persistenceTranscriptHistory
        lastRequestContext = lock.context.requestContext
        lastRequestContextModelHandle = lock.context.model
        selectedModelHandle = lock.context.model
        selectedThinking = lock.context.selectedThinking
        transcriptAutoScrollVersion += 1
    }

    func matchingBackgroundSnapshot(
        summary: AiChatSessionSummary,
        snapshot: AiChatSessionSnapshot?,
    ) -> AiChatExecutionPhase? {
        guard let requestID = snapshot?.lastRequestID else {
            return executionPhase.matchingBackgroundSnapshot(
                summary: summary,
                snapshot: snapshot,
            )
        }
        if let backgroundPhase = backgroundExecutionPhases[requestID]?.matchingBackgroundSnapshot(
            summary: summary,
            snapshot: snapshot,
        ) {
            return backgroundPhase
        }
        guard executionPhase.matchesOwner(requestID: requestID, runID: snapshot?.lastRunID) else { return nil }
        if case let .processing(lock) = executionPhase,
           let snapshot,
           snapshot.transcriptHistory.count > lock.request.messages.count
        {
            return .completed(lock.recordingFinalSnapshot(snapshot))
        }
        return executionPhase.matchingBackgroundSnapshot(
            summary: summary,
            snapshot: snapshot,
        )
    }

    func hasBackgroundOwnerMatching(requestID: AiChatRequestID, runID: AiChatRunID?) -> Bool {
        executionPhase.matchesOwner(requestID: requestID, runID: runID)
            || backgroundExecutionPhases[requestID]?.matchesOwner(requestID: requestID, runID: runID) == true
    }

    var hasRemainingBackgroundLifecycleOwner: Bool {
        pendingRequestStart != nil
            || !backgroundPendingRequestStarts.isEmpty
            || executionPhase.lock != nil
            || !backgroundExecutionPhases.isEmpty
    }

    mutating func removeBackgroundOwner(_ removal: BackgroundAiChatOwnerRemoval?) {
        guard let removal else { return }
        guard let requestID = removal.requestID else {
            if removal.removeLegacySessionOwner {
                pendingRequestStart = nil
                executionPhase = .idle
                backgroundExecutionPhases = [:]
            }
            return
        }
        if executionPhase.matchesOwner(requestID: requestID, runID: removal.runID) {
            executionPhase = .idle
        }
        if backgroundExecutionPhases[requestID]?.matchesOwner(requestID: requestID, runID: removal.runID) == true {
            backgroundExecutionPhases[requestID] = nil
        }
    }

    func canRefreshFailureFromBackground(context: AiChatRequestContextSnapshot) -> Bool {
        guard sessionID == context.sessionID,
              pendingRequestStart == nil
        else { return false }
        guard executionPhase.isProcessing else { return true }
        return executionPhase.matchesOwner(requestID: context.requestID, runID: context.runID)
    }

    mutating func applyBackgroundFailure(
        context: AiChatRequestContextSnapshot,
        backgroundAiChat: AiChatFeature.State,
    ) {
        guard let matchingPhase = backgroundAiChat.backgroundExecutionPhases[context.requestID]?
            .matchingFailure(context: context)
            ?? backgroundAiChat.executionPhase.matchingFailure(context: context)
        else { return }
        if let lock = matchingPhase.lock {
            applyBackgroundLockPayload(lock)
        }
        executionPhase = matchingPhase
        streamingAssistantDraft = nil
        lockedModelHandle = nil
        if case let .failed(_, failure) = matchingPhase {
            lastExecutionFailure = failure
        }
    }

    func canRefreshFromBackground(
        summary: AiChatSessionSummary,
        snapshot: AiChatSessionSnapshot? = nil,
    ) -> Bool {
        guard sessionID == summary.sessionID,
              pendingRequestStart == nil,
              !hasNewerSnapshotThanBackground(summary)
        else { return false }
        guard executionPhase.isProcessing else { return true }
        guard let requestID = snapshot?.lastRequestID else { return false }
        return executionPhase.matchesOwner(requestID: requestID, runID: snapshot?.lastRunID)
    }

    private func hasNewerSnapshotThanBackground(_ summary: AiChatSessionSummary) -> Bool {
        if let currentRow = sessionList.allRows.first(where: { $0.sessionID == summary.sessionID }),
           currentRow.isNewer(than: summary)
        {
            return true
        }
        if transcriptHistory.count > summary.messageCount {
            return true
        }
        if let lock = executionPhase.lock,
           lock.context.sessionID == summary.sessionID,
           let terminalAtMs = lock.observabilitySummary.terminalAtMs,
           terminalAtMs > summary.updatedAtMs
        {
            return true
        }
        return false
    }

    mutating func applyBackgroundSnapshot(
        summary: AiChatSessionSummary,
        snapshot: AiChatSessionSnapshot? = nil,
        backgroundAiChat: AiChatFeature.State,
    ) {
        let mergeResult = sessionList.replaceRowIfNewer(summary)
        guard mergeResult.acceptsRow else { return }
        if mergeResult.permitsSnapshotPayload {
            if let snapshot {
                currentSessionCustomTitle = snapshot.customTitle
            } else {
                currentSessionCustomTitle = backgroundAiChat.currentSessionCustomTitle
            }
            transcriptHistory = snapshot?.transcriptHistory ?? backgroundAiChat.transcriptHistory
            streamingAssistantDraft = nil
            transcriptAutoScrollVersion += 1
            lockedModelHandle = nil
            lastExecutionFailure = nil
            lastRequestContext = snapshot?.lastRequestContext ?? backgroundAiChat.lastRequestContext
            lastRequestContextModelHandle = snapshot?.model ?? backgroundAiChat.lastRequestContextModelHandle
            selectedModelHandle = snapshot?.model ?? backgroundAiChat.selectedModelHandle
            selectedThinking = snapshot?.selectedThinking ?? backgroundAiChat.selectedThinking
            sessionStatus = snapshot?.status ?? .active
            if let executionPhaseToApply = backgroundAiChat.matchingBackgroundSnapshot(
                summary: summary,
                snapshot: snapshot,
            ) ?? matchingBackgroundSnapshot(
                summary: summary,
                snapshot: snapshot,
            ) {
                executionPhase = executionPhaseToApply
            }
        }

        if restoreSessionID == nil || restoreSessionID == summary.sessionID {
            sessionList.selectedSessionID = summary.sessionID
        }
        if mode == .chat {
            sessionList.unreadCompletedSessionIDs.remove(summary.sessionID)
        } else {
            sessionList.unreadCompletedSessionIDs.insert(summary.sessionID)
        }
        sessionList.errorMessage = nil
    }
}

extension AiChatExecutionPhase {
    func matchesOwner(requestID: AiChatRequestID, runID: AiChatRunID?) -> Bool {
        guard let lock else { return false }
        if let runID {
            return lock.requestID == requestID && lock.runID == runID
        }
        return lock.requestID == requestID
    }

    func matchingRecoveryFollowUp(lock expectedLock: AiChatRequestLock) -> Self? {
        guard let lock,
              lock.context.sessionID == expectedLock.context.sessionID,
              lock.requestID == expectedLock.requestID,
              lock.runID == expectedLock.runID
        else { return nil }

        switch self {
        case .completed, .persistenceRecovery:
            return self
        case .idle, .processing, .failed, .cancelled:
            return nil
        }
    }

    func matchingFailure(context: AiChatRequestContextSnapshot) -> Self? {
        guard let lock,
              lock.context.sessionID == context.sessionID,
              lock.requestID == context.requestID,
              lock.runID == context.runID,
              case .failed = self
        else { return nil }
        return self
    }

    func matchingBackgroundSnapshot(
        summary: AiChatSessionSummary,
        snapshot: AiChatSessionSnapshot?,
    ) -> Self? {
        guard let lock, lock.context.sessionID == summary.sessionID else { return nil }
        if let requestID = snapshot?.lastRequestID, lock.requestID != requestID {
            return nil
        }
        if let runID = snapshot?.lastRunID, lock.runID != runID {
            return nil
        }
        return self
    }
}
