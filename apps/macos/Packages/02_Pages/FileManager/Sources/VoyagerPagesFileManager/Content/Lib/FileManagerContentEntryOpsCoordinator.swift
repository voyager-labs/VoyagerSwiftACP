import ComposableArchitecture
import Foundation
import VoyagerEntitiesEntry
import VoyagerFeaturesContentPageNavigation
import VoyagerFeaturesEntryArrangements
import VoyagerFeaturesEntryOperations

/// 대응 확정된 단일 이동 대상. raw는 symlink 해석 전 lexical 경로다.
private struct RecordedMoveTarget {
    let rawBefore: String
    let rawAfter: String
    let before: String
    let after: String
}

enum FileManagerContentEntryOpsCoordinator {
    static func handleEntryOperationsAction(
        _ action: EntryOperationsAction,
        state: inout FileManagerContentState,
    ) -> Effect<FileManagerContentAction> {
        switch action {
        case let .loading(.itemsLoaded(entries)):
            handleItemsLoaded(entries: entries, state: &state)

        case let .lifecycle(.entryActionCompleted(record)):
            .merge(
                recordIdentityTransitionIfEligible(record, state: &state),
                handleEntryActionCompleted(record, state: state),
                record.operationKind == .setTags ? setTagsRefreshEffect(record: record, state: state) : .none,
            )

        case let .undoRedo(.replaySucceeded(direction: direction, sourceRecordID: _, updatedRecord: record)):
            .merge(
                handleEntryActionApplied(direction: direction, record: record, state: state),
                record.operationKind == .setTags ? setTagsRefreshEffect(record: record, state: state) : .none,
            )

        case let .lifecycle(.pathsMutated(paths)):
            handleMutatedPaths(paths, removedPrefixes: [], state: state)

        case let .lifecycle(.operationFinished(path, kind, result)):
            // operationFinished는 record identity가 없어 이 전이와의 연관을 확정할 수 없다.
            // 경로·종류를 추측해 전이를 만료하면 무관한 실패가 성공한 전이를 파괴한다.
            // 따라서 실패로는 전이를 직접 만료하지 않는다. after-path가 끝내 도착하지
            // 않으면 종료(accepted) projection의 소비 경로가 정리한다.
            handleOperationFinished(path: path, kind: kind, result: result, state: state)

        case .edit(.cancelRename):
            // 편집 취소는 이미 완료된 identity 연산과 무관하므로 대기 전이를 만료하지 않는다.
            .none

        case let .lifecycle(.dropOperationFinished(path, kind, result)):
            handleDropOperationFinished(path: path, kind: kind, result: result, state: state)

        case .lifecycle(.emptyTrashCompleted):
            .send(.delegate(.closeWindow))

        default:
            .none
        }
    }

    static func reloadEntryItemsEffect(state: FileManagerContentState) -> Effect<FileManagerContentAction> {
        reloadEntryItemsEffect(
            navigationState: state.navigation.navigationState,
            showHidden: state.entryViewLayout.showHiddenFiles,
            priority: rootMetadataPriority(for: state.entryViewLayout.entryArrangements),
        )
    }

    static func reloadEntryItemsEffect(
        navigationState: ContentPageNavigationRoute,
        showHidden: Bool,
        priority: EntryMetadataPriority = .none,
    ) -> Effect<FileManagerContentAction> {
        switch navigationState {
        case .home:
            .none
        case let .folder(path):
            sendEntryOperations(.loading(.loadItems(
                path: path,
                showHidden: showHidden,
                priority: priority,
            )))
        case .recents:
            sendEntryOperations(.loading(.loadRecentItems(
                showHidden: showHidden,
                priority: priority,
            )))
        case let .tags(tagName):
            sendEntryOperations(.loading(.loadTagItems(
                tagName: tagName,
                showHidden: showHidden,
                priority: priority,
            )))
        case .computer:
            sendEntryOperations(.loading(.loadComputerItems))
        case .collection, .aiChat, .aiChatSessions:
            .none
        }
    }

    /// itemsLoaded reconcile 전에 pending selection을 동기 반영한다.
    @discardableResult
    static func applyPendingSelectionForLoadedEntries(
        entries: [EntryModel],
        state: inout FileManagerContentState,
    ) -> Bool {
        guard let selectID = state.pendingSelectEntryID else { return false }
        let standardizedSelectID = standardizedPath(selectID)
        let matchedID = entries.first(where: { standardizedPath($0.id) == standardizedSelectID })?.id
            ?? entries.first(where: { resolvedPath($0.id) == resolvedPath(selectID) })?.id
        guard let matchedID else {
            return false
        }

        let selectedIds = Set([matchedID])
        let didChangeSelection = state.entryViewLayout.selectedIds != selectedIds
        state.pendingSelectEntryID = nil
        state.entryViewLayout.selectedIds = selectedIds
        state.entryViewLayout.lastSelectedId = matchedID
        state.entryViewLayout.rangeAnchorId = matchedID
        state.entryViewLayout.shouldScrollToSelection = true
        return didChangeSelection
    }

