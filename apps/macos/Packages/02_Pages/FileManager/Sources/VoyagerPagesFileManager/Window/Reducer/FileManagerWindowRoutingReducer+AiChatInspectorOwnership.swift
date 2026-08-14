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

func routeInactiveInspectorAiChatAction(
    _ aiChatAction: AiChatAction,
    state: inout FileManagerWindowState,
) -> Effect<FileManagerWindowAction> {
    if let effect = routeBackgroundInspectorAiChatAction(aiChatAction, state: &state) {
        return effect
    }

    guard let tabID = inactiveInspectorTabID(for: aiChatAction, state: state),
          var inspectorState = state.tabInspectorStates[tabID]
    else {
        refreshInactiveInspectorAiChat(aiChatAction, state: &state)
        return .none
    }
    let effect = AiChatFeature()
        .reduce(into: &inspectorState.aiChat, action: aiChatAction)
        .map { FileManagerWindowAction.backgroundInspectorAiChat($0) }

    state.tabInspectorStates[tabID] = inspectorState.tabSnapshot()
    refreshInspectorAiChat(aiChatAction, backgroundAiChat: inspectorState.aiChat, state: &state)
    return effect
}

private func refreshInactiveInspectorAiChat(
    _ aiChatAction: AiChatAction,
    state: inout FileManagerWindowState,
) {
    if let payload = sessionSnapshotRefreshPayload(from: aiChatAction),
       state.inspector.aiChat.canRefreshFromBackground(summary: payload.summary)
    {
        refreshAiChatSnapshotsFromBackgroundIfNeeded(
            summary: payload.summary,
            snapshot: payload.snapshot,
            backgroundAiChat: state.inspector.aiChat,
            state: &state,
        )
    } else {
        refreshInactiveInspectorAiChatTerminal(aiChatAction, state: &state)
    }
}

private func refreshInactiveInspectorAiChatTerminal(
    _ aiChatAction: AiChatAction,
    state: inout FileManagerWindowState,
) {
    if let failedContext = failedAiChatContext(from: aiChatAction) {
        refreshAiChatFailureFromBackgroundIfNeeded(
            context: failedContext,
            backgroundAiChat: state.inspector.aiChat,
            state: &state,
        )
    } else if let recoveryLock = persistenceRecoveryLock(from: aiChatAction) {
        refreshAiChatRecoveryFromBackgroundIfNeeded(
            lock: recoveryLock,
            backgroundAiChat: state.inspector.aiChat,
            state: &state,
        )
    }
}

private func refreshInspectorAiChat(
    _ aiChatAction: AiChatAction,
    backgroundAiChat: AiChatFeature.State,
    state: inout FileManagerWindowState,
) {
    if let payload = sessionSnapshotRefreshPayload(from: aiChatAction) {
        refreshAiChatSnapshotsFromBackgroundIfNeeded(
            summary: payload.summary,
            snapshot: payload.snapshot,
            backgroundAiChat: backgroundAiChat,
            state: &state,
        )
    } else if let failedContext = failedAiChatContext(from: aiChatAction) {
        refreshAiChatFailureFromBackgroundIfNeeded(
            context: failedContext,
            backgroundAiChat: backgroundAiChat,
            state: &state,
        )
    } else if let recoveryLock = persistenceRecoveryLock(from: aiChatAction) {
        refreshAiChatRecoveryFromBackgroundIfNeeded(
            lock: recoveryLock,
            backgroundAiChat: backgroundAiChat,
            state: &state,
        )
    }
}

func routeBackgroundInspectorAiChatAction(
    _ aiChatAction: AiChatAction,
    state: inout FileManagerWindowState,
) -> Effect<FileManagerWindowAction>? {
    guard let sessionID = backgroundInspectorAiChatSessionID(for: aiChatAction, state: state),
          var inspectorState = state.backgroundInspectorAiChatStates[sessionID]
    else { return nil }

    if case let .requestContextResolved(resolutionID, _) = aiChatAction {
        inspectorState.aiChat.activateBackgroundPendingRequestStart(resolutionID: resolutionID)
        removeAiChatPendingRequestStart(resolutionID: resolutionID, state: &state)
    }

    let backgroundOwnerRemoval = backgroundAiChatOwnerRemoval(
        after: aiChatAction,
        backgroundAiChat: inspectorState.aiChat,
    )
    let finalSnapshotContext = backgroundFinalSnapshotContext(
        from: aiChatAction,
        backgroundAiChat: inspectorState.aiChat,
    )
    let effect = AiChatFeature()
        .reduce(into: &inspectorState.aiChat, action: aiChatAction)
        .map { action in
            if case let .sessionSnapshotSaved(summary, persistedSnapshot, _, _) = action,
               let context = finalSnapshotContext,
               let snapshot = persistedSnapshot ?? makeOffscreenFinalSnapshot(summary: summary, context: context)
            {
                return FileManagerWindowAction.backgroundInspectorAiChatSnapshotPersisted(snapshot)
            }
            return FileManagerWindowAction.backgroundInspectorAiChat(action)
        }

    refreshInspectorAiChat(aiChatAction, backgroundAiChat: inspectorState.aiChat, state: &state)

    inspectorState.aiChat.removeBackgroundOwner(backgroundOwnerRemoval)
    if inspectorState.aiChat.hasRemainingBackgroundLifecycleOwner {
        state.backgroundInspectorAiChatStates[sessionID] = inspectorState.tabSnapshot()
    } else {
        state.removeBackgroundInspectorAiChatState(sessionID: sessionID)
    }

    return effect
}

