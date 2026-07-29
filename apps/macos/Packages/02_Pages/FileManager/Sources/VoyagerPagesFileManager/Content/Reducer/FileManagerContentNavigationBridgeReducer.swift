import AppKit
import ComposableArchitecture
import Foundation
import VoyagerEntitiesAi
import VoyagerEntitiesCollection
import VoyagerEntitiesEntry
import VoyagerFeaturesContentPageNavigation
import VoyagerFeaturesEntryArrangements
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
                if case .folder = navigationState {
                    state.entryViewLayout.entryOperations.isReloading = !state.entryViewLayout.entryOperations.items
                        .isEmpty
                }
                return applyNavigationStateEffect(navigationState, state: state)

            case .view(.selectAllEntries):
                return .send(.entryViewLayout(.internal(.applySelectAll(
                    orderedItemIds: state.entryViewLayout.visibleSelectableEntryIDs(
                        isNormalDirectoryPage: isNormalDirectoryPage(state.navigation.navigationState),
                    ),
                ))))

            case .view(.toggleShowHiddenFilesAndReload):
                let showHidden = !state.entryViewLayout.showHiddenFiles
                return .concatenate(
                    .send(.entryViewLayout(.view(.toggleShowHiddenFiles))),
                    FileManagerContentEntryOpsCoordinator.reloadEntryItemsEffect(
                        navigationState: state.navigation.navigationState,
                        showHidden: showHidden,
                        priority: FileManagerContentEntryOpsCoordinator.rootMetadataPriority(
                            for: state.entryViewLayout.entryArrangements,
                        ),
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

        case let .aiChat(sessionID):
            "aiChat:\(sessionID)"

        case let .aiChatSessions(sessionID):
            "aiChatSessions:\(sessionID)"
        }
    }

    private func isNormalDirectoryPage(_ navigationState: ContentPageNavigationRoute) -> Bool {
        if case .folder = navigationState {
            return true
        }
        return false
    }

    private func applyNavigationStateEffect(
        _ navigationState: ContentPageNavigationRoute,
        state: State,
    ) -> Effect<Action> {
        let rootContextChange = Effect<Action>.send(.entryViewLayout(.hierarchy(.rootContextChanged(
            path: hierarchyRootPath(for: navigationState),
        ))))
        let cancelRootLoad: Effect<Action> = .cancel(
            id: EntryOperationsLoadingCancelID.loadItems(
                windowID: state.entryViewLayout.entryOperations.windowID,
                ownerID: state.entryViewLayout.entryOperations.loadingCancellationOwnerID,
            ),
        )
        return switch navigationState {
        case .home: homeRouteEffect(rootContextChange: rootContextChange)
        case let .folder(path): folderRouteEffect(path: path, state: state, rootContextChange: rootContextChange)
        case .recents: recentsRouteEffect(
                state: state,
                rootContextChange: rootContextChange,
                cancelRootLoad: cancelRootLoad,
            )
        case let .tags(tagName): tagsRouteEffect(
                tagName: tagName,
                state: state,
                rootContextChange: rootContextChange,
                cancelRootLoad: cancelRootLoad,
            )
        case .computer: computerRouteEffect(
                rootContextChange: rootContextChange,
                cancelRootLoad: cancelRootLoad,
            )
        case .collection: collectionRouteEffect(state: state, rootContextChange: rootContextChange)
        case let .aiChat(sessionID): aiChatRouteEffect(
                sessionID: sessionID,
                rootContextChange: rootContextChange,
            )
        case let .aiChatSessions(sessionID): aiChatSessionsRouteEffect(
                sessionID: sessionID,
                rootContextChange: rootContextChange,
            )
        }
    }

    private func homeRouteEffect(
        rootContextChange: Effect<Action>,
    ) -> Effect<Action> {
        .concatenate(
            rootContextChange,
            .cancel(id: CancelID.folderWatcher),
            sendEntryOperations(.loading(.cancelAndClearItems)),
            .send(.entryViewLayout(.internal(.clearCollectionPresentation))),
            .send(.entryViewLayout(.internal(.applyClearSelection))),
        )
    }

    private func folderRouteEffect(
        path: String,
        state: State,
        rootContextChange: Effect<Action>,
    ) -> Effect<Action> {
        .concatenate(
            rootContextChange,
            .send(.entryViewLayout(.internal(.clearCollectionPresentation))),
            sendEntryOperations(.loading(.loadItems(
                path: path,
                showHidden: state.entryViewLayout.showHiddenFiles,
                priority: FileManagerContentEntryOpsCoordinator.rootMetadataPriority(
                    for: state.entryViewLayout.entryArrangements,
                ),
            ))),
            observeFolderChangesEffect(path: path),
        )
    }

    private func recentsRouteEffect(
        state: State,
        rootContextChange: Effect<Action>,
        cancelRootLoad: Effect<Action>,
    ) -> Effect<Action> {
        .concatenate(
            rootContextChange,
            .cancel(id: CancelID.folderWatcher),
            cancelRootLoad,
            .send(.entryViewLayout(.internal(.clearCollectionPresentation))),
            sendEntryOperations(.loading(.loadRecentItems(
                showHidden: state.entryViewLayout.showHiddenFiles,
            ))),
        )
    }

    private func tagsRouteEffect(
        tagName: String,
        state: State,
        rootContextChange: Effect<Action>,
        cancelRootLoad: Effect<Action>,
    ) -> Effect<Action> {
        .concatenate(
            rootContextChange,
            .cancel(id: CancelID.folderWatcher),
            cancelRootLoad,
            .send(.entryViewLayout(.internal(.clearCollectionPresentation))),
            sendEntryOperations(.loading(.loadTagItems(
                tagName: tagName,
                showHidden: state.entryViewLayout.showHiddenFiles,
            ))),
        )
    }

    private func computerRouteEffect(
        rootContextChange: Effect<Action>,
        cancelRootLoad: Effect<Action>,
    ) -> Effect<Action> {
        .concatenate(
            rootContextChange,
            .cancel(id: CancelID.folderWatcher),
            cancelRootLoad,
            .send(.entryViewLayout(.internal(.clearCollectionPresentation))),
            sendEntryOperations(.loading(.loadComputerItems)),
        )
    }

    private func collectionRouteEffect(
        state: State,
        rootContextChange: Effect<Action>,
    ) -> Effect<Action> {
        .concatenate(
            rootContextChange,
            observeCollectionScopeChangesEffect(
                context: state.collection.collectionContext,
                openedURL: state.collection.collectionSession.document?.url,
            ),
        )
    }

    private func aiChatRouteEffect(
        sessionID: String,
        rootContextChange: Effect<Action>,
    ) -> Effect<Action> {
        .concatenate(
            rootContextChange,
            aiChatEntryRouteEffect(aiChatRouteEffect(sessionID: sessionID)),
        )
    }

    private func aiChatSessionsRouteEffect(
        sessionID: String,
        rootContextChange: Effect<Action>,
    ) -> Effect<Action> {
        .concatenate(
            rootContextChange,
            aiChatEntryRouteEffect(aiChatSessionsRouteEffect(sessionID: sessionID)),
        )
    }

    private func hierarchyRootPath(for navigationState: ContentPageNavigationRoute) -> String {
        guard case let .folder(path) = navigationState else { return "" }
        return path
    }

    private func aiChatEntryRouteEffect(
        _ routeEffect: Effect<Action>,
    ) -> Effect<Action> {
        .concatenate(
            sendEntryOperations(.loading(.cancelAndClearItems)),
            .send(.entryViewLayout(.internal(.clearCollectionPresentation))),
            .send(.entryViewLayout(.internal(.applyClearSelection))),
            routeEffect,
        )
    }

    private func aiChatRouteEffect(sessionID: String) -> Effect<Action> {
        let aiChatSessionID = AiChatSessionID(rawValue: UUID(uuidString: sessionID) ?? UUID())
        return .merge(
            .cancel(id: CancelID.folderWatcher),
            .send(.aiChat(.routeToChatSession(aiChatSessionID))),
        )
    }

    private func aiChatSessionsRouteEffect(sessionID: String) -> Effect<Action> {
        let aiChatSessionID = AiChatSessionID(rawValue: UUID(uuidString: sessionID) ?? UUID())
        return .merge(
            .cancel(id: CancelID.folderWatcher),
            .send(.aiChat(.showSessionsForChat(aiChatSessionID))),
        )
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
                    let changedEvents = gatewayRelevantChangedEvents(events, interest: interest, openedURL: openedURL)
                    guard !changedEvents.isEmpty else { continue }

                    if interest.purpose == .collectionStale {
                        collectionStalenessClient.invalidateRecords(changedEvents.map(\.path))
                    }
                    await send(.externalFileSystemChanged(changedEvents))
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

nonisolated func gatewayRelevantChangedEvents(
    _ events: [FileChangeGatewayEvent],
    interest: FileChangeWatchInterest,
    openedURL: URL?,
) -> [FileChangeGatewayEvent] {
    let relevantPaths = Set(gatewayRelevantChangedPaths(events, interest: interest, openedURL: openedURL))
    return events.filter { relevantPaths.contains(FileChangeScopePolicy.normalizedPath($0.path)) }
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