    /// 성공한 rename/move 기록에서 선택된 원본 하나가 after-path로 정확히 대응될 때만
    /// consume-once 경로 전이를 기록한다. 기존 전이는 새 기록으로 대체된다(supersession).
    @discardableResult
    static func recordIdentityTransitionIfEligible(
        _ record: EntryActionRecord,
        state: inout FileManagerContentState,
    ) -> Effect<FileManagerContentAction> {
        guard record.operationKind == .rename || record.operationKind == .pasteFileMove else { return .none }
        guard case let .folder(currentPath) = state.navigation.navigationState else { return .none }
        let normalizedRoot = canonicalizedPath(currentPath)
        let selectedPaths = Set(state.entryViewLayout.selectedIds.map(canonicalizedPath))
        let movedTargets = record.targets.compactMap { target -> RecordedMoveTarget? in
            guard let beforePath = target.beforePath, let afterPath = target.afterPath else { return nil }
            let before = canonicalizedPath(beforePath)
            let after = canonicalizedPath(afterPath)
            return before == after ? nil : RecordedMoveTarget(
                rawBefore: beforePath,
                rawAfter: afterPath,
                before: before,
                after: after,
            )
        }
        let selectedMoves = movedTargets.filter { selectedPaths.contains($0.before) }
        guard selectedMoves.count == 1, let move = selectedMoves.first else { return .none }
        // 동일 원본이 여러 after-path로 기록되면 대응이 모호하므로 전이를 만들지 않는다.
        guard movedTargets.count(where: { $0.before == move.before }) == 1 else { return .none }
        guard isSameOrDescendant(path: move.before, of: normalizedRoot) else { return .none }

        // 명령 파이프라인은 operationFinished를 먼저 보내 그 reload가 이미 세대를 연 뒤,
        // entryActionCompleted가 여기 도달한다(EntryEditOperations 참조). 따라서 현재
        // loadingContext.generation은 이미 이 명령의 reload 세대다. 외부 일치 이벤트가
        // 이후에 도달해도 같은 세대로 판정되어 전이가 selection migration까지 유지된다.
        // 중간에 다른 reload가 끼면 generation 불일치로 전이가 만료된다.
        let projectionOwner = identityTransitionProjectionOwner(
            afterPath: move.rawAfter,
            rootPath: normalizedRoot,
            state: state,
        )
        let preservationOwner = identityTransitionPreservationOwner(
            beforePath: move.rawBefore,
            projectionOwner: projectionOwner,
            rootPath: normalizedRoot,
            state: state,
        )
        state.pendingIdentityTransition = FileManagerContentState.EntryIdentityTransition(
            recordID: record.id,
            beforePath: move.before,
            afterPath: move.after,
            rootPath: normalizedRoot,
            refreshGeneration: state.entryViewLayout.entryOperations.loadingContext.generation,
            projectionOwner: projectionOwner,
            preservationOwner: preservationOwner,
        )
        return .none
    }

    static func rootMetadataPriority(
        for arrangements: EntryArrangementsFeature.State,
    ) -> EntryMetadataPriority {
        rootMetadataPriority(
            sortKey: arrangements.sortKey,
            groupKey: arrangements.groupKey,
        )
    }

    static func rootMetadataPriority(
        sortKey: SortKey,
        groupKey: GroupKey,
    ) -> EntryMetadataPriority {
        let probes = [
            metadataProbe(for: sortKey),
            metadataProbe(for: groupKey),
        ].compactMap(\.self)
        return probes.isEmpty ? .none : .active(probes)
    }

