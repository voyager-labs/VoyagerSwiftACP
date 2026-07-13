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
            case let .sidebar(.delegate(.selectContentTab(tabID))):
                return .merge(
                    .send(.contentTabs(.setCurrent(tabID))),
                    brokenPinnedTabFeedbackEffect(tabID: tabID, state: state),
                )

            case let .sidebar(.delegate(.closeContentTab(tabID))):
                return .send(.closeContentTabRequested(tabID))

            case let .sidebar(.delegate(.pinContentTab(tabID))):
                guard state.pendingContentTabClose == nil else { return .none }
                guard state.canPinContentTab(tabID) else {
                    return cannotPinCollectionFeedbackEffect()
                }
                return .send(.contentTabs(.pin(tabID)))

            case let .sidebar(.delegate(.unpinContentTab(tabID))):
                guard state.pendingContentTabClose == nil else { return .none }
                return .send(.contentTabs(.unpin(tabID)))

            case .sidebar(.delegate(.openContentTab)):
                return .send(.contentTabs(.open(.homeDefault)))

            case let .sidebar(.delegate(.duplicateContentTab(sourceID))):
                return .send(.request(.duplicateContentTab(sourceID)))

            case .content(.delegate(.closeWindow)):
                return .send(.closeWindow)

            case .closeWindow:
                return .run { _ in
                    await MainActor.run {
                        NSApplication.shared.keyWindow?.close()
                    }
                }

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

            case let .contentTabs(.close(tabID)):
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
                return shouldCloseWindow ? .merge(handoffEffect, .send(.closeWindow)) : handoffEffect

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
                let activeTabIDBeforeSync = state.contentTabs.activeTabID
                let activeAnchorBeforeSync = activeTabIDBeforeSync.flatMap { state.contentTabs.tabs[id: $0]?.anchor }
                state.applyPinnedContentTabs(contentTabs)
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

            case let .contentTabs(.duplicate(sourceID, duplicateID)):
                // Post-reduce branch: ContentTabFeature가 row를 생성한 후 handoff/rollback 처리
                // tabs[id: duplicateID]가 없으면 core guard가 no-op이므로 projection만 유지
                guard state.contentTabs.tabs[id: duplicateID] != nil else {
                    syncDashboardProjections(state: &state)
                    return .none
                }

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

            case .contentTabs:
                syncDashboardProjections(state: &state)
                return .none

            case let .closeContentTabRequested(tabID):
                return handleCloseContentTabRequested(tabID: tabID, state: &state)

            case let .contentTabCloseAlertResponse(choice):
                return handleContentTabCloseAlertResponse(choice: choice, state: &state)

            case .content(.collection(.saveCompleted(.success))):
                guard state.pendingContentTabClose != nil else {
                    return .none
                }
                return .none

            case .content(.composer(.internal(.syncCollectionState))):
                guard state.pendingContentTabClose != nil else {
                    return .none
                }
                state.pendingContentTabClose?.didReceiveWriteBackComposerSync = true
                return finalizePendingContentTabCloseIfWriteBackEffectsCompleted(state: &state)

            case .navigation(.internal(.setNavigationState)):
                guard state.pendingContentTabClose != nil else {
                    return .none
                }
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
                guard state.pendingContentTabClose != nil else {
                    return .none
                }
                return .none

            case .content(.collection(.savePanelResponse(nil))),
                 .content(.collection(.writeBackFailed)),
                 .content(.collection(.delegate(.saveFeedback))):
                guard let pendingClose = state.pendingContentTabClose else {
                    return .none
                }
                restorePreviousActiveContentIfNeeded(pendingClose, state: &state)
                state.pendingContentTabClose = nil
                return .none

            default:
                return .none
            }
        }
    }
}

// MARK: - Close Content Tab Request

