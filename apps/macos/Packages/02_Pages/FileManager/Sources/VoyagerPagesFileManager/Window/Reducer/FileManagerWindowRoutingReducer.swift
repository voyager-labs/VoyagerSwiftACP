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

struct SelectedContentTabCloseOperationCancelID: Hashable {
    let operationID: UUID
}

@Reducer
struct FileManagerWindowRoutingReducer {
    @Dependency(\.collectionAlertClient)
    var collectionAlertClient
    @Dependency(\.fileManagerClient)
    var fileManagerClient
    @Dependency(\.fileManagerLocationsClient)
    var fileManagerLocationsClient
    @Dependency(\.entryLoadingClient)
    var entryLoadingClient
    @Dependency(\.aiConnectionsFileClient)
    var aiConnectionsFileClient
    @Dependency(\.undoManagerClient)
    var undoManagerClient
    @Dependency(\.uuid)
    var uuid

    typealias State = FileManagerWindowState
    typealias Action = FileManagerWindowAction

    private func cannotPinCollectionFeedbackEffect() -> Effect<Action> {
        let collectionAlertClient = collectionAlertClient
        return .run { _ in
            await collectionAlertClient.showCollectionOpenErrorAlert(
                "Cannot Pin Collection",
                "Save the collection before pinning it as a tab.",
            )
        }
    }

    private func brokenPinnedTabFeedbackEffect(tabID: ContentTabID, state: State) -> Effect<Action> {
        guard let tab = state.contentTabs.tabs[id: tabID], tab.isPinned else { return .none }
        guard isBrokenPinnedAnchor(tab.anchor) else { return .none }

        let collectionAlertClient = collectionAlertClient
        return .run { _ in
            await collectionAlertClient.showCollectionOpenErrorAlert(
                "Pinned Location Unavailable",
                "The pinned item no longer exists. Navigate to a valid location to update this pinned tab.",
            )
        }
    }

    private func isBrokenPinnedAnchor(_ anchor: ContentTabPageAnchor) -> Bool {
        switch anchor {
        case let .directory(path):
            var isDirectory = ObjCBool(false)
            return !fileManagerClient.fileExistsWithIsDirectory(path, &isDirectory) || !isDirectory.boolValue

        case let .collectionFile(url):
            return !fileManagerClient.fileExistsWithIsDirectory(url.path, nil)

        case .homeDefault,
             .virtualCollection,
             .aiChat:
            return false
        }
    }

    private func syncDashboardProjections(state: inout State) {
        state.syncContentTabSidebarItems()
        state.syncHomeLocationItems()
        state.syncHomeFavoriteItems()
    }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
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
                      contentTabAction.isCorrelatedSelectedContentTabCloseMutation(for: tabID)
                else { return .none }
                return handleSelectedContentTabCloseMutation(
                    operationID: operationID,
                    tabID: tabID,
                    action: contentTabAction,
                    state: &state,
                )

            case let .contentTabs(contentTabAction)
                where state.pendingSelectedContentTabClose != nil
                && !contentTabAction.isSelectionAllowedDuringBatchClose:
                return .none

            case let .reserveExternalContentTabs(reservations):
                guard state.pendingSelectedContentTabClose == nil,
                      let activeReservation = reservations.last,
                      state.reserveExternalContentTabs(reservations)
                else { return .none }
                return .send(.contentTabs(.setCurrent(activeReservation.id)))

            case .resyncActiveCollectionNavigation:
                guard let activeTabID = state.contentTabs.activeTabID,
                      case .collectionFile = state.contentTabs.tabs[id: activeTabID]?.anchor
                else { return .none }
                return resyncContentNavigationEffect(state: state)

