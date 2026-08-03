import AppKit
import ComposableArchitecture
import Foundation
import VoyagerEntitiesAi
import VoyagerEntitiesCollection
import VoyagerEntitiesEntry
import VoyagerFeaturesContentPageNavigation
import VoyagerFeaturesEntryOperations
import VoyagerShared

@Reducer
struct FileManagerContentNavigationBridgeReducer {
    typealias State = FileManagerContentState
    typealias Action = FileManagerContentAction

    private enum CancelID: Hashable {
        case folderWatcher(windowID: UUID?)
        case systemNotifications(windowID: UUID?)
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
                 .delegate(.closeWindow):
                return .none

            case let .internal(.saveScrollOffset(offset, forPath: path)):
                state.navigation.scrollPositions[path] = offset
                if path == scrollPositionKey(for: state.navigation.navigationState) {
                    state.entryViewLayout.savedScrollOffset = offset
                }
                return .none

            case .internal(.startObservingSystemNotifications):
                let cancelID = CancelID.systemNotifications(windowID: cancellationWindowID(state))
                return .run { send in
                    for await _ in await notificationCenterClient.notifications(
                        NSApplication.didBecomeActiveNotification,
                        nil,
                    ) {
                        await send(.internal(.systemAppDidBecomeActive))
                    }
                }
                .cancellable(id: cancelID, cancelInFlight: true)

            case .internal(.stopObservingSystemNotifications):
                let windowID = cancellationWindowID(state)
                return .merge(
                    .cancel(id: CancelID.systemNotifications(windowID: windowID)),
                    .cancel(id: CancelID.folderWatcher(windowID: windowID)),
                )

            case .internal(.systemAppDidBecomeActive):
                let entryOperationsAction = EntryOperationsAction.lifecycle(.appDidBecomeActive)
                return sendEntryOperations(entryOperationsAction)

            default:
                return .none
            }
        }
    }

    private func cancellationWindowID(_ state: State) -> UUID? {
        state.entryViewLayout.entryOperations.windowID
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

        case let .aiChat(sessionID):
            "aiChat:\(sessionID)"

        case let .aiChatSessions(sessionID):
            "aiChatSessions:\(sessionID)"
        }
    }

    private func applyNavigationStateEffect(
        _ navigationState: ContentPageNavigationRoute,
        state: State,
    ) -> Effect<Action> {
        let windowID = cancellationWindowID(state)
        return switch navigationState {
        case .home:
            .concatenate(
                .cancel(id: CancelID.folderWatcher(windowID: windowID)),
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
                observeFolderChangesEffect(path: path, windowID: windowID),
            )

        case .recents:
            .concatenate(
                .cancel(id: CancelID.folderWatcher(windowID: windowID)),
                .send(.entryViewLayout(.internal(.clearCollectionPresentation))),
                sendEntryOperations(.loading(.loadRecentItems(
                    showHidden: state.entryViewLayout.showHiddenFiles,
                ))),
            )

        case let .tags(tagName):
            .concatenate(
                .cancel(id: CancelID.folderWatcher(windowID: windowID)),
                .send(.entryViewLayout(.internal(.clearCollectionPresentation))),
                sendEntryOperations(.loading(.loadTagItems(
                    tagName: tagName,
                    showHidden: state.entryViewLayout.showHiddenFiles,
                ))),
            )

        case .computer:
            .concatenate(
                .cancel(id: CancelID.folderWatcher(windowID: windowID)),
                .send(.entryViewLayout(.internal(.clearCollectionPresentation))),
                sendEntryOperations(.loading(.loadComputerItems)),
            )

        case .collection:
            observeCollectionScopeChangesEffect(state: state, windowID: windowID)

        case let .aiChat(sessionID):
            aiChatEntryRouteEffect(aiChatRouteEffect(sessionID: sessionID, windowID: windowID))

        case let .aiChatSessions(sessionID):
            aiChatEntryRouteEffect(aiChatSessionsRouteEffect(sessionID: sessionID, windowID: windowID))
        }
    }

    private func aiChatEntryRouteEffect(_ routeEffect: Effect<Action>) -> Effect<Action> {
        .concatenate(
            .send(.entryViewLayout(.internal(.clearCollectionPresentation))),
            .send(.entryViewLayout(.internal(.applyClearSelection))),
            sendEntryOperations(.loading(.itemsLoaded([]))),
            routeEffect,
        )
    }

    private func aiChatRouteEffect(
        sessionID: String,
        windowID: UUID?,
    ) -> Effect<Action> {
        let aiChatSessionID = AiChatSessionID(rawValue: UUID(uuidString: sessionID) ?? UUID())
        return .merge(
            .cancel(id: CancelID.folderWatcher(windowID: windowID)),
            .send(.aiChat(.routeToChatSession(aiChatSessionID))),
        )
    }

    private func aiChatSessionsRouteEffect(
        sessionID: String,
        windowID: UUID?,
    ) -> Effect<Action> {
        let aiChatSessionID = AiChatSessionID(rawValue: UUID(uuidString: sessionID) ?? UUID())
        return .merge(
            .cancel(id: CancelID.folderWatcher(windowID: windowID)),
            .send(.aiChat(.showSessionsForChat(aiChatSessionID))),
        )
    }

    private func observeFolderChangesEffect(
        path: String,
        windowID: UUID?,
    ) -> Effect<Action> {
        let interest = FileChangeWatchInterest(
            id: "visible-folder:\(UUID().uuidString)",
            owner: .fileManager,
            purpose: .visibleFolderReload,
            roots: [path],
            includeSubfolders: true,
        )
        return observeGatewayChangesEffect(interest: interest, windowID: windowID)
    }

    private func observeCollectionScopeChangesEffect(
        state: State,
        windowID: UUID?,
    ) -> Effect<Action> {
        observeCollectionScopeChangesEffect(
            context: state.collection.collectionContext,
            openedURL: state.collection.collectionSession.document?.url,
            windowID: windowID,
        )
    }

    private func observeCollectionScopeChangesEffect(
        context: CollectionContext?,
        openedURL: URL?,
        windowID: UUID?,
    ) -> Effect<Action> {
        guard let context else {
            return .cancel(id: CancelID.folderWatcher(windowID: windowID))
        }
        let roots = collectionScopeWatchRoots(from: context)
        guard !roots.isEmpty else {
            return .cancel(id: CancelID.folderWatcher(windowID: windowID))
        }

        let interest = FileChangeWatchInterest(
            id: "collection-stale:\(UUID().uuidString)",
            owner: .collection,
            purpose: .collectionStale,
            roots: roots,
            includeSubfolders: context.includeSubfolders,
            excludedRoots: context.excludedScopes,
        )
        return observeGatewayChangesEffect(
            interest: interest,
            windowID: windowID,
            openedURL: openedURL,
        )
    }

    private func observeGatewayChangesEffect(
        interest: FileChangeWatchInterest,
        windowID: UUID?,
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
        .cancellable(id: CancelID.folderWatcher(windowID: windowID), cancelInFlight: true)
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
