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

struct SessionSnapshotSavedPayload {
    let summary: AiChatSessionSummary
    let snapshot: AiChatSessionSnapshot?
}

func refreshAiChatTabTitleFromSessionListIfNeeded(
    tabID: ContentTabID,
    action: AiChatAction,
    originContent: FileManagerContentFeature.State,
    state: inout FileManagerWindowState,
) {
    let onlyIfUsingFallback: Bool
    if shouldRefreshActiveAiChatTabTitleFromSessionList(action) {
        onlyIfUsingFallback = false
    } else if case .sessionListLoaded = action {
        onlyIfUsingFallback = true
    } else {
        return
    }

    guard !onlyIfUsingFallback || state.contentTabs.tabs[id: tabID]?.title == "AI Chat",
          case let .aiChat(sessionIDString) = state.contentTabs.tabs[id: tabID]?.anchor,
          let sessionUUID = UUID(uuidString: sessionIDString),
          let summary = originContent.aiChat.sessionList.allRows.first(where: {
              $0.sessionID.rawValue == sessionUUID
          })
    else { return }
    state.updateAiChatTabTitle(sessionID: summary.sessionID, title: summary.title)
}

func shouldRefreshActiveAiChatTabTitleFromSessionList(_ action: AiChatAction) -> Bool {
    switch action {
    case .submitTapped,
         .regenerateTapped,
         .requestContextResolved:
        true
    default:
        false
    }
}

func routeOriginAiChatAction(
    tabID: ContentTabID,
    aiChatAction: AiChatAction,
    originContent: FileManagerContentFeature.State,
    state: inout FileManagerWindowState,
) -> Effect<FileManagerWindowAction> {
    refreshAiChatTabTitleFromSessionListIfNeeded(
        tabID: tabID,
        action: aiChatAction,
        originContent: originContent,
        state: &state,
    )
    let snapshotSessionID = sessionSnapshotSavedSummary(from: aiChatAction)?.sessionID
    let effect = routeBackgroundAiChatAction(aiChatAction, state: &state)
    refreshAiChatFollowUpFromBackgroundIfNeeded(
        aiChatAction,
        backgroundAiChat: originContent.aiChat,
        state: &state,
        skipsActiveContent: true,
    )
    if let snapshotSessionID {
        state.refreshAiChatTabTitleFromCanonicalSummary(sessionID: snapshotSessionID)
    }
    return effect
}

func sessionSnapshotSavedSummary(from aiChatAction: AiChatAction) -> AiChatSessionSummary? {
    sessionSnapshotRefreshPayload(from: aiChatAction)?.summary
}

func sessionSnapshotRefreshPayload(from aiChatAction: AiChatAction) -> SessionSnapshotSavedPayload? {
    switch aiChatAction {
    case let .sessionSnapshotSaved(summary, snapshot, _, _):
        SessionSnapshotSavedPayload(summary: summary, snapshot: snapshot)
    case let .sessionSnapshotUpdated(summary, snapshot, _, _):
        SessionSnapshotSavedPayload(summary: summary, snapshot: snapshot)
    default:
        nil
    }
}

func removeAiChatPendingRequestStart(
    resolutionID: UUID,
    state: inout FileManagerWindowState,
) {
    state.content.aiChat.removePendingRequestStart(resolutionID: resolutionID)
    state.syncActiveTabContentState()

    for tabID in state.tabContentStates.keys {
        state.tabContentStates[tabID]?.aiChat.removePendingRequestStart(resolutionID: resolutionID)
    }

    state.inspector.aiChat.removePendingRequestStart(resolutionID: resolutionID)
    state.syncActiveTabInspectorState()

    for tabID in state.tabInspectorStates.keys {
        state.tabInspectorStates[tabID]?.aiChat.removePendingRequestStart(resolutionID: resolutionID)
    }
}

