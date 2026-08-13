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
    typealias State = FileManagerWindowState
    typealias Action = FileManagerWindowAction

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
    @Dependency(\.fileOperationUndoManagerClient)
    var fileOperationUndoManagerClient

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

    private func cancelPendingCollectionOpen(state: inout State) -> Effect<Action> {
        guard state.pendingCollectionOpenRequest != nil else { return .none }
        state.pendingCollectionOpenRequest = nil
        let clearLoadingEffect: Effect<Action> = if let activeTabID = state.contentTabs.activeTabID {
            .send(.tabContent(
                tabID: activeTabID,
                action: .entryViewLayout(.internal(.setCollectionContentLoading(false))),
            ))
        } else {
            .none
        }
        return .concatenate(
            .cancel(id: OpenCollectionFileCancelID(
                windowID: state.content.entryViewLayout.entryOperations.windowID,
            )),
            clearLoadingEffect,
        )
    }

    private func applyPinnedContentTabRuntimeNavigation(
        tabID: ContentTabID,
        navigationState: ContentPageNavigationRoute,
        state: inout State,
    ) -> Effect<Action> {
        guard let tab = state.contentTabs.tabs[id: tabID],
              tab.isPinned,
              let anchor = contentTabAnchor(
                  for: navigationState,
                  computerName: fileManagerClient.displayName("/"),
              )
        else { return .none }

        let isActiveTab = state.contentTabs.activeTabID == tabID
        let targetContentState: FileManagerContentState? = isActiveTab
            ? state.content
            : state.tabContentStates[tabID]
        guard targetContentState?.hasUnsavedCollectionChanges != true else { return .none }

        let shouldResetCollectionMode = targetContentState?.isCollectionMode == true
            && !navigationState.isCollection

        let cancelCollectionOpenEffect = isActiveTab ? cancelPendingCollectionOpen(state: &state) : .none
        let resetCollectionModeEffect = if isActiveTab, shouldResetCollectionMode {
            resetComposerAndClearCollectionModeEffect()
        } else {
            Effect<Action>.none
        }
        let currentNavigationState = targetContentState?.navigation.navigationState
        if isActiveTab, currentNavigationState == navigationState {
            return .concatenate(cancelCollectionOpenEffect, resetCollectionModeEffect)
        }
        guard currentNavigationState != navigationState || shouldResetCollectionMode else { return .none }

        guard isActiveTab else {
            var contentState = state.tabContentStates[tabID]
                ?? FileManagerContentFeature.State.initialContent(
                    for: anchor,
                    inheritingWindowContextFrom: state.content,
                )
            if shouldResetCollectionMode {
                contentState.resetComposerAndClearCollectionMode()
            }
            contentState.navigation.navigationState = navigationState
            switch navigationState {
            case let .aiChat(sessionID):
                let aiChatSessionID = AiChatSessionID(rawValue: UUID(uuidString: sessionID) ?? UUID())
                if !contentState.aiChat.prepareChatPresentation(for: aiChatSessionID) {
                    contentState.aiChat.prepareDeferredChatSessionRestore(for: aiChatSessionID)
                }
            case let .aiChatSessions(sessionID):
                let aiChatSessionID = AiChatSessionID(rawValue: UUID(uuidString: sessionID) ?? UUID())
                contentState.aiChat.prepareInactiveSessionsPresentation(for: aiChatSessionID)
            default:
                break
            }
            state.tabContentStates[tabID] = contentState
            return tab.anchor == anchor
                ? .none
                : .send(.contentTabs(.updateActivePageAnchor(tabID, anchor)))
        }

        return .concatenate(
            cancelCollectionOpenEffect,
            resetCollectionModeEffect,
            syncActiveContentTabEffect(
                navigationState,
                state: state,
                computerName: fileManagerClient.displayName("/"),
            ),
            .send(.navigation(.internal(.applyPinnedPeerNavigationState(navigationState)))),
            handleNavigateToState(navigationState, state: &state),
        )
    }

    private func undoManagerScope(tabID: ContentTabID, state: State) -> UndoManagerScope? {
        guard let windowID = state.windowID else { return nil }
        return UndoManagerScope(windowID: windowID, contentTabID: tabID.rawValue)
    }

    private func activateUndoManagerScopeEffect(tabID: ContentTabID, state: State) -> Effect<Action> {
        guard let scope = undoManagerScope(tabID: tabID, state: state) else { return .none }
        _ = fileOperationUndoManagerClient.activate(scope)
        return .none
    }

    private func deactivateUndoManagerScopeEffect(tabID: ContentTabID, state: State) -> Effect<Action> {
        guard let scope = undoManagerScope(tabID: tabID, state: state) else { return .none }
        fileOperationUndoManagerClient.deactivate(scope)
        return .none
    }

    private func replaceUndoManagerScopeEffect(
        closedTabID: ContentTabID,
        homeTabID: ContentTabID,
        state: State,
    ) -> Effect<Action> {
        guard let closedScope = undoManagerScope(tabID: closedTabID, state: state),
              let homeScope = undoManagerScope(tabID: homeTabID, state: state)
        else { return .none }
        fileOperationUndoManagerClient.deactivate(closedScope)
        _ = fileOperationUndoManagerClient.activate(homeScope)
        return .none
    }

    private func reconcileUndoManagerScopesEffect(
        tabAnchorsBeforeSync: [(id: ContentTabID, anchor: ContentTabPageAnchor)],
        state: State,
    ) -> Effect<Action> {
        let tabAnchorsAfterSync = state.contentTabs.tabs.map { (id: $0.id, anchor: $0.anchor) }
        let anchorsBeforeSync = Dictionary(uniqueKeysWithValues: tabAnchorsBeforeSync)
        let anchorsAfterSync = Dictionary(uniqueKeysWithValues: tabAnchorsAfterSync)
        let teardownEffect = tabAnchorsBeforeSync.reduce(Effect<Action>.none) { effect, tab in
            guard anchorsAfterSync[tab.id] != tab.anchor else { return effect }
            return .concatenate(effect, deactivateUndoManagerScopeEffect(tabID: tab.id, state: state))
        }
        let activationEffect = tabAnchorsAfterSync.reduce(Effect<Action>.none) { effect, tab in
            guard anchorsBeforeSync[tab.id] != tab.anchor else { return effect }
            return .concatenate(effect, activateUndoManagerScopeEffect(tabID: tab.id, state: state))
        }
        return .concatenate(teardownEffect, activationEffect)
    }

    var body: some Reducer<State, Action> {
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

            case let .reserveExternalContentTabs(reservations):
                guard let activeReservation = reservations.last,
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

            case let .tabContent(tabID, .delegate(.closeWindow)):
                guard tabID == state.contentTabs.activeTabID else { return .none }
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
                    handoffCleanupEffect,
                    activeTabHandoffEffect(
                        shouldResyncContentNavigation,
                        state: &state,
                        aiConnectionsFileClient: aiConnectionsFileClient,
                        skipAiChatCancel: true,
                    ),
                    closeInspectorForActiveAiChatEffect(state: state),
                )

            case .contentTabs(.open):
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

            case let .contentTabs(.close(tabID)):
                if keepPendingContentTabCloseFocused(state: &state) {
                    return .none
                }
                let isRemovedTab = state.contentTabs.tabs[id: tabID] == nil
                let isActualRemoval = isRemovedTab
                    && (state.tabContentStates[tabID] != nil || state.contentTabs.previousActiveTabID == tabID)
                let shouldRestorePreviousActiveTab = isActualRemoval
                    && state.contentTabs.previousActiveTabID == tabID
                let replacementHomeTabID: ContentTabID? = if shouldRestorePreviousActiveTab,
                                                             state.activeTabContentStateMissing,
                                                             let activeTabID = state.contentTabs.activeTabID,
                                                             state.contentTabs.tabs[id: activeTabID]?
                                                             .anchor == .homeDefault
                {
                    activeTabID
                } else {
                    nil
                }
                let shouldResyncContentNavigation = shouldRestorePreviousActiveTab
                let closedTabLoadingCancellationEffect: Effect<Action> = if isActualRemoval {
                    cancelLoadingEffectForClosedTab(
                        tabID: tabID,
                        wasActive: shouldRestorePreviousActiveTab,
                        state: state,
                    )
                } else {
                    .none
                }
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
                }
                syncDashboardProjections(state: &state)
                syncSidebarSelectionForActiveContentTab(state: &state)
                let undoManagerLifecycleEffect: Effect<Action> = if let replacementHomeTabID {
                    replaceUndoManagerScopeEffect(
                        closedTabID: tabID,
                        homeTabID: replacementHomeTabID,
                        state: state,
                    )
                } else if isActualRemoval {
                    deactivateUndoManagerScopeEffect(tabID: tabID, state: state)
                } else {
                    .none
                }
                let handoffEffect: Effect<Action> = .merge(
                    handoffCleanupEffect,
                    activeTabHandoffEffect(
                        shouldResyncContentNavigation,
                        state: &state,
                        aiConnectionsFileClient: aiConnectionsFileClient,
                        skipAiChatCancel: true,
                    ),
                    closeInspectorForActiveAiChatEffect(state: state),
                    undoManagerLifecycleEffect,
                    closedTabLoadingCancellationEffect,
                )
                return handoffEffect

            case .contentTabs(.restore):
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

            case let .applyPinnedContentTabs(contentTabs):
                let activeTabIDBeforeSync = state.contentTabs.activeTabID
                let activeAnchorBeforeSync = activeTabIDBeforeSync.flatMap { state.contentTabs.tabs[id: $0]?.anchor }
                let tabAnchorsBeforeSync = state.contentTabs.tabs.map { (id: $0.id, anchor: $0.anchor) }
                state.applyPinnedContentTabs(contentTabs)
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

            case .contentTabs:
                syncDashboardProjections(state: &state)
                return .none

            case let .closeContentTabRequested(tabID):
                return handleCloseContentTabRequested(tabID: tabID, state: &state)

            case let .contentTabCloseAlertResponse(choice):
                return handleContentTabCloseAlertResponse(choice: choice, state: &state)

            case let .tabContent(tabID, .composer(.internal(.syncCollectionState))):
                guard state.pendingContentTabClose?.tabID == tabID,
                      state.contentTabs.activeTabID == tabID
                else { return .none }
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

            case let .tabContent(tabID, .aiChat(aiChatAction)):
                guard let originContent = fileManagerContentState(for: tabID, state: state) else { return .none }
                refreshAiChatTabTitleFromSessionListIfNeeded(
                    tabID: tabID,
                    action: aiChatAction,
                    originContent: originContent,
                    state: &state,
                )
                let snapshotSessionID = sessionSnapshotSavedSummary(from: aiChatAction)?.sessionID
                let effect = routeBackgroundAiChatAction(aiChatAction, state: &state)
                refreshAiChatFollowUpFromBackgroundIfNeeded(
                    aiChatAction,
                    backgroundAiChat: originContent.aiChat,
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

            case let .backgroundInspectorChatSnapshotPersisted(snapshot):
                handleBackgroundInspectorAiChatSnapshotPersisted(snapshot, state: &state)
                return .none

            case let .tabContent(tabID, .collection(.savePanelResponse(nil))),
                 let .tabContent(tabID, .collection(.writeBackFailed)),
                 let .tabContent(tabID, .collection(.delegate(.saveFeedback))):
                guard let pendingClose = state.pendingContentTabClose,
                      pendingClose.tabID == tabID,
                      state.contentTabs.activeTabID == tabID
                else { return .none }
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

        if targetState.isCollectionMode, targetState.hasUnsavedCollectionChanges {
            state.pendingContentTabClose = PendingContentTabClose(
                tabID: tabID,
                previousActiveTabID: isActiveTarget ? nil : state.contentTabs.activeTabID,
                previousActiveContent: isActiveTarget ? nil : state.content,
                targetContent: isActiveTarget ? nil : targetState,
                previousActiveInspector: isActiveTarget ? nil : state.inspector,
                targetInspector: isActiveTarget ? nil : state.inspectorState(for: tabID),
            )
            let cancelCollectionOpenEffect = isActiveTarget
                ? cancelPendingCollectionOpen(state: &state)
                : .none
            return .concatenate(
                cancelCollectionOpenEffect,
                .run { send in
                    let choice = await collectionAlertClient.showUnsavedNavigationAlert()
                    await send(.contentTabCloseAlertResponse(choice))
                },
            )
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
    let composerCleanupEffect = ComposerFeature()
        .reduce(into: &state.composer, action: .internal(.cleanupCollectionWork))
        .map { FileManagerWindowAction.content(.composer($0)) }
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
    state.entryViewLayout.isCollectionContentLoading = false
    return .merge(composerCleanupEffect, aiChatCleanupEffect)
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

private func cancelLoadingEffectForClosedTab(
    tabID: ContentTabID,
    wasActive: Bool,
    state: FileManagerWindowState,
) -> Effect<FileManagerWindowAction> {
    let closedContent = wasActive ? state.content : state.tabContentStates[tabID]
    guard let closedContent else { return .none }
    let entryOperations = closedContent.entryViewLayout.entryOperations
    return .cancel(id: EntryOperationsLoadingCancelID.loadItems(
        windowID: entryOperations.windowID,
        ownerID: entryOperations.loadingCancellationOwnerID,
    ))
}

private func activeTabHandoffEffect(
    _ shouldResyncContentNavigation: Bool,
    state: inout FileManagerWindowState,
    aiConnectionsFileClient: AIConnectionsFileClient,
    skipAiChatCancel: Bool = false,
) -> Effect<FileManagerWindowAction> {
    guard shouldResyncContentNavigation else {
        return .none
    }
    state.pendingCollectionOpenRequest = nil
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
    let loadingCancellationEffect: Effect<FileManagerWindowAction> = state.contentTabs.previousActiveTabID
        .flatMap { state.tabContentStates[$0] }
        .map { previousContent in
            .cancel(id: EntryOperationsLoadingCancelID.loadItems(
                windowID: previousContent.entryViewLayout.entryOperations.windowID,
                ownerID: previousContent.entryViewLayout.entryOperations.loadingCancellationOwnerID,
            ))
        } ?? .none

    return .merge(
        .cancel(id: OpenCollectionFileCancelID(
            windowID: state.content.entryViewLayout.entryOperations.windowID,
        )),
        loadingCancellationEffect,
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
        await send(.tabContent(
            tabID: activeTabID,
            action: .aiChat(.providerConnectionsUpdated(connectionsFile)),
        ))
    }
    .cancellable(id: HomeAiChatOpenCancelID(tabID: activeTabID), cancelInFlight: true)
}

private func resyncContentNavigationEffect(state: FileManagerWindowState) -> Effect<FileManagerWindowAction> {
    guard let activeTabID = state.contentTabs.activeTabID else { return .none }
    if let collectionURL = collectionFileURLRequiringOpen(state: state) {
        return .send(.navigation(.view(.openCollectionFile(collectionURL))))
    }
    guard let navigationState = resyncNavigationStateForActiveContentTab(state: state) else {
        return .none
    }
    if case let .collection(navigation) = navigationState {
        return .concatenate(
            .send(.tabContent(tabID: activeTabID, action: .internal(.applyNavigationState(.collection(navigation))))),
            .send(.navigation(.internal(.navigateToCollection(navigation)))),
        )
    }
    return .send(.tabContent(tabID: activeTabID, action: .internal(.applyNavigationState(navigationState))))
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
