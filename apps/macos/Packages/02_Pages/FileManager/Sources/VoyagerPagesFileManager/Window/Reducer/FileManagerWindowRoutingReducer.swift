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

struct SelectedContentTabPinMutationOperationCancelID: Hashable {
    let operationID: UUID
}

@discardableResult
private func applyExternalPendingSelection(
    _ pendingSelectEntryID: String?,
    tabID: ContentTabID,
    anchor: ContentTabPageAnchor,
    pinnedAnchor: (ContentPageNavigationRoute) -> ContentTabPageAnchor?,
    state: inout FileManagerWindowState,
) -> Bool {
    guard let pendingSelectEntryID else { return false }
    let isActiveTab = state.contentTabs.activeTabID == tabID
    if isActiveTab {
        state.content.pendingSelectEntryID = pendingSelectEntryID
        let alreadyOnRoute = pinnedAnchor(state.content.navigation.navigationState) == anchor
        if alreadyOnRoute {
            let didApply = state.content.consumeExternalPendingSelectionIfAlreadyLoaded()
            state.syncActiveTabContentState()
            return didApply
        }
        state.syncActiveTabContentState()
        return false
    }
    var contentState = state.tabContentStates[tabID]
        ?? FileManagerContentFeature.State.initialContent(
            for: anchor,
            inheritingWindowContextFrom: state.content,
        )
    contentState.pendingSelectEntryID = pendingSelectEntryID
    let alreadyOnRoute = pinnedAnchor(contentState.navigation.navigationState) == anchor
    if alreadyOnRoute {
        let didApply = contentState.consumeExternalPendingSelectionIfAlreadyLoaded()
        state.tabContentStates[tabID] = contentState
        return didApply
    }
    state.tabContentStates[tabID] = contentState
    return false
}

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
    @Dependency(\.undoManagerClient)
    var undoManagerClient
    @Dependency(\.contentTabPinnedRecordClient)
    var contentTabPinnedRecordClient
    @Dependency(\.uuid)
    var uuid
    @Dependency(\.fileOperationUndoManagerClient)
    var fileOperationUndoManagerClient

    func cannotPinCollectionFeedbackEffect() -> Effect<Action> {
        let collectionAlertClient = collectionAlertClient
        return .run { _ in
            await collectionAlertClient.showCollectionOpenErrorAlert(
                "Cannot Pin Collection",
                "Save the collection before pinning it as a tab.",
            )
        }
    }

    func brokenPinnedTabFeedbackEffect(tabID: ContentTabID, state: State) -> Effect<Action> {
        guard let anchor = state.contentTabs.pinnedRecords[tabID]?.anchor,
              isBrokenPinnedAnchor(anchor)
        else { return .none }

        let collectionAlertClient = collectionAlertClient
        return .run { _ in
            await collectionAlertClient.showCollectionOpenErrorAlert(
                "Pinned Location Unavailable",
                "The pinned item no longer exists. Navigate to a valid location to update this pinned tab.",
            )
        }
    }

    func selectContentTabEffect(tabID: ContentTabID, state: inout State) -> Effect<Action> {
        let activationEffect = Effect<Action>.concatenate(
            .send(.contentTabs(.setCurrent(tabID))),
            .send(.contentTabs(.collapseSelectionToActive)),
        )
        guard state.contentTabs.activeTabID == tabID,
              state.contentTabs.tabs[id: tabID]?.isPinned == true,
              let record = state.contentTabs.pinnedRecords[tabID],
              record.isSupportedPinnedContentTab
        else { return activationEffect }
        return returnActiveContentTabToPinnedLocationEffect(
            tabID: tabID,
            record: record,
            leadingEffect: activationEffect,
            state: &state,
        )
    }

    func returnContentTabToPinnedLocationEffect(
        tabID: ContentTabID,
        pendingSelectEntryID: String?,
        activateIfNeeded: Bool,
        state: inout State,
    ) -> Effect<Action> {
        guard state.contentTabs.tabs[id: tabID]?.isPinned == true,
              let record = state.contentTabs.pinnedRecords[tabID],
              record.isSupportedPinnedContentTab
        else { return .none }

        guard state.contentTabs.activeTabID == tabID else {
            if activateIfNeeded {
                return .concatenate(
                    .send(.contentTabs(.setCurrent(tabID))),
                    .send(.returnContentTabToPinnedLocation(
                        tabID,
                        pendingSelectEntryID: pendingSelectEntryID,
                    )),
                )
            }
            return returnInactiveContentTabToPinnedLocationWithoutActivation(
                tabID: tabID,
                record: record,
                pendingSelectEntryID: pendingSelectEntryID,
                state: &state,
            )
        }

        return returnActiveContentTabToPinnedLocationEffect(
            tabID: tabID,
            record: record,
            leadingEffect: .none,
            state: &state,
            pendingSelectEntryID: pendingSelectEntryID,
        )
    }

    private func returnActiveContentTabToPinnedLocationEffect(
        tabID: ContentTabID,
        record: ContentTabPinnedRecord,
        leadingEffect: Effect<Action>,
        state: inout State,
        pendingSelectEntryID: String? = nil,
    ) -> Effect<Action> {
        if let pendingSelectEntryID {
            let request = ExternalContentTabReservation(
                id: tabID,
                anchor: record.anchor,
                pendingSelectEntryID: pendingSelectEntryID,
            )
            guard request.isValidExternalReservation else { return .none }
        }
        guard !isBrokenPinnedAnchor(record.anchor) else {
            return abortPinnedReturn(
                leadingEffect: leadingEffect,
                tabID: tabID,
                feedback: true,
                state: &state,
            )
        }
        if case let .collectionFile(url) = record.anchor,
           contentTabAnchor(
               for: state.content.navigation.navigationState,
               computerName: fileManagerClient.displayName("/"),
           ) != record.anchor
        {
            guard !state.content.hasUnsavedCollectionChanges else {
                return abortPinnedReturn(
                    leadingEffect: leadingEffect,
                    tabID: tabID,
                    feedback: false,
                    state: &state,
                )
            }
            return .concatenate(
                leadingEffect,
                .send(.navigation(.view(.openCollectionFile(url)))),
            )
        }
        let navigationState = contentState(
            for: record.anchor,
            inheritingWindowContextFrom: state.content,
        ).navigation.navigationState
        return .concatenate(
            leadingEffect,
            .send(.applyPinnedContentTabRuntimeNavigation(
                tabID: tabID,
                navigationState: navigationState,
                pendingSelectEntryID: pendingSelectEntryID,
            )),
        )
    }

    func isBrokenPinnedAnchor(_ anchor: ContentTabPageAnchor) -> Bool {
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

    func syncDashboardProjections(state: inout State) {
        state.syncContentTabSidebarItems()
        state.syncHomeLocationItems()
        state.syncHomeFavoriteItems()
    }

    func applyPinnedContentTabRuntimeNavigation(
        tabID: ContentTabID,
        navigationState: ContentPageNavigationRoute,
        pendingSelectEntryID: String?,
        state: inout State,
    ) -> Effect<Action> {
        guard let tab = state.contentTabs.tabs[id: tabID],
              tab.isPinned,
              let anchor = pinnedAnchor(for: navigationState)
        else { return .none }

        let isActiveTab = state.contentTabs.activeTabID == tabID
        let didApplyLoadedSelection = applyExternalPendingSelection(
            pendingSelectEntryID,
            tabID: tabID,
            anchor: anchor,
            pinnedAnchor: { pinnedAnchor(for: $0) },
            state: &state,
        )
        let selectionChangedEffect: Effect<Action> = isActiveTab && didApplyLoadedSelection
            ? .send(.content(.entryViewLayout(.delegate(.selectionChanged))))
            : .none
        let targetContentState: FileManagerContentState? = isActiveTab ? state.content : state.tabContentStates[tabID]
        let currentNavigationState = targetContentState?.navigation.navigationState
        let currentAnchor = currentNavigationState.flatMap(pinnedAnchor)
        if anchor.isCollectionFileAnchor, currentAnchor == anchor {
            return isActiveTab
                ? .concatenate(cancelPendingCollectionOpen(state: &state), selectionChangedEffect)
                : selectionChangedEffect
        }
        guard targetContentState?.hasUnsavedCollectionChanges != true else { return selectionChangedEffect }
        return applyPinnedReturnNavigationEffects(
            tabID: tabID,
            navigationState: navigationState,
            selectionChangedEffect: selectionChangedEffect,
            state: &state,
        )
    }

    private func applyPinnedReturnNavigationEffects(
        tabID: ContentTabID,
        navigationState: ContentPageNavigationRoute,
        selectionChangedEffect: Effect<Action>,
        state: inout State,
    ) -> Effect<Action> {
        guard let tab = state.contentTabs.tabs[id: tabID],
              let anchor = pinnedAnchor(for: navigationState)
        else { return selectionChangedEffect }
        let isActiveTab = state.contentTabs.activeTabID == tabID
        let targetContentState = isActiveTab ? state.content : state.tabContentStates[tabID]
        let currentNavigationState = targetContentState?.navigation.navigationState
        let shouldResetCollectionMode = targetContentState?.isCollectionMode == true
            && !navigationState.isCollection
        let cancelCollectionOpenEffect = isActiveTab ? cancelPendingCollectionOpen(state: &state) : .none
        let resetCollectionModeEffect = if isActiveTab, shouldResetCollectionMode {
            resetComposerAndClearCollectionModeEffect()
        } else {
            Effect<Action>.none
        }
        if isActiveTab, currentNavigationState == navigationState {
            return .concatenate(cancelCollectionOpenEffect, resetCollectionModeEffect, selectionChangedEffect)
        }
        guard currentNavigationState != navigationState || shouldResetCollectionMode else {
            return selectionChangedEffect
        }
        guard isActiveTab else {
            return .concatenate(
                selectionChangedEffect,
                applyPinnedContentTabRuntimeNavigationToInactiveTab(
                    tabID: tabID,
                    anchor: anchor,
                    navigationState: navigationState,
                    shouldResetCollectionMode: shouldResetCollectionMode,
                    state: &state,
                ),
            )
        }
        return .concatenate(
            selectionChangedEffect,
            cancelCollectionOpenEffect,
            resetCollectionModeEffect,
            tab.anchor == anchor
                ? .none
                : .send(.contentTabs(.updateRuntimePageAnchor(tabID, anchor))),
            .send(.navigation(.internal(.applyPinnedPeerNavigationState(navigationState)))),
            handleNavigateToState(navigationState, state: &state),
        )
    }

    private func pinnedAnchor(for navigationState: ContentPageNavigationRoute) -> ContentTabPageAnchor? {
        contentTabAnchor(
            for: navigationState,
            computerName: fileManagerClient.displayName("/"),
        )
    }

    private func abortPinnedReturn(
        leadingEffect: Effect<Action>,
        tabID: ContentTabID,
        feedback: Bool,
        state: inout State,
    ) -> Effect<Action> {
        .concatenate(
            leadingEffect,
            cancelPendingCollectionOpen(state: &state),
            feedback ? brokenPinnedTabFeedbackEffect(tabID: tabID, state: state) : .none,
            .send(.delegate(.pinnedContentTabRuntimeNavigationFailed(tabID: tabID))),
        )
    }

    private func returnInactiveContentTabToPinnedLocationWithoutActivation(
        tabID: ContentTabID,
        record: ContentTabPinnedRecord,
        pendingSelectEntryID: String?,
        state: inout State,
    ) -> Effect<Action> {
        if let pendingSelectEntryID {
            let request = ExternalContentTabReservation(
                id: tabID,
                anchor: record.anchor,
                pendingSelectEntryID: pendingSelectEntryID,
            )
            guard request.isValidExternalReservation else { return .none }
        }
        guard !isBrokenPinnedAnchor(record.anchor) else {
            return abortPinnedReturn(
                leadingEffect: .none,
                tabID: tabID,
                feedback: true,
                state: &state,
            )
        }
        let navigationState = contentState(
            for: record.anchor,
            inheritingWindowContextFrom: state.content,
        ).navigation.navigationState
        return applyPinnedContentTabRuntimeNavigation(
            tabID: tabID,
            navigationState: navigationState,
            pendingSelectEntryID: pendingSelectEntryID,
            state: &state,
        )
    }

    private func applyPinnedContentTabRuntimeNavigationToInactiveTab(
        tabID: ContentTabID,
        anchor: ContentTabPageAnchor,
        navigationState: ContentPageNavigationRoute,
        shouldResetCollectionMode: Bool,
        state: inout State,
    ) -> Effect<Action> {
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
        let tabAnchor = state.contentTabs.tabs[id: tabID]?.anchor
        return tabAnchor == anchor
            ? .none
            : .send(.contentTabs(.updateRuntimePageAnchor(tabID, anchor)))
    }

    func undoManagerScope(tabID: ContentTabID, state: State) -> UndoManagerScope? {
        guard let windowID = state.windowID else { return nil }
        return UndoManagerScope(windowID: windowID, contentTabID: tabID.rawValue)
    }

    func activateUndoManagerScopeEffect(tabID: ContentTabID, state: State) -> Effect<Action> {
        guard let scope = undoManagerScope(tabID: tabID, state: state) else { return .none }
        _ = fileOperationUndoManagerClient.activate(scope)
        return .none
    }

    func deactivateUndoManagerScopeEffect(tabID: ContentTabID, state: State) -> Effect<Action> {
        guard let scope = undoManagerScope(tabID: tabID, state: state) else { return .none }
        fileOperationUndoManagerClient.deactivate(scope)
        return .none
    }

    func replaceUndoManagerScopeEffect(
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

    func reconcileUndoManagerScopesEffect(
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

    var body: some ReducerOf<Self> {
        routingBody
    }
}