func refreshAiChatFollowUpFromBackgroundIfNeeded(
    _ aiChatAction: AiChatAction,
    backgroundAiChat: AiChatFeature.State,
    state: inout FileManagerWindowState,
    skipsActiveContent: Bool = false,
    skipsActiveInspector: Bool = false,
) {
    if let payload = sessionSnapshotRefreshPayload(from: aiChatAction) {
        refreshAiChatSnapshotsFromBackgroundIfNeeded(
            summary: payload.summary,
            snapshot: payload.snapshot,
            backgroundAiChat: backgroundAiChat,
            state: &state,
            skipsActiveContent: skipsActiveContent,
            skipsActiveInspector: skipsActiveInspector,
        )
    } else if let failedContext = failedAiChatContext(from: aiChatAction) {
        refreshAiChatFailureFromBackgroundIfNeeded(
            context: failedContext,
            backgroundAiChat: backgroundAiChat,
            state: &state,
            skipsActiveContent: skipsActiveContent,
            skipsActiveInspector: skipsActiveInspector,
        )
    } else if let recoveryLock = persistenceRecoveryLock(from: aiChatAction) {
        refreshAiChatRecoveryFromBackgroundIfNeeded(
            lock: recoveryLock,
            backgroundAiChat: backgroundAiChat,
            state: &state,
            skipsActiveContent: skipsActiveContent,
            skipsActiveInspector: skipsActiveInspector,
        )
    }
}

func removeBackgroundAiChatOwnersPromotedToActiveContent(state: inout FileManagerWindowState) {
    let activeAiChat = state.content.aiChat
    let sessionIDs = activeAiChat.lifecycleOwnerSessionIDs
    for sessionID in sessionIDs {
        guard var backgroundContent = state.backgroundAiChatStates[sessionID] else { continue }
        backgroundContent.aiChat.removeBackgroundOwners(matching: activeAiChat)
        if backgroundContent.aiChat.hasRemainingBackgroundLifecycleOwner {
            state.backgroundAiChatStates[sessionID] = backgroundContent
        } else {
            state.removeBackgroundAiChatState(sessionID: sessionID)
        }
    }
}

func failedAiChatContext(from aiChatAction: AiChatAction) -> AiChatRequestContextSnapshot? {
    guard case let .executionEvent(.failed(context, _)) = aiChatAction else { return nil }
    return context
}

func persistenceRecoveryLock(from aiChatAction: AiChatAction) -> AiChatRequestLock? {
    switch aiChatAction {
    case let .persistenceFailed(lock, _),
         let .persistenceRecoverySucceeded(lock),
         let .persistenceRecoveryRetryFailed(lock, _):
        lock

    default:
        nil
    }
}

func handleBackgroundAiChatSnapshotPersisted(
    _ snapshot: AiChatSessionSnapshot,
    state: inout FileManagerWindowState,
) {
    let summary = AiChatSessionSummary(snapshot: snapshot)
    guard let backgroundContent = state.backgroundAiChatStates[snapshot.sessionID] else { return }
    let ownerRemoval = backgroundAiChatOwnerRemoval(
        requestID: snapshot.lastRequestID,
        runID: snapshot.lastRunID,
        backgroundAiChat: backgroundContent.aiChat,
    )
    admitFreshAiChatContentForPersistedSnapshotIfNeeded(summary: summary, state: &state)
    refreshAiChatSnapshotsFromBackgroundIfNeeded(
        summary: summary,
        snapshot: snapshot,
        backgroundAiChat: backgroundContent.aiChat,
        state: &state,
    )
    removeBackgroundAiChatOwnerFromContentAliases(
        ownerRemoval,
        canonicalSessionID: snapshot.sessionID,
        state: &state,
    )
}

