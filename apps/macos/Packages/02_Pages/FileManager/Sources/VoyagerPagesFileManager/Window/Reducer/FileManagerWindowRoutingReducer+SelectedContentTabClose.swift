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

extension FileManagerWindowRoutingReducer {
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
            return completeSelectedContentTabClose(pending, state: &state)
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

    private func completeSelectedContentTabClose(
        _ pending: PendingSelectedContentTabClose,
        state: inout State,
    ) -> Effect<Action> {
        let replayAction = takeDeferredPinnedContentTabsAction(state: &state)
        state.pendingSelectedContentTabClose = nil
        if let result = pending.aggregateResult {
            productMetricsClient.record(FileManagerProductMetricsProducer.contentTabTerminal(
                operationID: pending.operationID,
                identity: .closeSelectedContentTabs,
                source: .contentTabBar,
                result: result,
            ))
        }
        let cancelEffect = Effect<Action>.cancel(
            id: SelectedContentTabCloseOperationCancelID(operationID: pending.operationID),
        )
        guard let replayAction else { return cancelEffect }
        return .concatenate(cancelEffect, .send(replayAction))
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
        pending.aggregateResult = aggregateSelectedContentTabCloseResult(
            pending.aggregateResult,
            outcome: outcome,
        )
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

    private func aggregateSelectedContentTabCloseResult(
        _ current: ContentTabActionResult?,
        outcome: SelectedContentTabCloseOutcome,
    ) -> ContentTabActionResult {
        let next: ContentTabActionResult = switch outcome {
        case .removed, .unpinned, .missing:
            .success
        case .cancelled:
            .cancelled
        case .failed:
            .failure
        }
        if current == .failure || next == .failure {
            return .failure
        }
        if current == .success || next == .success {
            return .success
        }
        return .cancelled
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
}
