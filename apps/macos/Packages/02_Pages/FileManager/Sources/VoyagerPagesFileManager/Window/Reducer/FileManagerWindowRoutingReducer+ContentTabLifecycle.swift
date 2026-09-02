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

private struct ContentTabCloseDisposition {
    let isActualRemoval: Bool
    let shouldRestorePreviousActiveTab: Bool
    let shouldResetLastTabContent: Bool
    let replacementHomeTabID: ContentTabID?
    let shouldResyncContentNavigation: Bool
}

private struct ContentTabCloseEffectInputs {
    let handoffCleanup: Effect<FileManagerWindowAction>
    let undoManagerLifecycle: Effect<FileManagerWindowAction>
    let loadingCancellation: Effect<FileManagerWindowAction>
}

private func contentTabCloseDisposition(
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

    func handleRequestCloseSelectedContentTabs(state: inout State) -> Effect<Action> {
        guard state.canStartSelectedContentTabClose else { return .none }

        let selectionOrderedIDs = state.contentTabSelectionOrderedIDs
        let validSelectedIDs = selectionOrderedIDs.filter(state.contentTabs.selectedTabIDs.contains)
        guard validSelectedIDs.count >= 2 else { return .none }

        let activeTabID = state.contentTabs.activeTabID
        var orderedTargetIDs = validSelectedIDs.filter { $0 != activeTabID }
        if let activeTabID, validSelectedIDs.contains(activeTabID) {
            orderedTargetIDs.append(activeTabID)
        }
        let targetIDSet = Set(orderedTargetIDs)
        let preferredFallbackIDs = preferredSelectedContentTabCloseFallbackIDs(
            originalTabIDs: selectionOrderedIDs,
            originalActiveTabID: activeTabID,
            targetIDSet: targetIDSet,
            orderedTargetIDs: orderedTargetIDs,
        )
        let operationID = uuid()
        state.pendingSelectedContentTabClose = PendingSelectedContentTabClose(
            operationID: operationID,
            orderedTargetIDs: orderedTargetIDs,
            originalActiveTabID: activeTabID,
            preferredFallbackIDs: preferredFallbackIDs,
        )
        return .send(.processNextSelectedContentTabClose(operationID: operationID))
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
        let pendingPinnedReturnTabID = mode == .authoritative
            ? state.pendingPinnedCollectionReturnTabID
            : nil
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
        return pinnedContentTabsAppliedEffects(
            pendingPinnedReturnTabID: pendingPinnedReturnTabID,
            shouldResyncContentNavigation: shouldResyncContentNavigation,
            restorePendingCollectionHistory: mode == .authoritative,
            tabAnchorsBeforeSync: tabAnchorsBeforeSync,
            state: &state,
        )
    }

    func pinnedContentTabsAppliedEffects(
        pendingPinnedReturnTabID: ContentTabID?,
        shouldResyncContentNavigation: Bool,
        restorePendingCollectionHistory: Bool,
        tabAnchorsBeforeSync: [(id: ContentTabID, anchor: ContentTabPageAnchor)],
        state: inout State,
    ) -> Effect<Action> {
        let handoffCleanupEffect = shouldResyncContentNavigation
            ? prepareContentForActiveTabHandoff(state: &state.content)
            : .none
        let invalidatedPinnedReturnEffect: Effect<Action> = if let pendingPinnedReturnTabID,
                                                               state.pendingPinnedCollectionReturnTabID
                                                               != pendingPinnedReturnTabID
        {
            cancelPendingCollectionOpen(
                state: &state,
                failedPinnedReturnTabID: pendingPinnedReturnTabID,
            )
        } else {
            .none
        }
        return .concatenate(
            invalidatedPinnedReturnEffect,
            .merge(
                handoffCleanupEffect,
                activeTabHandoffEffect(
                    shouldResyncContentNavigation,
                    state: &state,
                    aiConnectionsFileClient: aiConnectionsFileClient,
                    restorePendingCollectionHistory: restorePendingCollectionHistory,
                ),
                closeInspectorForActiveAiChatEffect(state: state),
                reconcileUndoManagerScopesEffect(
                    tabAnchorsBeforeSync: tabAnchorsBeforeSync,
                    state: state,
                ),
            ),
        )
    }

    func finalizeContentTabClose(
        tabID: ContentTabID,
        state: inout State,
    ) -> Effect<Action> {
        if keepPendingContentTabCloseFocused(state: &state) {
            return .none
        }
        let disposition = contentTabCloseDisposition(tabID: tabID, state: state)
        let cancelCollectionOpenEffect = disposition.shouldResyncContentNavigation
            ? cancelPendingCollectionOpen(state: &state, failedPinnedReturnTabID: tabID)
            : .none
        state.pendingDirectoryReloadTabIDs.remove(tabID)
        let closedTabLoadingCancellationEffect = makeContentTabLoadingCancellationEffect(
            tabID: tabID,
            disposition: disposition,
            state: state,
        )
        let aiChatLifecycleSessionIDs = aiChatLifecycleSessionIDsToPreserve(state.content.aiChat)
        let isAiChatLifecyclePreservingTabClose = disposition.shouldResyncContentNavigation
            && !aiChatLifecycleSessionIDs.isEmpty
        if disposition.isActualRemoval {
            state.recentlyClosedNavigationRoute = navigationRouteForClosingTab(tabID, state: state)
        }
        let handoffCleanupEffect = makeContentTabHandoffCleanupEffect(
            disposition: disposition,
            isAiChatLifecyclePreservingTabClose: isAiChatLifecyclePreservingTabClose,
            aiChatLifecycleSessionIDs: aiChatLifecycleSessionIDs,
            state: &state,
        )
        applyContentTabCloseStateRemoval(
            tabID: tabID,
            disposition: disposition,
            state: &state,
        )
        syncDashboardProjections(state: &state)
        syncSidebarSelectionForActiveContentTab(state: &state)
        let undoManagerLifecycleEffect = makeContentTabUndoManagerLifecycleEffect(
            tabID: tabID,
            disposition: disposition,
            state: state,
        )
        return .concatenate(
            cancelCollectionOpenEffect,
            makeContentTabCloseEffects(
                ContentTabCloseEffectInputs(
                    handoffCleanup: handoffCleanupEffect,
                    undoManagerLifecycle: undoManagerLifecycleEffect,
                    loadingCancellation: closedTabLoadingCancellationEffect,
                ),
                disposition: disposition,
                state: &state,
            ),
        )
    }

    private func makeContentTabLoadingCancellationEffect(
        tabID: ContentTabID,
        disposition: ContentTabCloseDisposition,
        state: State,
    ) -> Effect<Action> {
        guard disposition.isActualRemoval || disposition.shouldResetLastTabContent else { return .none }
        return cancelLoadingEffectForClosedTab(
            tabID: tabID,
            wasActive: disposition.shouldRestorePreviousActiveTab,
            state: state,
        )
    }

    private func makeContentTabUndoManagerLifecycleEffect(
        tabID: ContentTabID,
        disposition: ContentTabCloseDisposition,
        state: State,
    ) -> Effect<Action> {
        if let replacementHomeTabID = disposition.replacementHomeTabID {
            return replaceUndoManagerScopeEffect(
                closedTabID: tabID,
                homeTabID: replacementHomeTabID,
                state: state,
            )
        }
        if disposition.isActualRemoval {
            return deactivateUndoManagerScopeEffect(tabID: tabID, state: state)
        }
        return .none
    }

    private func makeContentTabCloseEffects(
        _ inputs: ContentTabCloseEffectInputs,
        disposition: ContentTabCloseDisposition,
        state: inout State,
    ) -> Effect<Action> {
        let handoffEffect: Effect<Action> = .merge(
            inputs.handoffCleanup,
            activeTabHandoffEffect(
                disposition.shouldResyncContentNavigation,
                state: &state,
                aiConnectionsFileClient: aiConnectionsFileClient,
                skipAiChatCancel: true,
            ),
            closeInspectorForActiveAiChatEffect(state: state),
            inputs.undoManagerLifecycle,
            inputs.loadingCancellation,
        )
        return disposition.shouldResetLastTabContent
            ? .merge(handoffEffect, .send(.delegate(.closeWindow)))
            : handoffEffect
    }

    private func makeContentTabHandoffCleanupEffect(
        disposition: ContentTabCloseDisposition,
        isAiChatLifecyclePreservingTabClose: Bool,
        aiChatLifecycleSessionIDs: [AiChatSessionID],
        state: inout State,
    ) -> Effect<Action> {
        guard disposition.shouldResyncContentNavigation else { return .none }
        if isAiChatLifecyclePreservingTabClose {
            for aiChatSessionID in aiChatLifecycleSessionIDs {
                state.addBackgroundAiChatState(sessionID: aiChatSessionID, state: state.content)
            }
            return prepareContentForActiveTabHandoff(
                state: &state.content,
                skipAiChatCleanup: true,
            )
        }
        return prepareContentForActiveTabHandoff(state: &state.content)
    }

    private func applyContentTabCloseStateRemoval(
        tabID: ContentTabID,
        disposition: ContentTabCloseDisposition,
        state: inout State,
    ) {
        if disposition.isActualRemoval {
            state.addBackgroundAiChatState(for: tabID)
            state.addBackgroundInspectorAiChatState(for: tabID)
            state.removeContentState(for: tabID)
            state.removeInspectorState(for: tabID)
            if disposition.shouldRestorePreviousActiveTab {
                state.restoreContentStateForActiveTab()
                removeBackgroundAiChatOwnersPromotedToActiveContent(state: &state)
                state.restoreInspectorStateForActiveTab()
            }
        } else if disposition.shouldResetLastTabContent {
            state.addBackgroundAiChatState(for: tabID)
            state.addBackgroundInspectorAiChatState(for: tabID)
            state.content = contentState(
                for: state.contentTabs.tabs[id: tabID]?.anchor,
                inheritingWindowContextFrom: state.content,
            )
            state.inspector = .init()
            state.syncActiveTabContentState()
            state.syncActiveTabInspectorState()
        }
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
            return finalizeContentTabTeardownImmediately(
                tabID: tabID,
                batchOperationID: batchOperationID,
                state: &state,
            )

        case .invoking, .replaying, .refreshing, .recovering, .tearingDownTab:
            return .none
        }

        let usesActiveContent = state.contentTabs.activeTabID == tabID
        let ownerID = usesActiveContent
            ? state.content.entryViewLayout.entryOperations.undoOwnerID
            : state.tabContentStates[tabID]?.entryViewLayout.entryOperations.undoOwnerID
        guard let ownerID, let windowID = state.windowID else {
            return finalizeContentTabTeardownImmediately(
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

    private func finalizeContentTabTeardownImmediately(
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

    func handleCloseContentTabRequested(
        tabID: ContentTabID,
        state: inout State,
        batchOperationID: UUID? = nil,
    ) -> Effect<Action> {
        guard !state.contentTabs.pendingPinnedRecordIDs.contains(tabID) else { return .none }
        if let pendingClose = state.pendingContentTabClose {
            guard let batchOperationID,
                  pendingClose.tabID == tabID,
                  pendingClose.batchOperationID == batchOperationID
            else { return .none }
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
        guard var targetState = contentStateForClose(tabID: tabID, state: state) else {
            return routeContentTabCloseMutation(
                tabID: tabID,
                batchOperationID: batchOperationID,
                action: .requestClose(tabID),
            )
        }

        synchronizePendingCollectionDraftBeforeClose(
            tabID: tabID,
            isActiveTarget: isActiveTarget,
            targetState: &targetState,
            windowState: &state,
        )

        if let unsavedCloseEffect = routeUnsavedContentTabClose(
            tabID: tabID,
            targetState: targetState,
            isActiveTarget: isActiveTarget,
            batchOperationID: batchOperationID,
            state: &state,
        ) {
            return unsavedCloseEffect
        }

        return routeContentTabCloseMutation(
            tabID: tabID,
            batchOperationID: batchOperationID,
            action: .requestClose(tabID),
        )
    }

    private func contentStateForClose(
        tabID: ContentTabID,
        state: State,
    ) -> FileManagerContentState? {
        if tabID == state.contentTabs.activeTabID {
            return state.content
        }
        return state.tabContentStates[tabID]
    }

    private func synchronizePendingCollectionDraftBeforeClose(
        tabID: ContentTabID,
        isActiveTarget: Bool,
        targetState: inout FileManagerContentState,
        windowState: inout State,
    ) {
        guard targetState.composer.isCollectionSearching || targetState.composer.pendingSearchQuery != nil else {
            return
        }
        FileManagerContentComposerCoordinator.synchronizeOpenedCollectionDraftFromComposer(state: &targetState)
        if isActiveTarget {
            windowState.content = targetState
            windowState.syncActiveTabContentState()
        } else {
            windowState.tabContentStates[tabID] = targetState
        }
    }

    private func routeUnsavedContentTabClose(
        tabID: ContentTabID,
        targetState: FileManagerContentState,
        isActiveTarget: Bool,
        batchOperationID: UUID?,
        state: inout State,
    ) -> Effect<Action>? {
        guard targetState.isCollectionMode, targetState.hasUnsavedCollectionChanges else { return nil }
        let cancelCollectionOpenEffect = isActiveTarget
            ? cancelPendingCollectionOpen(state: &state, failedPinnedReturnTabID: tabID)
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