func handleBackgroundInspectorAiChatSnapshotPersisted(
    _ snapshot: AiChatSessionSnapshot,
    state: inout FileManagerWindowState,
) {
    let summary = AiChatSessionSummary(snapshot: snapshot)
    guard let inspectorState = state.backgroundInspectorAiChatStates[snapshot.sessionID] else { return }
    let ownerRemoval = backgroundAiChatOwnerRemoval(
        requestID: snapshot.lastRequestID,
        runID: snapshot.lastRunID,
        backgroundAiChat: inspectorState.aiChat,
    )
    admitFreshAiChatContentForPersistedSnapshotIfNeeded(summary: summary, state: &state)
    refreshAiChatSnapshotsFromBackgroundIfNeeded(
        summary: summary,
        snapshot: snapshot,
        backgroundAiChat: inspectorState.aiChat,
        state: &state,
    )
    removeBackgroundAiChatOwnerFromInspectorAliases(
        ownerRemoval,
        canonicalSessionID: snapshot.sessionID,
        state: &state,
    )
}

func removeBackgroundAiChatOwnerFromContentAliases(
    _ ownerRemoval: BackgroundAiChatOwnerRemoval?,
    canonicalSessionID: AiChatSessionID,
    state: inout FileManagerWindowState,
) {
    let sessionIDs = ownerRemoval?.requestID == nil
        ? [canonicalSessionID]
        : Array(state.backgroundAiChatStates.keys)
    for sessionID in sessionIDs {
        guard var backgroundContent = state.backgroundAiChatStates[sessionID] else { continue }
        backgroundContent.aiChat.removeBackgroundOwner(ownerRemoval)
        if backgroundContent.aiChat.hasRemainingBackgroundLifecycleOwner {
            state.backgroundAiChatStates[sessionID] = backgroundContent
        } else {
            state.removeBackgroundAiChatState(sessionID: sessionID)
        }
    }
}

func removeBackgroundAiChatOwnerFromInspectorAliases(
    _ ownerRemoval: BackgroundAiChatOwnerRemoval?,
    canonicalSessionID: AiChatSessionID,
    state: inout FileManagerWindowState,
) {
    let sessionIDs = ownerRemoval?.requestID == nil
        ? [canonicalSessionID]
        : Array(state.backgroundInspectorAiChatStates.keys)
    for sessionID in sessionIDs {
        guard var inspectorState = state.backgroundInspectorAiChatStates[sessionID] else { continue }
        inspectorState.aiChat.removeBackgroundOwner(ownerRemoval)
        if inspectorState.aiChat.hasRemainingBackgroundLifecycleOwner {
            state.backgroundInspectorAiChatStates[sessionID] = inspectorState.tabSnapshot()
        } else {
            state.removeBackgroundInspectorAiChatState(sessionID: sessionID)
        }
    }
}

struct BackgroundFinalSnapshotContext {
    let response: AiChatResponse
    let lock: AiChatRequestLock
}

func backgroundFinalSnapshotContext(
    from aiChatAction: AiChatAction,
    backgroundAiChat: AiChatFeature.State,
) -> BackgroundFinalSnapshotContext? {
    guard case let .executionEvent(.final(response)) = aiChatAction,
          let lock = finalSnapshotLock(for: response.context, backgroundAiChat: backgroundAiChat)
    else { return nil }

    return BackgroundFinalSnapshotContext(response: response, lock: lock)
}

func finalSnapshotLock(
    for context: AiChatRequestContextSnapshot,
    backgroundAiChat: AiChatFeature.State,
) -> AiChatRequestLock? {
    if case let .processing(lock) = backgroundAiChat.executionPhase,
       lock.context.requestID == context.requestID,
       lock.context.runID == context.runID
    {
        return lock
    }
    if case let .processing(lock) = backgroundAiChat.backgroundExecutionPhases[context.requestID],
       lock.context.runID == context.runID
    {
        return lock
    }
    return nil
}

