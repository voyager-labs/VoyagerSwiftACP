import AppKit
import ComposableArchitecture
import Foundation
import VoyagerEntitiesCollection
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

    @Dependency(\.collectionStalenessClient)
    private var collectionStalenessClient
    @Dependency(\.fileChangeGatewayClient)
    private var fileChangeGatewayClient
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
                 .delegate(.openPathInNewTab),
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
            observeCollectionScopeChangesEffect(
                context: state.collection.collectionContext,
                openedURL: state.collection.collectionSession.document?.url,
            )
        }
    }

    private func observeFolderChangesEffect(path: String) -> Effect<Action> {
        let interest = FileChangeWatchInterest(
            id: "visible-folder:\(UUID().uuidString)",
            owner: .fileManager,
            purpose: .visibleFolderReload,
            roots: [path],
            includeSubfolders: true,
        )
        return observeGatewayChangesEffect(interest: interest)
    }

    private func observeCollectionScopeChangesEffect(
        context: CollectionContext?,
        openedURL: URL?,
    ) -> Effect<Action> {
        guard let context else {
            return .cancel(id: CancelID.folderWatcher)
        }
        let roots = collectionScopeWatchRoots(from: context)
        guard !roots.isEmpty else {
            return .cancel(id: CancelID.folderWatcher)
        }

        let interest = FileChangeWatchInterest(
            id: "collection-stale:\(UUID().uuidString)",
            owner: .collection,
            purpose: .collectionStale,
            roots: roots,
            includeSubfolders: context.includeSubfolders,
            excludedRoots: context.excludedScopes,
        )
        return observeGatewayChangesEffect(interest: interest, openedURL: openedURL)
    }

    private func observeGatewayChangesEffect(
        interest: FileChangeWatchInterest,
        openedURL: URL? = nil,
    ) -> Effect<Action> {
        let collectionStalenessClient = collectionStalenessClient
        return .run { [fileChangeGatewayClient] send in
            fileChangeGatewayClient.updateInterests([interest])
            await withTaskCancellationHandler {
                for await events in fileChangeGatewayClient.observeEvents() {
                    let changedPaths = gatewayRelevantChangedPaths(events, interest: interest, openedURL: openedURL)
                    guard !changedPaths.isEmpty else { continue }

                    if interest.purpose == .collectionStale {
                        collectionStalenessClient.invalidateRecords(changedPaths)
                    }
                    await send(.externalFileSystemChanged(changedPaths))
                }
                fileChangeGatewayClient.removeInterests([interest.id])
            } onCancel: {
                fileChangeGatewayClient.removeInterests([interest.id])
            }
        }
        .cancellable(id: CancelID.folderWatcher, cancelInFlight: true)
    }

    private func sendEntryOperations(_ action: EntryOperationsAction) -> Effect<Action> {
        .send(.entryViewLayout(.entryOperations(action)))
    }
}

nonisolated func collectionScopeWatchRoots(from context: CollectionContext?) -> [String] {
    guard let context else { return [] }
    return FileChangeScopePolicy.allowedWatchRoots(from: context.scopes)
}

nonisolated func gatewayRelevantChangedPaths(
    _ events: [FileChangeGatewayEvent],
    interest: FileChangeWatchInterest,
    openedURL: URL?,
) -> [String] {
    collectionRelevantChangedPaths(
        FileChangeScopePolicy.interestAffectedPaths(events: events, interest: interest),
        openedURL: openedURL,
    )
}

nonisolated func collectionRelevantChangedPaths(_ paths: [String], openedURL: URL?) -> [String] {
    guard let openedURL else { return paths }
    let normalizedOpenedPath = openedURL.standardizedFileURL.path
    return paths.filter { path in
        let normalizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
        if normalizedPath == normalizedOpenedPath {
            return false
        }
        let packagePrefix = normalizedOpenedPath == "/" ? "/" : normalizedOpenedPath + "/"
        return !normalizedPath.hasPrefix(packagePrefix)
    }
}
