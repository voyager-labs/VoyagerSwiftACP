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

struct ContentTabCloseDisposition {
    let isActualRemoval: Bool
    let shouldRestorePreviousActiveTab: Bool
    let shouldResetLastTabContent: Bool
    let replacementHomeTabID: ContentTabID?
    let shouldResyncContentNavigation: Bool
}

func contentTabCloseDisposition(
    tabID: ContentTabID,
    state: FileManagerWindowState,
) -> ContentTabCloseDisposition {
    let isRemovedTab = state.contentTabs.tabs[id: tabID] == nil
    let isActualRemoval = isRemovedTab
        && (state.tabContentStates[tabID] != nil || state.contentTabs.previousActiveTabID == tabID)
    let shouldRestorePreviousActiveTab = isActualRemoval
        && state.contentTabs.previousActiveTabID == tabID
    let shouldResetLastTabContent = state.contentTabs.previousActiveTabID == tabID
        && state.contentTabs.activeTabID == tabID
    let replacementHomeTabID: ContentTabID? = if shouldResetLastTabContent {
        tabID
    } else if shouldRestorePreviousActiveTab,
              state.activeTabContentStateMissing,
              let activeTabID = state.contentTabs.activeTabID,
              state.contentTabs.tabs[id: activeTabID]?.anchor == .homeDefault
    {
        activeTabID
    } else {
        nil
    }
    return ContentTabCloseDisposition(
        isActualRemoval: isActualRemoval,
        shouldRestorePreviousActiveTab: shouldRestorePreviousActiveTab,
        shouldResetLastTabContent: shouldResetLastTabContent,
        replacementHomeTabID: replacementHomeTabID,
        shouldResyncContentNavigation: shouldRestorePreviousActiveTab || shouldResetLastTabContent,
    )
}

extension FileManagerWindowRoutingReducer {
    func allowsSelectedContentTabCloseLifecycleMutation(state: State) -> Bool {
        guard !state.isClosing else { return false }
        guard let batch = state.pendingSelectedContentTabClose else { return true }
        guard let pendingClose = state.pendingContentTabClose else { return false }
        return pendingClose.batchOperationID == batch.operationID
            && pendingClose.tabID == batch.currentTabID
    }

    func pinnedContentTabsApplicationMode(for action: Action) -> PinnedContentTabsApplicationMode {
        if case .applyAuthoritativePinnedContentTabs = action {
            return .authoritative
        }
        return .preservingRuntime
    }

    func takeDeferredPinnedContentTabsAction(state: inout State) -> Action? {
        defer {
            state.deferredPinnedContentTabs = nil
            state.deferredPinnedContentTabsMode = nil
        }
        guard let contentTabs = state.deferredPinnedContentTabs else { return nil }
        if state.deferredPinnedContentTabsMode == .authoritative {
            return .applyAuthoritativePinnedContentTabs(contentTabs)
        }
        return .applyPinnedContentTabs(contentTabs)
    }

    func applyPinnedContentTabs(
        _ contentTabs: ContentTabState,
        mode: PinnedContentTabsApplicationMode,
        state: inout State,
    ) -> Effect<Action> {
        guard state.pendingSelectedContentTabClose == nil,
              state.pendingSelectedContentTabPinMutation == nil,
              state.deferredPinnedContentTabs == nil
        else {
            state.deferredPinnedContentTabs = contentTabs
            state.deferredPinnedContentTabsMode = mode
            return .none
        }
        let activeTabIDBeforeSync = state.contentTabs.activeTabID
        let activeAnchorBeforeSync = activeTabIDBeforeSync.flatMap { state.contentTabs.tabs[id: $0]?.anchor }
        let tabAnchorsBeforeSync = state.contentTabs.tabs.map { (id: $0.id, anchor: $0.anchor) }
        let runtimePreservingTabIDs: Set<ContentTabID> = mode == .authoritative
            ? Set(state.pendingRuntimePreservationRecords.compactMap { tabID, record in
                contentTabs.pinnedRecords[tabID] == record ? tabID : nil
            })
            : []
        state.applyPinnedContentTabs(
            contentTabs,
            mode: mode,
            runtimePreservingTabIDs: runtimePreservingTabIDs,
        )
        if mode == .authoritative {
            state.pendingRuntimePreservationRecords.removeAll()
        }
        cleanPendingDirectoryReloadTabIDs(state: &state)
        syncDashboardProjections(state: &state)
        let activeAnchorAfterSync = state.contentTabs.activeTabID
            .flatMap { state.contentTabs.tabs[id: $0]?.anchor }
        let shouldResyncContentNavigation = state.contentTabs.activeTabID == activeTabIDBeforeSync
            && activeAnchorAfterSync != activeAnchorBeforeSync
            && activeAnchorAfterSync?.isCollectionFileAnchor == true
        let handoffCleanupEffect = shouldResyncContentNavigation
            ? prepareContentForActiveTabHandoff(state: &state.content)
            : .none
        return .merge(
            handoffCleanupEffect,
            activeTabHandoffEffect(
                shouldResyncContentNavigation,
                state: &state,
                aiConnectionsFileClient: aiConnectionsFileClient,
            ),
            closeInspectorForActiveAiChatEffect(state: state),
            reconcileUndoManagerScopesEffect(
                tabAnchorsBeforeSync: tabAnchorsBeforeSync,
                state: state,
            ),
        )
    }