    @discardableResult
    static func migrateSelectionAlongIdentityTransition(
        entries: [EntryModel],
        projectionOwner: FileManagerContentState.EntryIdentityTransitionProjectionOwner,
        state: inout FileManagerContentState,
    ) -> Bool {
        guard let transition = state.pendingIdentityTransition else { return false }
        guard case let .folder(currentPath) = state.navigation.navigationState,
              canonicalizedPath(currentPath) == transition.rootPath
        else {
            // 루트가 어긋난(다른 폴더로 이동한) 전이는 되살리지 않고 결정적으로 만료시킨다.
            state.pendingIdentityTransition = nil
            return false
        }
        switch (transition.projectionOwner, projectionOwner) {
        case let (.root(expectedGeneration), .root(actualGeneration)):
            guard expectedGeneration == actualGeneration else {
                state.pendingIdentityTransition = nil
                return false
            }
        case let (.folder(expectedID, expectedGeneration), .folder(actualID, actualGeneration)):
            guard canonicalizedPath(expectedID) == canonicalizedPath(actualID) else { return false }
            guard expectedGeneration == actualGeneration else {
                state.pendingIdentityTransition = nil
                return false
            }
        case (.root, .folder), (.folder, .root):
            return false
        }
        let matchedBeforeID = state.entryViewLayout.selectedIds.first {
            canonicalizedPath($0) == transition.beforePath
        }
        guard let matchedBeforeID else {
            // 소유자 세대가 일치하는 batch까지 before 선택이 없으면 사용자가 포기한 것이다.
            // 전이를 소비하지 않으면 잔존한 채 같은 경로의 실제 rename echo가 명령
            // refresh로 병합되어 후속 목록 갱신이 누락된다.
            state.pendingIdentityTransition = nil
            return false
        }
        let standardizedAfter = standardizedPath(transition.afterPath)
        let matchedAfterID = entries.first(where: { standardizedPath($0.id) == standardizedAfter })?.id
            ?? entries.first(where: { resolvedPath($0.id) == resolvedPath(transition.afterPath) })?.id
        guard let matchedAfterID else { return false }

        var selectedIds = state.entryViewLayout.selectedIds
        selectedIds.remove(matchedBeforeID)
        selectedIds.insert(matchedAfterID)
        state.entryViewLayout.selectedIds = selectedIds
        state.entryViewLayout.lastSelectedId = matchedAfterID
        state.entryViewLayout.rangeAnchorId = matchedAfterID
        state.pendingIdentityTransition = nil
        return true
    }

    static func identityTransitionOwnerIsCurrent(
        _ owner: FileManagerContentState.EntryIdentityTransitionProjectionOwner,
        state: FileManagerContentState,
    ) -> Bool {
        switch owner {
        case let .root(generation):
            return state.entryViewLayout.entryOperations.loadingContext.generation == generation
        case let .folder(id, generation):
            guard let node = state.entryViewLayout.hierarchy.nodesByID[id] else { return false }
            return node.generation == generation || node.generation &+ 1 == generation
        }
    }

    /// 예약된 root reload가 loadingContext.begin에서 세대를 하나 올리므로, 보존하기로 한
    /// 대기 전이의 root 소유자를 새 세대로 재기준화한다. 폴더 소유자는 root 완료 시
    /// 기존 리베이스 경로(rebaseFolderIdentityTransitionOwnersAfterRootSnapshot)가 담당한다.
    static func rebaseIdentityTransitionForNextRootReload(state: inout FileManagerContentState) {
        guard var transition = state.pendingIdentityTransition else { return }
        func rebased(_ owner: FileManagerContentState.EntryIdentityTransitionProjectionOwner)
            -> FileManagerContentState.EntryIdentityTransitionProjectionOwner
        {
            guard case let .root(generation) = owner else { return owner }
            return .root(generation: generation &+ 1)
        }
        transition.projectionOwner = rebased(transition.projectionOwner)
        transition.preservationOwner = transition.preservationOwner.map(rebased)
        state.pendingIdentityTransition = transition
    }

    private static func identityTransitionProjectionOwner(
        afterPath: String,
        rootPath: String,
        state: FileManagerContentState,
    ) -> FileManagerContentState.EntryIdentityTransitionProjectionOwner {
        let rootOwner = FileManagerContentState.EntryIdentityTransitionProjectionOwner.root(
            generation: state.entryViewLayout.entryOperations.loadingContext.generation,
        )
        // symlink 엔트리는 마지막 컴포넌트가 target으로 해석될 수 있으므로 부모 판정은
        // lexical(standardized) 경로를 먼저 쓰고, canonical 비교는 시스템 symlink(/tmp 등)
        // 동등성 폴백으로만 사용한다.
        let directParentPath = standardizedPath(parentPath(for: afterPath))
        if directParentPath == rootPath || canonicalizedPath(directParentPath) == rootPath {
            return rootOwner
        }
        guard let folderID = state.entryViewLayout.hierarchy.nodesByID.keys.first(where: {
            standardizedPath($0) == directParentPath || canonicalizedPath($0) == directParentPath
        }),
            state.entryViewLayout.hierarchy.expandedFolderIDs.contains(folderID),
            let node = state.entryViewLayout.hierarchy.nodesByID[folderID]
        else { return rootOwner }
        return .folder(id: folderID, generation: node.generation &+ 1)
    }

