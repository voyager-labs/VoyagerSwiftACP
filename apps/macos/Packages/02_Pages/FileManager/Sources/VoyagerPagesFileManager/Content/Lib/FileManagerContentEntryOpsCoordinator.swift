import ComposableArchitecture
import Foundation
import VoyagerEntitiesEntry
import VoyagerFeaturesContentPageNavigation
import VoyagerFeaturesEntryArrangements
import VoyagerFeaturesEntryOperations

enum FileManagerContentEntryOpsCoordinator {
    static func handleEntryOperationsAction(
        _ action: EntryOperationsAction,
        state: inout FileManagerContentState,
    ) -> Effect<FileManagerContentAction> {
        switch action {
        case let .loading(.itemsLoaded(entries)):
            handleItemsLoaded(entries: entries, state: &state)

        case let .lifecycle(.entryActionCompleted(record)):
            entryActionCompletedEffect(record, state: &state)

        case let .undoRedo(.replaySucceeded(direction: direction, sourceRecordID: _, updatedRecord: record)):
            .merge(
                handleEntryActionApplied(direction: direction, record: record, state: &state),
                record.operationKind == .setTags ? setTagsRefreshEffect(record: record, state: state) : .none,
            )

        case let .lifecycle(.pathsMutated(paths)):
            handleMutatedPaths(paths, removedPrefixes: [], state: state)

        case let .lifecycle(.operationFinished(path, kind, result)):
            // operationFinished는 record identity가 없어 이 전이와의 연관을 확정할 수 없다.
            // 경로·종류를 추측해 전이를 만료하면 무관한 실패가 성공한 전이를 파괴한다.
            // 따라서 실패로는 전이를 직접 만료하지 않는다. after-path가 끝내 도착하지
            // 않으면 종료(accepted) projection의 소비 경로가 정리한다.
            kind == .externalObjectImportItem
                ? .none
                : handleOperationFinished(path: path, kind: kind, result: result, state: &state)

        case .edit(.cancelRename):
            // 편집 취소는 이미 완료된 identity 연산과 무관하므로 대기 전이를 만료하지 않는다.
            .none

        case let .lifecycle(.dropOperationFinished(path, kind, result)):
            handleDropOperationFinished(path: path, kind: kind, result: result, state: &state)

        case let .externalDrop(.importFinished(result)):
            handleExternalImportFinished(result: result, state: state)

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
        state.setPendingEntrySelection(entryID: nil, destinationPath: nil)
        state.entryViewLayout.selectedIds = selectedIds
        state.entryViewLayout.lastSelectedId = matchedID
        state.entryViewLayout.rangeAnchorId = matchedID
        state.entryViewLayout.shouldScrollToSelection = true
        return didChangeSelection
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

    /// 지연 reload는 전이가 실제로 등록된 경우에만 의미가 있다. 실패·무선택
    /// 레코드까지 reload하면 무관한 세대 bump가 선택 migration을 깬다.
    private static func entryActionCompletedEffect(
        _ record: EntryActionRecord,
        state: inout FileManagerContentState,
    ) -> Effect<FileManagerContentAction> {
        FileManagerContentIdentityTransitionCoordinator.recordIfEligible(record, state: &state)
        return .merge(
            handleEntryActionCompleted(record, state: &state),
            record.operationKind == .setTags ? setTagsRefreshEffect(record: record, state: state) : .none,
        )
    }

    private static func handleExternalImportFinished(
        result: ExternalDropImportResult,
        state: FileManagerContentState,
    ) -> Effect<FileManagerContentAction> {
        guard case .collection = state.navigation.navigationState else {
            return reloadEntryItemsEffect(state: state)
        }
        guard !result.succeededPaths.isEmpty else { return .none }
        return .concatenate(
            .send(.collection(.externalPathsChanged(result.succeededPaths))),
            .send(.view(.refreshStaleCollection)),
        )
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
        state: inout FileManagerContentState,
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
            let invalidation: Effect<FileManagerContentAction> =
                .send(.entryViewLayout(.hierarchy(.hierarchyInvalidated(
                    affectedPaths: affectedPaths.map(parentPath(for:)),
                    removedPrefixes: removedPrefixes,
                ))))
            // reload는 지연 대상 identity 종류에서만 발화한다. 나머지는 이미
            // operationFinished 성공 경로가 reload를 소유하므로 이중 stream을 막는다.
            guard record.operationKind == .rename || record.operationKind == .pasteFileMove else {
                return invalidation
            }
            // record 기반 전이가 이 호출 직전에 기록된 뒤 reload 세대를 연다.
            // 예약되는 reload가 세대를 올리므로 방금 기록된 root 소유자를 새 세대로
            // 재기준화해 후속 batch에서 selection migration이 살아남게 한다.
            FileManagerContentIdentityTransitionCoordinator.rebaseForNextRootReload(state: &state)
            return .concatenate(
                invalidation,
                FileManagerContentEntryOpsCoordinator.reloadEntryItemsEffect(state: state),
            )
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
        state: inout FileManagerContentState,
    ) -> Effect<FileManagerContentAction> {
        // undo/redo는 entryActionCompleted 대신 replaySucceeded만 온다. folder route의
        // identity 종류는 operationFinished에서 reload를 보류했으므로 완료 경로와 동일하게
        // 여기서 전이를 등록하고, 계층 무효화와 root reload를 수행해야 이전/다음 identity가
        // 반영되면서 선택 migration도 살아남는다.
        if case .folder = state.navigation.navigationState {
            // undo는 실행이 after→before로 뒤집히지만 updatedRecord는 원래 target을
            // 유지한다. 선택된 항목은 실행 후 위치에 있으므로 실행 방향 기준으로
            // 뒤집은 record를 전이 등록에 사용한다.
            let effectiveRecord: EntryActionRecord = {
                guard direction == .undo else { return record }
                let targets = record.targets.map { target in
                    EntryActionRecord.Target(beforePath: target.afterPath, afterPath: target.beforePath)
                }
                return EntryActionRecord(operationKind: record.operationKind, targets: targets)
            }()
            // 현재 표시 중인 root 폴더 자체가 실행되는 move라면 존재하지 않는 경로를
            // reload하는 대신 실행 방향 destination으로 이동해 창을 살아있는 폴더에 둔다.
            if case let .folder(navigationRoot) = state.navigation.navigationState,
               let selfMove = effectiveRecord.targets.first(where: {
                   $0.beforePath.map { canonicalizedPath($0) == canonicalizedPath(navigationRoot) } == true
               }),
               let relocatedRoot = selfMove.afterPath
            {
                return .send(.internal(.requestNavigation(.view(.navigateToPath(relocatedRoot)))))
            }
            _ = FileManagerContentIdentityTransitionCoordinator.recordIfEligible(effectiveRecord, state: &state)
            // 무효화·removed prefix도 실행 방향 기준으로 계산해 undo 시 복원된
            // 경로가 제거되지 않고 실제 사라진 경로가 즉시 정리되게 한다.
            let affectedPaths = effectiveRecord.targets.flatMap { target in
                [target.beforePath, target.afterPath].compactMap(\.self)
            }
            let removedPrefixes = effectiveRecord.operationKind.removesSourceAtOrigin
                ? effectiveRecord.targets.compactMap(\.beforePath)
                : []
            guard !affectedPaths.isEmpty else { return .none }
            let invalidation: Effect<FileManagerContentAction> =
                .send(.entryViewLayout(.hierarchy(.hierarchyInvalidated(
                    affectedPaths: affectedPaths.map(parentPath(for:)),
                    removedPrefixes: removedPrefixes,
                ))))
            guard record.operationKind == .rename || record.operationKind == .pasteFileMove else {
                return invalidation
            }
            FileManagerContentIdentityTransitionCoordinator.rebaseForNextRootReload(state: &state)
            return .concatenate(
                invalidation,
                FileManagerContentEntryOpsCoordinator.reloadEntryItemsEffect(state: state),
            )
        }

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
        state: inout FileManagerContentState,
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
            if kind == .rename || kind == .pasteFileMove,
               case .folder = state.navigation.navigationState
            {
                // 이 두 종류는 record가 operationFinished 뒤에 도착한다. 즉시 reload가
                // reconcile로 before 선택을 지우면 record 기반 전이 생성 자격이 사라진다.
                // folder route에서는 entryActionCompleted가 전이를 만든 뒤 reload를 시작한다.
                false
            } else {
                kind != .setTags
            }
        case let .failure(error):
            shouldReloadOnFailure(kind: kind, error: error)
        }
        if shouldReload {
            FileManagerContentIdentityTransitionCoordinator.rebaseForSameRootReload(
                navigationState: state.navigation.navigationState,
                state: &state,
            )
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
        state: inout FileManagerContentState,
    ) -> Effect<FileManagerContentAction> {
        guard case let .failure(error) = result,
              shouldReloadOnFailure(kind: kind, error: error)
        else { return .none }
        FileManagerContentIdentityTransitionCoordinator.rebaseForSameRootReload(
            navigationState: state.navigation.navigationState,
            state: &state,
        )
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
        let identityMigrated = FileManagerContentIdentityTransitionCoordinator.migrateSelection(
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