    func processNextSelectedContentTabClose(
        operationID: UUID,
        state: inout State,
    ) -> Effect<Action> {
        guard !state.isClosing,
              var pending = state.pendingSelectedContentTabClose,
              pending.operationID == operationID,
              pending.currentTabID == nil
        else { return .none }

        guard pending.cursor < pending.orderedTargetIDs.count else {
            let replayAction = takeDeferredPinnedContentTabsAction(state: &state)
            state.pendingSelectedContentTabClose = nil
            let cancelEffect = Effect<Action>.cancel(
                id: SelectedContentTabCloseOperationCancelID(operationID: operationID),
            )
            guard let replayAction else { return cancelEffect }
            return .concatenate(cancelEffect, .send(replayAction))
        }

        let tabID = pending.orderedTargetIDs[pending.cursor]
        pending.currentTabID = tabID
        state.pendingSelectedContentTabClose = pending
        guard state.contentTabs.tabs[id: tabID] != nil else {
            return .send(.selectedContentTabCloseItemCompleted(
                operationID: operationID,
                tabID: tabID,
                outcome: .missing,
            ))
        }
        let originalPreviousActiveTabID = state.contentTabs.previousActiveTabID
        if tabID == pending.originalActiveTabID,
           let fallbackID = preferredSelectedContentTabCloseFallbackID(
               pending: pending,
               excluding: tabID,
               state: state,
           )
        {
            state.contentTabs.previousActiveTabID = fallbackID
        }
        state.pendingContentTabClose = PendingContentTabClose(
            tabID: tabID,
            originalPreviousActiveTabID: originalPreviousActiveTabID,
            batchOperationID: operationID,
        )
        return handleCloseContentTabRequested(
            tabID: tabID,
            state: &state,
            batchOperationID: operationID,
        )
    }

    func completeSelectedContentTabCloseItem(
        operationID: UUID,
        tabID: ContentTabID,
        outcome: SelectedContentTabCloseOutcome,
        state: inout State,
    ) -> Effect<Action> {
        guard !state.isClosing,
              var pending = state.pendingSelectedContentTabClose,
              pending.operationID == operationID,
              pending.currentTabID == tabID
        else { return .none }

        switch outcome {
        case .removed, .unpinned, .missing:
            state.contentTabs.selectedTabIDs.remove(tabID)
        case .cancelled, .failed:
            if state.contentTabs.tabs[id: tabID] != nil {
                state.contentTabs.selectedTabIDs.insert(tabID)
            }
        }
        state.contentTabs.reconcileSelection()

        if pending.originalActiveTabID == tabID,
           state.contentTabs.tabs[id: tabID] == nil,
           let fallbackID = preferredSelectedContentTabCloseFallbackID(
               pending: pending,
               excluding: tabID,
               state: state,
           ),
           state.contentTabs.activeTabID != fallbackID
        {
            state.contentTabs.previousActiveTabID = tabID
            state.contentTabs.activeTabID = fallbackID
            state.restoreContentStateForActiveTab()
            state.restoreInspectorStateForActiveTab()
            syncDashboardProjections(state: &state)
        }

        if let pendingClose = state.pendingContentTabClose,
           pendingClose.batchOperationID == operationID,
           pendingClose.tabID == tabID
        {
            if outcome == .cancelled || outcome == .failed {
                state.contentTabs.previousActiveTabID = pendingClose.originalPreviousActiveTabID
            }
            state.pendingContentTabClose = nil
        }
        pending.cursor += 1
        pending.currentTabID = nil
        state.pendingSelectedContentTabClose = pending
        return .send(.processNextSelectedContentTabClose(operationID: operationID))
    }

