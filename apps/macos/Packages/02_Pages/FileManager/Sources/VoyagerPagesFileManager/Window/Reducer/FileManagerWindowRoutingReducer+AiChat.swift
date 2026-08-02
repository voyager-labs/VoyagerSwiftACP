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

func aiChatLifecycleSessionIDsToPreserve(_ state: AiChatFeature.State) -> [AiChatSessionID] {
    var sessionIDs: [AiChatSessionID] = []
    func append(_ sessionID: AiChatSessionID?) {
        guard let sessionID, !sessionIDs.contains(sessionID) else { return }
        sessionIDs.append(sessionID)
    }

    if state.executionPhase.isProcessing
        || state.executionPhase.shouldPreserveLifecycleOwner
    {
        append(state.executionPhase.lock?.context.sessionID)
    }
    append(state.pendingRequestStart?.sessionID)
    for pendingRequestStart in state.backgroundPendingRequestStarts.values {
        append(pendingRequestStart.sessionID)
    }
    for phase in state.backgroundExecutionPhases.values where phase.isProcessing || phase.shouldPreserveLifecycleOwner {
        append(phase.lock?.context.sessionID)
    }
    return sessionIDs
}

func cancelAndRemoveBackgroundAiChatOwners(
    sessionID: AiChatSessionID,
    state: inout FileManagerWindowState,
) -> Effect<FileManagerWindowAction> {
    var effects: [Effect<FileManagerWindowAction>] = []
    if let backgroundContent = state.removeBackgroundAiChatState(sessionID: sessionID) {
        effects.append(cancelBackgroundAiChatWork(sessionID: sessionID, aiChat: backgroundContent.aiChat))
    }
    if let backgroundInspector = state.removeBackgroundInspectorAiChatState(sessionID: sessionID) {
        effects.append(cancelBackgroundInspectorAiChatWork(sessionID: sessionID, aiChat: backgroundInspector.aiChat))
    }

    for backgroundSessionID in state.backgroundAiChatStates.keys {
        guard var backgroundContent = state.backgroundAiChatStates[backgroundSessionID],
              backgroundContent.aiChat.hasLifecycleOwner(sessionID: sessionID)
        else { continue }
        effects.append(cancelBackgroundAiChatWork(sessionID: sessionID, aiChat: backgroundContent.aiChat))
        backgroundContent.aiChat.removeLifecycleOwners(sessionID: sessionID)
        if backgroundContent.aiChat.hasRemainingBackgroundLifecycleOwner {
            state.backgroundAiChatStates[backgroundSessionID] = backgroundContent
        } else {
            state.removeBackgroundAiChatState(sessionID: backgroundSessionID)
        }
    }

    for backgroundSessionID in state.backgroundInspectorAiChatStates.keys {
        guard var backgroundInspector = state.backgroundInspectorAiChatStates[backgroundSessionID],
              backgroundInspector.aiChat.hasLifecycleOwner(sessionID: sessionID)
        else { continue }
        effects.append(cancelBackgroundInspectorAiChatWork(sessionID: sessionID, aiChat: backgroundInspector.aiChat))
        backgroundInspector.aiChat.removeLifecycleOwners(sessionID: sessionID)
        if backgroundInspector.aiChat.hasRemainingBackgroundLifecycleOwner {
            state.backgroundInspectorAiChatStates[backgroundSessionID] = backgroundInspector.tabSnapshot()
        } else {
            state.removeBackgroundInspectorAiChatState(sessionID: backgroundSessionID)
        }
    }
    return .merge(effects)
}

func cancelBackgroundAiChatWork(
    sessionID: AiChatSessionID,
    aiChat: AiChatFeature.State,
) -> Effect<FileManagerWindowAction> {
    var scopedAiChat = aiChat.cancellationScope(sessionID: sessionID)
    return AiChatFeature()
        .reduce(into: &scopedAiChat, action: .cancelRequestLifecycle(sessionID))
        .map { FileManagerWindowAction.backgroundAiChat($0) }
}

