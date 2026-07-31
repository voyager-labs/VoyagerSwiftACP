import VoyagerEntitiesAi
import VoyagerFeaturesAiChat

enum ContentTabTransferEligibility: Equatable {
    case eligible
    case rejected(ContentTabTransferEligibilityRejection)
}

enum ContentTabTransferEligibilityRejection: Equatable, Error {
    case pendingContentTabClose
    case pendingPinnedRecordPersistence
    case pendingCollectionOperation
    case pendingAiChatOperation
    case malformedOwnership(ContentTabOwnershipInvariant)
}

enum ContentTabOwnershipInvariant: Equatable {
    case missingTab(ContentTabID)
    case missingActiveTab
    case missingContent(ContentTabID)
    case missingInspector(ContentTabID)
    case unexpectedInspector(ContentTabID)
    case ambiguousActiveContent(ContentTabID)
    case ambiguousActiveInspector(ContentTabID)
    case orphanContent(ContentTabID)
    case orphanInspector(ContentTabID)
    case ambiguousAiChatProvenance
}

extension FileManagerWindowState {
    func transferEligibility(tabID: ContentTabID) -> ContentTabTransferEligibility {
        if let rejection = ownershipRejection(tabID: tabID) {
            return .rejected(rejection)
        }
        if let rejection = durablePendingRejection(tabID: tabID) {
            return .rejected(rejection)
        }
        return .eligible
    }

    func destinationTransferEligibility() -> ContentTabTransferEligibility {
        if let rejection = backgroundAiChatOwnershipRejection() {
            return .rejected(rejection)
        }
        for tabID in contentTabs.tabs.ids {
            if let rejection = durablePendingRejection(tabID: tabID) {
                return .rejected(rejection)
            }
        }
        return .eligible
    }

    private func ownershipRejection(tabID: ContentTabID) -> ContentTabTransferEligibilityRejection? {
        guard contentTabs.tabs[id: tabID] != nil else {
            return .malformedOwnership(.missingTab(tabID))
        }
        guard let activeTabID = contentTabs.activeTabID, contentTabs.tabs[id: activeTabID] != nil else {
            return .malformedOwnership(.missingActiveTab)
        }
        if let invariant = orphanOwnershipInvariant() ?? tabOwnerInvariant(activeTabID: activeTabID) {
            return .malformedOwnership(invariant)
        }
        return backgroundAiChatOwnershipRejection()
    }

    private func orphanOwnershipInvariant() -> ContentTabOwnershipInvariant? {
        let tabIDs = Set(contentTabs.tabs.ids)
        if let orphanID = tabContentStates.keys
            .filter({ !tabIDs.contains($0) })
            .min(by: { $0.rawValue < $1.rawValue })
        {
            return .orphanContent(orphanID)
        }
        if let orphanID = tabInspectorStates.keys
            .filter({ !tabIDs.contains($0) })
            .min(by: { $0.rawValue < $1.rawValue })
        {
            return .orphanInspector(orphanID)
        }
        return nil
    }

    private func tabOwnerInvariant(activeTabID: ContentTabID) -> ContentTabOwnershipInvariant? {
        for ownerTabID in contentTabs.tabs.ids {
            guard let cachedContent = tabContentStates[ownerTabID] else { return .missingContent(ownerTabID) }
            if ownerTabID == activeTabID, cachedContent != content {
                return .ambiguousActiveContent(ownerTabID)
            }
            if let invariant = inspectorOwnerInvariant(ownerTabID: ownerTabID, activeTabID: activeTabID) {
                return invariant
            }
        }
        return nil
    }

    private func inspectorOwnerInvariant(
        ownerTabID: ContentTabID,
        activeTabID: ContentTabID,
    ) -> ContentTabOwnershipInvariant? {
        guard supportsInspector(tabID: ownerTabID) else {
            return tabInspectorStates[ownerTabID] == nil ? nil : .unexpectedInspector(ownerTabID)
        }
        guard let cachedInspector = tabInspectorStates[ownerTabID] else { return .missingInspector(ownerTabID) }
        if ownerTabID == activeTabID, cachedInspector != inspector.tabSnapshot() {
            return .ambiguousActiveInspector(ownerTabID)
        }
        return nil
    }

    private func durablePendingRejection(tabID: ContentTabID) -> ContentTabTransferEligibilityRejection? {
        if pendingContentTabClose != nil { return .pendingContentTabClose }
        if contentTabs.pendingPinnedRecordOperations[tabID] != nil {
            return .pendingPinnedRecordPersistence
        }
        guard let targetContent = authoritativeContentState(for: tabID) else {
            return .malformedOwnership(.missingContent(tabID))
        }
        if targetContent.hasDurablePendingCollectionOperation
            || (contentTabs.activeTabID == tabID && pendingCollectionOpenRequest != nil)
        {
            return .pendingCollectionOperation
        }
        if hasDurablePendingAiChatOperation(tabID: tabID, targetContent: targetContent) {
            return .pendingAiChatOperation
        }
        return nil
    }