    func preferredSelectedContentTabCloseFallbackID(
        pending: PendingSelectedContentTabClose,
        excluding tabID: ContentTabID,
        state: State,
    ) -> ContentTabID? {
        let targetIDs = Set(pending.orderedTargetIDs)
        let livePreferredIDs = pending.preferredFallbackIDs.filter {
            $0 != tabID && state.contentTabs.tabs[id: $0] != nil
        }
        let nonTargetSurvivors = livePreferredIDs.filter { !targetIDs.contains($0) }
        let failedOrCancelledSurvivors = livePreferredIDs.filter {
            targetIDs.contains($0) && state.contentTabs.selectedTabIDs.contains($0)
        }
        let successfullyUnpinnedSurvivors = livePreferredIDs.filter {
            targetIDs.contains($0) && !state.contentTabs.selectedTabIDs.contains($0)
        }
        return (nonTargetSurvivors + failedOrCancelledSurvivors + successfullyUnpinnedSurvivors).first
    }

    func isCurrentSelectedContentTabClose(
        operationID: UUID,
        tabID: ContentTabID,
        state: State,
    ) -> Bool {
        guard !state.isClosing,
              let batch = state.pendingSelectedContentTabClose,
              let pendingClose = state.pendingContentTabClose
        else { return false }
        return batch.operationID == operationID
            && batch.currentTabID == tabID
            && pendingClose.batchOperationID == operationID
            && pendingClose.tabID == tabID
    }

    func handleSelectedContentTabCloseMutation(
        operationID: UUID,
        tabID: ContentTabID,
        action: ContentTabAction,
        state: inout State,
    ) -> Effect<Action> {
        guard !isStalePinnedRecordPersistenceResult(action, in: state.contentTabs) else { return .none }
        switch action {
        case .requestClose:
            return prepareContentTabTeardown(
                tabID: tabID,
                state: &state,
                batchOperationID: operationID,
            )

        case .close:
            return .none

        case .commitClose:
            state.pendingContentTabClose = nil
            return .merge(
                finalizeContentTabClose(tabID: tabID, state: &state),
                .send(.selectedContentTabCloseItemCompleted(
                    operationID: operationID,
                    tabID: tabID,
                    outcome: .removed,
                )),
            )

        case .pinnedRecordSaveSucceeded,
             .pinnedRecordSaveFailed,
             .pinnedRecordStoreUnavailable,
             .pinnedRecordSaveNotApplied:
            // pinned batch close completion은 FileManagerFeature가 durable terminal 뒤 commitClose로 연결한다.
            return .none

        default:
            return .none
        }
    }

    func preferredSelectedContentTabCloseFallbackIDs(
        originalTabIDs: [ContentTabID],
        originalActiveTabID: ContentTabID?,
        targetIDSet: Set<ContentTabID>,
        orderedTargetIDs: [ContentTabID],
    ) -> [ContentTabID] {
        let nonTargetIDs: [ContentTabID]
        if let originalActiveTabID,
           let activeIndex = originalTabIDs.firstIndex(of: originalActiveTabID)
        {
            let rightIDs = originalTabIDs.dropFirst(activeIndex + 1).filter { !targetIDSet.contains($0) }
            let leftIDs = originalTabIDs[..<activeIndex].reversed().filter { !targetIDSet.contains($0) }
            nonTargetIDs = Array(rightIDs) + Array(leftIDs)
        } else {
            nonTargetIDs = originalTabIDs.filter { !targetIDSet.contains($0) }
        }
        return nonTargetIDs + orderedTargetIDs.filter { $0 != originalActiveTabID }
    }