func cancelBackgroundInspectorAiChatWork(
    sessionID: AiChatSessionID,
    aiChat: AiChatFeature.State,
) -> Effect<FileManagerWindowAction> {
    var scopedAiChat = aiChat.cancellationScope(sessionID: sessionID)
    return AiChatFeature()
        .reduce(into: &scopedAiChat, action: .cancelRequestLifecycle(sessionID))
        .map { FileManagerWindowAction.backgroundInspectorAiChat($0) }
}

func propagateAiChatSessionDeleteSucceeded(
    sessionID: AiChatSessionID,
    state: inout FileManagerWindowState,
) {
    state.content.aiChat.applySessionDeleteSucceeded(sessionID: sessionID)
    state.syncActiveTabContentState()

    for tabID in state.tabContentStates.keys {
        state.tabContentStates[tabID]?.aiChat.applySessionDeleteSucceeded(sessionID: sessionID)
    }

    state.inspector.aiChat.applySessionDeleteSucceeded(sessionID: sessionID)
    state.syncActiveTabInspectorState()

    for tabID in state.tabInspectorStates.keys {
        state.tabInspectorStates[tabID]?.aiChat.applySessionDeleteSucceeded(sessionID: sessionID)
    }

    state.removeBackgroundAiChatState(sessionID: sessionID)
    state.removeBackgroundInspectorAiChatState(sessionID: sessionID)

    for sessionKey in Array(state.backgroundAiChatStates.keys) {
        state.backgroundAiChatStates[sessionKey]?.aiChat.applySessionDeleteSucceeded(sessionID: sessionID)
    }
    for sessionKey in Array(state.backgroundInspectorAiChatStates.keys) {
        if var backgroundInspector = state.backgroundInspectorAiChatStates[sessionKey] {
            backgroundInspector.aiChat.applySessionDeleteSucceeded(sessionID: sessionID)
            state.backgroundInspectorAiChatStates[sessionKey] = backgroundInspector.tabSnapshot()
        }
    }
}

func refreshAiChatCustomTitle(
    summary: AiChatSessionSummary,
    customTitle: String?,
    state: inout FileManagerWindowState,
) {
    let sessionID = summary.sessionID
    state.content.aiChat.refreshCustomTitle(summary: summary, customTitle: customTitle)
    state.syncActiveTabContentState()

    for tabID in state.tabContentStates.keys {
        state.tabContentStates[tabID]?.aiChat.refreshCustomTitle(summary: summary, customTitle: customTitle)
    }

    state.inspector.aiChat.refreshCustomTitle(summary: summary, customTitle: customTitle)
    state.syncActiveTabInspectorState()

    for tabID in state.tabInspectorStates.keys {
        state.tabInspectorStates[tabID]?.aiChat.refreshCustomTitle(summary: summary, customTitle: customTitle)
    }

    if var backgroundContent = state.backgroundAiChatStates[sessionID] {
        backgroundContent.aiChat.refreshCustomTitle(summary: summary, customTitle: customTitle)
        state.backgroundAiChatStates[sessionID] = backgroundContent
    }
    if var backgroundInspector = state.backgroundInspectorAiChatStates[sessionID] {
        backgroundInspector.aiChat.refreshCustomTitle(summary: summary, customTitle: customTitle)
        state.backgroundInspectorAiChatStates[sessionID] = backgroundInspector.tabSnapshot()
    }
}