    private func hasDurablePendingAiChatOperation(
        tabID: ContentTabID,
        targetContent: FileManagerContentFeature.State,
    ) -> Bool {
        pendingAiChatInspectorOpen?.tabID == tabID
            || pendingAiChatNewChat?.tabID == tabID
            || targetContent.aiChat.hasDurablePendingTransferOperation
            || authoritativeInspectorState(for: tabID)?.aiChat.hasDurablePendingTransferOperation == true
            || backgroundAiChatTargetsTab(tabID)
    }

    private func authoritativeContentState(for tabID: ContentTabID) -> FileManagerContentFeature.State? {
        contentTabs.activeTabID == tabID ? content : tabContentStates[tabID]
    }

    private func authoritativeInspectorState(for tabID: ContentTabID) -> FileManagerInspectorFeature.State? {
        guard supportsInspector(tabID: tabID) else { return nil }
        return contentTabs.activeTabID == tabID ? inspector : tabInspectorStates[tabID]
    }

    private func backgroundAiChatOwnershipRejection() -> ContentTabTransferEligibilityRejection? {
        for sessionID in pendingBackgroundAiChatSessionIDs()
            where aiChatOwnerTabIDs(sessionID: sessionID).count > 1
        {
            return .malformedOwnership(.ambiguousAiChatProvenance)
        }
        return nil
    }

    private func backgroundAiChatTargetsTab(_ tabID: ContentTabID) -> Bool {
        pendingBackgroundAiChatSessionIDs().contains { sessionID in
            aiChatOwnerTabIDs(sessionID: sessionID) == [tabID]
        }
    }

    private func pendingBackgroundAiChatSessionIDs() -> Set<AiChatSessionID> {
        Set(
            backgroundAiChatStates.compactMap { sessionID, state in
                state.aiChat.hasDurablePendingTransferOperation ? sessionID : nil
            } + backgroundInspectorAiChatStates.compactMap { sessionID, state in
                state.aiChat.hasDurablePendingTransferOperation ? sessionID : nil
            },
        )
    }

    private func aiChatOwnerTabIDs(sessionID: AiChatSessionID) -> [ContentTabID] {
        contentTabs.tabs.ids.filter { aiChatOwnedSessionIDs(for: $0).contains(sessionID) }
    }

    private func aiChatOwnedSessionIDs(for tabID: ContentTabID) -> Set<AiChatSessionID> {
        var sessionIDs = authoritativeContentState(for: tabID)?.aiChat.transferOwnedSessionIDs ?? []
        if let inspectorSessionIDs = authoritativeInspectorState(for: tabID)?.aiChat.transferOwnedSessionIDs {
            sessionIDs.formUnion(inspectorSessionIDs)
        }
        return sessionIDs
    }
}

private extension FileManagerContentFeature.State {
    var hasDurablePendingCollectionOperation: Bool {
        collection.isSaving
            || collection.pendingSave != nil
            || collection.pendingSaveContext != nil
            || collection.collectionSession.phase.isOpening
            || collection.collectionSession.phase.isInflightRefresh
            || collection.collectionSession.phase.isInflightWriteBack
    }
}

private extension AiChatFeature.State {
    var hasDurablePendingTransferOperation: Bool {
        if pendingRequestStart != nil
            || !backgroundPendingRequestStarts.isEmpty
            || streamingAssistantDraft != nil
            || sessionStatus == .restoring
        {
            return true
        }
        if executionPhase.blocksContentTabTransfer { return true }
        return backgroundExecutionPhases.values.contains { $0.blocksContentTabTransfer }
    }

    var transferOwnedSessionIDs: Set<AiChatSessionID> {
        var sessionIDs = Set<AiChatSessionID>()
        if let sessionID { sessionIDs.insert(sessionID) }
        if let restoreSessionID { sessionIDs.insert(restoreSessionID) }
        if let pendingRequestStart { sessionIDs.insert(pendingRequestStart.sessionID) }
        sessionIDs.formUnion(backgroundPendingRequestStarts.values.map(\.sessionID))
        if let sessionID = executionPhase.lock?.context.sessionID { sessionIDs.insert(sessionID) }
        sessionIDs.formUnion(backgroundExecutionPhases.values.compactMap { $0.lock?.context.sessionID })
        return sessionIDs
    }
}

private extension AiChatExecutionPhase {
    var blocksContentTabTransfer: Bool {
        switch self {
        case .processing, .persistenceRecovery:
            true
        case .idle, .completed, .failed, .cancelled:
            false
        }
    }
}