    /// 교차 폴더 move에서 before-path가 사라지는 소스 projection의 소유자를 계산한다.
    /// migration 소유자와 동일하면 nil이고, 판정 불가한 소스는 root 소유자로 귀결된다.
    private static func identityTransitionPreservationOwner(
        beforePath: String,
        projectionOwner: FileManagerContentState.EntryIdentityTransitionProjectionOwner,
        rootPath: String,
        state: FileManagerContentState,
    ) -> FileManagerContentState.EntryIdentityTransitionProjectionOwner? {
        let sourceOwner = identityTransitionProjectionOwner(
            afterPath: beforePath,
            rootPath: rootPath,
            state: state,
        )
        return sourceOwner == projectionOwner ? nil : sourceOwner
    }

    private static func setTagsRefreshEffect(
        record: EntryActionRecord,
        state: FileManagerContentState,
    ) -> Effect<FileManagerContentAction> {
        guard case .collection = state.navigation.navigationState else {
            return reloadEntryItemsEffect(state: state)
        }
        let successfulPaths = record.targets.compactMap(\.afterPath)
        guard !successfulPaths.isEmpty else { return .none }
        return .concatenate(
            .send(.collection(.externalPathsChanged(successfulPaths))),
            .send(.view(.refreshStaleCollection)),
        )
    }

    private static func handleEntryActionCompleted(
        _ record: EntryActionRecord,
        state: FileManagerContentState,
    ) -> Effect<FileManagerContentAction> {
        if case let .folder(currentPath) = state.navigation.navigationState,
           let updatedRootPath = record.targets.first(where: {
               $0.beforePath.map { pathsEqual($0, currentPath) } == true && $0.afterPath != nil
           })?.afterPath
        {
            return .send(.internal(.requestNavigation(.view(.navigateToPath(updatedRootPath)))))
        }

        if case .folder = state.navigation.navigationState {
            let affectedPaths = record.targets.flatMap { target in
                [target.beforePath, target.afterPath].compactMap(\.self)
            }
            let removedPrefixes = record.operationKind.removesSourceAtOrigin
                ? record.targets.compactMap(\.beforePath)
                : []
            guard !affectedPaths.isEmpty else { return .none }
            return .send(.entryViewLayout(.hierarchy(.hierarchyInvalidated(
                affectedPaths: affectedPaths.map(parentPath(for:)),
                removedPrefixes: removedPrefixes,
            ))))
        }

        guard case .collection = state.navigation.navigationState,
              record.operationKind == .putBack
        else {
            return .none
        }

        return restoreCollectionPathsEffect(
            record.targets.compactMap(\.afterPath),
            state: state,
        )
    }

    private static func handleEntryActionApplied(
        direction: EntryActionDirection,
        record: EntryActionRecord,
        state: FileManagerContentState,
    ) -> Effect<FileManagerContentAction> {
        guard case .collection = state.navigation.navigationState,
              direction == .undo,
              record.operationKind == .moveToTrash
        else {
            return .none
        }

        return restoreCollectionPathsEffect(
            record.targets.compactMap(\.beforePath),
            state: state,
        )
    }

    private static func restoreCollectionPathsEffect(
        _ restoredPaths: [String],
        state _: FileManagerContentState,
    ) -> Effect<FileManagerContentAction> {
        guard !restoredPaths.isEmpty else {
            return .none
        }
        return .send(.entryViewLayout(.internal(.addCollectionPaths(restoredPaths))))
    }

    private static func handleMutatedPaths(
        _ paths: [String],
        removedPrefixes: [String],
        state: FileManagerContentState,
    ) -> Effect<FileManagerContentAction> {
        switch state.navigation.navigationState {
        case .folder:
            guard !paths.isEmpty else { return .none }
            return .send(.entryViewLayout(.hierarchy(.hierarchyInvalidated(
                affectedPaths: paths.map(parentPath(for:)),
                removedPrefixes: removedPrefixes,
            ))))

        case .collection:
            return .send(.entryViewLayout(.internal(.removeCollectionPaths(paths))))

        default:
            return .none
        }
    }

