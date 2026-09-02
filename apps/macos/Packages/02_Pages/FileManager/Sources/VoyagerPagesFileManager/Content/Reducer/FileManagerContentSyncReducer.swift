import ComposableArchitecture
import CoreServices
import Foundation
import os
import VoyagerEntitiesCollection
import VoyagerFeaturesContentPageNavigation
import VoyagerFeaturesEntryArrangements
import VoyagerShared
import VoyagerWidgetsEntryViewLayout

@Reducer
struct FileManagerContentSyncReducer {
    typealias State = FileManagerContentState
    typealias Action = FileManagerContentAction

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .externalFileSystemChanged(events, deliveryChainToken):
                let paths = events.map(\.path)
                switch state.navigation.navigationState {
                case .collection:
                    let affectsCollection = collectionPathsAffectCurrentContext(paths, state: state)
                    guard affectsCollection else {
                        return .none
                    }
                    logFileManagerReloadRequest(events, deliveryChainToken: deliveryChainToken)
                    return .send(.collection(.externalPathsChanged(paths)))

                case let .folder(path):
                    guard pathsAffectCurrentFolder(paths, currentPath: path, state: state) else {
                        return .none
                    }
                    return scheduleExternalFolderRefresh(
                        events,
                        deliveryChainToken: deliveryChainToken,
                        currentPath: path,
                        state: &state,
                    )

                case .recents, .tags, .computer:
                    logFileManagerReloadRequest(events, deliveryChainToken: deliveryChainToken)
                    return FileManagerContentEntryOpsCoordinator.reloadEntryItemsEffect(state: state)

                case .home, .aiChat, .aiChatSessions:
                    return .none
                }

