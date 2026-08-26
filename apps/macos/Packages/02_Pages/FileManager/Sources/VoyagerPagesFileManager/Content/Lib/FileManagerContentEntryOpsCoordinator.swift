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
            afterLexicalPath: move.rawAfter,
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
        // 화면 row 매칭은 lexical identity가 우선이다. afterPath는 symlink를
        // 해석하므로 대상 실체 파일이 같은 목록에 있으면 잘못된 행을 먼저 고른다.
        // leaf까지 resolve하는 fallback은 두지 않는다: 대상 파일이 더 이른 batch에
        // 오면 renamed symlink 행 도착 전에 선택을 빼앗고 전이를 소비해 버린다.
        let lexicalAfterPath = transition.afterLexicalPath.isEmpty ? transition.afterPath : transition.afterLexicalPath
        let standardizedAfter = standardizedPath(lexicalAfterPath)
        let matchedAfterID = entries.first(where: { standardizedPath($0.id) == standardizedAfter })?.id
        guard let matchedAfterID else { return false }

        var selectedIds = state.entryViewLayout.selectedIds
        selectedIds.remove(matchedBeforeID)
        selectedIds.insert(matchedAfterID)
        state.entryViewLayout.selectedIds = selectedIds
        state.entryViewLayout.lastSelectedId = matchedAfterID
        state.entryViewLayout.rangeAnchorId = matchedAfterID
        // 정상 migration 완료 시 preservation(소스) 폴더에 누적된 staged 항목을 먼저
        // 커밋한다. 이후 도착하는 소스 terminal이 retained snapshot을 마무리할 때
        // 정상 항목이 함께 유지된다.
        if case let .folder(preservationID, _) = transition.preservationOwner,
           let staged = state.entryViewLayout.hierarchy.identityMigrationStagedChildrenByFolder[preservationID],
           !staged.isEmpty
        {
            state.entryViewLayout.hierarchy.nodesByID[preservationID]?.folder.children = staged
            state.entryViewLayout.hierarchy.nodesByID[preservationID]?.folder.hasAppliedContentBatch = true
            state.entryViewLayout.hierarchy.identityMigrationStagedChildrenByFolder[preservationID] = nil
            state.entryViewLayout.hierarchy.identityMigrationDeferredAfterIDByFolder[preservationID] = nil
        }
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

    /// hierarchyInvalidated가 확장 폴더 node를 재시작하면 그 세대도 하나 올라간다.
    /// 무효화 대상 폴더를 소유자로 저장한 대기 전이의 해당 소유자를 새 세대로
    /// 재기준화해 후속 folder batch에서 selection migration이 살아남게 한다.
    static func rebaseIdentityTransitionForHierarchyInvalidation(
        affectedPaths: [String],
        state: inout FileManagerContentState,
    ) {
        guard var transition = state.pendingIdentityTransition else { return }
        let canonicalAffected = Set(affectedPaths.map { canonicalizedPath($0) })
        func rebased(_ owner: FileManagerContentState.EntryIdentityTransitionProjectionOwner)
            -> FileManagerContentState.EntryIdentityTransitionProjectionOwner
        {
            guard case let .folder(id, generation) = owner,
                  canonicalAffected.contains(canonicalizedPath(id)),
                  let node = state.entryViewLayout.hierarchy.nodesByID[id],
                  node.generation == generation
            else { return owner }
            return .folder(id: id, generation: generation &+ 1)
        }
        transition.projectionOwner = rebased(transition.projectionOwner)
        transition.preservationOwner = transition.preservationOwner.map(rebased)
        state.pendingIdentityTransition = transition
    }

    /// 지연 reload는 전이가 실제로 등록된 경우에만 의미가 있다. 실패·무선택
    /// 레코드까지 reload하면 무관한 세대 bump가 선택 migration을 깬다.
    private static func entryActionCompletedEffect(
        _ record: EntryActionRecord,
        state: inout FileManagerContentState,
    ) -> Effect<FileManagerContentAction> {
        recordIdentityTransitionIfEligible(record, state: &state)
        return .merge(
            handleEntryActionCompleted(record, state: &state),
            record.operationKind == .setTags ? setTagsRefreshEffect(record: record, state: state) : .none,
        )
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
            rebaseIdentityTransitionForNextRootReload(state: &state)
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
            _ = recordIdentityTransitionIfEligible(effectiveRecord, state: &state)
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
            rebaseIdentityTransitionForNextRootReload(state: &state)
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
