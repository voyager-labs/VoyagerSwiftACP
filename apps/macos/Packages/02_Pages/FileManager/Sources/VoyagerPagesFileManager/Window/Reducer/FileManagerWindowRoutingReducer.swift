import AppKit
import ComposableArchitecture
import Foundation
import VoyagerEntitiesAi
import VoyagerEntitiesCollection
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
                if shouldResyncContentNavigation {
                    prepareContentForActiveTabHandoff(state: &state.content)
                    state.saveCurrentContentStateForPreviousActiveTab()
                    state.restoreContentStateForActiveTab()
                }
                state.syncContentTabSidebarItems()
                syncSidebarSelectionForActiveContentTab(state: &state)
                return .merge(
                    activeTabHandoffEffect(
                        shouldResyncContentNavigation,
                        state: state,
                        aiConnectionsFileClient: aiConnectionsFileClient,
                    ),
                    closeInspectorForActiveAiChatEffect(state: state),
                )

            case .contentTabs(.open):
                if keepPendingContentTabCloseFocusedAfterOpen(state: &state) {
                    return .none
                }
                let shouldResyncContentNavigation = state.contentTabs.previousActiveTabID != nil
                    || state.activeTabContentStateMissing
                if shouldResyncContentNavigation {
                    prepareContentForActiveTabHandoff(state: &state.content)
                    state.saveCurrentContentStateForPreviousActiveTab()
                    if state.activeTabContentStateMissing {
                        let activeAnchor = state.contentTabs.activeTabID
                            .flatMap { state.contentTabs.tabs[id: $0]?.anchor }
                        state.content = contentState(for: activeAnchor, inheritingWindowContextFrom: state.content)
                        state.syncActiveTabContentState()
                    }
                }
                state.syncContentTabSidebarItems()
                syncSidebarSelectionForActiveContentTab(state: &state)
                return .merge(
                    activeTabHandoffEffect(
                        shouldResyncContentNavigation,
                        state: state,
                        aiConnectionsFileClient: aiConnectionsFileClient,
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
                let isAiChatProcessingTabClose = shouldResyncContentNavigation
                    && (state.content.aiChat.executionPhase.isProcessing
                        || state.content.aiChat.pendingRequestStart != nil)
                if isRemovedTab {
                    state.recentlyClosedNavigationRoute = navigationRouteForClosingTab(tabID, state: state)
                }
                if shouldResyncContentNavigation {
                    if isAiChatProcessingTabClose {
                        if let aiChatSessionID = state.content.aiChat.sessionID {
                            state.addBackgroundAiChatState(sessionID: aiChatSessionID, state: state.content)
                        }
                        prepareContentForActiveTabHandoff(state: &state.content, skipAiChatCleanup: true)
                    } else {
                        prepareContentForActiveTabHandoff(state: &state.content)
                    }
                }
                if isRemovedTab {
                    state.removeContentState(for: tabID)
                    if shouldRestorePreviousActiveTab {
                        state.restoreContentStateForActiveTab()
                    }
                } else if shouldResetLastTabContent {
                    state.content = contentState(
                        for: state.contentTabs.tabs[id: tabID]?.anchor,
                        inheritingWindowContextFrom: state.content,
                    )
                    state.syncActiveTabContentState()
                    shouldCloseWindow = true
                }
                state.syncContentTabSidebarItems()
                syncSidebarSelectionForActiveContentTab(state: &state)
                let handoffEffect: Effect<Action> = .merge(
                    activeTabHandoffEffect(
                        shouldResyncContentNavigation,
                        state: state,
                        aiConnectionsFileClient: aiConnectionsFileClient,
                        skipAiChatCancel: isAiChatProcessingTabClose,
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
                if shouldResyncContentNavigation {
                    prepareContentForActiveTabHandoff(state: &state.content)
                    state.saveCurrentContentStateForPreviousActiveTab()
                    state.restoreContentStateForActiveTab()
                    if let restoredRoute = state.recentlyClosedNavigationRoute {
                        state.content.navigation.navigationState = restoredRoute
                        state.syncActiveTabContentState()
                        state.recentlyClosedNavigationRoute = nil
                    }
                }
                state.syncContentTabSidebarItems()
                syncSidebarSelectionForActiveContentTab(state: &state)
                return .merge(
                    activeTabHandoffEffect(
                        shouldResyncContentNavigation,
                        state: state,
                        aiConnectionsFileClient: aiConnectionsFileClient,
                    ),
                    closeInspectorForActiveAiChatEffect(state: state),
                )

            case let .applyPinnedContentTabs(contentTabs):
                let activeTabIDBeforeSync = state.contentTabs.activeTabID
                let activeAnchorBeforeSync = activeTabIDBeforeSync.flatMap { state.contentTabs.tabs[id: $0]?.anchor }
                state.applyPinnedContentTabs(contentTabs)
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

            case .contentTabs:
                state.syncContentTabSidebarItems()
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

            case let .content(.aiChat(aiChatAction)):
                return routeBackgroundAiChatAction(aiChatAction, state: &state)

            case let .backgroundAiChat(aiChatAction):
                return routeBackgroundAiChatAction(aiChatAction, state: &state)

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

        if targetState.isCollectionMode, targetState.canSaveCollection {
            state.pendingContentTabClose = PendingContentTabClose(
                tabID: tabID,
                previousActiveTabID: isActiveTarget ? nil : state.contentTabs.activeTabID,
                previousActiveContent: isActiveTarget ? nil : state.content,
                targetContent: isActiveTarget ? nil : targetState,
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
            state.contentTabs.previousActiveTabID = previousActiveTabID
            state.contentTabs.activeTabID = pendingClose.tabID
        }
        state.content = targetContent
        state.syncActiveTabContentState()
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
        }
        state.content = previousActiveContent
        if let previousActiveTabID = pendingClose.previousActiveTabID {
            state.contentTabs.previousActiveTabID = pendingClose.tabID
            state.contentTabs.activeTabID = previousActiveTabID
            state.tabContentStates[previousActiveTabID] = previousActiveContent
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
) {
    clearInFlightComposerStateOnTabSwitch(state: &state.composer)
    if !skipAiChatCleanup {
        clearInFlightAiChatStateOnTabSwitch(state: &state.aiChat)
    }
    state.entryViewLayout.entryOperations.isLoading = false
    state.entryViewLayout.entryOperations.isReloading = false
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

private func routeBackgroundAiChatAction(
    _ aiChatAction: AiChatAction,
    state: inout FileManagerWindowState,
) -> Effect<FileManagerWindowAction> {
    guard let sessionID = backgroundAiChatSessionID(for: aiChatAction, state: state),
          var backgroundContent = state.backgroundAiChatStates[sessionID]
    else { return .none }

    let effect = AiChatFeature()
        .reduce(into: &backgroundContent.aiChat, action: aiChatAction)
        .map { FileManagerWindowAction.backgroundAiChat($0) }

    if shouldRemoveBackgroundAiChatState(after: aiChatAction) {
        state.removeBackgroundAiChatState(sessionID: sessionID)
    } else {
        state.backgroundAiChatStates[sessionID] = backgroundContent
    }

    return effect
}

private func backgroundAiChatSessionID(
    for aiChatAction: AiChatAction,
    state: FileManagerWindowState,
) -> AiChatSessionID? {
    switch aiChatAction {
    case let .executionEvent(event):
        aiChatEventSessionID(event)
    case let .persistenceFailed(lock, _),
         let .persistenceRecoverySucceeded(lock),
         let .persistenceRecoveryRetryFailed(lock, _):
        lock.context.sessionID
    case let .sessionSnapshotSaved(summary):
        summary.sessionID
    case .cancelInFlightWork:
        state.backgroundAiChatStates.keys.first
    default:
        nil
    }
}

private func shouldRemoveBackgroundAiChatState(after aiChatAction: AiChatAction) -> Bool {
    switch aiChatAction {
    case let .executionEvent(event):
        if case .failed = event { true } else { false }
    case .sessionSnapshotSaved,
         .persistenceRecoverySucceeded,
         .persistenceRecoveryRetryFailed,
         .cancelInFlightWork:
        true
    default:
        false
    }
}