            default:
                return .none
            }
        }
    }

    /// 외부 변경 배치를 현재 폴더 refresh로 예약한다.
    /// 대기 중인 명령 완료 전이와 겹치는 경로는 명령 경로가 이미 예약한 refresh에 병합하고(중복 제거),
    /// 나머지 경로는 기존 라우트 동작을 그대로 따른다. 루트·세대가 어긋난 전이도 여기서 만료된다.
    private func scheduleExternalFolderRefresh(
        _ events: [FileChangeGatewayEvent],
        deliveryChainToken: String?,
        currentPath: String,
        state: inout State,
    ) -> Effect<Action> {
        var scheduledEvents = events
        if let transition = state.pendingIdentityTransition,
           events.contains(where: {
               FileManagerContentIdentityTransitionCoordinator.transitionOverlaps($0.path, transition)
           })
        {
            let rootMatches = transition.rootPath == normalizedPath(for: currentPath)
            // primary migration 뒤에도 primary가 현재 세대이고 terminal이 아니면 primary owner가
            // 전이를 소유한다. primary owner가 stale하거나 terminal인 경우에만 남은 pending
            // destination 소유자의 세대로 전환한다.
            let generationMatches = transitionGenerationMatches(transition, state: state)
            if rootMatches, generationMatches {
                // 일치 이벤트는 명령이 이미 예약한 refresh로 병합한다(중복 refresh 억제).
                // 병합 대상은 명령 자체 활동이 남기는 확정 신호(ItemRenamed)뿐이다. 독립적인
                // ItemModified 등은 명령 snapshot 이후 변경일 수 있어 기존 refresh로 통과한다.
                // 전이는 소비하지 않는다: after-path projection이 도착해 선택을 옮길 때까지
                // 유지되어야 selection migration이 완료된다.
                scheduledEvents = eventsForCommandIdentityRefresh(events, transition: transition)
                if scheduledEvents.isEmpty {
                    // command echo인지 증명할 correlation 정보가 없는 pure rename pair는
                    // 버리지 않는다. 현재 command snapshot 뒤의 외부 역-rename일 수 있으므로
                    // scope를 저장하고 transition이 정산된 뒤 trailing refresh를 예약한다.
                    accumulatePendingExternalRefresh(
                        events,
                        currentPath: currentPath,
                        transition: transition,
                        state: &state,
                    )
                    return .none
                }
            } else {
                // 루트·세대가 어긋난(stale) 전이는 결정적으로 만료하고 기존 라우트 동작으로 처리한다.
                FileManagerContentIdentityTransitionCoordinator.discard(state: &state)
            }
        }

        logFileManagerReloadRequest(scheduledEvents, deliveryChainToken: deliveryChainToken)
        let normalizedPaths = scheduledEvents.map { normalizedPath(for: $0.path) }
        var affectedPaths = hierarchyAffectedPaths(for: normalizedPaths)
        var removedPrefixes = removedPrefixes(for: scheduledEvents)
        var shouldCoarseReload = scheduledEvents.contains(where: requiresCoarseHierarchyReload)
        if let pending = state.pendingExternalRefresh,
           pending.rootPath == normalizedPath(for: currentPath)
        {
            for path in pending.affectedPaths where !affectedPaths.contains(path) {
                affectedPaths.append(path)
            }
            for path in pending.removedPrefixes where !removedPrefixes.contains(path) {
                removedPrefixes.append(path)
            }
            shouldCoarseReload = shouldCoarseReload || pending.requiresCoarseHierarchyReload
            // This delivery is already a refresh boundary for the same root; consume the
            // deferred scope so a later identity settlement cannot schedule the same reload
            // twice.
            state.pendingExternalRefresh = nil
        }
        FileManagerContentIdentityTransitionCoordinator.rebaseForNextRootReload(state: &state)
        // invalidation이 확장 폴더 node를 재시작하면 그 세대도 올라가므로 폴더 소유자를 재기준화한다.
        // coarse 재스캔은 모든 확장 폴더를 되감는다.
        FileManagerContentIdentityTransitionCoordinator.rebaseForHierarchyInvalidation(
            affectedPaths: shouldCoarseReload
                ? Array(state.entryViewLayout.hierarchy.expandedFolderIDs)
                : affectedPaths,
            state: &state,
            removedPrefixes: removedPrefixes,
        )
        let hierarchyAction: EntryListHierarchyAction = shouldCoarseReload
            ? .coarseHierarchyInvalidated(
                removedPrefixes: removedPrefixes,
                retainsCompleteSnapshots: true,
            )
            : .hierarchyInvalidated(
                affectedPaths: affectedPaths,
                removedPrefixes: removedPrefixes,
            )
        return .concatenate(
            .send(.entryViewLayout(.hierarchy(hierarchyAction))),
            FileManagerContentEntryOpsCoordinator.reloadEntryItemsEffect(state: state),
        )
    }

    private func accumulatePendingExternalRefresh(
        _ events: [FileChangeGatewayEvent],
        currentPath: String,
        transition: State.EntryIdentityTransition,
        state: inout State,
    ) {
        let rootPath = normalizedPath(for: currentPath)
        let eventPaths = events.map { normalizedPath(for: $0.path) }
        let affectedPaths = hierarchyAffectedPaths(for: eventPaths)
        let identityAfterPaths = Set(
            ([transition.afterLexicalPath.isEmpty ? transition.afterPath : transition.afterLexicalPath]
                + transition.additionalMoves.map {
                    $0.afterLexicalPath.isEmpty ? $0.afterPath : $0.afterLexicalPath
                })
                .map(normalizedPath(for:)),
        )
        // A pure rename echo has no direction/provenance. Keep the before path as a
        // removal hint, but retain every after path until the trailing root reload so
        // the newly selected identity is not pruned before the final snapshot arrives.
        let removed = removedPrefixes(for: events).filter { !identityAfterPaths.contains($0) }
        var pending = state.pendingExternalRefresh
            ?? .init(
                rootPath: rootPath,
                affectedPaths: [],
                removedPrefixes: [],
                requiresCoarseHierarchyReload: false,
            )
        guard pending.rootPath == rootPath else {
            state.pendingExternalRefresh = .init(
                rootPath: rootPath,
                affectedPaths: affectedPaths,
                removedPrefixes: removed,
                requiresCoarseHierarchyReload: events.contains(where: requiresCoarseHierarchyReload),
            )
            return
        }
        for path in affectedPaths where !pending.affectedPaths.contains(path) {
            pending.affectedPaths.append(path)
        }
        for path in removed where !pending.removedPrefixes.contains(path) {
            pending.removedPrefixes.append(path)
        }
        pending.requiresCoarseHierarchyReload = pending.requiresCoarseHierarchyReload
            || events.contains(where: requiresCoarseHierarchyReload)
        state.pendingExternalRefresh = pending
    }

    private func transitionGenerationMatches(
        _ transition: FileManagerContentState.EntryIdentityTransition,
        state: FileManagerContentState,
    ) -> Bool {
        let primaryOwnerIsCurrent = FileManagerContentIdentityTransitionCoordinator.ownerIsCurrent(
            transition.projectionOwner,
            state: state,
        )
        let primaryIsTerminal = FileManagerContentIdentityTransitionCoordinator.primaryOwnerIsTerminal(
            transition,
            state: state,
        )
        return transition.primaryMigrated
            && (primaryIsTerminal || !primaryOwnerIsCurrent)
            ? FileManagerContentIdentityTransitionCoordinator.hasCurrentPendingDestinationOwner(
                transition,
                state: state,
            )
            : primaryOwnerIsCurrent
    }

    private func eventsForCommandIdentityRefresh(
        _ events: [FileChangeGatewayEvent],
        transition: FileManagerContentState.EntryIdentityTransition,
    ) -> [FileChangeGatewayEvent] {
        let provenEchoPaths = commandIdentityEchoPaths(events: events, transition: transition)
        return events.filter {
            requiresCoarseHierarchyReload($0)
                || !isCommandIdentityEcho($0)
                || !FileManagerContentIdentityTransitionCoordinator.transitionOverlaps(
                    $0.path,
                    transition,
                )
                || !provenEchoPaths.contains(
                    FileManagerContentIdentityTransitionCoordinator.standardizedPath($0.path),
                )
        }
    }

    private func commandIdentityEchoPaths(
        events: [FileChangeGatewayEvent],
        transition: FileManagerContentState.EntryIdentityTransition,
    ) -> Set<String> {
        let pureRenamePaths: Set<String> = Set(events.compactMap { event in
            guard isCommandIdentityEcho(event) else { return nil }
            return FileManagerContentIdentityTransitionCoordinator.standardizedPath(event.path)
        })
        let primaryBefore = transition.beforeLexicalPath.isEmpty
            ? transition.beforePath
            : transition.beforeLexicalPath
        let primaryAfter = transition.afterLexicalPath.isEmpty
            ? transition.afterPath
            : transition.afterLexicalPath
        let identityPairs = [(primaryBefore, primaryAfter)] + transition.additionalMoves.map { move in
            (
                move.beforeLexicalPath.isEmpty ? move.beforePath : move.beforeLexicalPath,
                move.afterLexicalPath.isEmpty ? move.afterPath : move.afterLexicalPath,
            )
        }
        return identityPairs.reduce(into: Set<String>()) { provenPaths, pair in
            let before = FileManagerContentIdentityTransitionCoordinator.standardizedPath(pair.0)
            let after = FileManagerContentIdentityTransitionCoordinator.standardizedPath(pair.1)
            guard before != after,
                  pureRenamePaths.contains(before),
                  pureRenamePaths.contains(after)
            else { return }
            provenPaths.insert(before)
            provenPaths.insert(after)
        }
    }

    /// 명령 자체 활동이 FSEvents에 남기는 후보 신호. command correlation ID가 없는
    /// gateway event는 동일 delivery의 before/after 쌍이 확인될 때만 echo로 확정한다.
    /// Helper gateway는 같은 경로의 이벤트 플래그를 `|`로 병합하므로, rename과
    /// 후속 변경이 한 delivery로 합쳐지면 해당 비트를 함께 보고한다. 파일 종류
    /// 서술 비트를 제외한 ItemRenamed 이외의 의미 있는 비트가 하나라도 있으면
    /// 독립 변경(xattr·권한·Finder 정보 포함)으로 보존한다.
    private func isCommandIdentityEcho(_ event: FileChangeGatewayEvent) -> Bool {
        let renamed = event.flags & UInt32(kFSEventStreamEventFlagItemRenamed) != 0
        guard renamed else { return false }
        let descriptorBits = UInt32(
            kFSEventStreamEventFlagItemIsFile
                | kFSEventStreamEventFlagItemIsDir
                | kFSEventStreamEventFlagItemIsSymlink,
        )
        let meaningfulBits = event.flags
            & ~descriptorBits
            & ~UInt32(kFSEventStreamEventFlagItemRenamed)
        return meaningfulBits == 0
    }

    private func logFileManagerReloadRequest(
        _ events: [FileChangeGatewayEvent],
        deliveryChainToken: String?,
    ) {
        guard let deliveryChainToken else { return }
        logFileManagerDeliveryMarker(
            "fs_reload_requested",
            events: events,
            chainToken: deliveryChainToken,
            latencyFrom: events.map(\.emittedAt).min(),
        )
    }

    private func pathsAffectCurrentFolder(_ paths: [String], currentPath: String, state: State) -> Bool {
        let normalizedCurrentPath = normalizedPath(for: currentPath)

        if paths.contains(where: { path in
            let candidatePath = normalizedPath(for: path)
            return candidatePath == normalizedCurrentPath
                || isSameOrDescendant(path: candidatePath, of: normalizedCurrentPath)
        }) {
            return true
        }

        // 조상/포함 디렉터리 또는 현재 root 이벤트: FSEvents는 변경 파일 대신
        // 포함 디렉터리 경로를 보고할 수 있다. 대기 중인 identity 전이가 겹칠 때만
        // 관련으로 판정해 상관관계(중복 refresh 병합)로 흘려보낸다. 이때 무관한
        // 경로를 버리지 않는다(배치 전체를 그대로 전달).
        guard let transition = state.pendingIdentityTransition else { return false }
        return paths.contains {
            FileManagerContentIdentityTransitionCoordinator.transitionOverlaps($0, transition)
        }
    }

    private func isSameOrDescendant(path: String, of ancestor: String) -> Bool {
        let pathComponents = URL(fileURLWithPath: path).pathComponents
        let ancestorComponents = URL(fileURLWithPath: ancestor).pathComponents
        return pathComponents.starts(with: ancestorComponents)
    }

    private func parentPath(for path: String) -> String {
        URL(fileURLWithPath: normalizedPath(for: path)).deletingLastPathComponent().path
    }

    private func hierarchyAffectedPaths(for normalizedPaths: [String]) -> [String] {
        (normalizedPaths + normalizedPaths.map(parentPath(for:))).reduce(into: []) { paths, path in
            if !paths.contains(path) {
                paths.append(path)
            }
        }
    }

    private func normalizedPath(for path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
    }

    private func removedPrefixes(for events: [FileChangeGatewayEvent]) -> [String] {
        Array(Set(events.compactMap { event in
            let removesItem = event.flags & UInt32(kFSEventStreamEventFlagItemRemoved) != 0
            let renamesItem = event.flags & UInt32(kFSEventStreamEventFlagItemRenamed) != 0
            guard removesItem || renamesItem else { return nil }
            return normalizedPath(for: event.path)
        })).sorted()
    }

    private func requiresCoarseHierarchyReload(_ event: FileChangeGatewayEvent) -> Bool {
        [
            kFSEventStreamEventFlagMustScanSubDirs,
            kFSEventStreamEventFlagUserDropped,
            kFSEventStreamEventFlagKernelDropped,
        ].contains { event.flags & UInt32($0) != 0 }
    }

    private func collectionPathsAffectCurrentContext(_ paths: [String], state: State) -> Bool {
        let relevantPaths = paths.filter {
            !isOpenedCollectionDocumentPath($0, openedURL: state.openedCollectionURL)
        }
        guard !relevantPaths.isEmpty else {
            return false
        }
        guard let context = state.collection.collectionContext else {
            return true
        }
        return collectionChangeIsRelevant(
            changedPaths: relevantPaths,
            scopes: context.scopes,
            excludedScopes: context.excludedScopes,
            includeSubfolders: context.includeSubfolders,
        )
    }

    private func isOpenedCollectionDocumentPath(_ path: String, openedURL: URL?) -> Bool {
        guard let openedURL else {
            return false
        }

        let lexicalPath = URL(fileURLWithPath: path).path
        let lexicalOpenedPath = openedURL.path
        let lexicalPackagePrefix = lexicalOpenedPath == "/" ? "/" : lexicalOpenedPath + "/"
        if lexicalPath == lexicalOpenedPath || lexicalPath.hasPrefix(lexicalPackagePrefix) {
            return true
        }

        let candidatePath = normalizedPath(for: path)
        let normalizedOpenedPath = normalizedPath(for: openedURL.path)
        if candidatePath == normalizedOpenedPath {
            return true
        }

        let packagePrefix = normalizedOpenedPath == "/" ? "/" : normalizedOpenedPath + "/"
        return candidatePath.hasPrefix(packagePrefix)
    }
}

private let fileManagerSyncDeliveryLogger = os.Logger(
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
    fileManagerSyncDeliveryLogger.info("\(message, privacy: .public)")
}
