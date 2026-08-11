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
    var routingBody: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .applyPinnedContentTabRuntimeNavigation(tabID, navigationState):
                return applyPinnedContentTabRuntimeNavigation(
                    tabID: tabID,
                    navigationState: navigationState,
                    state: &state,
                )

            case .navigation(.view(.navigateToPath)),
                 .navigation(.view(.showRecents)),
                 .navigation(.view(.showComputer)),
                 .navigation(.view(.showTag)),
                 .navigation(.view(.showAiChat)),
                 .navigation(.view(.showAiChatSessions)),
                 .navigation(.view(.goBack)),
                 .navigation(.view(.goForward)),
                 .navigation(.view(.goToHistoryIndex)),
                 .navigation(.view(.goToEnclosingDirectory)):
                return cancelPendingCollectionOpen(state: &state)

            case let .requestSelectedContentTabPinMutation(target):
                return handleRequestSelectedContentTabPinMutation(target: target, state: &state)

            case let .requestContentTabDomainTransition(request):
                return handleRequestContentTabDomainTransition(request, state: &state)

            case let .processNextSelectedContentTabPinMutation(operationID):
                return processNextSelectedContentTabPinMutation(operationID: operationID, state: &state)

            case let .selectedPinMutationItemCompleted(operationID, tabID, outcome):
                return completeSelectedContentTabPinMutationItem(
                    operationID: operationID,
                    tabID: tabID,
                    outcome: outcome,
                    state: &state,
                )

            case let .selectedPinMutationBatchCompleted(result):
                let replayAction = takeDeferredPinnedContentTabsAction(state: &state)
                let replaySnapshot: Effect<Action> = if case .applyAuthoritativePinnedContentTabs = replayAction,
                                                        let revision = state.lastConfirmedTopNavigationCommitRevision
                {
                    .send(.applyCommittedTopNavigationSnapshot(
                        order: state.lastConfirmedTopNavigationOrder,
                        revision: revision,
                        authoritativePinnedContentTabs: nil,
                    ))
                } else {
                    .none
                }
                return .concatenate(
                    replaySnapshot,
                    replayAction.map(Effect.send) ?? .none,
                    selectedContentTabPinMutationFeedbackEffect(result),
                )

            case let .performSelectedContentTabPinMutation(operationID, tabID, contentTabAction):
                return handleSelectedContentTabPinMutation(
                    operationID: operationID,
                    tabID: tabID,
                    action: contentTabAction,
                    state: &state,
                )

            case .requestCloseSelectedContentTabs:
                return handleRequestCloseSelectedContentTabs(state: &state)

            case .onAppear:
                state.isClosing = false
                return .none

            case .onDisappear:
                return handleWindowDisappear(state: &state)

            case let .processNextSelectedContentTabClose(operationID):
                return processNextSelectedContentTabClose(operationID: operationID, state: &state)

            case let .selectedContentTabCloseItemCompleted(operationID, tabID, outcome):
                return completeSelectedContentTabCloseItem(
                    operationID: operationID,
                    tabID: tabID,
                    outcome: outcome,
                    state: &state,
                )

            case let .performSelectedContentTabCloseMutation(operationID, tabID, contentTabAction):
                guard !state.isClosing,
                      let pending = state.pendingSelectedContentTabClose,
                      pending.operationID == operationID,
                      pending.currentTabID == tabID,
                      isCorrelatedSelectedContentTabCloseMutation(contentTabAction, for: tabID)
                else { return .none }
                return handleSelectedContentTabCloseMutation(
                    operationID: operationID,
                    tabID: tabID,
                    action: contentTabAction,
                    state: &state,
                )

            case let .contentTabs(contentTabAction)
                where state.pendingSelectedContentTabPinMutation != nil
                && isDirectCloseMutation(contentTabAction):
                return .none

            case let .contentTabs(contentTabAction)
                where state.pendingSelectedContentTabClose != nil
                && !isSelectionAllowedDuringBatchClose(contentTabAction):
                return .none

            case let .reserveExternalContentTabs(reservations):
                guard state.pendingSelectedContentTabClose == nil,
                      let activeReservation = reservations.last,
                      state.reserveExternalContentTabs(reservations)
                else { return .none }
                return .send(.contentTabs(.setCurrent(activeReservation.id)))

            case let .activateExternalContentTabUndoScopes(tabIDs):
                guard Set(tabIDs).count == tabIDs.count,
                      tabIDs.allSatisfy({ state.contentTabs.tabs[id: $0] != nil })
                else { return .none }
                for tabID in tabIDs {
                    _ = activateUndoManagerScopeEffect(tabID: tabID, state: state)
                }
                return .none

            case .resyncActiveCollectionNavigation:
                guard let activeTabID = state.contentTabs.activeTabID,
                      case .collectionFile = state.contentTabs.tabs[id: activeTabID]?.anchor
                else { return .none }
                return resyncContentNavigationEffect(state: state)

            case let .sidebar(.delegate(.selectContentTab(tabID))):
                guard state.pendingSelectedContentTabClose == nil,
                      state.contentTabs.tabs[id: tabID] != nil
                else { return .none }
                return .merge(
                    .concatenate(
                        .send(.contentTabs(.setCurrent(tabID))),
                        .send(.contentTabs(.collapseSelectionToActive)),
                    ),
                    brokenPinnedTabFeedbackEffect(tabID: tabID, state: state),
                )

            case let .sidebar(.delegate(.closeContentTab(tabID))):
                guard state.contentTabRowInteractionSurface.isCloseEnabled else { return .none }
                return .send(.closeContentTabRequested(tabID))

            case .sidebar(.delegate(.closeSelectedContentTabs)):
                guard state.contentTabRowInteractionSurface.isCloseEnabled else { return .none }
                return .send(.request(.closeSelectedContentTabs))

            case let .sidebar(.delegate(.pinContentTab(tabID))):
                guard state.pendingSelectedContentTabClose == nil,
                      state.pendingSelectedContentTabPinMutation == nil,
                      state.pendingContentTabClose == nil,
                      state.pendingContentTabTeardown == nil
                else { return .none }
                guard state.canPinContentTab(tabID) else {
                    return cannotPinCollectionFeedbackEffect()
                }
                return .send(.contentTabs(.pin(tabID)))

            case let .sidebar(.delegate(.unpinContentTab(tabID))):
                guard state.pendingSelectedContentTabPinMutation == nil,
                      state.contentTabRowInteractionSurface.isCloseEnabled
                else { return .none }
                return .send(.contentTabs(.unpin(tabID)))

            case let .sidebar(.delegate(.setSelectedContentTabsPinned(target))):
                return .send(.requestSelectedContentTabPinMutation(target: target))

            case let .sidebar(.delegate(.contentTabDomainTransitionRequested(request))):
                return .send(.requestContentTabDomainTransition(request))

            case .sidebar(.delegate(.openContentTab)):
                guard state.contentTabMoveParticipantRequestID == nil,
                      state.pendingSelectedContentTabClose == nil,
                      state.contentTabs.tabs.count < ContentTabConstants.maxTabs
                else { return .none }
                return .send(.contentTabs(.open(.homeDefault)))

            case let .sidebar(.delegate(.duplicateContentTab(sourceID))):
                guard state.pendingSelectedContentTabClose == nil else { return .none }
                return .send(.request(.duplicateContentTab(sourceID)))

            case let .tabContent(tabID, .delegate(.closeWindow)):
                guard tabID == state.contentTabs.activeTabID else { return .none }
                return .send(.delegate(.closeWindow))

            case .sidebar(.delegate(.duplicateSelectedContentTabs)):
                guard state.pendingSelectedContentTabClose == nil else { return .none }
                return .send(.request(.duplicateSelectedContentTabs))

            case let .sidebar(.delegate(.toggleContentTabSelection(id))):
                return .send(.contentTabs(.toggleSelection(id)))

            case let .sidebar(.delegate(.selectContentTabRange(to: id))):
                return .send(.contentTabs(.selectRange(
                    to: id,
                    orderedIDs: state.contentTabSelectionOrderedIDs,
                )))

            case .sidebar(.delegate(.collapseContentTabSelectionToActive)):
                return .send(.contentTabs(.collapseSelectionToActive))

            case .sidebar(.delegate(.dismissTopNavigationPresentation)):
                state.sidebar.topNavigationArrangementPresentation = nil
                return .none

            case let .sidebar(.delegate(.fileManagerTopNavigationReorderRequested(sourceID, anchorID, placement))):
                guard state.pendingSelectedContentTabClose == nil,
                      state.pendingSelectedContentTabPinMutation == nil
                else { return .none }
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
                let destination: FileManagerTopNavigationMoveDestination = placement == .before
                    ? .before(anchorID)
                    : .after(anchorID)
                return .send(.topNavigationMoveRequested(source: sourceID, destination: destination))

            case .content(.delegate(.requestDuplicate)):
                let command: Action.WindowCommand = state.contentTabs.orderedValidSelectedTabIDs.count > 1
                    ? .duplicateSelectedContentTabs
                    : .duplicate
                return .send(.request(command))

            case .content(.delegate(.closeWindow)):
                return .send(.delegate(.closeWindow))

            case let .contentTabs(.setCurrent(targetID)):
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

            case .contentTabs(.open):
                guard state.contentTabMoveParticipantRequestID == nil else { return .none }
                if keepPendingContentTabCloseFocusedAfterOpen(state: &state) {
                    return .none
                }
                let openedTabID = state.activeTabContentStateMissing
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

            case let .contentTabs(.requestClose(tabID)):
                guard state.contentTabMoveParticipantRequestID == nil,
                      !state.contentTabs.pendingPinnedRecordIDs.contains(tabID)
                else { return .none }
                guard let tab = state.contentTabs.tabs[id: tabID] else { return .none }
                if tab.isPinned {
                    return .send(.contentTabs(.close(tabID)))
                }
                return prepareContentTabTeardown(tabID: tabID, state: &state)

            case let .contentTabs(.close(tabID)):
                guard state.contentTabMoveParticipantRequestID == nil,
                      state.contentTabs.tabs[id: tabID] == nil
                else { return .none }
                return finalizeContentTabClose(tabID: tabID, state: &state)

            case let .contentTabs(.commitClose(tabID)):
                guard state.contentTabMoveParticipantRequestID == nil,
                      !state.contentTabs.pendingPinnedRecordIDs.contains(tabID)
                else { return .none }
                return finalizeContentTabClose(tabID: tabID, state: &state)

            case .contentTabs(.restore):
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

            case let .applyPinnedContentTabs(contentTabs),
                 let .applyAuthoritativePinnedContentTabs(contentTabs):
                return applyPinnedContentTabs(
                    contentTabs,
                    mode: pinnedContentTabsApplicationMode(for: action),
                    state: &state,
                )

            case .contentTabs(.duplicateSelected):
                // Pre-scope reducer가 captured identity를 internal action으로 전달한 뒤 owner handoff를 수행한다.
                return .none

            case let .internal(.duplicateSelectedContentTabsReduced(requests, preexistingTabIDs)):
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
                let preOperationActiveID = state.contentTabs.previousActiveTabID
                let windowContentSnapshot = state.content
                let ownerSnapshots: [BatchDuplicateOwnerSnapshot] = createdRequests.compactMap { request in
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

            case .contentTabs(.duplicate):
                // Pre-scope reducer가 기존 identity를 캡처한 internal action에서 post-reduce 처리를 수행한다.
                return .none

            case let .internal(.duplicateContentTabReduced(
                sourceID,
                duplicateID,
                duplicateIDWasPreexisting,
            )):
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

                // Pinned source는 active를 유지하므로 duplicate cache만 source snapshot으로 초기화한다.
                guard state.contentTabs.activeTabID == duplicateID else {
                    state.tabContentStates[duplicateID] = duplicatedContentState
                    syncDashboardProjections(state: &state)
                    return .none
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
                    .concatenate(
                        handoffCleanupEffect,
                        duplicatedAiChatRestoreEffect,
                        handoffEffect,
                    ),
                    closeInspectorForActiveAiChatEffect(state: state),
                )

            case .contentTabs(.reorder):
                state.syncContentTabSidebarItems()
                return .none

            // MARK: - CTM-001-select_content_tabs

            // Child selection mutation은 보존하고 unrelated Window projection/cleanup은 실행하지 않는다.
            case .contentTabs(.toggleSelection),
                 .contentTabs(.selectRange),
                 .contentTabs(.collapseSelectionToActive):
                return .none

            case .contentTabs:
                cleanPendingDirectoryReloadTabIDs(state: &state)
                syncDashboardProjections(state: &state)
                return .none

            case let .content(.entryViewLayout(.entryOperations(.outcome(.entriesMutated(impact))))):
                return handleEntriesMutated(impact, state: &state)

            case let .tabContent(
                tabID,
                .entryViewLayout(.entryOperations(.outcome(.entriesMutated(impact)))),
            ):
                guard fileManagerContentState(for: tabID, state: state) != nil else { return .none }
                return handleEntriesMutated(impact, state: &state)

            case let .content(
                .entryViewLayout(.entryOperations(.outcome(.undoManagerAvailabilityChanged(availability)))),
            ):
                state.undoManagerAvailability = availability
                return .none

            case let .tabContent(
                tabID,
                .entryViewLayout(.entryOperations(.outcome(.undoManagerAvailabilityChanged(availability)))),
            ):
                guard fileManagerContentState(for: tabID, state: state) != nil else { return .none }
                state.undoManagerAvailability = availability
                return .none

            case let .content(
                .entryViewLayout(.entryOperations(.outcome(.entryActionReplayFinished(direction, terminal)))),
            ):
                return handleEntryActionReplayTerminal(
                    direction: direction,
                    terminal: terminal,
                    ownerID: state.content.entryViewLayout.entryOperations.undoOwnerID,
                    makeFallbackRequestID: { uuid() },
                    undoManagerClient: undoManagerClient,
                    state: &state,
                )

            case let .tabContent(
                tabID,
                .entryViewLayout(.entryOperations(.outcome(.entryActionReplayFinished(direction, terminal)))),
            ):
                guard let ownerID = fileManagerContentState(for: tabID, state: state)?
                    .entryViewLayout.entryOperations.undoOwnerID
                else {
                    state.undoRedoPhase = .desynchronized
                    state.undoManagerAvailability = .init()
                    return .none
                }
                return handleEntryActionReplayTerminal(
                    direction: direction,
                    terminal: terminal,
                    ownerID: ownerID,
                    makeFallbackRequestID: { uuid() },
                    undoManagerClient: undoManagerClient,
                    state: &state,
                )

            case let .internal(.sidebarEntryDrop(.outcome(.entriesMutated(impact)))):
                return handleEntriesMutated(impact, state: &state)

            case let .internal(.sidebarEntryDrop(.lifecycle(.entryActionCompleted(record))))
                where record.operationKind == .moveToTrash:
                return handleAffectedDirectoryRefresh(
                    paths: parentDirectoryPaths(for: record.targets),
                    state: &state,
                )

            case let .internal(.sidebarEntryDrop(.outcome(.undoManagerAvailabilityChanged(availability)))):
                state.undoManagerAvailability = availability
                return .none

            case let .internal(.sidebarEntryDrop(.outcome(.entryActionReplayFinished(direction, terminal)))):
                return .merge(
                    handleEntryActionReplayTerminal(
                        direction: direction,
                        terminal: terminal,
                        ownerID: state.sidebarEntryDropOperations.undoOwnerID,
                        makeFallbackRequestID: { uuid() },
                        undoManagerClient: undoManagerClient,
                        state: &state,
                    ),
                    handleSidebarEntryActionReplayTerminal(terminal, state: &state),
                )

            case let .internal(.undoManagerOwnerInvalidationFinished(requestID, ownerID, result)):
                guard allowsSelectedContentTabCloseLifecycleMutation(state: state) else { return .none }
                return handleUndoManagerOwnerInvalidationFinished(
                    requestID: requestID,
                    ownerID: ownerID,
                    result: result,
                    makeUndoOwnerID: { uuid() },
                    state: &state,
                )

            case let .internal(.undoManagerEventReceived(event)):
                return routeUndoManagerEvent(event, state: &state)

            case let .internal(.routeContent(tabID, contentAction)):
                return routeContentAction(
                    contentAction,
                    tabID: tabID,
                    makeFallbackRequestID: { uuid() },
                    undoManagerClient: undoManagerClient,
                    state: &state,
                )

            case let .closeContentTabRequested(tabID):
                guard state.pendingSelectedContentTabClose == nil,
                      state.pendingSelectedContentTabPinMutation == nil
                else { return .none }
                return handleCloseContentTabRequested(tabID: tabID, state: &state)

            case let .contentTabCloseAlertResponse(choice):
                guard state.pendingSelectedContentTabClose == nil else { return .none }
                return handleContentTabCloseAlertResponse(choice: choice, state: &state)

            case let .selectedContentTabCloseAlertResponse(operationID, tabID, choice):
                guard isCurrentSelectedContentTabClose(
                    operationID: operationID,
                    tabID: tabID,
                    state: state,
                ) else { return .none }
                return handleContentTabCloseAlertResponse(choice: choice, state: &state)

            case let .tabContent(tabID, .collection(.saveCompleted(.success))):
                guard state.pendingSelectedContentTabClose == nil,
                      state.pendingContentTabClose?.tabID == tabID,
                      state.contentTabs.activeTabID == tabID
                else { return .none }
                return .none

            case let .tabContent(tabID, .composer(.internal(.syncCollectionState))):
                guard state.pendingSelectedContentTabClose == nil,
                      state.pendingContentTabClose?.tabID == tabID,
                      state.contentTabs.activeTabID == tabID
                else { return .none }
                state.pendingContentTabClose?.didReceiveWriteBackComposerSync = true
                return finalizePendingContentTabCloseIfWriteBackEffectsCompleted(state: &state)

            case let .performBatchCloseContentAction(
                operationID,
                tabID,
                .collection(.saveCompleted(.success)),
            ):
                guard isCurrentSelectedContentTabClose(
                    operationID: operationID,
                    tabID: tabID,
                    state: state,
                ) else { return .none }
                return .none

            case let .performBatchCloseContentAction(
                operationID,
                tabID,
                .composer(.internal(.syncCollectionState)),
            ):
                guard isCurrentSelectedContentTabClose(
                    operationID: operationID,
                    tabID: tabID,
                    state: state,
                ) else { return .none }
                state.pendingContentTabClose?.didReceiveWriteBackComposerSync = true
                return finalizePendingContentTabCloseIfWriteBackEffectsCompleted(state: &state)

            case let .navigation(.internal(.setNavigationState(navigationState))):
                let pendingCloseEffect: Effect<Action>
                if let pendingTabID = state.pendingContentTabClose?.tabID,
                   state.contentTabs.activeTabID == pendingTabID
                {
                    state.pendingContentTabClose?.didReceiveWriteBackNavigationState = true
                    pendingCloseEffect = finalizePendingContentTabCloseIfWriteBackEffectsCompleted(state: &state)
                } else {
                    pendingCloseEffect = .none
                }

                let pinnedCollectionFanOutEffect: Effect<Action> = if case let .collection(collectionNavigation) =
                    navigationState,
                    case .file = collectionNavigation.kind
                {
                    syncPinnedContentTabRuntimeNavigationEffect(
                        navigationState,
                        state: state,
                        computerName: fileManagerClient.displayName("/"),
                    )
                } else {
                    .none
                }
                return .merge(pendingCloseEffect, pinnedCollectionFanOutEffect)

            case let .performBatchCloseNavigationAction(
                operationID,
                tabID,
                .internal(.setNavigationState),
            ):
                guard isCurrentSelectedContentTabClose(
                    operationID: operationID,
                    tabID: tabID,
                    state: state,
                ) else { return .none }
                state.pendingContentTabClose?.didReceiveWriteBackNavigationState = true
                return finalizePendingContentTabCloseIfWriteBackEffectsCompleted(state: &state)

            // Delete/rename 결과는 동일 session의 모든 tab/background owner에 적용되는 session-global event다.
            case let .tabContent(tabID, .aiChat(.deleteSessionTapped(sessionID))):
                guard fileManagerContentState(for: tabID, state: state) != nil else { return .none }
                return cancelAndRemoveBackgroundAiChatOwners(sessionID: sessionID, state: &state)

            case let .inspector(.aiChat(.deleteSessionTapped(sessionID))):
                return cancelAndRemoveBackgroundAiChatOwners(sessionID: sessionID, state: &state)

            case let .tabContent(tabID, .aiChat(.sessionDeleteSucceeded(sessionID))):
                guard fileManagerContentState(for: tabID, state: state) != nil else { return .none }
                propagateAiChatSessionDeleteSucceeded(sessionID: sessionID, state: &state)
                return .none

            case let .inspector(.aiChat(.sessionDeleteSucceeded(sessionID))):
                propagateAiChatSessionDeleteSucceeded(sessionID: sessionID, state: &state)
                return .none

            case let .tabContent(tabID, .aiChat(.sessionDeleteFailed(sessionID, _))):
                guard fileManagerContentState(for: tabID, state: state) != nil else { return .none }
                state.removeBackgroundAiChatState(sessionID: sessionID)
                state.removeBackgroundInspectorAiChatState(sessionID: sessionID)
                return .none

            case let .inspector(.aiChat(.sessionDeleteFailed(sessionID, _))):
                state.removeBackgroundAiChatState(sessionID: sessionID)
                state.removeBackgroundInspectorAiChatState(sessionID: sessionID)
                return .none

            case let .tabContent(tabID, .aiChat(.sessionRenameSucceeded(summary, customTitle))):
                guard fileManagerContentState(for: tabID, state: state) != nil else { return .none }
                refreshAiChatCustomTitle(summary: summary, customTitle: customTitle, state: &state)
                state.updateAiChatTabTitle(sessionID: summary.sessionID, title: summary.title)
                return .none

            case let .inspector(.aiChat(.sessionRenameSucceeded(summary, customTitle))):
                refreshAiChatCustomTitle(summary: summary, customTitle: customTitle, state: &state)
                state.updateAiChatTabTitle(sessionID: summary.sessionID, title: summary.title)
                return .none

            case let .content(.aiChat(aiChatAction)):
                guard let activeTabID = state.contentTabs.activeTabID else { return .none }
                return routeOriginAiChatAction(
                    tabID: activeTabID,
                    aiChatAction: aiChatAction,
                    originContent: state.content,
                    state: &state,
                )

            case let .tabContent(tabID, .aiChat(aiChatAction)):
                guard let originContent = fileManagerContentState(for: tabID, state: state) else { return .none }
                return routeOriginAiChatAction(
                    tabID: tabID,
                    aiChatAction: aiChatAction,
                    originContent: originContent,
                    state: &state,
                )

            case let .backgroundAiChat(aiChatAction):
                let snapshotSessionID = sessionSnapshotSavedSummary(from: aiChatAction)?.sessionID
                let effect = routeBackgroundAiChatAction(aiChatAction, state: &state)
                if let snapshotSessionID {
                    state.refreshAiChatTabTitleFromCanonicalSummary(sessionID: snapshotSessionID)
                }
                return effect

            case let .backgroundAiChatSnapshotPersisted(snapshot):
                handleBackgroundAiChatSnapshotPersisted(snapshot, state: &state)
                return .none

            case let .inspector(.aiChat(aiChatAction)):
                let snapshotSessionID = sessionSnapshotSavedSummary(from: aiChatAction)?.sessionID
                let effect = routeInactiveInspectorAiChatAction(aiChatAction, state: &state)
                refreshAiChatFollowUpFromBackgroundIfNeeded(
                    aiChatAction,
                    backgroundAiChat: state.inspector.aiChat,
                    state: &state,
                    skipsActiveInspector: true,
                )
                if let snapshotSessionID {
                    state.refreshAiChatTabTitleFromCanonicalSummary(sessionID: snapshotSessionID)
                }
                return effect

            case let .backgroundInspectorAiChat(aiChatAction):
                let snapshotSessionID = sessionSnapshotSavedSummary(from: aiChatAction)?.sessionID
                let effect = routeInactiveInspectorAiChatAction(aiChatAction, state: &state)
                if let snapshotSessionID {
                    state.refreshAiChatTabTitleFromCanonicalSummary(sessionID: snapshotSessionID)
                }
                return effect

            case let .backgroundInspectorAiChatSnapshotPersisted(snapshot):
                handleBackgroundInspectorAiChatSnapshotPersisted(snapshot, state: &state)
                return .none

            case let .tabContent(tabID, .collection(.saveCompleted(.failure))):
                guard state.pendingSelectedContentTabClose == nil,
                      state.pendingContentTabClose?.tabID == tabID,
                      state.contentTabs.activeTabID == tabID
                else { return .none }
                state.pendingContentTabClose?.didReceiveSaveCompletedFailure = true
                return finalizePendingContentTabCloseFailureIfReady(state: &state)

            case let .tabContent(tabID, .collection(.savePanelResponse(nil))):
                guard state.pendingSelectedContentTabClose == nil,
                      state.pendingContentTabClose?.tabID == tabID,
                      state.contentTabs.activeTabID == tabID
                else { return .none }
                return finishPendingContentTabCloseWithoutClosing(outcome: .cancelled, state: &state)

            case let .tabContent(tabID, .collection(.writeBackFailed)):
                guard state.pendingSelectedContentTabClose == nil,
                      state.pendingContentTabClose?.tabID == tabID,
                      state.contentTabs.activeTabID == tabID
                else { return .none }
                state.pendingContentTabClose?.didReceiveWriteBackFailure = true
                return finalizePendingContentTabCloseFailureIfReady(state: &state)

            case let .tabContent(tabID, .collection(.delegate(.saveFeedback(feedback)))):
                guard state.pendingSelectedContentTabClose == nil,
                      state.pendingContentTabClose?.tabID == tabID,
                      state.contentTabs.activeTabID == tabID
                else { return .none }
                recordPendingContentTabCloseSaveFeedback(feedback, state: &state)
                return finalizePendingContentTabCloseFailureIfReady(state: &state)

            case let .performBatchCloseContentAction(
                operationID,
                tabID,
                .collection(.saveCompleted(.failure)),
            ):
                guard isCurrentSelectedContentTabClose(
                    operationID: operationID,
                    tabID: tabID,
                    state: state,
                ) else { return .none }
                state.pendingContentTabClose?.didReceiveSaveCompletedFailure = true
                return finalizePendingContentTabCloseFailureIfReady(state: &state)

            case let .performBatchCloseContentAction(
                operationID,
                tabID,
                .collection(.savePanelResponse(nil)),
            ):
                guard isCurrentSelectedContentTabClose(
                    operationID: operationID,
                    tabID: tabID,
                    state: state,
                ) else { return .none }
                return finishPendingContentTabCloseWithoutClosing(outcome: .cancelled, state: &state)

            case let .performBatchCloseContentAction(
                operationID,
                tabID,
                .collection(.writeBackFailed),
            ):
                guard isCurrentSelectedContentTabClose(
                    operationID: operationID,
                    tabID: tabID,
                    state: state,
                ) else { return .none }
                state.pendingContentTabClose?.didReceiveWriteBackFailure = true
                return finalizePendingContentTabCloseFailureIfReady(state: &state)

            case let .performBatchCloseContentAction(
                operationID,
                tabID,
                .collection(.delegate(.saveFeedback(feedback))),
            ):
                guard isCurrentSelectedContentTabClose(
                    operationID: operationID,
                    tabID: tabID,
                    state: state,
                ) else { return .none }
                recordPendingContentTabCloseSaveFeedback(feedback, state: &state)
                return finalizePendingContentTabCloseFailureIfReady(state: &state)

            default:
                return .none
            }
        }
    }
}