    func keepPendingContentTabCloseFocusedAfterOpen(state: inout State) -> Bool {
        guard let pendingClose = state.pendingContentTabClose else {
            return false
        }
        if let activeTabID = state.contentTabs.activeTabID, activeTabID != pendingClose.tabID {
            state.contentTabs.tabs.remove(id: activeTabID)
            state.contentTabs.reconcileSelection()
            state.removeContentState(for: activeTabID)
            state.removeInspectorState(for: activeTabID)
        }
        keepPendingContentTabCloseFocused(pendingClose, state: &state)
        return true
    }

    func keepPendingContentTabCloseFocused(state: inout State) -> Bool {
        guard let pendingClose = state.pendingContentTabClose else {
            return false
        }
        keepPendingContentTabCloseFocused(pendingClose, state: &state)
        return true
    }

    func keepPendingContentTabCloseFocused(
        _ pendingClose: PendingContentTabClose,
        state: inout State,
    ) {
        state.contentTabs.activeTabID = pendingClose.tabID
        state.contentTabs.previousActiveTabID = pendingClose.previousActiveTabID
        state.syncActiveTabContentState()
        state.syncActiveTabInspectorState()
        state.syncContentTabSidebarItems()
        syncSidebarSelectionForActiveContentTab(state: &state)
    }

    /// Pending close rollback variant: exact duplicateID rows/caches만 제거하고 pending state로 복원한다.
    /// ContentTabFeature duplicate actions가 previousActiveTabID를 덮어썼으므로 pendingClose의 원본 값을 사용한다.
    func keepPendingDuplicateContentTabCloseFocused(
        duplicateID: ContentTabID,
        state: inout State,
    ) -> Bool {
        keepPendingDuplicateContentTabCloseFocused(duplicateIDs: [duplicateID], state: &state)
    }

    func keepPendingDuplicateContentTabCloseFocused(
        duplicateIDs: [ContentTabID],
        state: inout State,
    ) -> Bool {
        guard let pendingClose = state.pendingContentTabClose else { return false }
        let duplicateIDSet = Set(duplicateIDs)
        let wasGeneratedDuplicateActive = state.contentTabs.activeTabID.map(duplicateIDSet.contains) == true
        for duplicateID in duplicateIDs {
            state.contentTabs.tabs.remove(id: duplicateID)
            state.removeContentState(for: duplicateID)
            state.removeInspectorState(for: duplicateID)
        }
        state.contentTabs.reconcileSelection()
        if wasGeneratedDuplicateActive {
            state.contentTabs.activeTabID = pendingClose.tabID
            state.contentTabs.previousActiveTabID = pendingClose.previousActiveTabID
        }
        // Pending target/Content/Inspector는 staging하지 않고 기존 source selection을 유지한다.
        state.syncContentTabSidebarItems()
        syncSidebarSelectionForActiveContentTab(state: &state)
        return true
    }

    func prepareContentTabTeardown(
        tabID: ContentTabID,
        state: inout State,
        batchOperationID: UUID? = nil,
    ) -> Effect<Action> {
        guard state.pendingContentTabTeardown == nil,
              state.contentTabs.tabs[id: tabID]?.isPinned == false
        else { return .none }

        switch state.undoRedoPhase {
        case .idle:
            break

        case .desynchronized:
            if let batchOperationID {
                return .send(.performSelectedContentTabCloseMutation(
                    operationID: batchOperationID,
                    tabID: tabID,
                    action: .commitClose(tabID),
                ))
            }
            _ = ContentTabFeature().reduce(into: &state.contentTabs, action: .commitClose(tabID))
            return finalizeContentTabClose(tabID: tabID, state: &state)

        case .invoking, .replaying, .refreshing, .recovering, .tearingDownTab:
            return .none
        }

        let usesActiveContent = state.contentTabs.activeTabID == tabID
        let ownerID = usesActiveContent
            ? state.content.entryViewLayout.entryOperations.undoOwnerID
            : state.tabContentStates[tabID]?.entryViewLayout.entryOperations.undoOwnerID
        guard let ownerID, let windowID = state.windowID else {
            return commitContentTabCloseWithoutUndo(
                tabID: tabID,
                batchOperationID: batchOperationID,
                state: &state,
            )
        }

        let requestID = uuid()
        state.pendingContentTabTeardown = .init(
            requestID: requestID,
            tabID: tabID,
            ownerID: ownerID,
        )
        state.undoRedoPhase = .tearingDownTab(requestID: requestID, ownerID: ownerID)
        state.undoManagerAvailability = .init()
        let invalidationEffect = invalidateUndoOwnerEffect(
            requestID: requestID,
            ownerID: ownerID,
            windowID: windowID,
            undoManagerClient: undoManagerClient,
        )
        guard let batchOperationID else { return invalidationEffect }
        return invalidationEffect.cancellable(
            id: SelectedContentTabCloseOperationCancelID(operationID: batchOperationID),
        )
    }

