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
           events.contains(where: { transitionOverlaps(normalizedPath(for: $0.path), transition) })
        {
            let rootMatches = transition.rootPath == normalizedPath(for: currentPath)
            let generationMatches = FileManagerContentEntryOpsCoordinator.identityTransitionOwnerIsCurrent(
                transition.projectionOwner,
                state: state,
            )
            if rootMatches, generationMatches {
                // 일치 이벤트는 명령이 이미 예약한 refresh로 병합한다(중복 refresh 억제).
                // 병합 대상은 명령 자체 활동이 남기는 확정 신호(ItemRenamed)뿐이다. 독립적인
                // ItemModified 등은 명령 snapshot 이후 변경일 수 있어 기존 refresh로 통과한다.
                // 전이는 소비하지 않는다: after-path projection이 도착해 선택을 옮길 때까지
                // 유지되어야 selection migration이 완료된다.
                scheduledEvents = events.filter {
                    requiresCoarseHierarchyReload($0)
                        || !isCommandIdentityEcho($0)
                        || !transitionOverlaps(normalizedPath(for: $0.path), transition)
                }
                if scheduledEvents.isEmpty {
                    // 모든 경로가 명령 refresh에 병합됨. 중복 refresh를 예약하지 않는다.
                    return .none
                }
            } else {
                // 루트·세대가 어긋난(stale) 전이는 결정적으로 만료하고 기존 라우트 동작으로 처리한다.
                state.pendingIdentityTransition = nil
            }
        }

        logFileManagerReloadRequest(scheduledEvents, deliveryChainToken: deliveryChainToken)
        let normalizedPaths = scheduledEvents.map { normalizedPath(for: $0.path) }
        let affectedPaths = hierarchyAffectedPaths(for: normalizedPaths)
        let removedPrefixes = removedPrefixes(for: scheduledEvents)
        // coarse 재스캔은 모든 확장 폴더 스냅샷을 비워 대기 전이의 before 행 선택을
        // 깬다. 전이의 소유자 폴더가 확장돼 있으면 이번 배치를 해당 폴더의 targeted
        // 무효화로 격하한다(startLoad retained 경로로 완전 child snapshot 보존).
        var downgradeOwnerFolderID: String?
        if scheduledEvents.contains(where: requiresCoarseHierarchyReload),
           let transition = state.pendingIdentityTransition,
           case let .folder(id, _) = transition.projectionOwner,
           state.entryViewLayout.hierarchy.expandedFolderIDs.contains(id)
        {
            downgradeOwnerFolderID = id
        }
        let rebaseAffectedPaths = downgradeOwnerFolderID.map { [$0] }
            ?? (scheduledEvents.contains(where: requiresCoarseHierarchyReload)
                ? Array(state.entryViewLayout.hierarchy.expandedFolderIDs)
                : affectedPaths)
        FileManagerContentEntryOpsCoordinator.rebaseIdentityTransitionForNextRootReload(state: &state)
        FileManagerContentEntryOpsCoordinator.rebaseIdentityTransitionForHierarchyInvalidation(
            affectedPaths: rebaseAffectedPaths,
            state: &state,
        )
        let hierarchyAction: EntryListHierarchyAction = if let downgradeOwnerFolderID {
            .hierarchyInvalidated(affectedPaths: [downgradeOwnerFolderID], removedPrefixes: [])
        } else if scheduledEvents.contains(where: requiresCoarseHierarchyReload) {
            .coarseHierarchyInvalidated(removedPrefixes: removedPrefixes)
        } else {
            .hierarchyInvalidated(
                affectedPaths: affectedPaths,
                removedPrefixes: removedPrefixes,
            )
        }
        return .concatenate(
            .send(.entryViewLayout(.hierarchy(hierarchyAction))),
            FileManagerContentEntryOpsCoordinator.reloadEntryItemsEffect(state: state),
        )
    }

    /// 이벤트 경로와 전이 before/after identity(또는 그 subtree/조상)가 겹치는지 판정한다.
    /// FSEvents는 변경 파일 경로 대신 포함 디렉터리나 현재 root 경로를 보고하기도 하므로
    /// 조상 방향까지 포함해 pathComponents 기준으로 대칭 비교한다(문자열 prefix 오매칭 방지).
    private func transitionOverlaps(
        _ normalizedEventPath: String,
        _ transition: FileManagerContentState.EntryIdentityTransition,
    ) -> Bool {
        isSameOrDescendant(path: normalizedEventPath, of: transition.beforePath)
            || isSameOrDescendant(path: normalizedEventPath, of: transition.afterPath)
            || isSameOrDescendant(path: transition.beforePath, of: normalizedEventPath)
            || isSameOrDescendant(path: transition.afterPath, of: normalizedEventPath)
    }

    /// 명령 자체 활동이 FSEvents에 남기는 확정 신호. rename/move는 양쪽 경로에
    /// ItemRenamed를 보고하므로 이것만 중복 제거 대상이 된다.
    private func isCommandIdentityEcho(_ event: FileChangeGatewayEvent) -> Bool {
        event.flags & UInt32(kFSEventStreamEventFlagItemRenamed) != 0
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
        return paths.contains { transitionOverlaps(normalizedPath(for: $0), transition) }
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