private extension FileManagerWindowRoutingReducer {
    func keepPendingContentTabCloseFocusedAfterOpen(state: inout State) -> Bool {
        guard let pendingClose = state.pendingContentTabClose else {
            return false
        }
        if let activeTabID = state.contentTabs.activeTabID, activeTabID != pendingClose.tabID {
            state.contentTabs.tabs.remove(id: activeTabID)
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

    /// Pending close rollback variant: exact duplicateID row/cache만 제거하고 pending state로 복원한다.
    /// ContentTabFeature.duplicate가 previousActiveTabID를 덮어썼으므로 pendingClose에 보관된 원본 값을 사용한다.
    func keepPendingDuplicateContentTabCloseFocused(
        duplicateID: ContentTabID,
        state: inout State,
    ) -> Bool {
        guard let pendingClose = state.pendingContentTabClose else { return false }
        // Exact duplicateID row/cache 제거
        let wasActive = state.contentTabs.activeTabID == duplicateID
        state.contentTabs.tabs.remove(id: duplicateID)
        state.removeContentState(for: duplicateID)
        state.removeInspectorState(for: duplicateID)
        // Duplicate가 active였으면(unpinned source) pendingClose에 보관된 원본 ID로 복원
        if wasActive {
            state.contentTabs.activeTabID = pendingClose.tabID
            state.contentTabs.previousActiveTabID = pendingClose.previousActiveTabID
        }
        // Pending target/Content/Inspector/projection은 변경하지 않음
        state.syncContentTabSidebarItems()
        syncSidebarSelectionForActiveContentTab(state: &state)
        return true
    }

    func handleCloseContentTabRequested(
        tabID: ContentTabID,
        state: inout State,
    ) -> Effect<Action> {
        guard state.pendingContentTabClose == nil else {
            return .none
        }

        guard state.contentTabs.tabs[id: tabID] != nil else {
            return .none
        }

        if state.contentTabs.tabs[id: tabID]?.isPinned == true {
            return .send(.contentTabs(.close(tabID)))
        }

        let isActiveTarget = tabID == state.contentTabs.activeTabID
        let targetState: FileManagerContentState
        if isActiveTarget {
            targetState = state.content
        } else {
            guard let inactiveState = state.tabContentStates[tabID] else {
                return .send(.contentTabs(.close(tabID)))
            }
            targetState = inactiveState
        }

        if targetState.isCollectionMode, targetState.canSaveCollection {
            state.pendingContentTabClose = PendingContentTabClose(
                tabID: tabID,
                previousActiveTabID: isActiveTarget ? nil : state.contentTabs.activeTabID,
                previousActiveContent: isActiveTarget ? nil : state.content,
                targetContent: isActiveTarget ? nil : targetState,
                previousActiveInspector: isActiveTarget ? nil : state.inspector,
                targetInspector: isActiveTarget ? nil : state.inspectorState(for: tabID),
            )
            return .run { send in
                let choice = await collectionAlertClient.showUnsavedNavigationAlert()
                await send(.contentTabCloseAlertResponse(choice))
            }
        }

        return .send(.contentTabs(.close(tabID)))
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
            state.pendingContentTabClose = nil
            return .none

        case .discard:
            state.pendingContentTabClose = nil
            if pendingClose.targetContent != nil {
                return .send(.contentTabs(.close(pendingClose.tabID)))
            }
            return .concatenate(
                .send(.content(.view(.discardCollectionChanges))),
                .send(.contentTabs(.close(pendingClose.tabID))),
            )

        case .save:
            stagePendingTargetContentIfNeeded(pendingClose, state: &state)
            guard canStartPendingContentSave(state.content) else {
                restorePreviousActiveContentIfNeeded(pendingClose, state: &state)
                state.pendingContentTabClose = nil
                return .none
            }
            return .send(.content(.composer(.saveCollection)))
        }
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
        state.pendingContentTabClose = nil
        return .send(.contentTabs(.close(pendingClose.tabID)))
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

    return .send(.content(.aiChat(.setup(AiChatSetupState(
        restoreSessionID: AiChatSessionID(rawValue: sessionUUID),
        sessionID: nil,
        mode: .chat,
    )))))
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
    return .merge(
        cancelInFlightContentEffectsOnTabSwitch(state: state, skipAiChatCancel: skipAiChatCancel),
        resyncContentNavigationEffect(state: state),
        restartAiChatProviderLoadOnTabRestoreEffect(
            state: state,
            aiConnectionsFileClient: aiConnectionsFileClient,
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
    guard var backgroundContent = state.backgroundAiChatStates[snapshot.sessionID] else { return }
    let ownerRemoval = backgroundAiChatOwnerRemoval(
        requestID: snapshot.lastRequestID,
        runID: snapshot.lastRunID,
        backgroundAiChat: backgroundContent.aiChat,
    )
    refreshAiChatSnapshotsFromBackgroundIfNeeded(
        summary: summary,
        snapshot: snapshot,
        backgroundAiChat: backgroundContent.aiChat,
        state: &state,
    )
    backgroundContent.aiChat.removeBackgroundOwner(ownerRemoval)
    if backgroundContent.aiChat.hasRemainingBackgroundLifecycleOwner {
        state.backgroundAiChatStates[snapshot.sessionID] = backgroundContent
    } else {
        state.removeBackgroundAiChatState(sessionID: snapshot.sessionID)
    }
}

private func handleBackgroundInspectorAiChatSnapshotPersisted(
    _ snapshot: AiChatSessionSnapshot,
    state: inout FileManagerWindowState,
) {
    let summary = AiChatSessionSummary(snapshot: snapshot)
    guard var inspectorState = state.backgroundInspectorAiChatStates[snapshot.sessionID] else { return }
    let ownerRemoval = backgroundAiChatOwnerRemoval(
        requestID: snapshot.lastRequestID,
        runID: snapshot.lastRunID,
        backgroundAiChat: inspectorState.aiChat,
    )
    refreshAiChatSnapshotsFromBackgroundIfNeeded(
        summary: summary,
        snapshot: snapshot,
        backgroundAiChat: inspectorState.aiChat,
        state: &state,
    )
    inspectorState.aiChat.removeBackgroundOwner(ownerRemoval)
    if inspectorState.aiChat.hasRemainingBackgroundLifecycleOwner {
        state.backgroundInspectorAiChatStates[snapshot.sessionID] = inspectorState.tabSnapshot()
    } else {
        state.removeBackgroundInspectorAiChatState(sessionID: snapshot.sessionID)
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
    guard context.sessionID != nil else { return }

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
    guard lock.context.sessionID != nil else { return }

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