    func handleCloseContentTabRequested(
        tabID: ContentTabID,
        state: inout State,
        batchOperationID: UUID? = nil,
    ) -> Effect<Action> {
        guard !state.contentTabs.pendingPinnedRecordIDs.contains(tabID) else { return .none }
        guard canHandleContentTabClose(tabID: tabID, batchOperationID: batchOperationID, state: state) else {
            return .none
        }

        guard state.contentTabs.tabs[id: tabID] != nil else {
            return .none
        }

        if state.contentTabs.tabs[id: tabID]?.isPinned == true {
            return routeContentTabCloseMutation(
                tabID: tabID,
                batchOperationID: batchOperationID,
                action: .close(tabID),
            )
        }

        let isActiveTarget = tabID == state.contentTabs.activeTabID
        let targetState: FileManagerContentState
        if isActiveTarget {
            targetState = state.content
        } else {
            guard let inactiveState = state.tabContentStates[tabID] else {
                return routeContentTabCloseMutation(
                    tabID: tabID,
                    batchOperationID: batchOperationID,
                    action: .requestClose(tabID),
                )
            }
            targetState = inactiveState
        }

        if targetState.isCollectionMode, targetState.hasUnsavedCollectionChanges {
            let cancelCollectionOpenEffect = isActiveTarget
                ? cancelPendingCollectionOpen(state: &state)
                : Effect<Action>.none
            return .concatenate(
                cancelCollectionOpenEffect,
                beginUnsavedContentTabClose(
                    tabID: tabID,
                    targetState: targetState,
                    isActiveTarget: isActiveTarget,
                    batchOperationID: batchOperationID,
                    state: &state,
                ),
            )
        }

        return routeContentTabCloseMutation(
            tabID: tabID,
            batchOperationID: batchOperationID,
            action: .requestClose(tabID),
        )
    }

    private func commitContentTabCloseWithoutUndo(
        tabID: ContentTabID,
        batchOperationID: UUID?,
        state: inout State,
    ) -> Effect<Action> {
        if let batchOperationID {
            return .send(.performSelectedContentTabCloseMutation(
                operationID: batchOperationID,
                tabID: tabID,
                action: .commitClose(tabID),
            ))
        }
        _ = ContentTabFeature().reduce(into: &state.contentTabs, action: .commitClose(tabID))
        return finalizeContentTabClose(tabID: tabID, state: &state)
    }

    private func canHandleContentTabClose(
        tabID: ContentTabID,
        batchOperationID: UUID?,
        state: State,
    ) -> Bool {
        guard let pendingClose = state.pendingContentTabClose else { return true }
        return batchOperationID != nil
            && pendingClose.tabID == tabID
            && pendingClose.batchOperationID == batchOperationID
    }

    func routeContentTabCloseMutation(
        tabID: ContentTabID,
        batchOperationID: UUID?,
        action: ContentTabAction,
    ) -> Effect<Action> {
        guard let operationID = batchOperationID else {
            return .send(.contentTabs(action))
        }
        return .send(.performSelectedContentTabCloseMutation(
            operationID: operationID,
            tabID: tabID,
            action: action,
        ))
    }