func routeBackgroundAiChatAction(
    _ aiChatAction: AiChatAction,
    state: inout FileManagerWindowState,
) -> Effect<FileManagerWindowAction> {
    guard let sessionID = backgroundAiChatSessionID(for: aiChatAction, state: state),
          var backgroundContent = state.backgroundAiChatStates[sessionID]
    else { return .none }

    if case let .requestContextResolved(resolutionID, _) = aiChatAction {
        backgroundContent.aiChat.activateBackgroundPendingRequestStart(resolutionID: resolutionID)
        removeAiChatPendingRequestStart(resolutionID: resolutionID, state: &state)
    }

    let backgroundOwnerRemoval = backgroundAiChatOwnerRemoval(
        after: aiChatAction,
        backgroundAiChat: backgroundContent.aiChat,
    )
    let finalSnapshotContext = backgroundFinalSnapshotContext(
        from: aiChatAction,
        backgroundAiChat: backgroundContent.aiChat,
    )
    let effect = AiChatFeature()
        .reduce(into: &backgroundContent.aiChat, action: aiChatAction)
        .map { action in
            if case let .sessionSnapshotSaved(summary, persistedSnapshot, _, _) = action,
               let context = finalSnapshotContext,
               let snapshot = persistedSnapshot ?? makeOffscreenFinalSnapshot(summary: summary, context: context)
            {
                return FileManagerWindowAction.backgroundAiChatSnapshotPersisted(snapshot)
            }
            return FileManagerWindowAction.backgroundAiChat(action)
        }

    if let payload = sessionSnapshotRefreshPayload(from: aiChatAction) {
        refreshAiChatSnapshotsFromBackgroundIfNeeded(
            summary: payload.summary,
            snapshot: payload.snapshot,
            backgroundAiChat: backgroundContent.aiChat,
            state: &state,
        )
    } else if let failedContext = failedAiChatContext(from: aiChatAction) {
        refreshAiChatFailureFromBackgroundIfNeeded(
            context: failedContext,
            backgroundAiChat: backgroundContent.aiChat,
            state: &state,
        )
    } else if let recoveryLock = persistenceRecoveryLock(from: aiChatAction) {
        refreshAiChatRecoveryFromBackgroundIfNeeded(
            lock: recoveryLock,
            backgroundAiChat: backgroundContent.aiChat,
            state: &state,
        )
    }

    backgroundContent.aiChat.removeBackgroundOwner(backgroundOwnerRemoval)
    if backgroundContent.aiChat.hasRemainingBackgroundLifecycleOwner {
        state.backgroundAiChatStates[sessionID] = backgroundContent
    } else {
        state.removeBackgroundAiChatState(sessionID: sessionID)
    }

    return effect
}

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
    guard var backgroundContent = state.backgroundAiChatStates[snapshot.sessionID] else { return }
    let ownerRemoval = backgroundAiChatOwnerRemoval(
        requestID: snapshot.lastRequestID,
        runID: snapshot.lastRunID,
        backgroundAiChat: backgroundContent.aiChat,
    )
    refreshAiChatSnapshotsFromBackgroundIfNeeded(
        summary: summary,
        snapshot: snapshot,
        backgroundAiChat: backgroundContent.aiChat,
        state: &state,
    )
    backgroundContent.aiChat.removeBackgroundOwner(ownerRemoval)
    if backgroundContent.aiChat.hasRemainingBackgroundLifecycleOwner {
        state.backgroundAiChatStates[snapshot.sessionID] = backgroundContent
    } else {
        state.removeBackgroundAiChatState(sessionID: snapshot.sessionID)
    }
}

func handleBackgroundInspectorAiChatSnapshotPersisted(
    _ snapshot: AiChatSessionSnapshot,
    state: inout FileManagerWindowState,
) {
    let summary = AiChatSessionSummary(snapshot: snapshot)
    guard var inspectorState = state.backgroundInspectorAiChatStates[snapshot.sessionID] else { return }
    let ownerRemoval = backgroundAiChatOwnerRemoval(
        requestID: snapshot.lastRequestID,
        runID: snapshot.lastRunID,
        backgroundAiChat: inspectorState.aiChat,
    )
    refreshAiChatSnapshotsFromBackgroundIfNeeded(
        summary: summary,
        snapshot: snapshot,
        backgroundAiChat: inspectorState.aiChat,
        state: &state,
    )
    inspectorState.aiChat.removeBackgroundOwner(ownerRemoval)
    if inspectorState.aiChat.hasRemainingBackgroundLifecycleOwner {
        state.backgroundInspectorAiChatStates[snapshot.sessionID] = inspectorState.tabSnapshot()
    } else {
        state.removeBackgroundInspectorAiChatState(sessionID: snapshot.sessionID)
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