func makeOffscreenFinalSnapshot(
    summary: AiChatSessionSummary,
    context: BackgroundFinalSnapshotContext,
) -> AiChatSessionSnapshot? {
    let response = context.response
    let lock = context.lock
    guard let sessionID = lock.context.sessionID, sessionID == summary.sessionID else { return nil }
    var transcriptHistory = lock.request.messages
    if let index = lock.assistantReplacementIndex,
       transcriptHistory.indices.contains(index),
       transcriptHistory[index].role == .assistant
    {
        transcriptHistory[index] = response.assistantMessage
    } else {
        transcriptHistory.append(response.assistantMessage)
    }

    return AiChatSessionSnapshot(
        sessionID: sessionID,
        status: .active,
        customTitle: lock.customTitle,
        provider: lock.context.provider,
        model: lock.context.model,
        selectedModelRow: lock.selectedModelRow,
        selectedThinking: lock.context.selectedThinking,
        transcriptHistory: transcriptHistory,
        lastRequestID: lock.requestID,
        lastRunID: lock.runID,
        lastRequestContext: lock.context.requestContext,
        updatedAtMs: summary.updatedAtMs,
    )
}

func refreshAiChatFailureFromBackgroundIfNeeded(
    context: AiChatRequestContextSnapshot,
    backgroundAiChat: AiChatFeature.State,
    state: inout FileManagerWindowState,
    skipsActiveContent: Bool = false,
    skipsActiveInspector: Bool = false,
) {
    guard let sessionID = context.sessionID else { return }
    admitFreshAiChatContentForBackgroundTerminalStateIfNeeded(
        sessionID: sessionID,
        state: &state,
        skipsActiveContent: skipsActiveContent,
    )

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
    guard let sessionID = lock.context.sessionID else { return }
    admitFreshAiChatContentForBackgroundTerminalStateIfNeeded(
        sessionID: sessionID,
        state: &state,
        skipsActiveContent: skipsActiveContent,
    )

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

func admitFreshAiChatContentForBackgroundTerminalStateIfNeeded(
    sessionID: AiChatSessionID,
    state: inout FileManagerWindowState,
    skipsActiveContent: Bool,
) {
    let anchor = ContentTabPageAnchor.aiChat(sessionID: sessionID.rawValue.uuidString)

    if !skipsActiveContent,
       let activeTabID = state.contentTabs.activeTabID,
       state.contentTabs.tabs[id: activeTabID]?.anchor == anchor,
       state.content.aiChat.canAdmitBackgroundTerminalState
    {
        state.content.aiChat.sessionID = sessionID
    }

    for tabID in state.tabContentStates.keys {
        guard tabID != state.contentTabs.activeTabID,
              state.contentTabs.tabs[id: tabID]?.anchor == anchor,
              state.tabContentStates[tabID]?.aiChat.canAdmitBackgroundTerminalState == true
        else {
            continue
        }
        state.tabContentStates[tabID]?.aiChat.sessionID = sessionID
    }
}

func admitFreshAiChatContentForPersistedSnapshotIfNeeded(
    summary: AiChatSessionSummary,
    state: inout FileManagerWindowState,
) {
    let anchor = ContentTabPageAnchor.aiChat(sessionID: summary.sessionID.rawValue.uuidString)

    if let activeTabID = state.contentTabs.activeTabID,
       state.contentTabs.tabs[id: activeTabID]?.anchor == anchor,
       state.content.aiChat.canAdmitPersistedBackgroundSnapshot(summary: summary)
    {
        state.content.aiChat.sessionID = summary.sessionID
    }

    for tabID in state.tabContentStates.keys {
        guard tabID != state.contentTabs.activeTabID,
              state.contentTabs.tabs[id: tabID]?.anchor == anchor,
              state.tabContentStates[tabID]?.aiChat
              .canAdmitPersistedBackgroundSnapshot(summary: summary) == true
        else {
            continue
        }
        state.tabContentStates[tabID]?.aiChat.sessionID = summary.sessionID
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

    var canAdmitBackgroundTerminalState: Bool {
        sessionID == nil
            && restoreSessionID == nil
            && pendingRequestStart == nil
    }

    func canAdmitPersistedBackgroundSnapshot(summary: AiChatSessionSummary) -> Bool {
        sessionID == nil
            && restoreSessionID == nil
            && pendingRequestStart == nil
            && !hasNewerSnapshotThanBackground(summary)
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
