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
    private func makeBatchDuplicateOwnerSnapshots(
        createdRequests: [ContentTabDuplicateRequest],
        windowContentSnapshot: FileManagerContentFeature.State,
        state: State,
    ) -> [BatchDuplicateOwnerSnapshot] {
        let preOperationActiveID = state.contentTabs.previousActiveTabID
        return createdRequests.compactMap { request in
            guard let sourceItem = state.contentTabs.tabs[id: request.sourceID],
                  let duplicateAnchor = state.contentTabs.tabs[id: request.duplicateID]?.anchor
            else { return nil }
            let sourceContent: FileManagerContentFeature.State? = if request.sourceID == preOperationActiveID {
                windowContentSnapshot
            } else {
                state.tabContentStates[request.sourceID]
            }
            let sourceAiChatLifecycleSessionIDs = sourceContent.map {
                aiChatLifecycleSessionIDsToPreserve($0.aiChat)
            } ?? []
            return BatchDuplicateOwnerSnapshot(
                request: request,
                sourceItem: sourceItem,
                duplicateAnchor: duplicateAnchor,
                sourceContent: sourceContent,
                sourceAiChatLifecycleSessionIDs: sourceAiChatLifecycleSessionIDs,
                duplicatedContent: makeDuplicatedContentState(
                    sourceContent,
                    anchor: duplicateAnchor,
                    inheritingWindowContextFrom: windowContentSnapshot,
                ),
            )
        }
    }

    func sidebarReorderRequested(
        sourceID: FileManagerTopNavigationItemID,
        anchorID: FileManagerTopNavigationItemID,
        placement: FileManagerTopNavigationReorderPlacement,
        actionSource: ContentTabActionSource,
        state: inout State,
    ) -> Effect<Action> {
        guard state.pendingSelectedContentTabClose == nil,
              state.pendingSelectedContentTabPinMutation == nil else { return .none }
        if case let .contentTab(sourceTabID) = sourceID,
           state.contentTabs.tabs[id: sourceTabID]?.isPinned == false
        {
            guard case let .contentTab(anchorTabID) = anchorID,
                  state.contentTabs.tabs[id: anchorTabID]?.isPinned == false
            else {
                return .none
            }
            let activeDragSnapshot: ContentTabDragSnapshot? = if let snapshot =
                state.sidebar.contentTabDragSnapshot,
                snapshot.lifecycle == .inFlight,
                snapshot.initiatingTabID == sourceTabID,
                snapshot.orderedTabIDs.contains(sourceTabID)
            {
                snapshot
            } else {
                nil
            }
            let orderedMovingIDs = activeDragSnapshot?.orderedTabIDs ?? [sourceTabID]
            guard ContentTabFeature.reorderedTabs(
                state.contentTabs.tabs,
                orderedMovingIDs: orderedMovingIDs,
                anchorID: anchorTabID,
                placement: placement,
            ) != nil else {
                return .none
            }
            if activeDragSnapshot != nil {
                state.sidebar.contentTabDragSnapshot = nil
            }
            guard orderedMovingIDs.count > 1 else {
                return .send(.contentTabs(.reorder(
                    sourceID: sourceTabID,
                    targetID: anchorTabID,
                    placement: placement,
                )))
            }
            return .send(.contentTabs(.reorderGroup(
                orderedMovingIDs: orderedMovingIDs,
                anchorID: anchorTabID,
                placement: placement,
            )))
        }
        return .send(.topNavigationMoveRequested(
            source: sourceID,
            destination: placement == .before ? .before(anchorID) : .after(anchorID),
            actionSource: actionSource,
        ))
    }

    func contentTabsSetCurrent(targetID: ContentTabID, state: inout State) -> Effect<Action> {
        guard state.contentTabs.activeTabID == targetID else { return .none }
        if keepPendingContentTabCloseFocused(state: &state) {
            return .none
        }
        let shouldResyncContentNavigation = state.contentTabs.previousActiveTabID != nil
            || state.activeTabContentStateMissing
        let handoffCleanupEffect: Effect<Action>
        if shouldResyncContentNavigation {
            let aiChatLifecycleSessionIDs = aiChatLifecycleSessionIDsToPreserve(state.content.aiChat)
            if aiChatLifecycleSessionIDs.isEmpty {
                handoffCleanupEffect = prepareContentForActiveTabHandoff(state: &state.content)
            } else {
                for aiChatSessionID in aiChatLifecycleSessionIDs {
                    state.addBackgroundAiChatState(sessionID: aiChatSessionID, state: state.content)
                }
                handoffCleanupEffect = prepareContentForActiveTabHandoff(
                    state: &state.content,
                    skipAiChatCleanup: true,
                )
            }
        } else {
            handoffCleanupEffect = .none
        }
        if shouldResyncContentNavigation {
            state.saveCurrentContentStateForPreviousActiveTab()
            state.saveCurrentInspectorStateForPreviousActiveTab()
            state.restoreContentStateForActiveTab()
            removeBackgroundAiChatOwnersPromotedToActiveContent(state: &state)
            state.restoreInspectorStateForActiveTab()
        }
        syncDashboardProjections(state: &state)
        syncSidebarSelectionForActiveContentTab(state: &state)
        consumePendingDirectoryReloadForActiveTab(state: &state)
        return .merge(
            .concatenate(
                handoffCleanupEffect,
                restoreActiveAiChatSessionIfNeededEffect(state: state),
                activeTabHandoffEffect(
                    shouldResyncContentNavigation,
                    state: &state,
                    aiConnectionsFileClient: aiConnectionsFileClient,
                    skipAiChatCancel: true,
                ),
            ),
            closeInspectorForActiveAiChatEffect(state: state),
        )
    }

    func contentTabsOpen(state: inout State) -> Effect<Action> {
        guard state.contentTabMoveParticipantRequestID == nil else { return .none }
        if keepPendingContentTabCloseFocusedAfterOpen(state: &state) {
            return .none
        }
        let openedTabID = state.activeTabContentStateMissing ? state.contentTabs.activeTabID : nil
        let shouldResyncContentNavigation = state.contentTabs.previousActiveTabID != nil
            || state.activeTabContentStateMissing
        let handoffCleanupEffect: Effect<Action>
        if shouldResyncContentNavigation {
            let aiChatLifecycleSessionIDs = aiChatLifecycleSessionIDsToPreserve(state.content.aiChat)
            if aiChatLifecycleSessionIDs.isEmpty {
                handoffCleanupEffect = prepareContentForActiveTabHandoff(state: &state.content)
            } else {
                for aiChatSessionID in aiChatLifecycleSessionIDs {
                    state.addBackgroundAiChatState(sessionID: aiChatSessionID, state: state.content)
                }
                handoffCleanupEffect = prepareContentForActiveTabHandoff(
                    state: &state.content,
                    skipAiChatCleanup: true,
                )
            }
        } else {
            handoffCleanupEffect = .none
        }
        if shouldResyncContentNavigation {
            state.saveCurrentContentStateForPreviousActiveTab()
            state.saveCurrentInspectorStateForPreviousActiveTab()
            if state.activeTabContentStateMissing {
                let activeAnchor = state.contentTabs.activeTabID
                    .flatMap { state.contentTabs.tabs[id: $0]?.anchor }
                state.content = contentState(for: activeAnchor, inheritingWindowContextFrom: state.content)
                state.syncActiveTabContentState()
            }
            state.restoreInspectorStateForActiveTab()
        }
        syncDashboardProjections(state: &state)
        syncSidebarSelectionForActiveContentTab(state: &state)
        return .merge(
            handoffCleanupEffect,
            activeTabHandoffEffect(
                shouldResyncContentNavigation,
                state: &state,
                aiConnectionsFileClient: aiConnectionsFileClient,
                skipAiChatCancel: true,
            ),
            closeInspectorForActiveAiChatEffect(state: state),
            openedTabID.map { activateUndoManagerScopeEffect(tabID: $0, state: state) } ?? .none,
        )
    }

    func contentTabsRestore(state: inout State) -> Effect<Action> {
        guard state.contentTabMoveParticipantRequestID == nil else { return .none }
        if keepPendingContentTabCloseFocused(state: &state) {
            return .none
        }
        let restoredTabID = state.activeTabContentStateMissing
            ? state.contentTabs.activeTabID
            : nil
        let shouldResyncContentNavigation = state.contentTabs.previousActiveTabID != nil
            || state.activeTabContentStateMissing
        let handoffCleanupEffect: Effect<Action>
        if shouldResyncContentNavigation {
            let aiChatLifecycleSessionIDs = aiChatLifecycleSessionIDsToPreserve(state.content.aiChat)
            if aiChatLifecycleSessionIDs.isEmpty {
                handoffCleanupEffect = prepareContentForActiveTabHandoff(state: &state.content)
            } else {
                for aiChatSessionID in aiChatLifecycleSessionIDs {
                    state.addBackgroundAiChatState(sessionID: aiChatSessionID, state: state.content)
                }
                handoffCleanupEffect = prepareContentForActiveTabHandoff(
                    state: &state.content,
                    skipAiChatCleanup: true,
                )
            }
        } else {
            handoffCleanupEffect = .none
        }
        if shouldResyncContentNavigation {
            state.saveCurrentContentStateForPreviousActiveTab()
            state.saveCurrentInspectorStateForPreviousActiveTab()
            state.restoreContentStateForActiveTab()
            removeBackgroundAiChatOwnersPromotedToActiveContent(state: &state)
            state.restoreInspectorStateForActiveTab()
            if let restoredRoute = state.recentlyClosedNavigationRoute {
                state.content.navigation.navigationState = restoredRoute
                state.syncActiveTabContentState()
                state.recentlyClosedNavigationRoute = nil
            }
        }
        syncDashboardProjections(state: &state)
        syncSidebarSelectionForActiveContentTab(state: &state)
        return .merge(
            handoffCleanupEffect,
            activeTabHandoffEffect(
                shouldResyncContentNavigation,
                state: &state,
                aiConnectionsFileClient: aiConnectionsFileClient,
                skipAiChatCancel: true,
            ),
            closeInspectorForActiveAiChatEffect(state: state),
            restoredTabID.map { activateUndoManagerScopeEffect(tabID: $0, state: state) } ?? .none,
        )
    }

    func duplicateSelectedContentTabsReduced(
        requests: [ContentTabDuplicateRequest],
        preexistingTabIDs: Set<ContentTabID>,
        state: inout State,
    ) -> Effect<Action> {
        // ContentTabFeature가 identity와 source metadata로 만든 row만 owner-state handoff 대상으로 사용한다.
        let createdRequests = createdDuplicateRequests(
            requests,
            preexistingTabIDs: preexistingTabIDs,
            state: state,
        )
        guard !createdRequests.isEmpty else {
            syncDashboardProjections(state: &state)
            return .none
        }

        // Core mutation 이후에도 Content owner는 pre-operation active를 가리킨다.
        // 모든 source owner를 local snapshot으로 먼저 고정해 첫 handoff가 뒤 source를 오염시키지 않게 한다.
        let windowContentSnapshot = state.content
        let ownerSnapshots = makeBatchDuplicateOwnerSnapshots(
            createdRequests: createdRequests,
            windowContentSnapshot: windowContentSnapshot,
            state: state,
        )
        guard ownerSnapshots.count == createdRequests.count,
              let activeDuplicate = ownerSnapshots.first
        else {
            syncDashboardProjections(state: &state)
            return .none
        }

        if keepPendingDuplicateContentTabCloseFocused(
            duplicateIDs: ownerSnapshots.map(\.request.duplicateID),
            state: &state,
        ) {
            return .none
        }

        let duplicateUndoScopeActivationEffect = ownerSnapshots
            .reduce(Effect<Action>.none) { effect, snapshot in
                .concatenate(
                    effect,
                    activateUndoManagerScopeEffect(tabID: snapshot.request.duplicateID, state: state),
                )
            }

        let shouldResyncContentNavigation = state.contentTabs.previousActiveTabID != nil
            || state.activeTabContentStateMissing

        // Inactive duplicates receive fresh Content owners immediately; Inspector owners stay absent/default.
        for snapshot in ownerSnapshots.dropFirst() {
            state.tabContentStates[snapshot.request.duplicateID] = snapshot.duplicatedContent
        }

        let outgoingAiChatLifecycleSessionIDs = aiChatLifecycleSessionIDsToPreserve(
            windowContentSnapshot.aiChat,
        )
        var lifecycleSources = ownerSnapshots.compactMap { snapshot in
            snapshot.sourceContent.map {
                (sessionIDs: snapshot.sourceAiChatLifecycleSessionIDs, content: $0)
            }
        }
        lifecycleSources.insert(
            (sessionIDs: outgoingAiChatLifecycleSessionIDs, content: windowContentSnapshot),
            at: 0,
        )
        for lifecycleSource in lifecycleSources {
            for sessionID in lifecycleSource.sessionIDs {
                state.addBackgroundAiChatState(sessionID: sessionID, state: lifecycleSource.content)
            }
        }

        let handoffCleanupEffect: Effect<Action>
        if shouldResyncContentNavigation {
            handoffCleanupEffect = prepareContentForActiveTabHandoff(
                state: &state.content,
                skipAiChatCleanup: !outgoingAiChatLifecycleSessionIDs.isEmpty,
            )
            state.saveCurrentContentStateForPreviousActiveTab()
            state.saveCurrentInspectorStateForPreviousActiveTab()
            state.content = activeDuplicate.duplicatedContent
            state.syncActiveTabContentState()
            state.restoreInspectorStateForActiveTab()
        } else {
            handoffCleanupEffect = .none
        }

        let duplicatedAiChatRestoreEffect = activeDuplicate.sourceAiChatLifecycleSessionIDs.isEmpty
            ? restoreActiveAiChatSessionIfNeededEffect(state: state)
            : Effect<Action>.none
        syncDashboardProjections(state: &state)
        syncSidebarSelectionForActiveContentTab(state: &state)
        return .merge(
            duplicateUndoScopeActivationEffect,
            .concatenate(
                handoffCleanupEffect,
                duplicatedAiChatRestoreEffect,
                activeTabHandoffEffect(
                    shouldResyncContentNavigation,
                    state: &state,
                    aiConnectionsFileClient: aiConnectionsFileClient,
                    skipAiChatCancel: true,
                ),
            ),
            closeInspectorForActiveAiChatEffect(state: state),
        )
    }

    func duplicateContentTabReduced(
        sourceID: ContentTabID,
        duplicateID: ContentTabID,
        duplicateIDWasPreexisting: Bool,
        state: inout State,
    ) -> Effect<Action> {
        // Post-reduce branch: ContentTabFeature가 row를 생성한 후 handoff/rollback 처리
        // 기존 identity collision이나 row 미생성은 core guard no-op이므로 state를 그대로 유지한다.
        guard !duplicateIDWasPreexisting,
              state.contentTabs.tabs[id: duplicateID] != nil
        else { return .none }

        // Pending close 상태: exact duplicateID row/cache 제거 후 pending state 복원
        if keepPendingDuplicateContentTabCloseFocused(
            duplicateID: duplicateID,
            state: &state,
        ) {
            return .none
        }

        let sourceAnchor = state.contentTabs.tabs[id: sourceID]?.anchor
        let duplicateAnchor = state.contentTabs.tabs[id: duplicateID]?.anchor
        let sourceContentState = duplicateSourceContentState(
            sourceID: sourceID,
            duplicateID: duplicateID,
            state: state,
        )
        let sourceAiChatLifecycleSessionIDs = sourceContentState.map {
            aiChatLifecycleSessionIDsToPreserve($0.aiChat)
        } ?? []
        let duplicatedContentState = makeDuplicatedContentState(
            sourceContentState,
            anchor: duplicateAnchor ?? sourceAnchor,
            inheritingWindowContextFrom: state.content,
        )
        let duplicateUndoScopeActivationEffect = activateUndoManagerScopeEffect(
            tabID: duplicateID,
            state: state,
        )

        // Pinned source는 active를 유지하므로 duplicate cache만 source snapshot으로 초기화한다.
        guard state.contentTabs.activeTabID == duplicateID else {
            state.tabContentStates[duplicateID] = duplicatedContentState
            syncDashboardProjections(state: &state)
            return duplicateUndoScopeActivationEffect
        }

        // === Active duplicate: .contentTabs(.open) handoff 패턴 적용 ===
        let shouldResyncContentNavigation = state.contentTabs.previousActiveTabID != nil
            || state.activeTabContentStateMissing
        let outgoingAiChatLifecycleSessionIDs = aiChatLifecycleSessionIDsToPreserve(state.content.aiChat)
        let handoffCleanupEffect: Effect<Action>
        if shouldResyncContentNavigation {
            if outgoingAiChatLifecycleSessionIDs.isEmpty {
                handoffCleanupEffect = prepareContentForActiveTabHandoff(state: &state.content)
            } else {
                for aiChatSessionID in outgoingAiChatLifecycleSessionIDs {
                    state.addBackgroundAiChatState(sessionID: aiChatSessionID, state: state.content)
                }
                handoffCleanupEffect = prepareContentForActiveTabHandoff(
                    state: &state.content,
                    skipAiChatCleanup: true,
                )
            }
        } else {
            handoffCleanupEffect = .none
        }
        if shouldResyncContentNavigation {
            state.saveCurrentContentStateForPreviousActiveTab()
            state.saveCurrentInspectorStateForPreviousActiveTab()
            state.content = duplicatedContentState
            state.syncActiveTabContentState()
            state.restoreInspectorStateForActiveTab()
        }
        let duplicatedAiChatRestoreEffect = sourceAiChatLifecycleSessionIDs.isEmpty
            ? restoreActiveAiChatSessionIfNeededEffect(state: state)
            : Effect<Action>.none
        syncDashboardProjections(state: &state)
        syncSidebarSelectionForActiveContentTab(state: &state)
        let handoffEffect = activeTabHandoffEffect(
            shouldResyncContentNavigation,
            state: &state,
            aiConnectionsFileClient: aiConnectionsFileClient,
            skipAiChatCancel: true,
        )
        return .merge(
            duplicateUndoScopeActivationEffect,
            .concatenate(
                handoffCleanupEffect,
                duplicatedAiChatRestoreEffect,
                handoffEffect,
            ),
            closeInspectorForActiveAiChatEffect(state: state),
        )
    }
}