    func beginUnsavedContentTabClose(
        tabID: ContentTabID,
        targetState: FileManagerContentState,
        isActiveTarget: Bool,
        batchOperationID: UUID?,
        state: inout State,
    ) -> Effect<Action> {
        state.pendingContentTabClose = PendingContentTabClose(
            tabID: tabID,
            previousActiveTabID: isActiveTarget ? nil : state.contentTabs.activeTabID,
            originalPreviousActiveTabID: state.pendingContentTabClose?.originalPreviousActiveTabID,
            previousActiveContent: isActiveTarget ? nil : state.content,
            targetContent: isActiveTarget ? nil : targetState,
            previousActiveInspector: isActiveTarget ? nil : state.inspector,
            targetInspector: isActiveTarget ? nil : state.inspectorState(for: tabID),
            batchOperationID: batchOperationID,
        )
        let alertEffect = Effect<Action>.run { send in
            let choice = await collectionAlertClient.showUnsavedNavigationAlert()
            if let batchOperationID {
                await send(.selectedContentTabCloseAlertResponse(
                    operationID: batchOperationID,
                    tabID: tabID,
                    choice: choice,
                ))
            } else {
                await send(.contentTabCloseAlertResponse(choice))
            }
        }
        guard let batchOperationID else { return alertEffect }
        return alertEffect.cancellable(
            id: SelectedContentTabCloseOperationCancelID(operationID: batchOperationID),
        )
    }

    func handleContentTabCloseAlertResponse(
        choice: CollectionNavigationChoice,
        state: inout State,
    ) -> Effect<Action> {
        guard let pendingClose = state.pendingContentTabClose else {
            return .none
        }

        switch choice {
        case .cancel:
            guard let operationID = pendingClose.batchOperationID else {
                state.pendingContentTabClose = nil
                return .none
            }
            return .send(.selectedContentTabCloseItemCompleted(
                operationID: operationID,
                tabID: pendingClose.tabID,
                outcome: .cancelled,
            ))

        case .discard:
            return handleDiscardContentTabClose(pendingClose, state: &state)

        case .save:
            stagePendingTargetContentIfNeeded(pendingClose, state: &state)
            guard canStartPendingContentSave(state.content) else {
                restorePreviousActiveContentIfNeeded(pendingClose, state: &state)
                state.pendingContentTabClose = nil
                guard let operationID = pendingClose.batchOperationID else { return .none }
                return .send(.selectedContentTabCloseItemCompleted(
                    operationID: operationID,
                    tabID: pendingClose.tabID,
                    outcome: .failed,
                ))
            }
            let requiresWriteBackFailureTerminal =
                state.content.collection.collectionSession.phase.isInflightWriteBack
            state.pendingContentTabClose?.requiresWriteBackFailureTerminal =
                requiresWriteBackFailureTerminal
            guard let operationID = pendingClose.batchOperationID else {
                return .send(.content(.composer(.saveCollection)))
            }
            return .send(.performBatchCloseContentAction(
                operationID: operationID,
                tabID: pendingClose.tabID,
                action: .composer(.saveCollection),
            ))
        }
    }

    func handleDiscardContentTabClose(
        _ pendingClose: PendingContentTabClose,
        state: inout State,
    ) -> Effect<Action> {
        if let operationID = pendingClose.batchOperationID {
            let closeEffect = routeContentTabCloseMutation(
                tabID: pendingClose.tabID,
                batchOperationID: operationID,
                action: .requestClose(pendingClose.tabID),
            )
            guard pendingClose.targetContent == nil else {
                return closeEffect
            }
            return .concatenate(
                .send(.content(.view(.discardCollectionChanges))),
                closeEffect,
            )
        }

        state.pendingContentTabClose = nil
        guard pendingClose.targetContent == nil else {
            return .send(.contentTabs(.requestClose(pendingClose.tabID)))
        }
        return .concatenate(
            .send(.content(.view(.discardCollectionChanges))),
            .send(.contentTabs(.requestClose(pendingClose.tabID))),
        )
    }

