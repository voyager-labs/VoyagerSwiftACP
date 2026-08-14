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

func backgroundAiChatSessionID(
    for aiChatAction: AiChatAction,
    state: FileManagerWindowState,
) -> AiChatSessionID? {
    switch aiChatAction {
    case let .executionEvent(event):
        backgroundExecutionSessionID(event: event, state: state)
    case let .persistenceFailed(lock, _),
         let .persistenceRecoverySucceeded(lock),
         let .persistenceRecoveryRetryFailed(lock, _):
        backgroundPersistenceSessionID(lock: lock, state: state)
    case let .sessionSnapshotSaved(summary, _, requestID, runID):
        backgroundSnapshotSessionID(
            summary: summary,
            requestID: requestID,
            runID: runID,
            state: state,
        )
    case let .sessionSnapshotUpdated(summary, _, requestID, runID):
        backgroundSnapshotSessionID(
            summary: summary,
            requestID: requestID,
            runID: runID,
            state: state,
        )
    case let .requestContextResolved(resolutionID, _):
        backgroundPendingSessionID(resolutionID: resolutionID, state: state)
    default:
        nil
    }
}

private func backgroundExecutionSessionID(
    event: AiChatEvent,
    state: FileManagerWindowState,
) -> AiChatSessionID? {
    guard let sessionID = aiChatEventSessionID(event),
          let requestID = aiChatEventRequestID(event),
          state.backgroundAiChatStates[sessionID]?.aiChat.hasBackgroundOwnerMatching(
              requestID: requestID,
              runID: aiChatEventRunID(event),
          ) == true
    else { return nil }
    return sessionID
}

private func backgroundPersistenceSessionID(
    lock: AiChatRequestLock,
    state: FileManagerWindowState,
) -> AiChatSessionID? {
    guard let sessionID = lock.context.sessionID,
          state.backgroundAiChatStates[sessionID]?.aiChat.hasBackgroundOwnerMatching(
              requestID: lock.requestID,
              runID: lock.runID,
          ) == true
    else { return nil }
    return sessionID
}

private func backgroundSnapshotSessionID(
    summary: AiChatSessionSummary,
    requestID: AiChatRequestID?,
    runID: AiChatRunID?,
    state: FileManagerWindowState,
) -> AiChatSessionID? {
    guard let requestID else { return summary.sessionID }
    guard state.backgroundAiChatStates[summary.sessionID]?.aiChat.hasBackgroundOwnerMatching(
        requestID: requestID,
        runID: runID,
    ) == true else { return nil }
    return summary.sessionID
}

private func backgroundPendingSessionID(
    resolutionID: UUID,
    state: FileManagerWindowState,
) -> AiChatSessionID? {
    if let pendingSessionID = state.backgroundAiChatStates.values.compactMap({ backgroundContent in
        backgroundContent.aiChat.pendingRequestStart?.resolutionID == resolutionID
            ? backgroundContent.aiChat.pendingRequestStart?.sessionID
            : backgroundContent.aiChat.backgroundPendingRequestStarts[resolutionID]?.sessionID
    }).first,
        state.backgroundAiChatStates[pendingSessionID] != nil
    {
        return pendingSessionID
    }
    return state.backgroundAiChatStates.first { _, backgroundContent in
        backgroundContent.aiChat.pendingRequestStart?.resolutionID == resolutionID
            || backgroundContent.aiChat.backgroundPendingRequestStarts[resolutionID] != nil
    }?.key
}

struct BackgroundAiChatOwnerRemoval {
    let requestID: AiChatRequestID?
    let runID: AiChatRunID?
    let removeLegacySessionOwner: Bool
}

func backgroundAiChatOwnerRemoval(
    after aiChatAction: AiChatAction,
    backgroundAiChat: AiChatFeature.State,
) -> BackgroundAiChatOwnerRemoval? {
    switch aiChatAction {
    case .executionEvent:
        nil
    case let .sessionSnapshotSaved(_, _, requestID, runID):
        backgroundAiChatOwnerRemoval(
            requestID: requestID,
            runID: runID,
            backgroundAiChat: backgroundAiChat,
        )
    case let .persistenceRecoverySucceeded(lock):
        backgroundAiChat.hasBackgroundOwnerMatching(requestID: lock.requestID, runID: lock.runID)
            ? BackgroundAiChatOwnerRemoval(
                requestID: lock.requestID,
                runID: lock.runID,
                removeLegacySessionOwner: false,
            )
            : nil
    case .persistenceRecoveryRetryFailed:
        nil
    default:
        nil
    }
}

func backgroundAiChatOwnerRemoval(
    requestID: AiChatRequestID?,
    runID: AiChatRunID?,
    backgroundAiChat: AiChatFeature.State,
) -> BackgroundAiChatOwnerRemoval? {
    guard let requestID else {
        return BackgroundAiChatOwnerRemoval(requestID: nil, runID: nil, removeLegacySessionOwner: true)
    }
    guard backgroundAiChat.hasBackgroundOwnerMatching(requestID: requestID, runID: runID) else { return nil }
    return BackgroundAiChatOwnerRemoval(requestID: requestID, runID: runID, removeLegacySessionOwner: false)
}
