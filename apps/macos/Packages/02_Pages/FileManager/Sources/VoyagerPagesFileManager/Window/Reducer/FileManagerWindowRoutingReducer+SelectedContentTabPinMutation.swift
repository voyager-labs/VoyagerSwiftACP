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
    func handleRequestSelectedContentTabPinMutation(
        target: SelectedContentTabPinMutationTargetState,
        state: inout State,
    ) -> Effect<Action> {
        guard state.canStartSelectedContentTabPinMutation else { return .none }
        let orderedTargetIDs = state.contentTabSelectionOrderedIDs
            .filter(state.contentTabs.selectedTabIDs.contains)
        guard orderedTargetIDs.count >= 2 else { return .none }

        let operationID = uuid()
        state.pendingSelectedContentTabPinMutation = PendingSelectedContentTabPinMutation(
            operationID: operationID,
            target: target,
            orderedTargetIDs: orderedTargetIDs,
        )
        return .send(.processNextSelectedContentTabPinMutation(operationID: operationID))
    }

    func handleRequestContentTabDomainTransition(
        _ request: ContentTabDomainTransitionRequest,
        state: inout State,
    ) -> Effect<Action> {
        guard admittedContentTabDomainTransition(request, state: state) else { return .none }
        let target: SelectedContentTabPinMutationTargetState = switch request.targetDomain {
        case .pinned: .pinned
        case .unpinned: .unpinned
        }
        let operationID = uuid()
        state.pendingSelectedContentTabPinMutation = PendingSelectedContentTabPinMutation(
            operationID: operationID,
            target: target,
            orderedTargetIDs: request.orderedTabIDs,
            origin: .drag,
            dragOperationID: request.operationID,
            sourceWindowID: request.sourceWindowID,
            sourceDomain: request.sourceDomain,
            targetDomain: request.targetDomain,
            initialPlacement: request.placement,
        )
        return .send(.processNextSelectedContentTabPinMutation(operationID: operationID))
    }

    private func admittedContentTabDomainTransition(
        _ request: ContentTabDomainTransitionRequest,
        state: State,
    ) -> Bool {
        guard state.canStartSelectedContentTabPinMutation,
              request.sourceDomain != request.targetDomain,
              state.windowID == request.sourceWindowID,
              state.sidebar.currentWindowID == request.sourceWindowID,
              !request.orderedTabIDs.isEmpty,
              Set(request.orderedTabIDs).count == request.orderedTabIDs.count,
              request.orderedTabIDs.contains(request.initiatingTabID)
        else { return false }

        let sourceIsPinned = request.sourceDomain == .pinned
        guard request.orderedTabIDs.allSatisfy({ tabID in
            guard let tab = state.contentTabs.tabs[id: tabID] else { return false }
            let hasPinnedRecord = state.contentTabs.pinnedRecords[tabID] != nil
            guard tab.isPinned == sourceIsPinned,
                  hasPinnedRecord == sourceIsPinned
            else { return false }
            return request.targetDomain == .unpinned || state.canPinContentTab(tabID)
        }) else { return false }

        switch request.placement {
        case let .before(anchorID), let .after(anchorID):
            guard !request.orderedTabIDs.contains(anchorID),
                  let anchor = state.contentTabs.tabs[id: anchorID],
                  ContentTabDomain.domain(isPinned: anchor.isPinned) == request.targetDomain,
                  (state.contentTabs.pinnedRecords[anchorID] != nil) == anchor.isPinned
            else { return false }
        case .empty:
            guard !state.contentTabs.tabs.contains(where: { tab in
                !request.orderedTabIDs.contains(tab.id)
                    && ContentTabDomain.domain(isPinned: tab.isPinned) == request.targetDomain
            }) else { return false }
        }
        return true
    }

    func processNextSelectedContentTabPinMutation(
        operationID: UUID,
        state: inout State,
    ) -> Effect<Action> {
        guard !state.isClosing,
              var pending = state.pendingSelectedContentTabPinMutation,
              pending.operationID == operationID,
              pending.currentTabID == nil
        else { return .none }

        guard pending.cursor < pending.orderedTargetIDs.count else {
            return completeSelectedContentTabPinMutation(pending, state: &state)
        }

        let tabID = pending.orderedTargetIDs[pending.cursor]
        pending.currentTabID = tabID
        state.pendingSelectedContentTabPinMutation = pending
        guard let tab = state.contentTabs.tabs[id: tabID] else {
            return completeSelectedContentTabPinMutationPreflight(
                operationID: operationID,
                tabID: tabID,
            )
        }

        pending.currentItemRollbackSnapshot = ContentTabPinnedRecordRollbackSnapshot(
            previousIsPinned: tab.isPinned,
            previousPinnedRecord: state.contentTabs.pinnedRecords[tabID],
            previousTabIndex: state.contentTabs.tabs.index(id: tabID),
        )
        state.pendingSelectedContentTabPinMutation = pending

        switch pending.target {
        case .pinned:
            guard !tab.isPinned, state.canPinContentTab(tabID) else {
                return completeSelectedContentTabPinMutationPreflight(
                    operationID: operationID,
                    tabID: tabID,
                )
            }
            return .send(.performSelectedContentTabPinMutation(
                operationID: operationID,
                tabID: tabID,
                action: .pin(tabID, placement: pending.currentPlacement),
            ))

        case .unpinned:
            guard tab.isPinned else {
                return completeSelectedContentTabPinMutationPreflight(
                    operationID: operationID,
                    tabID: tabID,
                )
            }
            return .send(.performSelectedContentTabPinMutation(
                operationID: operationID,
                tabID: tabID,
                action: .unpin(tabID, placement: pending.currentPlacement),
            ))
        }
    }

    func completeSelectedContentTabPinMutation(
        _ pending: PendingSelectedContentTabPinMutation,
        state: inout State,
    ) -> Effect<Action> {
        let result = SelectedContentTabPinMutationResult(
            operationID: pending.operationID,
            target: pending.target,
            totalCount: pending.totalCount,
            successCount: pending.successCount,
            failureCount: pending.failureCount,
            remainingCount: pending.remainingCount,
            origin: pending.origin,
        )
        guard result.totalCount == result.successCount + result.failureCount + result.remainingCount else {
            return .none
        }
        state.pendingSelectedContentTabPinMutation = nil
        return .concatenate(
            .cancel(id: SelectedContentTabPinMutationOperationCancelID(operationID: pending.operationID)),
            .send(.selectedPinMutationBatchCompleted(result)),
        )
    }

    /// 배치 pin/unpin 완료를 집계 terminal 한 건으로 기록한다. 항목별 이벤트는 만들지 않는다.
    /// 수용 항목 중 실패가 있으면 failure가 우선하고, 전부 적용 성공일 때만 success, 그 외는 cancelled다.
    /// source_surface는 배치 origin을 보존한다. menu는 content_tab_bar, drag는 drag_and_drop다.
    func recordSelectedPinMutationBatchMetric(_ result: SelectedContentTabPinMutationResult) {
        guard result.totalCount > 0 else { return }
        let outcome: ContentTabActionResult = if result.failureCount > 0 {
            .failure
        } else if result.successCount > 0 {
            .success
        } else {
            .cancelled
        }
        productMetricsClient.record(FileManagerProductMetricsProducer.contentTabTerminal(
            operationID: result.operationID,
            identity: result.target == .pinned ? .pinContentTabs : .unpinContentTabs,
            source: result.origin == .drag ? .dragAndDrop : .contentTabBar,
            result: outcome,
        ))
    }

    func completeSelectedContentTabPinMutationPreflight(
        operationID: UUID,
        tabID: ContentTabID,
    ) -> Effect<Action> {
        .send(.selectedPinMutationItemCompleted(
            operationID: operationID,
            tabID: tabID,
            outcome: .remaining,
        ))
    }

    func completeSelectedContentTabPinMutationItem(
        operationID: UUID,
        tabID: ContentTabID,
        outcome: SelectedContentTabPinMutationOutcome,
        state: inout State,
    ) -> Effect<Action> {
        guard !state.isClosing,
              var pending = state.pendingSelectedContentTabPinMutation,
              pending.operationID == operationID,
              pending.currentTabID == tabID
        else { return .none }

        switch outcome {
        case .success:
            pending.successCount += 1
            if pending.origin == .drag {
                pending.lastSuccessfullyPlacedID = tabID
            }
        case .failure:
            pending.failureCount += 1
        case .remaining:
            pending.remainingCount += 1
        }
        pending.cursor += 1
        pending.currentTabID = nil
        pending.currentItemRollbackSnapshot = nil
        pending.currentPersistenceContext = nil
        pending.currentTopNavigationToken = nil
        state.pendingSelectedContentTabPinMutation = pending
        return .send(.processNextSelectedContentTabPinMutation(operationID: operationID))
    }

    func handleSelectedContentTabPinMutation(
        operationID: UUID,
        tabID: ContentTabID,
        action: ContentTabAction,
        state: inout State,
    ) -> Effect<Action> {
        guard !state.isClosing,
              let pending = state.pendingSelectedContentTabPinMutation,
              pending.operationID == operationID,
              pending.currentTabID == tabID,
              !isStalePinnedRecordPersistenceResult(action, in: state.contentTabs),
              isCorrelatedSelectedContentTabPinMutation(action, for: tabID, target: pending.target)
        else { return .none }

        let outcome: SelectedContentTabPinMutationOutcome
        switch action {
        case let .pinnedRecordSaveSucceeded(successTabID, context) where successTabID == tabID:
            outcome = contentTabPinnedRecordClient.isCurrentMutationGeneration(context.generation)
                ? .success
                : .remaining
        case let .pinnedRecordSaveFailed(failedTabID, _, rollback) where failedTabID == tabID:
            if pending.target == .unpinned, let previousRecord = rollback.previousPinnedRecord {
                state.pendingRuntimePreservationRecords[tabID] = previousRecord
            }
            outcome = .failure
        case let .pinnedRecordStoreUnavailable(unavailableTabID, _, _, rollback)
            where unavailableTabID == tabID:
            if pending.target == .unpinned, let previousRecord = rollback.previousPinnedRecord {
                state.pendingRuntimePreservationRecords[tabID] = previousRecord
            }
            outcome = .failure
        case let .pinnedRecordSaveNotApplied(nonAppliedTabID, _, _, rollback) where nonAppliedTabID == tabID:
            if pending.target == .unpinned, let previousRecord = rollback.previousPinnedRecord {
                state.pendingRuntimePreservationRecords[tabID] = previousRecord
            }
            outcome = .remaining
        default:
            return .none
        }
        return .send(.selectedPinMutationItemCompleted(
            operationID: operationID,
            tabID: tabID,
            outcome: outcome,
        ))
    }

    func selectedContentTabPinMutationFeedbackEffect(
        _ result: SelectedContentTabPinMutationResult,
    ) -> Effect<Action> {
        let title: String
        let message: String
        if result.failureCount > 0 {
            title = result.target == .pinned
                ? "Some Tabs Couldn’t Be Pinned"
                : "Some Tabs Couldn’t Be Unpinned"
            message = "Completed \(result.successCount) of \(result.totalCount) selected tabs. "
                + "\(result.failureCount) failed and \(result.remainingCount) remained unchanged."
        } else if result.remainingCount > 0 {
            title = result.target == .pinned
                ? "Some Tabs Remained Unpinned"
                : "Some Tabs Remained Pinned"
            message = "Completed \(result.successCount) of \(result.totalCount) selected tabs. "
                + "\(result.remainingCount) remained unchanged."
        } else {
            return .none
        }

        let collectionAlertClient = collectionAlertClient
        return .run { _ in
            await collectionAlertClient.showCollectionOpenErrorAlert(title, message)
        }
    }
}