    func finalizePendingContentTabCloseIfWriteBackEffectsCompleted(
        state: inout State,
    ) -> Effect<Action> {
        guard let pendingClose = state.pendingContentTabClose,
              pendingClose.didReceiveWriteBackNavigationState,
              pendingClose.didReceiveWriteBackComposerSync
        else {
            return .none
        }
        restorePreviousActiveContentIfNeeded(pendingClose, state: &state)
        if let operationID = pendingClose.batchOperationID {
            return .send(.performSelectedContentTabCloseMutation(
                operationID: operationID,
                tabID: pendingClose.tabID,
                action: .requestClose(pendingClose.tabID),
            ))
        }
        state.pendingContentTabClose = nil
        return .send(.contentTabs(.requestClose(pendingClose.tabID)))
    }

    func recordPendingContentTabCloseSaveFeedback(
        _ feedback: CollectionSaveFeedback,
        state: inout State,
    ) {
        state.pendingContentTabClose?.didReceiveSaveFeedbackFailure = true
        if feedback.stage == .saveBlocked {
            state.pendingContentTabClose?.didReceiveSaveBlockedFeedback = true
        }
    }

    func finalizePendingContentTabCloseFailureIfReady(
        state: inout State,
    ) -> Effect<Action> {
        guard let pendingClose = state.pendingContentTabClose,
              pendingClose.didReceiveSaveFeedbackFailure
        else { return .none }
        let didReceiveSaveFailureTerminals = pendingClose.didReceiveSaveCompletedFailure
            && (!pendingClose.requiresWriteBackFailureTerminal || pendingClose.didReceiveWriteBackFailure)
        guard pendingClose.didReceiveSaveBlockedFeedback || didReceiveSaveFailureTerminals else { return .none }
        return finishPendingContentTabCloseWithoutClosing(outcome: .failed, state: &state)
    }

    func finishPendingContentTabCloseWithoutClosing(
        outcome: SelectedContentTabCloseOutcome,
        state: inout State,
    ) -> Effect<Action> {
        guard let pendingClose = state.pendingContentTabClose else { return .none }
        restorePreviousActiveContentIfNeeded(pendingClose, state: &state)
        guard let operationID = pendingClose.batchOperationID else {
            state.pendingContentTabClose = nil
            return .none
        }
        return .send(.selectedContentTabCloseItemCompleted(
            operationID: operationID,
            tabID: pendingClose.tabID,
            outcome: outcome,
        ))
    }

    func canStartPendingContentSave(_ content: FileManagerContentFeature.State) -> Bool {
        !content.collection.isSaving
            && !content.composer.isLoadingSearch
            && !content.composer.isLoadingFilters
    }

    func stagePendingTargetContentIfNeeded(
        _ pendingClose: PendingContentTabClose,
        state: inout State,
    ) {
        guard let targetContent = pendingClose.targetContent else {
            return
        }
        if let previousActiveTabID = pendingClose.previousActiveTabID {
            state.tabContentStates[previousActiveTabID] = state.content
            state.tabInspectorStates[previousActiveTabID] = state.inspector.tabSnapshot()
            state.contentTabs.previousActiveTabID = previousActiveTabID
            state.contentTabs.activeTabID = pendingClose.tabID
        }
        state.content = targetContent
        if let targetInspector = pendingClose.targetInspector {
            state.inspector = targetInspector.tabSnapshot()
        }
        state.syncActiveTabContentState()
        state.syncActiveTabInspectorState()
    }

    func restorePreviousActiveContentIfNeeded(
        _ pendingClose: PendingContentTabClose,
        state: inout State,
    ) {
        guard let previousActiveContent = pendingClose.previousActiveContent else {
            return
        }
        if pendingClose.targetContent != nil {
            state.tabContentStates[pendingClose.tabID] = state.content
            state.tabInspectorStates[pendingClose.tabID] = state.inspector.tabSnapshot()
        }
        state.content = previousActiveContent
        if let previousActiveInspector = pendingClose.previousActiveInspector {
            state.inspector = previousActiveInspector.tabSnapshot()
        }
        if let previousActiveTabID = pendingClose.previousActiveTabID {
            state.contentTabs.previousActiveTabID = pendingClose.tabID
            state.contentTabs.activeTabID = previousActiveTabID
            state.tabContentStates[previousActiveTabID] = previousActiveContent
            state.tabInspectorStates[previousActiveTabID] = state.inspector.tabSnapshot()
        }
    }
}
