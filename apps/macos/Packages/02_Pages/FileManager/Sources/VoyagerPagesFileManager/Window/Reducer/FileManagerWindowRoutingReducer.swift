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

    func cancelPendingCollectionOpen(state: inout State) -> Effect<Action> {
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