func inactiveInspectorTabID(
    for aiChatAction: AiChatAction,
    state: FileManagerWindowState,
) -> ContentTabID? {
    if case let .requestContextResolved(resolutionID, _) = aiChatAction {
        return state.tabInspectorStates.first { tabID, inspectorState in
            tabID != state.contentTabs.activeTabID
                && (inspectorState.aiChat.pendingRequestStart?.resolutionID == resolutionID
                    || inspectorState.aiChat.backgroundPendingRequestStarts[resolutionID] != nil)
        }?.key
    }

    guard let sessionID = inspectorAiChatSessionID(for: aiChatAction) else { return nil }
    return state.tabInspectorStates.first { tabID, inspectorState in
        tabID != state.contentTabs.activeTabID
            && inspectorState.ownsSessionOrRequest(sessionID: sessionID, action: aiChatAction)
    }?.key
}

func backgroundInspectorAiChatSessionID(
    for aiChatAction: AiChatAction,
    state: FileManagerWindowState,
) -> AiChatSessionID? {
    switch aiChatAction {
    case let .requestContextResolved(resolutionID, _):
        backgroundInspectorPendingSessionID(resolutionID: resolutionID, state: state)
    case let .executionEvent(event):
        backgroundInspectorExecutionSessionID(event: event, state: state)
    case let .persistenceFailed(lock, _),
         let .persistenceRecoverySucceeded(lock),
         let .persistenceRecoveryRetryFailed(lock, _):
        backgroundInspectorAiChatSessionID(for: lock, state: state)
    case let .sessionSnapshotSaved(summary, _, requestID, runID):
        backgroundInspectorSnapshotSessionID(
            summary: summary,
            requestID: requestID,
            runID: runID,
            state: state,
        )
    case let .sessionSnapshotUpdated(summary, _, requestID, runID):
        backgroundInspectorSnapshotSessionID(
            summary: summary,
            requestID: requestID,
            runID: runID,
            state: state,
        )
    default:
        inspectorAiChatSessionID(for: aiChatAction)
    }
}

private func backgroundInspectorPendingSessionID(
    resolutionID: UUID,
    state: FileManagerWindowState,
) -> AiChatSessionID? {
    if let pendingSessionID = state.backgroundInspectorAiChatStates.values.compactMap({ inspectorState in
        inspectorState.aiChat.pendingRequestStart?.resolutionID == resolutionID
            ? inspectorState.aiChat.pendingRequestStart?.sessionID
            : inspectorState.aiChat.backgroundPendingRequestStarts[resolutionID]?.sessionID
    }).first,
        state.backgroundInspectorAiChatStates[pendingSessionID] != nil
    {
        return pendingSessionID
    }
    return state.backgroundInspectorAiChatStates.first { _, inspectorState in
        inspectorState.aiChat.pendingRequestStart?.resolutionID == resolutionID
            || inspectorState.aiChat.backgroundPendingRequestStarts[resolutionID] != nil
    }?.key
}

private func backgroundInspectorExecutionSessionID(
    event: AiChatEvent,
    state: FileManagerWindowState,
) -> AiChatSessionID? {
    guard let sessionID = aiChatEventSessionID(event),
          let requestID = aiChatEventRequestID(event),
          state.backgroundInspectorAiChatStates[sessionID]?.aiChat.hasBackgroundOwnerMatching(
              requestID: requestID,
              runID: aiChatEventRunID(event),
          ) == true
    else { return nil }
    return sessionID
}

private func backgroundInspectorSnapshotSessionID(
    summary: AiChatSessionSummary,
    requestID: AiChatRequestID?,
    runID: AiChatRunID?,
    state: FileManagerWindowState,
) -> AiChatSessionID? {
    guard let requestID else { return summary.sessionID }
    guard state.backgroundInspectorAiChatStates[summary.sessionID]?.aiChat.hasBackgroundOwnerMatching(
        requestID: requestID,
        runID: runID,
    ) == true else { return nil }
    return summary.sessionID
}

func backgroundInspectorAiChatSessionID(
    for lock: AiChatRequestLock,
    state: FileManagerWindowState,
) -> AiChatSessionID? {
    guard let sessionID = lock.context.sessionID else { return nil }
    guard state.backgroundInspectorAiChatStates[sessionID]?.aiChat.hasBackgroundOwnerMatching(
        requestID: lock.requestID,
        runID: lock.runID,
    ) == true
    else { return nil }
    return sessionID
}

func inspectorAiChatSessionID(for aiChatAction: AiChatAction) -> AiChatSessionID? {
    switch aiChatAction {
    case let .executionEvent(event):
        aiChatEventSessionID(event)
    case let .persistenceFailed(lock, _),
         let .persistenceRecoverySucceeded(lock),
         let .persistenceRecoveryRetryFailed(lock, _):
        lock.context.sessionID
    case let .sessionSnapshotSaved(summary, _, _, _):
        summary.sessionID
    case let .sessionSnapshotUpdated(summary, _, _, _):
        summary.sessionID
    default:
        nil
    }
}

extension FileManagerInspectorFeature.State {
    func ownsSessionOrRequest(sessionID: AiChatSessionID, action: AiChatAction) -> Bool {
        if aiChat.sessionID == sessionID { return true }
        if aiChat.executionPhase.lock?.context.sessionID == sessionID { return true }
        if aiChat.backgroundExecutionPhases.values.contains(where: { $0.lock?.context.sessionID == sessionID }) {
            return true
        }
        if case let .executionEvent(event) = action,
           let requestID = aiChatEventRequestID(event),
           aiChat.backgroundExecutionPhases[requestID] != nil
        {
            return true
        }
        return false
    }
}