    private static func handleOperationFinished(
        path: String,
        kind: OperationKind,
        result: Result<Void, FileOpError>,
        state: FileManagerContentState,
    ) -> Effect<FileManagerContentAction> {
        let removedPathEffect: Effect<FileManagerContentAction> = if kind == .deleteImmediately,
                                                                     case .success = result
        {
            handleMutatedPaths([path], removedPrefixes: [path], state: state)
        } else {
            .none
        }
        // 취소와 목록을 바꾸지 않는 종류의 실패는 파일시스템을 바꾸지 않는다. 무관한
        // 실패의 reload가 로딩 세대를 올려 대기 중인 identity 전이를 간접적으로 만료하지
        // 않게 한다. paste move/copy는 교체 확인 후 목적지 선삭제(destructive pre-step)를
        // 포함하므로, 취소 아닌 실패는 선삭제가 반영됐을 수 있어 route 재로드로 수렴시킨다.
        let shouldReload: Bool = switch result {
        case .success:
            kind != .setTags
        case let .failure(error):
            shouldReloadOnFailure(kind: kind, error: error)
        }
        return .merge(
            removedPathEffect,
            shouldReload ? reloadEntryItemsEffect(state: state) : .none,
        )
    }

    /// drop 성공은 finishBatch의 entriesMutated impact가 담당하므로 여기서 reload하지
    /// 않는다. 실패는 clipboard paste와 같은 교체-선삭제 파이프라인을 공유하므로 동일
    /// 분류를 적용한다.
    private static func handleDropOperationFinished(
        path _: String,
        kind: OperationKind,
        result: Result<Void, FileOpError>,
        state: FileManagerContentState,
    ) -> Effect<FileManagerContentAction> {
        guard case let .failure(error) = result,
              shouldReloadOnFailure(kind: kind, error: error)
        else { return .none }
        return reloadEntryItemsEffect(state: state)
    }

    private static func shouldReloadOnFailure(
        kind: OperationKind,
        error: FileOpError,
    ) -> Bool {
        guard case .cancelled = error else { return kind.mayMutateBeforeFailure }
        return false
    }

    /// itemsLoaded 후 pendingSelectEntryID가 있으면 해당 엔트리를 선택 focus
    private static func handleItemsLoaded(
        entries: [EntryModel],
        state: inout FileManagerContentState,
    ) -> Effect<FileManagerContentAction> {
        let pendingSelectionApplied = applyPendingSelectionForLoadedEntries(entries: entries, state: &state)
        let identityMigrated = migrateSelectionAlongIdentityTransition(
            entries: entries,
            projectionOwner: .root(
                generation: state.entryViewLayout.entryOperations.loadingContext.generation,
            ),
            state: &state,
        )
        guard pendingSelectionApplied || identityMigrated else {
            return .none
        }
        return .send(.entryViewLayout(.delegate(.selectionChanged)))
    }

    private static func standardizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }

    private static func resolvedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().path
    }

    /// 외부 이벤트 비교와 같은 표준화 기준(standardize + symlink resolve)을 적용한다.
    private static func canonicalizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
    }

    private static func isSameOrDescendant(path: String, of ancestor: String) -> Bool {
        URL(fileURLWithPath: path).pathComponents.starts(with: URL(fileURLWithPath: ancestor).pathComponents)
    }

    private static func parentPath(for path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.deletingLastPathComponent().path
    }

    private static func pathsEqual(_ lhs: String, _ rhs: String) -> Bool {
        URL(fileURLWithPath: lhs).standardizedFileURL.path
            == URL(fileURLWithPath: rhs).standardizedFileURL.path
    }

    private static func metadataProbe(for key: SortKey) -> EntryMetadataProbe? {
        switch key {
        case .kind, .application, .dateLastOpened:
            .spotlight
        case .tags:
            .tags
        case .name, .size, .dateModified, .dateCreated, .dateAdded:
            nil
        }
    }

    private static func metadataProbe(for key: GroupKey) -> EntryMetadataProbe? {
        switch key {
        case .kind, .application, .dateLastOpened:
            .spotlight
        case .tags:
            .tags
        case .none, .name, .size, .dateModified, .dateCreated, .dateAdded:
            nil
        }
    }

    private static func sendEntryOperations(_ action: EntryOperationsAction) -> Effect<FileManagerContentAction> {
        .send(.entryViewLayout(.entryOperations(action)))
    }
}

private extension OperationKind {
    var removesSourceAtOrigin: Bool {
        switch self {
        case .pasteFileMove, .rename, .moveToTrash, .putBack:
            true
        default:
            false
        }
    }

    /// 교체 확인 후 목적지 선삭제 또는 부분 배치를 포함하는 다단계 파이프라인 종류.
    /// 취소 아닌 실패도 일부 파일시스템 결과가 이미 반영됐을 수 있다.
    var mayMutateBeforeFailure: Bool {
        switch self {
        case .pasteFileMove, .pasteFileCopy, .extract:
            true
        default:
            false
        }
    }
}