            case let .sidebar(.delegate(.selectContentTab(tabID))):
                guard state.pendingSelectedContentTabClose == nil else { return .none }
                return .merge(
                    .send(.contentTabs(.setCurrent(tabID))),
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
                      state.pendingContentTabClose == nil,
                      state.pendingContentTabTeardown == nil
                else { return .none }
                guard state.canPinContentTab(tabID) else {
                    return cannotPinCollectionFeedbackEffect()
                }
                return .send(.contentTabs(.pin(tabID)))

            case let .sidebar(.delegate(.unpinContentTab(tabID))):
                guard state.contentTabRowInteractionSurface.isCloseEnabled else { return .none }
                return .send(.contentTabs(.unpin(tabID)))

            case .sidebar(.delegate(.openContentTab)):
                guard state.pendingSelectedContentTabClose == nil,
                      state.contentTabs.tabs.count < ContentTabConstants.maxTabs
                else { return .none }
                return .send(.contentTabs(.open(.homeDefault)))

            case let .sidebar(.delegate(.duplicateContentTab(sourceID))):
                guard state.pendingSelectedContentTabClose == nil else { return .none }
                return .send(.request(.duplicateContentTab(sourceID)))

            case .sidebar(.delegate(.duplicateSelectedContentTabs)):
                guard state.pendingSelectedContentTabClose == nil else { return .none }
                return .send(.request(.duplicateSelectedContentTabs))

            case let .sidebar(.delegate(.toggleContentTabSelection(id))):
                return .send(.contentTabs(.toggleSelection(id)))

            case let .sidebar(.delegate(.selectContentTabRange(to: id))):
                return .send(.contentTabs(.selectRange(to: id)))

            case .sidebar(.delegate(.collapseContentTabSelectionToActive)):
                return .send(.contentTabs(.collapseSelectionToActive))

            case let .sidebar(.delegate(.contentTabReorderRequested(sourceID, targetID, placement))):
                guard state.pendingSelectedContentTabClose == nil else { return .none }
                return .send(.contentTabs(.reorder(
                    sourceID: sourceID,
                    targetID: targetID,
                    placement: placement,
                )))

            case .content(.delegate(.requestDuplicate)):
                let command: Action.WindowCommand = state.contentTabs.selectedTabIDs.count > 1
                    ? .duplicateSelectedContentTabs
                    : .duplicate
                return .send(.request(command))

            case .content(.delegate(.closeWindow)):
                return .send(.delegate(.closeWindow))

            case .contentTabs(.setCurrent):
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
                            state: state,
                            aiConnectionsFileClient: aiConnectionsFileClient,
                            skipAiChatCancel: true,
                        ),
                    ),
                    closeInspectorForActiveAiChatEffect(state: state),
                )

            case .contentTabs(.open):
                if keepPendingContentTabCloseFocusedAfterOpen(state: &state) {
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
                        state: state,
                        aiConnectionsFileClient: aiConnectionsFileClient,
                        skipAiChatCancel: true,
                    ),
                    closeInspectorForActiveAiChatEffect(state: state),
                )

            case let .contentTabs(.requestClose(tabID)):
                guard let tab = state.contentTabs.tabs[id: tabID] else { return .none }
                if tab.isPinned {
                    return .send(.contentTabs(.close(tabID)))
                }
                return prepareContentTabTeardown(tabID: tabID, state: &state)

            case let .contentTabs(.close(tabID)):
                return finalizeContentTabClose(tabID: tabID, state: &state)

            case let .contentTabs(.commitClose(tabID)):
                return finalizeContentTabClose(tabID: tabID, state: &state)

            case .contentTabs(.restore):
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
                        state: state,
                        aiConnectionsFileClient: aiConnectionsFileClient,
                        skipAiChatCancel: true,
                    ),
                    closeInspectorForActiveAiChatEffect(state: state),
                )

            case let .applyPinnedContentTabs(contentTabs):
                guard state.pendingSelectedContentTabClose == nil else {
                    state.deferredPinnedContentTabs = contentTabs
                    return .none
                }
                let activeTabIDBeforeSync = state.contentTabs.activeTabID
                let activeAnchorBeforeSync = activeTabIDBeforeSync.flatMap { state.contentTabs.tabs[id: $0]?.anchor }
                state.applyPinnedContentTabs(contentTabs)
                cleanPendingDirectoryReloadTabIDs(state: &state)
                syncDashboardProjections(state: &state)
                let activeAnchorAfterSync = state.contentTabs.activeTabID
                    .flatMap { state.contentTabs.tabs[id: $0]?.anchor }
                let shouldResyncContentNavigation = state.contentTabs.activeTabID == activeTabIDBeforeSync
                    && activeAnchorAfterSync != activeAnchorBeforeSync
                    && activeAnchorAfterSync?.isCollectionFileAnchor == true
                return .merge(
                    activeTabHandoffEffect(
                        shouldResyncContentNavigation,
                        state: state,
                        aiConnectionsFileClient: aiConnectionsFileClient,
                    ),
                    closeInspectorForActiveAiChatEffect(state: state),
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
                            state: state,
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
                    state: state,
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

            case let .content(
                .entryViewLayout(.entryOperations(.outcome(.undoManagerAvailabilityChanged(availability)))),
            ):
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
                guard state.pendingSelectedContentTabClose == nil else { return .none }
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

            case .content(.collection(.saveCompleted(.success))):
                guard state.pendingSelectedContentTabClose == nil,
                      state.pendingContentTabClose != nil
                else { return .none }
                return .none

            case .content(.composer(.internal(.syncCollectionState))):
                guard state.pendingSelectedContentTabClose == nil,
                      state.pendingContentTabClose != nil
                else { return .none }
                state.pendingContentTabClose?.didReceiveWriteBackComposerSync = true
                return finalizePendingContentTabCloseIfWriteBackEffectsCompleted(state: &state)

            case .navigation(.internal(.setNavigationState)):
                guard state.pendingSelectedContentTabClose == nil,
                      state.pendingContentTabClose != nil
                else { return .none }
                state.pendingContentTabClose?.didReceiveWriteBackNavigationState = true
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

            case let .content(.aiChat(.deleteSessionTapped(sessionID))),
                 let .inspector(.aiChat(.deleteSessionTapped(sessionID))):
                return cancelAndRemoveBackgroundAiChatOwners(sessionID: sessionID, state: &state)

            case let .content(.aiChat(.sessionDeleteSucceeded(sessionID))),
                 let .inspector(.aiChat(.sessionDeleteSucceeded(sessionID))):
                propagateAiChatSessionDeleteSucceeded(sessionID: sessionID, state: &state)
                return .none

            case let .content(.aiChat(.sessionDeleteFailed(sessionID, _))),
                 let .inspector(.aiChat(.sessionDeleteFailed(sessionID, _))):
                state.removeBackgroundAiChatState(sessionID: sessionID)
                state.removeBackgroundInspectorAiChatState(sessionID: sessionID)
                return .none

            case let .content(.aiChat(.sessionRenameSucceeded(summary, customTitle))),
                 let .inspector(.aiChat(.sessionRenameSucceeded(summary, customTitle))):
                refreshAiChatCustomTitle(
                    summary: summary,
                    customTitle: customTitle,
                    state: &state,
                )
                state.updateAiChatTabTitle(sessionID: summary.sessionID, title: summary.title)
                return .none

            case let .content(.aiChat(aiChatAction)):
                if shouldRefreshActiveAiChatTabTitleFromSessionList(aiChatAction) {
                    state.refreshActiveAiChatTabTitleFromSessionList()
                    state.syncContentTabSidebarItems()
                } else if case .sessionListLoaded = aiChatAction {
                    state.refreshActiveAiChatTabTitleFromSessionList(onlyIfUsingFallback: true)
                    state.syncContentTabSidebarItems()
                }
                let snapshotSessionID = sessionSnapshotSavedSummary(from: aiChatAction)?.sessionID
                let effect = routeBackgroundAiChatAction(aiChatAction, state: &state)
                refreshAiChatFollowUpFromBackgroundIfNeeded(
                    aiChatAction,
                    backgroundAiChat: state.content.aiChat,
                    state: &state,
                    skipsActiveContent: true,
                )
                if let snapshotSessionID {
                    state.refreshAiChatTabTitleFromCanonicalSummary(sessionID: snapshotSessionID)
                }
                return effect

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

            case .content(.collection(.saveCompleted(.failure))):
                guard state.pendingSelectedContentTabClose == nil,
                      state.pendingContentTabClose != nil
                else { return .none }
                state.pendingContentTabClose?.didReceiveSaveCompletedFailure = true
                return finalizePendingContentTabCloseFailureIfReady(state: &state)

            case .content(.collection(.savePanelResponse(nil))):
                guard state.pendingSelectedContentTabClose == nil else { return .none }
                return finishPendingContentTabCloseWithoutClosing(outcome: .cancelled, state: &state)

            case .content(.collection(.writeBackFailed)):
                guard state.pendingSelectedContentTabClose == nil,
                      state.pendingContentTabClose != nil
                else { return .none }
                state.pendingContentTabClose?.didReceiveWriteBackFailure = true
                return finalizePendingContentTabCloseFailureIfReady(state: &state)

            case let .content(.collection(.delegate(.saveFeedback(feedback)))):
                guard state.pendingSelectedContentTabClose == nil,
                      state.pendingContentTabClose != nil
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

private extension FileManagerWindowRoutingReducer {
    func handleWindowDisappear(state: inout State) -> Effect<Action> {
        let operationID = state.pendingSelectedContentTabClose?.operationID
            ?? state.pendingContentTabClose?.batchOperationID
        if let pendingClose = state.pendingContentTabClose {
            restorePreviousActiveContentIfNeeded(pendingClose, state: &state)
            normalizeCloseTriggeredSaveState(pendingClose, state: &state)
        }
        if let teardown = state.pendingContentTabTeardown,
           case let .tearingDownTab(requestID, ownerID) = state.undoRedoPhase,
           requestID == teardown.requestID,
           ownerID == teardown.ownerID
        {
            state.undoRedoPhase = .desynchronized
            state.undoManagerAvailability = .init()
        }
        state.isClosing = true
        state.pendingSelectedContentTabClose = nil
        state.pendingContentTabClose = nil
        state.deferredPinnedContentTabs = nil
        state.pendingContentTabTeardown = nil
        guard let operationID else { return .none }
        return .cancel(id: SelectedContentTabCloseOperationCancelID(operationID: operationID))
    }

    func normalizeCloseTriggeredSaveState(
        _ pendingClose: PendingContentTabClose,
        state: inout State,
    ) {
        if pendingClose.targetContent != nil,
           var targetContent = state.tabContentStates[pendingClose.tabID]
        {
            normalizeCloseTriggeredCollectionState(&targetContent.collection)
            state.tabContentStates[pendingClose.tabID] = targetContent
        } else {
            normalizeCloseTriggeredCollectionState(&state.content.collection)
            state.syncActiveTabContentState()
        }
    }

    func normalizeCloseTriggeredCollectionState(_ collection: inout CollectionState) {
        collection.isSaving = false
        collection.pendingSave = nil
        collection.pendingSaveContext = nil
        if collection.collectionSession.phase.isInflightRefresh
            || collection.collectionSession.phase.isInflightWriteBack
        {
            collection.collectionSession.failRefreshOrWriteBack()
        }
    }
}

// MARK: - Close Content Tab Request

private func routeContentAction(
    _ action: FileManagerContentAction,
    tabID: ContentTabID,
    makeFallbackRequestID: () -> UUID,
    undoManagerClient: UndoManagerClient,
    state: inout FileManagerWindowState,
) -> Effect<FileManagerWindowAction> {
    let ownerID = if tabID == state.contentTabs.activeTabID {
        state.content.entryViewLayout.entryOperations.undoOwnerID
    } else {
        state.tabContentStates[tabID]?.entryViewLayout.entryOperations.undoOwnerID
    }
    let windowEffect: Effect<FileManagerWindowAction>
    switch action {
    case let .entryViewLayout(.entryOperations(.outcome(.entriesMutated(impact)))):
        windowEffect = handleEntriesMutated(impact, state: &state)
    case let .entryViewLayout(.entryOperations(.outcome(.undoManagerAvailabilityChanged(availability)))):
        state.undoManagerAvailability = availability
        windowEffect = .none
    case let .entryViewLayout(.entryOperations(.outcome(.entryActionReplayFinished(direction, terminal)))):
        guard let ownerID else {
            state.undoRedoPhase = .desynchronized
            state.undoManagerAvailability = .init()
            return .none
        }
        windowEffect = handleEntryActionReplayTerminal(
            direction: direction,
            terminal: terminal,
            ownerID: ownerID,
            makeFallbackRequestID: makeFallbackRequestID,
            undoManagerClient: undoManagerClient,
            state: &state,
        )
    default:
        windowEffect = .none
    }
    guard state.contentTabs.tabs[id: tabID] != nil else { return windowEffect }

    let effect: Effect<FileManagerContentAction>
    if tabID == state.contentTabs.activeTabID {
        effect = FileManagerContentFeature().reduce(into: &state.content, action: action)
        state.syncActiveTabContentState()
    } else {
        guard var content = state.tabContentStates[tabID] else { return .none }
        effect = FileManagerContentFeature().reduce(into: &content, action: action)
        state.tabContentStates[tabID] = content
    }

    let routedEffect = effect.map { FileManagerWindowAction.internal(.routeContent(tabID: tabID, action: $0)) }
    return .merge(routedEffect, windowEffect)
}

private func routeUndoManagerEvent(
    _ event: UndoManagerEvent,
    state: inout FileManagerWindowState,
) -> Effect<FileManagerWindowAction> {
    let requestID: UUID
    let expectedDirection: EntryActionDirection
    switch state.undoRedoPhase {
    case let .invoking(currentRequestID, direction), let .replaying(currentRequestID, direction):
        requestID = currentRequestID
        expectedDirection = direction
    case .idle, .refreshing, .recovering, .tearingDownTab, .desynchronized:
        state.undoRedoPhase = .desynchronized
        state.undoManagerAvailability = .init()
        return .none
    }

    guard expectedDirection == event.direction else {
        state.undoRedoPhase = .desynchronized
        return .none
    }

    let replayAction: EntryOperationsAction = switch event.direction {
    case .undo:
        .undoRedo(.undoEntryAction(event.record))
    case .redo:
        .undoRedo(.redoEntryAction(event.record))
    }
    state.undoRedoPhase = .replaying(requestID: requestID, direction: event.direction)

    if state.sidebarEntryDropOperations.undoOwnerID == event.ownerID {
        return .send(.internal(.sidebarEntryDrop(replayAction)))
    }
    if state.content.entryViewLayout.entryOperations.undoOwnerID == event.ownerID {
        return .send(.content(.entryViewLayout(.entryOperations(replayAction))))
    }

    let activeTabID = state.contentTabs.activeTabID
    let matchingTabIDs: [ContentTabID] = state.tabContentStates.compactMap { element in
        let (tabID, contentState) = element
        guard tabID != activeTabID,
              contentState.entryViewLayout.entryOperations.undoOwnerID == event.ownerID
        else { return nil }
        return tabID
    }
    guard matchingTabIDs.count == 1, let tabID = matchingTabIDs.first else {
        state.undoRedoPhase = .desynchronized
        return .none
    }
    return .send(.internal(.routeContent(
        tabID: tabID,
        action: .entryViewLayout(.entryOperations(replayAction)),
    )))
}

func handleEntriesMutated(
    _ impact: EntryOperationsMutationImpact,
    state: inout FileManagerWindowState,
) -> Effect<FileManagerWindowAction> {
    handleAffectedDirectoryRefresh(
        paths: impact.sourceParentPaths + [impact.destinationPath],
        state: &state,
    )
}

private func handleEntryActionReplayTerminal(
    direction: EntryActionDirection,
    terminal: EntryActionReplayTerminal,
    ownerID: UUID,
    makeFallbackRequestID: () -> UUID,
    undoManagerClient: UndoManagerClient,
    state: inout FileManagerWindowState,
) -> Effect<FileManagerWindowAction> {
    let requestID: UUID?
    switch state.undoRedoPhase {
    case let .invoking(currentRequestID, expectedDirection),
         let .replaying(currentRequestID, expectedDirection):
        guard expectedDirection == direction else {
            state.undoRedoPhase = .desynchronized
            state.undoManagerAvailability = .init()
            return .none
        }
        requestID = currentRequestID
    case .idle:
        requestID = nil
    case .refreshing, .recovering, .tearingDownTab, .desynchronized:
        return .none
    }

    switch terminal {
    case .success:
        let refreshRequestID = requestID ?? makeFallbackRequestID()
        state.undoRedoPhase = .refreshing(requestID: refreshRequestID)
        let windowID = state.windowID
        return .run { send in
            let availability = await undoManagerClient.availability(windowID)
            await send(.internal(.undoManagerReplayAvailabilityChanged(
                requestID: refreshRequestID,
                availability: availability,
            )))
        }

    case .failure(reason: .operationFailed, appliedTargets: _):
        guard let requestID, let windowID = state.windowID else {
            state.undoRedoPhase = .desynchronized
            state.undoManagerAvailability = .init()
            return .none
        }
        state.undoRedoPhase = .recovering(
            requestID: requestID,
            direction: direction,
            ownerID: ownerID,
        )
        state.undoManagerAvailability = .init()
        return invalidateUndoOwnerEffect(
            requestID: requestID,
            ownerID: ownerID,
            windowID: windowID,
            undoManagerClient: undoManagerClient,
        )

    case .failure(reason: .ownerRecordMismatch, appliedTargets: _),
         .failure(reason: .ownerBusy, appliedTargets: _):
        state.undoRedoPhase = .desynchronized
        state.undoManagerAvailability = .init()
        return .none
    }
}

private func invalidateUndoOwnerEffect(
    requestID: UUID,
    ownerID: UUID,
    windowID: UUID,
    undoManagerClient: UndoManagerClient,
) -> Effect<FileManagerWindowAction> {
    .run { send in
        let result = await undoManagerClient.invalidateOwner(windowID, ownerID)
        await send(.internal(.undoManagerOwnerInvalidationFinished(
            requestID: requestID,
            ownerID: ownerID,
            result: result,
        )))
    }
}

private func rotateRecoveredUndoOwner(
    ownerID: UUID,
    makeUndoOwnerID: () -> UUID,
    state: inout FileManagerWindowState,
) -> Bool {
    if state.sidebarEntryDropOperations.undoOwnerID == ownerID {
        state.sidebarEntryDropOperations.rotateUndoOwner(to: makeUndoOwnerID())
        return true
    }
    if state.content.entryViewLayout.entryOperations.undoOwnerID == ownerID {
        state.content.entryViewLayout.entryOperations.rotateUndoOwner(to: makeUndoOwnerID())
        state.syncActiveTabContentState()
        return true
    }

    let activeTabID = state.contentTabs.activeTabID
    let matchingTabIDs = state.tabContentStates.compactMap { element -> ContentTabID? in
        let (tabID, contentState) = element
        guard tabID != activeTabID,
              contentState.entryViewLayout.entryOperations.undoOwnerID == ownerID
        else { return nil }
        return tabID
    }
    guard matchingTabIDs.count == 1, let tabID = matchingTabIDs.first else { return false }
    state.tabContentStates[tabID]?.entryViewLayout.entryOperations.rotateUndoOwner(to: makeUndoOwnerID())
    return true
}

private func handleUndoManagerOwnerInvalidationFinished(
    requestID: UUID,
    ownerID: UUID,
    result: UndoManagerInvalidationResult,
    makeUndoOwnerID: () -> UUID,
    state: inout FileManagerWindowState,
) -> Effect<FileManagerWindowAction> {
    switch state.undoRedoPhase {
    case let .recovering(currentRequestID, _, currentOwnerID):
        guard currentRequestID == requestID, currentOwnerID == ownerID else { return .none }
        guard result.succeeded,
              rotateRecoveredUndoOwner(
                  ownerID: ownerID,
                  makeUndoOwnerID: makeUndoOwnerID,
                  state: &state,
              )
        else {
            state.undoRedoPhase = .desynchronized
            state.undoManagerAvailability = .init()
            return .none
        }
        state.undoRedoPhase = .idle
        state.undoManagerAvailability = result.availability
        return .none

    case let .tearingDownTab(currentRequestID, currentOwnerID):
        guard currentRequestID == requestID,
              currentOwnerID == ownerID,
              let pending = state.pendingContentTabTeardown,
              pending.requestID == requestID,
              pending.ownerID == ownerID
        else { return .none }
        state.pendingContentTabTeardown = nil
        guard result.succeeded else {
            state.undoRedoPhase = .desynchronized
            state.undoManagerAvailability = .init()
            if let operationID = state.pendingContentTabClose?.batchOperationID {
                return .send(.selectedContentTabCloseItemCompleted(
                    operationID: operationID,
                    tabID: pending.tabID,
                    outcome: .failed,
                ))
            }
            return .none
        }
        state.undoRedoPhase = .idle
        state.undoManagerAvailability = result.availability
        if let operationID = state.pendingContentTabClose?.batchOperationID {
            return .send(.performSelectedContentTabCloseMutation(
                operationID: operationID,
                tabID: pending.tabID,
                action: .commitClose(pending.tabID),
            ))
        }
        return .send(.contentTabs(.commitClose(pending.tabID)))

    case .idle, .invoking, .replaying, .refreshing, .desynchronized:
        return .none
    }
}

func handleSidebarEntryActionReplayTerminal(
    _ terminal: EntryActionReplayTerminal,
    state: inout FileManagerWindowState,
) -> Effect<FileManagerWindowAction> {
    let targets: [EntryActionRecord.Target]
    switch terminal {
    case let .success(record):
        targets = record.targets
    case let .failure(reason: .operationFailed, appliedTargets: appliedTargets):
        targets = appliedTargets
    case .failure(reason: .ownerRecordMismatch, appliedTargets: _),
         .failure(reason: .ownerBusy, appliedTargets: _):
        return .none
    }

    return handleAffectedDirectoryRefresh(paths: parentDirectoryPaths(for: targets), state: &state)
}

private func parentDirectoryPaths(for targets: [EntryActionRecord.Target]) -> [String] {
    var parentPaths: [String] = []
    for path in targets.flatMap({ [$0.beforePath, $0.afterPath] }).compactMap(\.self) {
        let parentPath = URL(fileURLWithPath: path).deletingLastPathComponent().path
        guard !parentPaths.contains(where: { EntryDropPathPolicy.areEquivalent($0, parentPath) }) else { continue }
        parentPaths.append(parentPath)
    }
    return parentPaths
}

private func handleAffectedDirectoryRefresh(
    paths affectedPaths: [String],
    state: inout FileManagerWindowState,
) -> Effect<FileManagerWindowAction> {
    var activeDirectoryTabID: ContentTabID?

    for tab in state.contentTabs.tabs where tab.page == .directory {
        guard let currentPath = currentDirectoryPath(for: tab, state: state),
              affectedPaths.contains(where: { EntryDropPathPolicy.areEquivalent($0, currentPath) })
        else { continue }

        if tab.id == state.contentTabs.activeTabID {
            activeDirectoryTabID = tab.id
        } else {
            state.pendingDirectoryReloadTabIDs.insert(tab.id)
        }
    }

    guard let activeDirectoryTabID else { return .none }
    return .send(.internal(.routeContent(
        tabID: activeDirectoryTabID,
        action: .internal(.reloadDirectoryListing),
    )))
}

private func currentDirectoryPath(
    for tab: ContentTabItem,
    state: FileManagerWindowState,
) -> String? {
    if tab.id == state.contentTabs.activeTabID {
        guard case let .folder(path) = state.content.navigation.navigationState else { return nil }
        return path
    }
    if let content = state.tabContentStates[tab.id] {
        guard case let .folder(path) = content.navigation.navigationState else { return nil }
        return path
    }
    guard case let .directory(path) = tab.anchor else { return nil }
    return path
}

private func consumePendingDirectoryReloadForActiveTab(state: inout FileManagerWindowState) {
    guard let activeTabID = state.contentTabs.activeTabID,
          state.pendingDirectoryReloadTabIDs.contains(activeTabID),
          state.contentTabs.tabs[id: activeTabID]?.page == .directory,
          case .folder = state.content.navigation.navigationState
    else {
        cleanPendingDirectoryReloadTabIDs(state: &state)
        return
    }
    state.pendingDirectoryReloadTabIDs.remove(activeTabID)
}

private func cleanPendingDirectoryReloadTabIDs(state: inout FileManagerWindowState) {
    let directoryTabIDs = Set(state.contentTabs.tabs.compactMap { tab in
        tab.page == .directory ? tab.id : nil
    })
    state.pendingDirectoryReloadTabIDs.formIntersection(directoryTabIDs)
}

private extension FileManagerWindowRoutingReducer {
    func allowsSelectedContentTabCloseLifecycleMutation(state: State) -> Bool {
        guard !state.isClosing else { return false }
        guard let batch = state.pendingSelectedContentTabClose else { return true }
        guard let pendingClose = state.pendingContentTabClose else { return false }
        return pendingClose.batchOperationID == batch.operationID
            && pendingClose.tabID == batch.currentTabID
    }

    func handleRequestCloseSelectedContentTabs(state: inout State) -> Effect<Action> {
        guard state.canStartSelectedContentTabClose else { return .none }

        let validSelectedIDs = state.contentTabs.orderedValidSelectedTabIDs
        guard validSelectedIDs.count >= 2 else { return .none }

        let activeTabID = state.contentTabs.activeTabID
        var orderedTargetIDs = validSelectedIDs.filter { $0 != activeTabID }
        if let activeTabID, validSelectedIDs.contains(activeTabID) {
            orderedTargetIDs.append(activeTabID)
        }
        let targetIDSet = Set(orderedTargetIDs)
        let preferredFallbackIDs = preferredSelectedContentTabCloseFallbackIDs(
            originalTabIDs: state.contentTabs.selectionOrderedTabIDs,
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
            let deferredPinnedContentTabs = state.deferredPinnedContentTabs
            state.pendingSelectedContentTabClose = nil
            state.deferredPinnedContentTabs = nil
            let cancelEffect = Effect<Action>.cancel(
                id: SelectedContentTabCloseOperationCancelID(operationID: operationID),
            )
            guard let deferredPinnedContentTabs else { return cancelEffect }
            return .concatenate(
                cancelEffect,
                .send(.applyPinnedContentTabs(deferredPinnedContentTabs)),
            )
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
        guard !action.isStalePinnedRecordPersistenceResult(in: state.contentTabs)
            || action.isPinnedRecordSaveNotApplied
        else { return .none }
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

        case let .pinnedRecordSaveSucceeded(successTabID, _) where successTabID == tabID:
            return .send(.selectedContentTabCloseItemCompleted(
                operationID: operationID,
                tabID: tabID,
                outcome: .unpinned,
            ))

        case let .pinnedRecordSaveFailed(failedTabID, _, _, _, _) where failedTabID == tabID:
            return .send(.selectedContentTabCloseItemCompleted(
                operationID: operationID,
                tabID: tabID,
                outcome: .failed,
            ))

        case let .pinnedRecordSaveNotApplied(nonAppliedTabID, _, _, _)
            where nonAppliedTabID == tabID:
            return .send(.selectedContentTabCloseItemCompleted(
                operationID: operationID,
                tabID: tabID,
                outcome: .cancelled,
            ))

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

    func finalizeContentTabClose(
        tabID: ContentTabID,
        state: inout State,
    ) -> Effect<Action> {
        if keepPendingContentTabCloseFocused(state: &state) {
            return .none
        }
        var shouldCloseWindow = false
        let isRemovedTab = state.contentTabs.tabs[id: tabID] == nil
        let shouldRestorePreviousActiveTab = isRemovedTab
            && state.contentTabs.previousActiveTabID == tabID
        let shouldResetLastTabContent = state.contentTabs.previousActiveTabID == tabID
            && state.contentTabs.activeTabID == tabID
        let shouldResyncContentNavigation = shouldRestorePreviousActiveTab || shouldResetLastTabContent
        state.pendingDirectoryReloadTabIDs.remove(tabID)
        let aiChatLifecycleSessionIDs = aiChatLifecycleSessionIDsToPreserve(state.content.aiChat)
        let isAiChatLifecyclePreservingTabClose = shouldResyncContentNavigation
            && !aiChatLifecycleSessionIDs.isEmpty
        if isRemovedTab {
            state.recentlyClosedNavigationRoute = navigationRouteForClosingTab(tabID, state: state)
        }
        let handoffCleanupEffect: Effect<Action>
        if shouldResyncContentNavigation {
            if isAiChatLifecyclePreservingTabClose {
                for aiChatSessionID in aiChatLifecycleSessionIDs {
                    state.addBackgroundAiChatState(sessionID: aiChatSessionID, state: state.content)
                }
                handoffCleanupEffect = prepareContentForActiveTabHandoff(
                    state: &state.content,
                    skipAiChatCleanup: true,
                )
            } else {
                handoffCleanupEffect = prepareContentForActiveTabHandoff(state: &state.content)
            }
        } else {
            handoffCleanupEffect = .none
        }
        if isRemovedTab {
            state.addBackgroundAiChatState(for: tabID)
            state.addBackgroundInspectorAiChatState(for: tabID)
            state.removeContentState(for: tabID)
            state.removeInspectorState(for: tabID)
            if shouldRestorePreviousActiveTab {
                state.restoreContentStateForActiveTab()
                removeBackgroundAiChatOwnersPromotedToActiveContent(state: &state)
                state.restoreInspectorStateForActiveTab()
            }
        } else if shouldResetLastTabContent {
            state.addBackgroundAiChatState(for: tabID)
            state.addBackgroundInspectorAiChatState(for: tabID)
            state.content = contentState(
                for: state.contentTabs.tabs[id: tabID]?.anchor,
                inheritingWindowContextFrom: state.content,
            )
            state.inspector = .init()
            state.syncActiveTabContentState()
            state.syncActiveTabInspectorState()
            shouldCloseWindow = true
        }
        syncDashboardProjections(state: &state)
        syncSidebarSelectionForActiveContentTab(state: &state)
        let handoffEffect: Effect<Action> = .merge(
            handoffCleanupEffect,
            activeTabHandoffEffect(
                shouldResyncContentNavigation,
                state: state,
                aiConnectionsFileClient: aiConnectionsFileClient,
                skipAiChatCancel: true,
            ),
            closeInspectorForActiveAiChatEffect(state: state),
        )
        return shouldCloseWindow
            ? .merge(handoffEffect, .send(.delegate(.closeWindow)))
            : handoffEffect
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

        if targetState.isCollectionMode, targetState.canSaveCollection {
            return beginUnsavedContentTabClose(
                tabID: tabID,
                targetState: targetState,
                isActiveTarget: isActiveTarget,
                batchOperationID: batchOperationID,
                state: &state,
            )
        }

        return routeContentTabCloseMutation(
            tabID: tabID,
            batchOperationID: batchOperationID,
            action: .requestClose(tabID),
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

private struct BatchDuplicateOwnerSnapshot {
    let request: ContentTabDuplicateRequest
    let sourceItem: ContentTabItem
    let duplicateAnchor: ContentTabPageAnchor
    let sourceContent: FileManagerContentFeature.State?
    let sourceAiChatLifecycleSessionIDs: [AiChatSessionID]
    let duplicatedContent: FileManagerContentFeature.State
}

private func createdDuplicateRequests(
    _ requests: [ContentTabDuplicateRequest],
    preexistingTabIDs: Set<ContentTabID>,
    state: FileManagerWindowState,
) -> [ContentTabDuplicateRequest] {
    guard let activeDuplicateID = state.contentTabs.activeTabID,
          requests.contains(where: { $0.duplicateID == activeDuplicateID })
    else { return [] }

    var seenSourceIDs = Set<ContentTabID>()
    var seenDuplicateIDs = Set<ContentTabID>()
    var createdRequests: [ContentTabDuplicateRequest] = []
    for request in requests {
        guard request.sourceID != request.duplicateID,
              !seenSourceIDs.contains(request.sourceID),
              !seenDuplicateIDs.contains(request.duplicateID),
              !preexistingTabIDs.contains(request.duplicateID),
              let sourceItem = state.contentTabs.tabs[id: request.sourceID],
              let duplicateItem = state.contentTabs.tabs[id: request.duplicateID]
        else { continue }
        guard duplicateItem.page == sourceItem.page,
              duplicateItem.anchor == sourceItem.anchor,
              duplicateItem.title == sourceItem.title,
              duplicateItem.iconName == sourceItem.iconName,
              !duplicateItem.isPinned
        else { continue }
        seenSourceIDs.insert(request.sourceID)
        seenDuplicateIDs.insert(request.duplicateID)
        createdRequests.append(request)
    }
    return createdRequests
}

private func duplicateSourceContentState(
    sourceID: ContentTabID,
    duplicateID: ContentTabID,
    state: FileManagerWindowState,
) -> FileManagerContentFeature.State? {
    if state.contentTabs.activeTabID == duplicateID {
        if state.contentTabs.previousActiveTabID == sourceID {
            return state.content
        }
        return state.tabContentStates[sourceID]
    }
    if state.contentTabs.activeTabID == sourceID {
        return state.content
    }
    return state.tabContentStates[sourceID]
}

private func makeDuplicatedContentState(
    _ sourceContentState: FileManagerContentFeature.State?,
    anchor: ContentTabPageAnchor?,
    inheritingWindowContextFrom windowContentState: FileManagerContentFeature.State,
) -> FileManagerContentFeature.State {
    var duplicatedContentState = FileManagerContentFeature.State.initialContent(
        for: anchor,
        inheritingWindowContextFrom: sourceContentState ?? windowContentState,
    )
    guard let sourceContentState else {
        return duplicatedContentState
    }

    duplicatedContentState.navigation.backHistory = sourceContentState.navigation.backHistory
    duplicatedContentState.navigation.forwardHistory = sourceContentState.navigation.forwardHistory
    return duplicatedContentState
}

private func restoreActiveAiChatSessionIfNeededEffect(
    state: FileManagerWindowState,
) -> Effect<FileManagerWindowAction> {
    guard let activeTabID = state.contentTabs.activeTabID,
          case let .aiChat(sessionID) = state.contentTabs.tabs[id: activeTabID]?.anchor,
          let sessionUUID = UUID(uuidString: sessionID),
          state.content.aiChat.sessionID == nil,
          state.content.aiChat.restoreSessionID == nil
    else {
        return .none
    }

    let aiChatSessionID = AiChatSessionID(rawValue: sessionUUID)
    guard !hasBackgroundAiChatLifecycleOwner(sessionID: aiChatSessionID, state: state) else {
        return .none
    }

    return .send(.content(.aiChat(.setup(AiChatSetupState(
        restoreSessionID: aiChatSessionID,
        sessionID: nil,
        mode: .chat,
    )))))
}

private func hasBackgroundAiChatLifecycleOwner(
    sessionID: AiChatSessionID,
    state: FileManagerWindowState,
) -> Bool {
    state.backgroundAiChatStates.values.contains {
        $0.aiChat.hasLifecycleOwner(sessionID: sessionID)
    } || state.backgroundInspectorAiChatStates.values.contains {
        $0.aiChat.hasLifecycleOwner(sessionID: sessionID)
    }
}

private func navigationRouteForClosingTab(
    _ tabID: ContentTabID,
    state: FileManagerWindowState,
) -> ContentPageNavigationRoute? {
    if state.contentTabs.previousActiveTabID == tabID {
        return state.content.navigation.navigationState
    }
    return state.tabContentStates[tabID]?.navigation.navigationState
}

private func prepareContentForActiveTabHandoff(
    state: inout FileManagerContentFeature.State,
    skipAiChatCleanup: Bool = false,
) -> Effect<FileManagerWindowAction> {
    clearInFlightComposerStateOnTabSwitch(state: &state.composer)
    let aiChatCleanupEffect: Effect<FileManagerWindowAction>
    if skipAiChatCleanup {
        aiChatCleanupEffect = .none
    } else {
        aiChatCleanupEffect = AiChatFeature()
            .reduce(into: &state.aiChat, action: .cancelInFlightWork)
            .map { FileManagerWindowAction.content(.aiChat($0)) }
        clearInFlightAiChatStateOnTabSwitch(state: &state.aiChat)
    }
    state.entryViewLayout.entryOperations.isLoading = false
    state.entryViewLayout.entryOperations.isReloading = false
    return aiChatCleanupEffect
}

private func clearInFlightAiChatStateOnTabSwitch(state: inout AiChatState) {
    state.pendingRequestStart = nil
    state.streamingAssistantDraft = nil
    state.lockedModelHandle = nil
    state.executionPhase = .idle
    state.restoreSessionID = nil
    state.restoreOutcome = nil
    state.restoreFailure = nil
    if state.modelListState == .loading {
        state.modelListState = .idle
        state.modelListRequestID = nil
        state.modelListProvider = nil
        state.modelListProviderOrder = []
        state.modelListPendingProviders = []
        state.modelListLoadedModelsByProvider = [:]
        state.modelListFailedProviders = [:]
    }
    if state.sessionStatus == .restoring {
        state.sessionStatus = state.sessionID == nil ? .idle : .active
    }
}

private func clearInFlightComposerStateOnTabSwitch(state: inout ComposerFeature.State) {
    guard state.isLoadingSearch
        || state.isLoadingFilters
        || state.isFilteringInFlight
        || state.activeSearchRequestID != nil
        || state.activeFiltersRequestID != nil
    else { return }

    state.isLoadingSearch = false
    state.isLoadingFilters = false
    state.isFilteringInFlight = false
    state.activeSearchRequestID = nil
    state.activeFiltersRequestID = nil
    state.pendingSearchQuery = nil
    state.queryRenderPhase = .idle
}

private func activeTabHandoffEffect(
    _ shouldResyncContentNavigation: Bool,
    state: FileManagerWindowState,
    aiConnectionsFileClient: AIConnectionsFileClient,
    skipAiChatCancel: Bool = false,
) -> Effect<FileManagerWindowAction> {
    guard shouldResyncContentNavigation else {
        return .none
    }
    let navigationEffect = resyncContentNavigationEffect(state: state)
    return .concatenate(
        cancelInFlightContentEffectsOnTabSwitch(state: state, skipAiChatCancel: skipAiChatCancel),
        .merge(
            navigationEffect,
            restartAiChatProviderLoadOnTabRestoreEffect(
                state: state,
                aiConnectionsFileClient: aiConnectionsFileClient,
            ),
        ),
    )
}

private func cancelInFlightContentEffectsOnTabSwitch(
    state: FileManagerWindowState,
    skipAiChatCancel: Bool = false,
) -> Effect<FileManagerWindowAction> {
    .merge(
        .cancel(id: OpenCollectionFileCancelID(
            windowID: state.content.entryViewLayout.entryOperations.windowID,
        )),
        .cancel(id: EntryOperationsLoadingCancelID.loadItems(
            windowID: state.content.entryViewLayout.entryOperations.windowID,
        )),
        .cancel(id: ComposerFeature.CancelID.search(ownerID: state.content.composer.cancellationOwnerID)),
        .cancel(id: ComposerFeature.CancelID.filters(ownerID: state.content.composer.cancellationOwnerID)),
        state.contentTabs.previousActiveTabID
            .map { .cancel(id: HomeAiChatOpenCancelID(tabID: $0)) }
            ?? .none,
        skipAiChatCancel ? .none : contentPaneAiChatCancelEffect(state: state),
    )
}

private func contentPaneAiChatCancelEffect(state: FileManagerWindowState) -> Effect<FileManagerWindowAction> {
    guard !state.inspector.inspectorVisible || state.inspector.activeMode != .chat else {
        return .none
    }
    return .send(.content(.aiChat(.cancelInFlightWork)))
}

private func restartAiChatProviderLoadOnTabRestoreEffect(
    state: FileManagerWindowState,
    aiConnectionsFileClient: AIConnectionsFileClient,
) -> Effect<FileManagerWindowAction> {
    guard let activeTabID = state.contentTabs.activeTabID,
          case .aiChat = state.contentTabs.tabs[id: activeTabID]?.anchor
    else { return .none }
    if case .loaded = state.content.aiChat.modelListState {
        return .none
    }

    return .run { send in
        let connectionsFile: AIConnectionsFile
        do {
            connectionsFile = try await aiConnectionsFileClient.load()
        } catch {
            connectionsFile = .empty()
        }
        await send(.content(.aiChat(.providerConnectionsUpdated(connectionsFile))))
    }
    .cancellable(id: HomeAiChatOpenCancelID(tabID: activeTabID), cancelInFlight: true)
}

private func resyncContentNavigationEffect(state: FileManagerWindowState) -> Effect<FileManagerWindowAction> {
    if let collectionURL = collectionFileURLRequiringOpen(state: state) {
        return .send(.navigation(.view(.openCollectionFile(collectionURL))))
    }
    guard let navigationState = resyncNavigationStateForActiveContentTab(state: state) else {
        return .none
    }
    if case let .collection(navigation) = navigationState {
        return .concatenate(
            .send(.content(.internal(.applyNavigationState(.collection(navigation))))),
            .send(.navigation(.internal(.navigateToCollection(navigation)))),
        )
    }
    return .send(.content(.internal(.applyNavigationState(navigationState))))
}

private func collectionFileURLRequiringOpen(state: FileManagerWindowState) -> URL? {
    guard let activeTabID = state.contentTabs.activeTabID,
          case let .collectionFile(url) = state.contentTabs.tabs[id: activeTabID]?.anchor
    else { return nil }
    guard state.content.collection.collectionSession.document?.url.standardizedFileURL != url.standardizedFileURL else {
        return nil
    }
    if case let .collection(navigation) = state.content.navigation.navigationState,
       case let .file(navigationURL, _) = navigation.kind,
       navigationURL.standardizedFileURL == url.standardizedFileURL,
       !isEmptyCollectionContext(navigation.context)
    {
        return nil
    }
    return url
}

private func isEmptyCollectionContext(_ context: CollectionContext) -> Bool {
    context.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && context.scopes.isEmpty
        && context.excludedScopes.isEmpty
        && context.conditions.isEmpty
}

private func resyncNavigationStateForActiveContentTab(
    state: FileManagerWindowState,
) -> ContentPageNavigationRoute? {
    guard let activeTabID = state.contentTabs.activeTabID,
          let activeAnchor = state.contentTabs.tabs[id: activeTabID]?.anchor
    else { return nil }

    switch activeAnchor {
    case .homeDefault:
        return .home
    case let .aiChat(sessionID):
        if case let .aiChatSessions(restoredSessionID) = state.content.navigation.navigationState,
           restoredSessionID == sessionID
        {
            return .aiChatSessions(sessionID)
        }
        return .aiChat(sessionID)
    case let .directory(path):
        return .folder(path)
    case .collectionFile:
        if case let .collection(navigation) = state.content.navigation.navigationState {
            return .collection(navigation)
        }
        return nil
    case .virtualCollection:
        switch state.content.navigation.navigationState {
        case .recents,
             .tags,
             .computer:
            return state.content.navigation.navigationState
        default:
            return nil
        }
    }
}

private func closeInspectorForActiveAiChatEffect(state: FileManagerWindowState) -> Effect<FileManagerWindowAction> {
    guard state.inspector.inspectorVisible,
          let activeTabID = state.contentTabs.activeTabID,
          case .aiChat = state.contentTabs.tabs[id: activeTabID]?.anchor
    else {
        return .none
    }
    return .send(.inspector(.closeChat))
}

private func syncSidebarSelectionForActiveContentTab(state _: inout FileManagerWindowState) {}

private func contentState(
    for anchor: ContentTabPageAnchor?,
    inheritingWindowContextFrom source: FileManagerContentFeature.State,
) -> FileManagerContentFeature.State {
    var content = FileManagerContentFeature.State()
    content.applyWindowContext(from: source)

    switch anchor {
    case let .directory(path):
        content.navigation.seedInitialFolderPath(path)
    case let .collectionFile(url):
        content.navigation.navigationState = .collection(.init(
            kind: .file(url: url, name: url.deletingPathExtension().lastPathComponent),
            context: CollectionContext(query: "", scopes: [], conditions: []),
            sortKey: .name,
            sortOrder: .ascending,
            viewLayout: .list,
        ))
    case let .virtualCollection(id):
        content.navigation.navigationState = .tags(id)
    case let .aiChat(sessionID):
        content.navigation.navigationState = .aiChat(sessionID)
        content.aiChat.mode = .chat
    case .homeDefault,
         .none:
        break
    }

    return content
}

private extension ContentTabPageAnchor {
    var isCollectionFileAnchor: Bool {
        if case .collectionFile = self {
            true
        } else {
            false
        }
    }
}

private extension AiChatExecutionPhase {
    var shouldPreserveLifecycleOwner: Bool {
        switch self {
        case let .completed(lock):
            lock.finalSnapshot != nil
        case .persistenceRecovery:
            true
        default:
            false
        }
    }
}

private func aiChatLifecycleSessionIDsToPreserve(_ state: AiChatFeature.State) -> [AiChatSessionID] {
    var sessionIDs: [AiChatSessionID] = []
    func append(_ sessionID: AiChatSessionID?) {
        guard let sessionID, !sessionIDs.contains(sessionID) else { return }
        sessionIDs.append(sessionID)
    }

    if state.executionPhase.isProcessing
        || state.executionPhase.shouldPreserveLifecycleOwner
    {
        append(state.executionPhase.lock?.context.sessionID)
    }
    append(state.pendingRequestStart?.sessionID)
    for pendingRequestStart in state.backgroundPendingRequestStarts.values {
        append(pendingRequestStart.sessionID)
    }
    for phase in state.backgroundExecutionPhases.values where phase.isProcessing || phase.shouldPreserveLifecycleOwner {
        append(phase.lock?.context.sessionID)
    }
    return sessionIDs
}

private func cancelAndRemoveBackgroundAiChatOwners(
    sessionID: AiChatSessionID,
    state: inout FileManagerWindowState,
) -> Effect<FileManagerWindowAction> {
    var effects: [Effect<FileManagerWindowAction>] = []
    if let backgroundContent = state.removeBackgroundAiChatState(sessionID: sessionID) {
        effects.append(cancelBackgroundAiChatWork(sessionID: sessionID, aiChat: backgroundContent.aiChat))
    }
    if let backgroundInspector = state.removeBackgroundInspectorAiChatState(sessionID: sessionID) {
        effects.append(cancelBackgroundInspectorAiChatWork(sessionID: sessionID, aiChat: backgroundInspector.aiChat))
    }

    for backgroundSessionID in state.backgroundAiChatStates.keys {
        guard var backgroundContent = state.backgroundAiChatStates[backgroundSessionID],
              backgroundContent.aiChat.hasLifecycleOwner(sessionID: sessionID)
        else { continue }
        effects.append(cancelBackgroundAiChatWork(sessionID: sessionID, aiChat: backgroundContent.aiChat))
        backgroundContent.aiChat.removeLifecycleOwners(sessionID: sessionID)
        if backgroundContent.aiChat.hasRemainingBackgroundLifecycleOwner {
            state.backgroundAiChatStates[backgroundSessionID] = backgroundContent
        } else {
            state.removeBackgroundAiChatState(sessionID: backgroundSessionID)
        }
    }

    for backgroundSessionID in state.backgroundInspectorAiChatStates.keys {
        guard var backgroundInspector = state.backgroundInspectorAiChatStates[backgroundSessionID],
              backgroundInspector.aiChat.hasLifecycleOwner(sessionID: sessionID)
        else { continue }
        effects.append(cancelBackgroundInspectorAiChatWork(sessionID: sessionID, aiChat: backgroundInspector.aiChat))
        backgroundInspector.aiChat.removeLifecycleOwners(sessionID: sessionID)
        if backgroundInspector.aiChat.hasRemainingBackgroundLifecycleOwner {
            state.backgroundInspectorAiChatStates[backgroundSessionID] = backgroundInspector.tabSnapshot()
        } else {
            state.removeBackgroundInspectorAiChatState(sessionID: backgroundSessionID)
        }
    }
    return .merge(effects)
}

private func cancelBackgroundAiChatWork(
    sessionID: AiChatSessionID,
    aiChat: AiChatFeature.State,
) -> Effect<FileManagerWindowAction> {
    var scopedAiChat = aiChat.cancellationScope(sessionID: sessionID)
    return AiChatFeature()
        .reduce(into: &scopedAiChat, action: .cancelRequestLifecycle(sessionID))
        .map { FileManagerWindowAction.backgroundAiChat($0) }
}

private func cancelBackgroundInspectorAiChatWork(
    sessionID: AiChatSessionID,
    aiChat: AiChatFeature.State,
) -> Effect<FileManagerWindowAction> {
    var scopedAiChat = aiChat.cancellationScope(sessionID: sessionID)
    return AiChatFeature()
        .reduce(into: &scopedAiChat, action: .cancelRequestLifecycle(sessionID))
        .map { FileManagerWindowAction.backgroundInspectorAiChat($0) }
}

private func propagateAiChatSessionDeleteSucceeded(
    sessionID: AiChatSessionID,
    state: inout FileManagerWindowState,
) {
    state.content.aiChat.applySessionDeleteSucceeded(sessionID: sessionID)
    state.syncActiveTabContentState()

    for tabID in state.tabContentStates.keys {
        state.tabContentStates[tabID]?.aiChat.applySessionDeleteSucceeded(sessionID: sessionID)
    }

    state.inspector.aiChat.applySessionDeleteSucceeded(sessionID: sessionID)
    state.syncActiveTabInspectorState()

    for tabID in state.tabInspectorStates.keys {
        state.tabInspectorStates[tabID]?.aiChat.applySessionDeleteSucceeded(sessionID: sessionID)
    }

    state.removeBackgroundAiChatState(sessionID: sessionID)
    state.removeBackgroundInspectorAiChatState(sessionID: sessionID)

    for sessionKey in Array(state.backgroundAiChatStates.keys) {
        state.backgroundAiChatStates[sessionKey]?.aiChat.applySessionDeleteSucceeded(sessionID: sessionID)
    }
    for sessionKey in Array(state.backgroundInspectorAiChatStates.keys) {
        if var backgroundInspector = state.backgroundInspectorAiChatStates[sessionKey] {
            backgroundInspector.aiChat.applySessionDeleteSucceeded(sessionID: sessionID)
            state.backgroundInspectorAiChatStates[sessionKey] = backgroundInspector.tabSnapshot()
        }
    }
}

private func refreshAiChatCustomTitle(
    summary: AiChatSessionSummary,
    customTitle: String?,
    state: inout FileManagerWindowState,
) {
    let sessionID = summary.sessionID
    state.content.aiChat.refreshCustomTitle(summary: summary, customTitle: customTitle)
    state.syncActiveTabContentState()

    for tabID in state.tabContentStates.keys {
        state.tabContentStates[tabID]?.aiChat.refreshCustomTitle(summary: summary, customTitle: customTitle)
    }

    state.inspector.aiChat.refreshCustomTitle(summary: summary, customTitle: customTitle)
    state.syncActiveTabInspectorState()

    for tabID in state.tabInspectorStates.keys {
        state.tabInspectorStates[tabID]?.aiChat.refreshCustomTitle(summary: summary, customTitle: customTitle)
    }

    if var backgroundContent = state.backgroundAiChatStates[sessionID] {
        backgroundContent.aiChat.refreshCustomTitle(summary: summary, customTitle: customTitle)
        state.backgroundAiChatStates[sessionID] = backgroundContent
    }
    if var backgroundInspector = state.backgroundInspectorAiChatStates[sessionID] {
        backgroundInspector.aiChat.refreshCustomTitle(summary: summary, customTitle: customTitle)
        state.backgroundInspectorAiChatStates[sessionID] = backgroundInspector.tabSnapshot()
    }
}

private func routeBackgroundAiChatAction(
    _ aiChatAction: AiChatAction,
    state: inout FileManagerWindowState,
) -> Effect<FileManagerWindowAction> {
    guard let sessionID = backgroundAiChatSessionID(for: aiChatAction, state: state),
          var backgroundContent = state.backgroundAiChatStates[sessionID]
    else { return .none }

    if case let .requestContextResolved(resolutionID, _) = aiChatAction {
        backgroundContent.aiChat.activateBackgroundPendingRequestStart(resolutionID: resolutionID)
        removeAiChatPendingRequestStart(resolutionID: resolutionID, state: &state)
    }

    let backgroundOwnerRemoval = backgroundAiChatOwnerRemoval(
        after: aiChatAction,
        backgroundAiChat: backgroundContent.aiChat,
    )
    let finalSnapshotContext = backgroundFinalSnapshotContext(
        from: aiChatAction,
        backgroundAiChat: backgroundContent.aiChat,
    )
    let effect = AiChatFeature()
        .reduce(into: &backgroundContent.aiChat, action: aiChatAction)
        .map { action in
            if case let .sessionSnapshotSaved(summary, persistedSnapshot, _, _) = action,
               let context = finalSnapshotContext,
               let snapshot = persistedSnapshot ?? makeOffscreenFinalSnapshot(summary: summary, context: context)
            {
                return FileManagerWindowAction.backgroundAiChatSnapshotPersisted(snapshot)
            }
            return FileManagerWindowAction.backgroundAiChat(action)
        }

    if let payload = sessionSnapshotRefreshPayload(from: aiChatAction) {
        refreshAiChatSnapshotsFromBackgroundIfNeeded(
            summary: payload.summary,
            snapshot: payload.snapshot,
            backgroundAiChat: backgroundContent.aiChat,
            state: &state,
        )
    } else if let failedContext = failedAiChatContext(from: aiChatAction) {
        refreshAiChatFailureFromBackgroundIfNeeded(
            context: failedContext,
            backgroundAiChat: backgroundContent.aiChat,
            state: &state,
        )
    } else if let recoveryLock = persistenceRecoveryLock(from: aiChatAction) {
        refreshAiChatRecoveryFromBackgroundIfNeeded(
            lock: recoveryLock,
            backgroundAiChat: backgroundContent.aiChat,
            state: &state,
        )
    }

    backgroundContent.aiChat.removeBackgroundOwner(backgroundOwnerRemoval)
    if backgroundContent.aiChat.hasRemainingBackgroundLifecycleOwner {
        state.backgroundAiChatStates[sessionID] = backgroundContent
    } else {
        state.removeBackgroundAiChatState(sessionID: sessionID)
    }

    return effect
}

private struct SessionSnapshotSavedPayload {
    let summary: AiChatSessionSummary
    let snapshot: AiChatSessionSnapshot?
}

private func shouldRefreshActiveAiChatTabTitleFromSessionList(_ action: AiChatAction) -> Bool {
    switch action {
    case .submitTapped,
         .regenerateTapped,
         .requestContextResolved:
        true
    default:
        false
    }
}

private func sessionSnapshotSavedSummary(from aiChatAction: AiChatAction) -> AiChatSessionSummary? {
    sessionSnapshotRefreshPayload(from: aiChatAction)?.summary
}

private func sessionSnapshotRefreshPayload(from aiChatAction: AiChatAction) -> SessionSnapshotSavedPayload? {
    switch aiChatAction {
    case let .sessionSnapshotSaved(summary, snapshot, _, _):
        SessionSnapshotSavedPayload(summary: summary, snapshot: snapshot)
    case let .sessionSnapshotUpdated(summary, snapshot, _, _):
        SessionSnapshotSavedPayload(summary: summary, snapshot: snapshot)
    default:
        nil
    }
}

private func removeAiChatPendingRequestStart(
    resolutionID: UUID,
    state: inout FileManagerWindowState,
) {
    state.content.aiChat.removePendingRequestStart(resolutionID: resolutionID)
    state.syncActiveTabContentState()

    for tabID in state.tabContentStates.keys {
        state.tabContentStates[tabID]?.aiChat.removePendingRequestStart(resolutionID: resolutionID)
    }

    state.inspector.aiChat.removePendingRequestStart(resolutionID: resolutionID)
    state.syncActiveTabInspectorState()

    for tabID in state.tabInspectorStates.keys {
        state.tabInspectorStates[tabID]?.aiChat.removePendingRequestStart(resolutionID: resolutionID)
    }
}

private func refreshAiChatFollowUpFromBackgroundIfNeeded(
    _ aiChatAction: AiChatAction,
    backgroundAiChat: AiChatFeature.State,
    state: inout FileManagerWindowState,
    skipsActiveContent: Bool = false,
    skipsActiveInspector: Bool = false,
) {
    if let payload = sessionSnapshotRefreshPayload(from: aiChatAction) {
        refreshAiChatSnapshotsFromBackgroundIfNeeded(
            summary: payload.summary,
            snapshot: payload.snapshot,
            backgroundAiChat: backgroundAiChat,
            state: &state,
            skipsActiveContent: skipsActiveContent,
            skipsActiveInspector: skipsActiveInspector,
        )
    } else if let failedContext = failedAiChatContext(from: aiChatAction) {
        refreshAiChatFailureFromBackgroundIfNeeded(
            context: failedContext,
            backgroundAiChat: backgroundAiChat,
            state: &state,
            skipsActiveContent: skipsActiveContent,
            skipsActiveInspector: skipsActiveInspector,
        )
    } else if let recoveryLock = persistenceRecoveryLock(from: aiChatAction) {
        refreshAiChatRecoveryFromBackgroundIfNeeded(
            lock: recoveryLock,
            backgroundAiChat: backgroundAiChat,
            state: &state,
            skipsActiveContent: skipsActiveContent,
            skipsActiveInspector: skipsActiveInspector,
        )
    }
}

private func removeBackgroundAiChatOwnersPromotedToActiveContent(state: inout FileManagerWindowState) {
    let activeAiChat = state.content.aiChat
    let sessionIDs = activeAiChat.lifecycleOwnerSessionIDs
    for sessionID in sessionIDs {
        guard var backgroundContent = state.backgroundAiChatStates[sessionID] else { continue }
        backgroundContent.aiChat.removeBackgroundOwners(matching: activeAiChat)
        if backgroundContent.aiChat.hasRemainingBackgroundLifecycleOwner {
            state.backgroundAiChatStates[sessionID] = backgroundContent
        } else {
            state.removeBackgroundAiChatState(sessionID: sessionID)
        }
    }
}

private func failedAiChatContext(from aiChatAction: AiChatAction) -> AiChatRequestContextSnapshot? {
    guard case let .executionEvent(.failed(context, _)) = aiChatAction else { return nil }
    return context
}

private func persistenceRecoveryLock(from aiChatAction: AiChatAction) -> AiChatRequestLock? {
    switch aiChatAction {
    case let .persistenceFailed(lock, _),
         let .persistenceRecoverySucceeded(lock),
         let .persistenceRecoveryRetryFailed(lock, _):
        lock

    default:
        nil
    }
}

private func handleBackgroundAiChatSnapshotPersisted(
    _ snapshot: AiChatSessionSnapshot,
    state: inout FileManagerWindowState,
) {
    let summary = AiChatSessionSummary(snapshot: snapshot)
    guard let backgroundContent = state.backgroundAiChatStates[snapshot.sessionID] else { return }
    let ownerRemoval = backgroundAiChatOwnerRemoval(
        requestID: snapshot.lastRequestID,
        runID: snapshot.lastRunID,
        backgroundAiChat: backgroundContent.aiChat,
    )
    admitFreshAiChatContentForPersistedSnapshotIfNeeded(summary: summary, state: &state)
    refreshAiChatSnapshotsFromBackgroundIfNeeded(
        summary: summary,
        snapshot: snapshot,
        backgroundAiChat: backgroundContent.aiChat,
        state: &state,
    )
    removeBackgroundAiChatOwnerFromContentAliases(
        ownerRemoval,
        canonicalSessionID: snapshot.sessionID,
        state: &state,
    )
}

private func handleBackgroundInspectorAiChatSnapshotPersisted(
    _ snapshot: AiChatSessionSnapshot,
    state: inout FileManagerWindowState,
) {
    let summary = AiChatSessionSummary(snapshot: snapshot)
    guard let inspectorState = state.backgroundInspectorAiChatStates[snapshot.sessionID] else { return }
    let ownerRemoval = backgroundAiChatOwnerRemoval(
        requestID: snapshot.lastRequestID,
        runID: snapshot.lastRunID,
        backgroundAiChat: inspectorState.aiChat,
    )
    admitFreshAiChatContentForPersistedSnapshotIfNeeded(summary: summary, state: &state)
    refreshAiChatSnapshotsFromBackgroundIfNeeded(
        summary: summary,
        snapshot: snapshot,
        backgroundAiChat: inspectorState.aiChat,
        state: &state,
    )
    removeBackgroundAiChatOwnerFromInspectorAliases(
        ownerRemoval,
        canonicalSessionID: snapshot.sessionID,
        state: &state,
    )
}

private func removeBackgroundAiChatOwnerFromContentAliases(
    _ ownerRemoval: BackgroundAiChatOwnerRemoval?,
    canonicalSessionID: AiChatSessionID,
    state: inout FileManagerWindowState,
) {
    let sessionIDs = ownerRemoval?.requestID == nil
        ? [canonicalSessionID]
        : Array(state.backgroundAiChatStates.keys)
    for sessionID in sessionIDs {
        guard var backgroundContent = state.backgroundAiChatStates[sessionID] else { continue }
        backgroundContent.aiChat.removeBackgroundOwner(ownerRemoval)
        if backgroundContent.aiChat.hasRemainingBackgroundLifecycleOwner {
            state.backgroundAiChatStates[sessionID] = backgroundContent
        } else {
            state.removeBackgroundAiChatState(sessionID: sessionID)
        }
    }
}

private func removeBackgroundAiChatOwnerFromInspectorAliases(
    _ ownerRemoval: BackgroundAiChatOwnerRemoval?,
    canonicalSessionID: AiChatSessionID,
    state: inout FileManagerWindowState,
) {
    let sessionIDs = ownerRemoval?.requestID == nil
        ? [canonicalSessionID]
        : Array(state.backgroundInspectorAiChatStates.keys)
    for sessionID in sessionIDs {
        guard var inspectorState = state.backgroundInspectorAiChatStates[sessionID] else { continue }
        inspectorState.aiChat.removeBackgroundOwner(ownerRemoval)
        if inspectorState.aiChat.hasRemainingBackgroundLifecycleOwner {
            state.backgroundInspectorAiChatStates[sessionID] = inspectorState.tabSnapshot()
        } else {
            state.removeBackgroundInspectorAiChatState(sessionID: sessionID)
        }
    }
}

private struct BackgroundFinalSnapshotContext {
    let response: AiChatResponse
    let lock: AiChatRequestLock
}

private func backgroundFinalSnapshotContext(
    from aiChatAction: AiChatAction,
    backgroundAiChat: AiChatFeature.State,
) -> BackgroundFinalSnapshotContext? {
    guard case let .executionEvent(.final(response)) = aiChatAction,
          let lock = finalSnapshotLock(for: response.context, backgroundAiChat: backgroundAiChat)
    else { return nil }

    return BackgroundFinalSnapshotContext(response: response, lock: lock)
}

private func finalSnapshotLock(
    for context: AiChatRequestContextSnapshot,
    backgroundAiChat: AiChatFeature.State,
) -> AiChatRequestLock? {
    if case let .processing(lock) = backgroundAiChat.executionPhase,
       lock.context.requestID == context.requestID,
       lock.context.runID == context.runID
    {
        return lock
    }
    if case let .processing(lock) = backgroundAiChat.backgroundExecutionPhases[context.requestID],
       lock.context.runID == context.runID
    {
        return lock
    }
    return nil
}

private func makeOffscreenFinalSnapshot(
    summary: AiChatSessionSummary,
    context: BackgroundFinalSnapshotContext,
) -> AiChatSessionSnapshot? {
    let response = context.response
    let lock = context.lock
    guard let sessionID = lock.context.sessionID, sessionID == summary.sessionID else { return nil }
    var transcriptHistory = lock.request.messages
    if let index = lock.assistantReplacementIndex,
       transcriptHistory.indices.contains(index),
       transcriptHistory[index].role == .assistant
    {
        transcriptHistory[index] = response.assistantMessage
    } else {
        transcriptHistory.append(response.assistantMessage)
    }

    return AiChatSessionSnapshot(
        sessionID: sessionID,
        status: .active,
        customTitle: lock.customTitle,
        provider: lock.context.provider,
        model: lock.context.model,
        selectedModelRow: lock.selectedModelRow,
        selectedThinking: lock.context.selectedThinking,
        transcriptHistory: transcriptHistory,
        lastRequestID: lock.requestID,
        lastRunID: lock.runID,
        lastRequestContext: lock.context.requestContext,
        updatedAtMs: summary.updatedAtMs,
    )
}

private func refreshAiChatFailureFromBackgroundIfNeeded(
    context: AiChatRequestContextSnapshot,
    backgroundAiChat: AiChatFeature.State,
    state: inout FileManagerWindowState,
    skipsActiveContent: Bool = false,
    skipsActiveInspector: Bool = false,
) {
    guard let sessionID = context.sessionID else { return }
    admitFreshAiChatContentForBackgroundTerminalStateIfNeeded(
        sessionID: sessionID,
        state: &state,
        skipsActiveContent: skipsActiveContent,
    )

    if !skipsActiveContent,
       state.content.aiChat.canRefreshFailureFromBackground(context: context)
    {
        state.content.aiChat.applyBackgroundFailure(context: context, backgroundAiChat: backgroundAiChat)
        state.syncActiveTabContentState()
    }

    for tabID in state.tabContentStates.keys {
        guard tabID != state.contentTabs.activeTabID else { continue }
        guard state.tabContentStates[tabID]?.aiChat.canRefreshFailureFromBackground(context: context) == true
        else { continue }
        state.tabContentStates[tabID]?.aiChat.applyBackgroundFailure(
            context: context,
            backgroundAiChat: backgroundAiChat,
        )
    }

    if !skipsActiveInspector,
       state.inspector.aiChat.canRefreshFailureFromBackground(context: context)
    {
        state.inspector.aiChat.applyBackgroundFailure(context: context, backgroundAiChat: backgroundAiChat)
        state.syncActiveTabInspectorState()
    }

    for tabID in state.tabInspectorStates.keys {
        guard tabID != state.contentTabs.activeTabID else { continue }
        guard state.tabInspectorStates[tabID]?.aiChat.canRefreshFailureFromBackground(context: context) == true
        else { continue }
        state.tabInspectorStates[tabID]?.aiChat.applyBackgroundFailure(
            context: context,
            backgroundAiChat: backgroundAiChat,
        )
    }
}

private func refreshAiChatRecoveryFromBackgroundIfNeeded(
    lock: AiChatRequestLock,
    backgroundAiChat: AiChatFeature.State,
    state: inout FileManagerWindowState,
    skipsActiveContent: Bool = false,
    skipsActiveInspector: Bool = false,
) {
    guard let sessionID = lock.context.sessionID else { return }
    admitFreshAiChatContentForBackgroundTerminalStateIfNeeded(
        sessionID: sessionID,
        state: &state,
        skipsActiveContent: skipsActiveContent,
    )

    if !skipsActiveContent,
       state.content.aiChat.canRefreshRecoveryFromBackground(lock: lock)
    {
        state.content.aiChat.applyBackgroundRecovery(lock: lock, backgroundAiChat: backgroundAiChat)
        state.syncActiveTabContentState()
    }

    for tabID in state.tabContentStates.keys {
        guard tabID != state.contentTabs.activeTabID else { continue }
        guard state.tabContentStates[tabID]?.aiChat.canRefreshRecoveryFromBackground(lock: lock) == true
        else { continue }
        state.tabContentStates[tabID]?.aiChat.applyBackgroundRecovery(
            lock: lock,
            backgroundAiChat: backgroundAiChat,
        )
    }

    if !skipsActiveInspector,
       state.inspector.aiChat.canRefreshRecoveryFromBackground(lock: lock)
    {
        state.inspector.aiChat.applyBackgroundRecovery(lock: lock, backgroundAiChat: backgroundAiChat)
        state.syncActiveTabInspectorState()
    }

    for tabID in state.tabInspectorStates.keys {
        guard tabID != state.contentTabs.activeTabID else { continue }
        guard state.tabInspectorStates[tabID]?.aiChat.canRefreshRecoveryFromBackground(lock: lock) == true
        else { continue }
        state.tabInspectorStates[tabID]?.aiChat.applyBackgroundRecovery(
            lock: lock,
            backgroundAiChat: backgroundAiChat,
        )
    }
}

private func admitFreshAiChatContentForBackgroundTerminalStateIfNeeded(
    sessionID: AiChatSessionID,
    state: inout FileManagerWindowState,
    skipsActiveContent: Bool,
) {
    let anchor = ContentTabPageAnchor.aiChat(sessionID: sessionID.rawValue.uuidString)

    if !skipsActiveContent,
       let activeTabID = state.contentTabs.activeTabID,
       state.contentTabs.tabs[id: activeTabID]?.anchor == anchor,
       state.content.aiChat.canAdmitBackgroundTerminalState
    {
        state.content.aiChat.sessionID = sessionID
    }

    for tabID in state.tabContentStates.keys {
        guard tabID != state.contentTabs.activeTabID,
              state.contentTabs.tabs[id: tabID]?.anchor == anchor,
              state.tabContentStates[tabID]?.aiChat.canAdmitBackgroundTerminalState == true
        else {
            continue
        }
        state.tabContentStates[tabID]?.aiChat.sessionID = sessionID
    }
}

private func admitFreshAiChatContentForPersistedSnapshotIfNeeded(
    summary: AiChatSessionSummary,
    state: inout FileManagerWindowState,
) {
    let anchor = ContentTabPageAnchor.aiChat(sessionID: summary.sessionID.rawValue.uuidString)

    if let activeTabID = state.contentTabs.activeTabID,
       state.contentTabs.tabs[id: activeTabID]?.anchor == anchor,
       state.content.aiChat.canAdmitPersistedBackgroundSnapshot(summary: summary)
    {
        state.content.aiChat.sessionID = summary.sessionID
    }

    for tabID in state.tabContentStates.keys {
        guard tabID != state.contentTabs.activeTabID,
              state.contentTabs.tabs[id: tabID]?.anchor == anchor,
              state.tabContentStates[tabID]?.aiChat
              .canAdmitPersistedBackgroundSnapshot(summary: summary) == true
        else {
            continue
        }
        state.tabContentStates[tabID]?.aiChat.sessionID = summary.sessionID
    }
}

private func refreshAiChatSnapshotsFromBackgroundIfNeeded(
    summary: AiChatSessionSummary,
    snapshot: AiChatSessionSnapshot? = nil,
    backgroundAiChat: AiChatFeature.State,
    state: inout FileManagerWindowState,
    skipsActiveContent: Bool = false,
    skipsActiveInspector: Bool = false,
) {
    if !skipsActiveContent,
       state.content.aiChat.canRefreshFromBackground(summary: summary, snapshot: snapshot)
    {
        state.content.aiChat.applyBackgroundSnapshot(
            summary: summary,
            snapshot: snapshot,
            backgroundAiChat: backgroundAiChat,
        )
        state.syncActiveTabContentState()
    }

    for tabID in state.tabContentStates.keys {
        guard tabID != state.contentTabs.activeTabID else { continue }
        guard state.tabContentStates[tabID]?.aiChat
            .canRefreshFromBackground(summary: summary, snapshot: snapshot) == true
        else {
            continue
        }
        state.tabContentStates[tabID]?.aiChat.applyBackgroundSnapshot(
            summary: summary,
            snapshot: snapshot,
            backgroundAiChat: backgroundAiChat,
        )
    }

    if !skipsActiveInspector,
       state.inspector.aiChat.canRefreshFromBackground(summary: summary, snapshot: snapshot)
    {
        state.inspector.aiChat.applyBackgroundSnapshot(
            summary: summary,
            snapshot: snapshot,
            backgroundAiChat: backgroundAiChat,
        )
        state.syncActiveTabInspectorState()
    }

    for tabID in state.tabInspectorStates.keys {
        guard tabID != state.contentTabs.activeTabID else { continue }
        guard state.tabInspectorStates[tabID]?.aiChat
            .canRefreshFromBackground(summary: summary, snapshot: snapshot) == true
        else {
            continue
        }
        state.tabInspectorStates[tabID]?.aiChat.applyBackgroundSnapshot(
            summary: summary,
            snapshot: snapshot,
            backgroundAiChat: backgroundAiChat,
        )
    }
}

private extension AiChatFeature.State {
    func canRefreshRecoveryFromBackground(lock: AiChatRequestLock) -> Bool {
        guard sessionID == lock.context.sessionID,
              pendingRequestStart == nil
        else { return false }
        guard executionPhase.isProcessing else { return true }
        return executionPhase.matchesOwner(requestID: lock.requestID, runID: lock.runID)
    }

    mutating func applyBackgroundRecovery(
        lock: AiChatRequestLock,
        backgroundAiChat: AiChatFeature.State,
    ) {
        guard let matchingPhase = backgroundAiChat.backgroundExecutionPhases[lock.requestID]?
            .matchingRecoveryFollowUp(lock: lock)
            ?? backgroundAiChat.executionPhase.matchingRecoveryFollowUp(lock: lock)
        else { return }

        if let finalSnapshot = matchingPhase.lock?.finalSnapshot ?? lock.finalSnapshot {
            applyBackgroundRecoveryFinalSnapshot(finalSnapshot)
        } else if let lock = matchingPhase.lock {
            applyBackgroundLockPayload(lock)
        }
        executionPhase = matchingPhase
        streamingAssistantDraft = nil
        lockedModelHandle = nil
        if case let .persistenceRecovery(_, failure) = matchingPhase {
            lastExecutionFailure = failure
        } else {
            lastExecutionFailure = nil
        }
    }

    mutating func applyBackgroundRecoveryFinalSnapshot(_ snapshot: AiChatSessionSnapshot) {
        sessionID = snapshot.sessionID
        sessionStatus = snapshot.status
        currentSessionCustomTitle = snapshot.customTitle
        transcriptHistory = snapshot.transcriptHistory
        transcriptAutoScrollVersion += 1
        lastRequestContext = snapshot.lastRequestContext
        lastRequestContextModelHandle = snapshot.model
        selectedModelHandle = snapshot.model
        selectedThinking = snapshot.selectedThinking
    }

    mutating func applyBackgroundLockPayload(_ lock: AiChatRequestLock) {
        transcriptHistory = lock.persistenceTranscriptHistory
        lastRequestContext = lock.context.requestContext
        lastRequestContextModelHandle = lock.context.model
        selectedModelHandle = lock.context.model
        selectedThinking = lock.context.selectedThinking
        transcriptAutoScrollVersion += 1
    }

    func matchingBackgroundSnapshot(
        summary: AiChatSessionSummary,
        snapshot: AiChatSessionSnapshot?,
    ) -> AiChatExecutionPhase? {
        guard let requestID = snapshot?.lastRequestID else {
            return executionPhase.matchingBackgroundSnapshot(
                summary: summary,
                snapshot: snapshot,
            )
        }
        if let backgroundPhase = backgroundExecutionPhases[requestID]?.matchingBackgroundSnapshot(
            summary: summary,
            snapshot: snapshot,
        ) {
            return backgroundPhase
        }
        guard executionPhase.matchesOwner(requestID: requestID, runID: snapshot?.lastRunID) else { return nil }
        if case let .processing(lock) = executionPhase,
           let snapshot,
           snapshot.transcriptHistory.count > lock.request.messages.count
        {
            return .completed(lock.recordingFinalSnapshot(snapshot))
        }
        return executionPhase.matchingBackgroundSnapshot(
            summary: summary,
            snapshot: snapshot,
        )
    }

    func hasBackgroundOwnerMatching(requestID: AiChatRequestID, runID: AiChatRunID?) -> Bool {
        executionPhase.matchesOwner(requestID: requestID, runID: runID)
            || backgroundExecutionPhases[requestID]?.matchesOwner(requestID: requestID, runID: runID) == true
    }

    var hasRemainingBackgroundLifecycleOwner: Bool {
        pendingRequestStart != nil
            || !backgroundPendingRequestStarts.isEmpty
            || executionPhase.lock != nil
            || !backgroundExecutionPhases.isEmpty
    }

    mutating func removeBackgroundOwner(_ removal: BackgroundAiChatOwnerRemoval?) {
        guard let removal else { return }
        guard let requestID = removal.requestID else {
            if removal.removeLegacySessionOwner {
                pendingRequestStart = nil
                executionPhase = .idle
                backgroundExecutionPhases = [:]
            }
            return
        }
        if executionPhase.matchesOwner(requestID: requestID, runID: removal.runID) {
            executionPhase = .idle
        }
        if backgroundExecutionPhases[requestID]?.matchesOwner(requestID: requestID, runID: removal.runID) == true {
            backgroundExecutionPhases[requestID] = nil
        }
    }

    func canRefreshFailureFromBackground(context: AiChatRequestContextSnapshot) -> Bool {
        guard sessionID == context.sessionID,
              pendingRequestStart == nil
        else { return false }
        guard executionPhase.isProcessing else { return true }
        return executionPhase.matchesOwner(requestID: context.requestID, runID: context.runID)
    }

    mutating func applyBackgroundFailure(
        context: AiChatRequestContextSnapshot,
        backgroundAiChat: AiChatFeature.State,
    ) {
        guard let matchingPhase = backgroundAiChat.backgroundExecutionPhases[context.requestID]?
            .matchingFailure(context: context)
            ?? backgroundAiChat.executionPhase.matchingFailure(context: context)
        else { return }
        if let lock = matchingPhase.lock {
            applyBackgroundLockPayload(lock)
        }
        executionPhase = matchingPhase
        streamingAssistantDraft = nil
        lockedModelHandle = nil
        if case let .failed(_, failure) = matchingPhase {
            lastExecutionFailure = failure
        }
    }

    var canAdmitBackgroundTerminalState: Bool {
        sessionID == nil
            && restoreSessionID == nil
            && pendingRequestStart == nil
    }

    func canAdmitPersistedBackgroundSnapshot(summary: AiChatSessionSummary) -> Bool {
        sessionID == nil
            && restoreSessionID == nil
            && pendingRequestStart == nil
            && !hasNewerSnapshotThanBackground(summary)
    }

    func canRefreshFromBackground(
        summary: AiChatSessionSummary,
        snapshot: AiChatSessionSnapshot? = nil,
    ) -> Bool {
        guard sessionID == summary.sessionID,
              pendingRequestStart == nil,
              !hasNewerSnapshotThanBackground(summary)
        else { return false }
        guard executionPhase.isProcessing else { return true }
        guard let requestID = snapshot?.lastRequestID else { return false }
        return executionPhase.matchesOwner(requestID: requestID, runID: snapshot?.lastRunID)
    }

    private func hasNewerSnapshotThanBackground(_ summary: AiChatSessionSummary) -> Bool {
        if let currentRow = sessionList.allRows.first(where: { $0.sessionID == summary.sessionID }),
           currentRow.isNewer(than: summary)
        {
            return true
        }
        if transcriptHistory.count > summary.messageCount {
            return true
        }
        if let lock = executionPhase.lock,
           lock.context.sessionID == summary.sessionID,
           let terminalAtMs = lock.observabilitySummary.terminalAtMs,
           terminalAtMs > summary.updatedAtMs
        {
            return true
        }
        return false
    }

    mutating func applyBackgroundSnapshot(
        summary: AiChatSessionSummary,
        snapshot: AiChatSessionSnapshot? = nil,
        backgroundAiChat: AiChatFeature.State,
    ) {
        let mergeResult = sessionList.replaceRowIfNewer(summary)
        guard mergeResult.acceptsRow else { return }
        if mergeResult.permitsSnapshotPayload {
            if let snapshot {
                currentSessionCustomTitle = snapshot.customTitle
            } else {
                currentSessionCustomTitle = backgroundAiChat.currentSessionCustomTitle
            }
            transcriptHistory = snapshot?.transcriptHistory ?? backgroundAiChat.transcriptHistory
            streamingAssistantDraft = nil
            transcriptAutoScrollVersion += 1
            lockedModelHandle = nil
            lastExecutionFailure = nil
            lastRequestContext = snapshot?.lastRequestContext ?? backgroundAiChat.lastRequestContext
            lastRequestContextModelHandle = snapshot?.model ?? backgroundAiChat.lastRequestContextModelHandle
            selectedModelHandle = snapshot?.model ?? backgroundAiChat.selectedModelHandle
            selectedThinking = snapshot?.selectedThinking ?? backgroundAiChat.selectedThinking
            sessionStatus = snapshot?.status ?? .active
            if let executionPhaseToApply = backgroundAiChat.matchingBackgroundSnapshot(
                summary: summary,
                snapshot: snapshot,
            ) ?? matchingBackgroundSnapshot(
                summary: summary,
                snapshot: snapshot,
            ) {
                executionPhase = executionPhaseToApply
            }
        }

        if restoreSessionID == nil || restoreSessionID == summary.sessionID {
            sessionList.selectedSessionID = summary.sessionID
        }
        if mode == .chat {
            sessionList.unreadCompletedSessionIDs.remove(summary.sessionID)
        } else {
            sessionList.unreadCompletedSessionIDs.insert(summary.sessionID)
        }
        sessionList.errorMessage = nil
    }
}

private extension AiChatExecutionPhase {
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

private func routeInactiveInspectorAiChatAction(
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

private func routeBackgroundInspectorAiChatAction(
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

private func inactiveInspectorTabID(
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

private func backgroundInspectorAiChatSessionID(
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

private func backgroundInspectorAiChatSessionID(
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

private func inspectorAiChatSessionID(for aiChatAction: AiChatAction) -> AiChatSessionID? {
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

private extension FileManagerInspectorFeature.State {
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

private func aiChatEventRequestID(_ event: AiChatEvent) -> AiChatRequestID? {
    switch event {
    case let .started(context),
         let .delta(context, _),
         let .failed(context, _):
        context.requestID

    case let .final(response):
        response.context.requestID
    }
}

private func aiChatEventRunID(_ event: AiChatEvent) -> AiChatRunID? {
    switch event {
    case let .started(context),
         let .delta(context, _),
         let .failed(context, _):
        context.runID

    case let .final(response):
        response.context.runID
    }
}

private extension AiChatFeature.State {
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

private extension AiChatExecutionPhase {
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

private func backgroundAiChatSessionID(
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

private struct BackgroundAiChatOwnerRemoval {
    let requestID: AiChatRequestID?
    let runID: AiChatRunID?
    let removeLegacySessionOwner: Bool
}

private func backgroundAiChatOwnerRemoval(
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

private func backgroundAiChatOwnerRemoval(
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
