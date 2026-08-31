import AppKit
import ComposableArchitecture
import Foundation
import os
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
                if let destinationPath = state.pendingSelectEntryDestinationPath {
                    let matchesDestination: Bool = switch navigationState {
                    case let .folder(path):
                        URL(fileURLWithPath: path).standardizedFileURL.path
                            == URL(fileURLWithPath: destinationPath).standardizedFileURL.path
                    default:
                        false
                    }
                    if !matchesDestination {
                        state.setPendingEntrySelection(entryID: nil, destinationPath: nil)
                    }
                }
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
                // hidden toggle reload도 세대를 올리므로 대기 전이를 재기준화한다.
                FileManagerContentIdentityTransitionCoordinator.rebaseForSameRootReload(
                    navigationState: state.navigation.navigationState,
                    state: &state,
                )
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
            id: EntryOperationsLoadingCancelID
                .loadItems(
                    windowID: state.entryViewLayout.entryOperations.windowID,
                    ownerID: state.entryViewLayout.entryOperations.loadingCancellationOwnerID,
                ),
        )
        return switch navigationState {
        case .home: homeRouteEffect(
                rootContextChange: rootContextChange,
                windowID: state.entryViewLayout.entryOperations.windowID,
            )
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
                windowID: state.entryViewLayout.entryOperations.windowID,
            )
        case .collection: collectionRouteEffect(state: state, rootContextChange: rootContextChange)
        case let .aiChat(sessionID): aiChatRouteEffect(
                sessionID: sessionID,
                rootContextChange: rootContextChange,
                windowID: state.entryViewLayout.entryOperations.windowID,
            )
        case let .aiChatSessions(sessionID): aiChatSessionsRouteEffect(
                sessionID: sessionID,
                rootContextChange: rootContextChange,
                windowID: state.entryViewLayout.entryOperations.windowID,
            )
        }
    }

    private func homeRouteEffect(
        rootContextChange: Effect<Action>,
        windowID: UUID?,
    ) -> Effect<Action> {
        .concatenate(
            rootContextChange,
            .cancel(id: CancelID.folderWatcher(windowID: windowID)),
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
            .merge(
                sendEntryOperations(.loading(.loadItems(
                    path: path,
                    showHidden: state.entryViewLayout.showHiddenFiles,
                    priority: FileManagerContentEntryOpsCoordinator.rootMetadataPriority(
                        for: state.entryViewLayout.entryArrangements,
                    ),
                ))),
                observeFolderChangesEffect(path: path, windowID: state.entryViewLayout.entryOperations.windowID),
            ),
        )
    }

    private func recentsRouteEffect(
        state: State,
        rootContextChange: Effect<Action>,
        cancelRootLoad: Effect<Action>,
    ) -> Effect<Action> {
        .concatenate(
            rootContextChange,
            .cancel(id: CancelID.folderWatcher(windowID: state.entryViewLayout.entryOperations.windowID)),
            cancelRootLoad,
            .send(.entryViewLayout(.internal(.clearCollectionPresentation))),
            sendEntryOperations(.loading(.loadRecentItems(
                showHidden: state.entryViewLayout.showHiddenFiles,
                priority: FileManagerContentEntryOpsCoordinator.rootMetadataPriority(
                    for: state.entryViewLayout.entryArrangements,
                ),
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
            .cancel(id: CancelID.folderWatcher(windowID: state.entryViewLayout.entryOperations.windowID)),
            cancelRootLoad,
            .send(.entryViewLayout(.internal(.clearCollectionPresentation))),
            sendEntryOperations(.loading(.loadTagItems(
                tagName: tagName,
                showHidden: state.entryViewLayout.showHiddenFiles,
                priority: FileManagerContentEntryOpsCoordinator.rootMetadataPriority(
                    for: state.entryViewLayout.entryArrangements,
                ),
            ))),
        )
    }

    private func computerRouteEffect(
        rootContextChange: Effect<Action>,
        cancelRootLoad: Effect<Action>,
        windowID: UUID?,
    ) -> Effect<Action> {
        .concatenate(
            rootContextChange,
            .cancel(id: CancelID.folderWatcher(windowID: windowID)),
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
                state: state,
                windowID: state.entryViewLayout.entryOperations.windowID,
            ),
        )
    }

    private func aiChatRouteEffect(
        sessionID: String,
        rootContextChange: Effect<Action>,
        windowID: UUID?,
    ) -> Effect<Action> {
        .concatenate(
            rootContextChange,
            aiChatEntryRouteEffect(aiChatRouteEffect(sessionID: sessionID, windowID: windowID)),
        )
    }

    private func aiChatSessionsRouteEffect(
        sessionID: String,
        rootContextChange: Effect<Action>,
        windowID: UUID?,
    ) -> Effect<Action> {
        .concatenate(
            rootContextChange,
            aiChatEntryRouteEffect(aiChatSessionsRouteEffect(sessionID: sessionID, windowID: windowID)),
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

    private func sendEntryOperations(_ action: EntryOperationsAction) -> Effect<Action> {
        .send(.entryViewLayout(.entryOperations(action)))
    }
}

private extension FileManagerContentNavigationBridgeReducer {
    func observeGatewayChangesEffect(
        interest: FileChangeWatchInterest,
        windowID: UUID?,
        openedURL: URL? = nil,
    ) -> Effect<Action> {
        let collectionStalenessClient = collectionStalenessClient
        return .run { [fileChangeGatewayClient] send in
            fileChangeGatewayClient.updateInterests([interest])
            var previousBatchFingerprint: GatewayBatchFingerprint?
            await withTaskCancellationHandler {
                for await batch in fileChangeGatewayClient.observeEvents() {
                    let changedEvents = gatewayRelevantChangedEvents(
                        batch.events,
                        interest: interest,
                        openedURL: openedURL,
                    )
                    guard !changedEvents.isEmpty else { continue }
                    let batchFingerprint = GatewayBatchFingerprint(events: changedEvents)
                    guard batchFingerprint != previousBatchFingerprint else { continue }
                    previousBatchFingerprint = batchFingerprint

                    if interest.purpose == .collectionStale {
                        collectionStalenessClient.invalidateRecords(changedEvents.map(\.path))
                    }
                    if let chainToken = batch.deliveryChainToken {
                        logFileManagerDeliveryMarker(
                            "fs_bridge_sent",
                            events: changedEvents,
                            chainToken: chainToken,
                            latencyFrom: changedEvents.map(\.emittedAt).min(),
                        )
                    }
                    await send(.externalFileSystemChanged(
                        changedEvents,
                        deliveryChainToken: batch.deliveryChainToken,
                    ))
                }
                fileChangeGatewayClient.removeInterests([interest.id])
            } onCancel: {
                fileChangeGatewayClient.removeInterests([interest.id])
            }
        }
        .cancellable(id: CancelID.folderWatcher(windowID: windowID), cancelInFlight: true)
    }
}

private struct GatewayBatchFingerprint: Equatable {
    let normalizedPaths: [String]
    let flags: UInt32
    let emittedAt: [Date]
    let eventCount: Int

    init(events: [FileChangeGatewayEvent]) {
        normalizedPaths = Array(Set(events.map { FileChangeScopePolicy.normalizedPath($0.path) })).sorted()
        flags = events.reduce(0) { $0 | $1.flags }
        emittedAt = Array(Set(events.map(\.emittedAt))).sorted()
        eventCount = events.count
    }
}

private let fileManagerDeliveryLogger = os.Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "fm.voyager.Voyager",
    category: "FileChangeGateway",
)

private func logFileManagerDeliveryMarker(
    _ marker: String,
    events: [FileChangeGatewayEvent],
    chainToken: String,
    latencyFrom: Date?,
    timestamp: Date = Date(),
) {
    let flags = events.reduce(UInt32(0)) { $0 | $1.flags }
    var message = "voyager.fs.delivery marker=\(marker) ts=\(timestamp.timeIntervalSince1970)"
    message += " eventCount=\(events.count) flagsSummary=\(String(format: "0x%llx", UInt64(flags)))"
    let latencyMs = max(0, timestamp.timeIntervalSince(latencyFrom ?? timestamp) * 1000)
    message += " latencyMs=\(latencyMs) chainToken=\(chainToken)"
    fileManagerDeliveryLogger.info("\(message, privacy: .public)")
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
    let relevantPaths = events.compactMap { event -> String? in
        guard event.isStaleWorthyPathChange else { return nil }
        let path = FileChangeScopePolicy.canonicalPath(event.path)
        guard interest.roots.contains(where: {
            FileChangeScopePolicy.affects(root: $0, path: path, includeSubfolders: interest.includeSubfolders)
        }) else { return nil }
        guard !interest.excludedRoots.contains(where: {
            FileChangeScopePolicy.affects(root: $0, path: path, includeSubfolders: true)
        }) else { return nil }
        return path
    }
    return collectionRelevantChangedPaths(
        relevantPaths,
        openedURL: openedURL,
    )
}

nonisolated func gatewayRelevantChangedEvents(
    _ events: [FileChangeGatewayEvent],
    interest: FileChangeWatchInterest,
    openedURL: URL?,
) -> [FileChangeGatewayEvent] {
    let relevantPaths = Set(gatewayRelevantChangedPaths(events, interest: interest, openedURL: openedURL))
    return events.filter { relevantPaths.contains(FileChangeScopePolicy.canonicalPath($0.path)) }
}

nonisolated func collectionRelevantChangedPaths(_ paths: [String], openedURL: URL?) -> [String] {
    guard let openedURL else { return paths }
    let normalizedOpenedPath = FileChangeScopePolicy.canonicalPath(openedURL.path)
    return paths.filter { path in
        let normalizedPath = FileChangeScopePolicy.canonicalPath(path)
        if normalizedPath == normalizedOpenedPath {
            return false
        }
        let packagePrefix = normalizedOpenedPath == "/" ? "/" : normalizedOpenedPath + "/"
        return !normalizedPath.hasPrefix(packagePrefix)
    }
}
