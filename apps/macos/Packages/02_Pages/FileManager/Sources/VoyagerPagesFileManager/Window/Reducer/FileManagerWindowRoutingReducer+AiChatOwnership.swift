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

func aiChatEventRequestID(_ event: AiChatEvent) -> AiChatRequestID? {
    switch event {
    case let .started(context),
         let .delta(context, _),
         let .status(context, _),
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
         let .status(context, _),
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
