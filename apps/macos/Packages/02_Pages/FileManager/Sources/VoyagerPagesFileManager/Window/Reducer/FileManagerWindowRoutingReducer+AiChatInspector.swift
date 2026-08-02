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
        if let payload = sessionSnapshotRefreshPayload(from: aiChatAction),
           state.inspector.aiChat.canRefreshFromBackground(summary: payload.summary)
        {
            refreshAiChatSnapshotsFromBackgroundIfNeeded(
                summary: payload.summary,
                snapshot: payload.snapshot,
                backgroundAiChat: state.inspector.aiChat,
                state: &state,
            )
        } else if let failedContext = failedAiChatContext(from: aiChatAction) {
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
        return .none
    }
    let effect = AiChatFeature()
        .reduce(into: &inspectorState.aiChat, action: aiChatAction)
        .map { FileManagerWindowAction.backgroundInspectorAiChat($0) }

    state.tabInspectorStates[tabID] = inspectorState.tabSnapshot()
    if let payload = sessionSnapshotRefreshPayload(from: aiChatAction) {
        refreshAiChatSnapshotsFromBackgroundIfNeeded(
            summary: payload.summary,
            snapshot: payload.snapshot,
            backgroundAiChat: inspectorState.aiChat,
            state: &state,
        )
    } else if let failedContext = failedAiChatContext(from: aiChatAction) {
        refreshAiChatFailureFromBackgroundIfNeeded(
            context: failedContext,
            backgroundAiChat: inspectorState.aiChat,
            state: &state,
        )
    } else if let recoveryLock = persistenceRecoveryLock(from: aiChatAction) {
        refreshAiChatRecoveryFromBackgroundIfNeeded(
            lock: recoveryLock,
            backgroundAiChat: inspectorState.aiChat,
            state: &state,
        )
    }
    return effect
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

    if let payload = sessionSnapshotRefreshPayload(from: aiChatAction) {
        refreshAiChatSnapshotsFromBackgroundIfNeeded(
            summary: payload.summary,
            snapshot: payload.snapshot,
            backgroundAiChat: inspectorState.aiChat,
            state: &state,
        )
    } else if let failedContext = failedAiChatContext(from: aiChatAction) {
        refreshAiChatFailureFromBackgroundIfNeeded(
            context: failedContext,
            backgroundAiChat: inspectorState.aiChat,
            state: &state,
        )
    } else if let recoveryLock = persistenceRecoveryLock(from: aiChatAction) {
        refreshAiChatRecoveryFromBackgroundIfNeeded(
            lock: recoveryLock,
            backgroundAiChat: inspectorState.aiChat,
            state: &state,
        )
    }

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
    if case let .requestContextResolved(resolutionID, _) = aiChatAction {
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

    if case let .executionEvent(event) = aiChatAction,
       let sessionID = aiChatEventSessionID(event),
       let requestID = aiChatEventRequestID(event)
    {
        guard state.backgroundInspectorAiChatStates[sessionID]?.aiChat.hasBackgroundOwnerMatching(
            requestID: requestID,
            runID: aiChatEventRunID(event),
        ) == true
        else { return nil }
        return sessionID
    }

    if case let .persistenceFailed(lock, _) = aiChatAction {
        return backgroundInspectorAiChatSessionID(for: lock, state: state)
    }

    if case let .persistenceRecoverySucceeded(lock) = aiChatAction {
        return backgroundInspectorAiChatSessionID(for: lock, state: state)
    }

    if case let .persistenceRecoveryRetryFailed(lock, _) = aiChatAction {
        return backgroundInspectorAiChatSessionID(for: lock, state: state)
    }

    if case let .sessionSnapshotSaved(summary, _, requestID, runID) = aiChatAction,
       let requestID
    {
        guard state.backgroundInspectorAiChatStates[summary.sessionID]?.aiChat.hasBackgroundOwnerMatching(
            requestID: requestID,
            runID: runID,
        ) == true
        else { return nil }
        return summary.sessionID
    }

    if case let .sessionSnapshotUpdated(summary, _, requestID, runID) = aiChatAction {
        guard state.backgroundInspectorAiChatStates[summary.sessionID]?.aiChat.hasBackgroundOwnerMatching(
            requestID: requestID,
            runID: runID,
        ) == true
        else { return nil }
        return summary.sessionID
    }

    return inspectorAiChatSessionID(for: aiChatAction)
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

func aiChatEventRequestID(_ event: AiChatEvent) -> AiChatRequestID? {
    switch event {
    case let .started(context),
         let .delta(context, _),
         let .failed(context, _):
        context.requestID

    case let .final(response):
        response.context.requestID
    }
}

func aiChatEventRunID(_ event: AiChatEvent) -> AiChatRunID? {
    switch event {
    case let .started(context),
         let .delta(context, _),
         let .failed(context, _):
        context.runID

    case let .final(response):
        response.context.runID
    }
}

extension AiChatFeature.State {
    var lifecycleOwnerSessionIDs: Set<AiChatSessionID> {
        var sessionIDs = Set<AiChatSessionID>()
        if let sessionID = pendingRequestStart?.sessionID {
            sessionIDs.insert(sessionID)
        }
        for pendingRequestStart in backgroundPendingRequestStarts.values {
            sessionIDs.insert(pendingRequestStart.sessionID)
        }
        if let sessionID = executionPhase.lock?.context.sessionID {
            sessionIDs.insert(sessionID)
        }
        for phase in backgroundExecutionPhases.values {
            if let sessionID = phase.lock?.context.sessionID {
                sessionIDs.insert(sessionID)
            }
        }
        return sessionIDs
    }

    mutating func activateBackgroundPendingRequestStart(resolutionID: UUID) {
        guard let pendingRequestStart = backgroundPendingRequestStarts[resolutionID] else { return }
        guard pendingRequestStart.sessionID == sessionID else { return }
        backgroundPendingRequestStarts.removeValue(forKey: resolutionID)
        if let currentPendingRequestStart = self.pendingRequestStart,
           currentPendingRequestStart.resolutionID != pendingRequestStart.resolutionID
        {
            backgroundPendingRequestStarts[currentPendingRequestStart.resolutionID] = currentPendingRequestStart
        }
        self.pendingRequestStart = pendingRequestStart
    }

    mutating func removePendingRequestStart(resolutionID: UUID) {
        if pendingRequestStart?.resolutionID == resolutionID {
            pendingRequestStart = nil
        }
        backgroundPendingRequestStarts.removeValue(forKey: resolutionID)
    }

    mutating func removeBackgroundOwners(matching activeAiChat: Self) {
        if let pendingRequestStart = activeAiChat.pendingRequestStart {
            if self.pendingRequestStart?.resolutionID == pendingRequestStart.resolutionID {
                self.pendingRequestStart = nil
            }
            backgroundPendingRequestStarts.removeValue(forKey: pendingRequestStart.resolutionID)
        }
        for pendingRequestStart in activeAiChat.backgroundPendingRequestStarts.values {
            backgroundPendingRequestStarts.removeValue(forKey: pendingRequestStart.resolutionID)
        }
        if let lock = activeAiChat.executionPhase.lock {
            removeBackgroundOwnerPromotedToActiveContent(lock)
        }
        for phase in activeAiChat.backgroundExecutionPhases.values {
            guard let lock = phase.lock else { continue }
            removeBackgroundOwnerPromotedToActiveContent(lock)
        }
    }

    mutating func removeBackgroundOwnerPromotedToActiveContent(_ lock: AiChatRequestLock) {
        guard !hasPendingFinalPersistenceOwner(matching: lock) else { return }
        removeBackgroundOwner(BackgroundAiChatOwnerRemoval(
            requestID: lock.requestID,
            runID: lock.runID,
            removeLegacySessionOwner: false,
        ))
    }

    func hasPendingFinalPersistenceOwner(matching lock: AiChatRequestLock) -> Bool {
        if executionPhase.hasPendingFinalPersistenceOwner(matching: lock) {
            return true
        }
        return backgroundExecutionPhases.values.contains {
            $0.hasPendingFinalPersistenceOwner(matching: lock)
        }
    }

    func hasLifecycleOwner(sessionID: AiChatSessionID) -> Bool {
        pendingRequestStart?.sessionID == sessionID
            || backgroundPendingRequestStarts.values.contains { $0.sessionID == sessionID }
            || executionPhase.lock?.context.sessionID == sessionID
            || backgroundExecutionPhases.values.contains { $0.lock?.context.sessionID == sessionID }
    }

    mutating func removeLifecycleOwners(sessionID: AiChatSessionID) {
        if pendingRequestStart?.sessionID == sessionID {
            pendingRequestStart = nil
        }
        backgroundPendingRequestStarts = backgroundPendingRequestStarts.filter { _, pendingRequestStart in
            pendingRequestStart.sessionID != sessionID
        }
        if executionPhase.lock?.context.sessionID == sessionID {
            executionPhase = .idle
        }
        backgroundExecutionPhases = backgroundExecutionPhases.filter { _, phase in
            phase.lock?.context.sessionID != sessionID
        }
    }

    func cancellationScope(sessionID: AiChatSessionID) -> Self {
        var scopedState = self
        if scopedState.pendingRequestStart?.sessionID != sessionID {
            scopedState.pendingRequestStart = nil
        }
        scopedState.backgroundPendingRequestStarts = scopedState.backgroundPendingRequestStarts
            .filter { _, pendingRequestStart in
                pendingRequestStart.sessionID == sessionID
            }
        if scopedState.executionPhase.lock?.context.sessionID != sessionID {
            scopedState.executionPhase = .idle
        }
        scopedState.backgroundExecutionPhases = scopedState.backgroundExecutionPhases.filter { _, phase in
            phase.lock?.context.sessionID == sessionID
        }
        return scopedState
    }

    mutating func applySessionDeleteSucceeded(sessionID deletedSessionID: AiChatSessionID) {
        pendingEmptyDraftDeletionSessionIDs.remove(deletedSessionID)
        sessionList.removeRow(sessionID: deletedSessionID)
        if restoreSessionID == deletedSessionID {
            restoreSessionID = nil
            restoreOutcome = nil
            restoreFailure = nil
        }
        if sessionID == deletedSessionID {
            sessionID = nil
            sessionStatus = .idle
            currentSessionCustomTitle = nil
            transcriptHistory = []
            draftText = ""
            streamingAssistantDraft = nil
            lockedModelHandle = nil
            lastExecutionFailure = nil
            lastRequestContext = nil
            lastRequestContextModelHandle = nil
            addedAttachments = []
            currentContextFolderStructureModes = [:]
            pendingRequestStart = nil
            executionPhase = .idle
            selectedModelHandle = nil
            selectedThinking = nil
            unavailableSelectedModelHandle = nil
        }
        removeLifecycleOwners(sessionID: deletedSessionID)
    }

    mutating func refreshCustomTitle(summary: AiChatSessionSummary, customTitle: String?) {
        guard sessionID == summary.sessionID || sessionList.allRows
            .contains(where: { $0.sessionID == summary.sessionID })
        else {
            refreshExecutionOwnerCustomTitle(sessionID: summary.sessionID, customTitle: customTitle)
            return
        }
        if sessionID == summary.sessionID {
            currentSessionCustomTitle = customTitle
        }
        sessionList.replaceRow(summary)
        refreshExecutionOwnerCustomTitle(sessionID: summary.sessionID, customTitle: customTitle)
    }

    mutating func refreshExecutionOwnerCustomTitle(sessionID: AiChatSessionID, customTitle: String?) {
        executionPhase = executionPhase.refreshingCustomTitle(sessionID: sessionID, customTitle: customTitle)
        for (requestID, phase) in backgroundExecutionPhases {
            backgroundExecutionPhases[requestID] = phase.refreshingCustomTitle(
                sessionID: sessionID,
                customTitle: customTitle,
            )
        }
    }
}

extension AiChatExecutionPhase {
    func hasPendingFinalPersistenceOwner(matching lock: AiChatRequestLock) -> Bool {
        guard case let .completed(completedLock) = self,
              completedLock.requestID == lock.requestID,
              completedLock.runID == lock.runID,
              completedLock.finalSnapshot != nil
        else {
            return false
        }
        return true
    }

    func refreshingCustomTitle(sessionID: AiChatSessionID, customTitle: String?) -> Self {
        guard lock?.context.sessionID == sessionID else { return self }
        switch self {
        case .idle:
            return .idle
        case let .processing(lock):
            return .processing(lock.recordingCustomTitle(customTitle))
        case let .completed(lock):
            return .completed(lock.recordingCustomTitle(customTitle))
        case let .failed(lock, failure):
            return .failed(lock.recordingCustomTitle(customTitle), failure)
        case let .cancelled(lock):
            return .cancelled(lock.recordingCustomTitle(customTitle))
        case let .persistenceRecovery(lock, failure):
            return .persistenceRecovery(lock.recordingCustomTitle(customTitle), failure)
        }
    }
}

func backgroundAiChatSessionID(
    for aiChatAction: AiChatAction,
    state: FileManagerWindowState,
) -> AiChatSessionID? {
    switch aiChatAction {
    case let .executionEvent(event):
        guard let sessionID = aiChatEventSessionID(event),
              let requestID = aiChatEventRequestID(event)
        else { return nil }
        guard state.backgroundAiChatStates[sessionID]?.aiChat.hasBackgroundOwnerMatching(
            requestID: requestID,
            runID: aiChatEventRunID(event),
        ) == true
        else { return nil }
        return sessionID
    case let .persistenceFailed(lock, _),
         let .persistenceRecoverySucceeded(lock),
         let .persistenceRecoveryRetryFailed(lock, _):
        guard let sessionID = lock.context.sessionID else { return nil }
        guard state.backgroundAiChatStates[sessionID]?.aiChat.hasBackgroundOwnerMatching(
            requestID: lock.requestID,
            runID: lock.runID,
        ) == true
        else { return nil }
        return sessionID
    case let .sessionSnapshotSaved(summary, _, requestID, runID):
        if let requestID {
            guard state.backgroundAiChatStates[summary.sessionID]?.aiChat.hasBackgroundOwnerMatching(
                requestID: requestID,
                runID: runID,
            ) == true
            else { return nil }
        }
        return summary.sessionID
    case let .sessionSnapshotUpdated(summary, _, requestID, runID):
        guard state.backgroundAiChatStates[summary.sessionID]?.aiChat.hasBackgroundOwnerMatching(
            requestID: requestID,
            runID: runID,
        ) == true
        else { return nil }
        return summary.sessionID
    case let .requestContextResolved(resolutionID, _):
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
    default:
        return nil
    }
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
