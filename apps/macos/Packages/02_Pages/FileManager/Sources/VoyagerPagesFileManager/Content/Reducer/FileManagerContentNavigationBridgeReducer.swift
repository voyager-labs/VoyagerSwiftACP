import AppKit
import ComposableArchitecture
import Foundation
import VoyagerEntitiesEntry
import VoyagerFeaturesContentPageNavigation
import VoyagerFeaturesEntryOperations
import VoyagerShared

@Reducer
struct FileManagerContentNavigationBridgeReducer {
    typealias State = FileManagerContentState
    typealias Action = FileManagerContentAction

    private enum CancelID {
        static let folderWatcher = "FileManagerContent.folderWatcher"
        static let systemNotifications = "FileManagerContent.systemNotifications"
    }

    @Dependency(\.entryWatchingClient)
    private var entryWatchingClient
    @Dependency(\.notificationCenterClient)
    private var notificationCenterClient

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .internal(.applyNavigationState(navigationState)):
                let scrollPositionKey = scrollPositionKey(for: navigationState)
                state.entryViewLayout.currentPath = scrollPositionKey
                state.entryViewLayout.savedScrollOffset = state.navigation.scrollPositions[scrollPositionKey]
                return applyNavigationStateEffect(navigationState, state: state)

            case .view(.selectAllEntries):
                return .send(.entryViewLayout(.internal(.applySelectAll(
                    orderedItemIds: state.entryViewLayout.entries.map(\.id),
                ))))

            case .view(.toggleShowHiddenFilesAndReload):
                let showHidden = !state.entryViewLayout.showHiddenFiles
                return .concatenate(
                    .send(.entryViewLayout(.view(.toggleShowHiddenFiles))),
                    FileManagerContentEntryOpsCoordinator.reloadEntryItemsEffect(
                        navigationState: state.navigation.navigationState,
                        showHidden: showHidden,
                    ),
                )

            case .delegate(.openPathInNewWindow),
                 .delegate(.closeWindow):
                return .none

            case let .internal(.saveScrollOffset(offset, forPath: path)):
                state.navigation.scrollPositions[path] = offset
                if path == scrollPositionKey(for: state.navigation.navigationState) {
                    state.entryViewLayout.savedScrollOffset = offset
                }
                return .none

            case .internal(.startObservingSystemNotifications):
                return .run { send in
                    for await _ in await notificationCenterClient.notifications(
                        NSApplication.didBecomeActiveNotification,
                        nil,
                    ) {
                        await send(.internal(.systemAppDidBecomeActive))
                    }
                }
                .cancellable(id: CancelID.systemNotifications, cancelInFlight: true)

            case .internal(.stopObservingSystemNotifications):
                return .merge(
                    .cancel(id: CancelID.systemNotifications),
                    .cancel(id: CancelID.folderWatcher),
                )

            case .internal(.systemAppDidBecomeActive):
                let entryOperationsAction = EntryOperationsAction.lifecycle(.appDidBecomeActive)
                return sendEntryOperations(entryOperationsAction)

            default:
                return .none
            }
        }
    }

    private func scrollPositionKey(for navigationState: ContentPageNavigationRoute) -> String {
        switch navigationState {
        case .home:
            "Home"

        case let .collection(collectionNavigation):
            switch collectionNavigation.kind {
            case .temporary:
                "collection:temporary"
            case let .file(url, _):
                "collection:\(url.standardizedFileURL.path)"
            }

        case let .folder(path):
            path

        case .recents:
            "Recents"

        case let .tags(tagName):
            tagName

        case .computer:
            ""
        }
    }

    private func applyNavigationStateEffect(
        _ navigationState: ContentPageNavigationRoute,
        state: State,
    ) -> Effect<Action> {
        switch navigationState {
        case .home:
            .concatenate(
                .cancel(id: CancelID.folderWatcher),
                .send(.entryViewLayout(.internal(.clearCollectionPresentation))),
                .send(.entryViewLayout(.internal(.applyClearSelection))),
                sendEntryOperations(.loading(.itemsLoaded([]))),
            )

        case let .folder(path):
            .concatenate(
                .send(.entryViewLayout(.internal(.clearCollectionPresentation))),
                sendEntryOperations(.loading(.loadItems(
                    path: path,
                    showHidden: state.entryViewLayout.showHiddenFiles,
                ))),
                observeFolderChangesEffect(path: path),
            )

        case .recents:
            .concatenate(
                .cancel(id: CancelID.folderWatcher),
                .send(.entryViewLayout(.internal(.clearCollectionPresentation))),
                sendEntryOperations(.loading(.loadRecentItems(
                    showHidden: state.entryViewLayout.showHiddenFiles,
                ))),
            )

        case let .tags(tagName):
            .concatenate(
                .cancel(id: CancelID.folderWatcher),
                .send(.entryViewLayout(.internal(.clearCollectionPresentation))),
                sendEntryOperations(.loading(.loadTagItems(
                    tagName: tagName,
                    showHidden: state.entryViewLayout.showHiddenFiles,
                ))),
            )

        case .computer:
            .concatenate(
                .cancel(id: CancelID.folderWatcher),
                .send(.entryViewLayout(.internal(.clearCollectionPresentation))),
                sendEntryOperations(.loading(.loadComputerItems)),
            )

        case .collection:
            .cancel(id: CancelID.folderWatcher)
        }
    }

    private func observeFolderChangesEffect(path: String) -> Effect<Action> {
        let url = URL(fileURLWithPath: path)
        return .run { [entryWatchingClient] send in
            for await changedPaths in entryWatchingClient.startWatchingDirectory(url) {
                await send(.externalFileSystemChanged(changedPaths))
            }
        }
        .cancellable(id: CancelID.folderWatcher, cancelInFlight: true)
    }

    private func sendEntryOperations(_ action: EntryOperationsAction) -> Effect<Action> {
        .send(.entryViewLayout(.entryOperations(action)))
    }
}
