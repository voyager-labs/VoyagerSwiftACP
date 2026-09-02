import ComposableArchitecture
import Foundation
import VoyagerEntitiesEntry
import VoyagerFeaturesContentPageNavigation
import VoyagerFeaturesEntryOperations
import VoyagerWidgetsEntryViewLayout

enum FileManagerContentIdentityTransitionCoordinator {
    private struct RecordedMoveTarget {
        let rawBefore: String
        let rawAfter: String
        let before: String
        let after: String
    }

    @discardableResult
    static func recordIfEligible(
        _ record: EntryActionRecord,
        state: inout FileManagerContentState,
    ) -> Effect<FileManagerContentAction> {
        guard record.operationKind == .rename || record.operationKind == .pasteFileMove else { return .none }
        guard case let .folder(currentPath) = state.navigation.navigationState else { return .none }
        let normalizedRoot = canonicalizedPath(currentPath)
        let lexicalRoot = standardizedPath(currentPath)
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
        guard !selectedMoves.isEmpty else { return .none }
        // 동일 before가 record 안에서 중복되면 신뢰할 수 없다. 중복 없는 이동만 보관하고,
        // 첫 이동을 primary로 나머지를 additionalMoves로 함께 추적해 다중 선택도 유지한다.
        let trustedMoves = selectedMoves.filter { move in
            movedTargets.count(where: { $0.before == move.before }) == 1
        }
        guard let move = trustedMoves.first else { return .none }
        guard isSameOrDescendant(path: standardizedPath(move.rawBefore), of: lexicalRoot) else { return .none }

        let projectionOwner = makeProjectionOwner(
            afterPath: move.rawAfter,
            rootPath: normalizedRoot,
            state: state,
        )
        let preservationOwner = preservationOwner(
            beforePath: move.rawBefore,
            projectionOwner: projectionOwner,
            rootPath: normalizedRoot,
            state: state,
        )
        let additionalMoves = trustedMoves.dropFirst()
            .filter { isSameOrDescendant(path: standardizedPath($0.rawBefore), of: lexicalRoot) }
            .map { target in
                FileManagerContentState.EntryMovePair(
                    beforePath: target.before,
                    afterPath: target.after,
                    beforeLexicalPath: target.rawBefore,
                    afterLexicalPath: target.rawAfter,
                    sourceOwner: Self.preservationOwner(
                        beforePath: target.rawBefore,
                        projectionOwner: projectionOwner,
                        rootPath: normalizedRoot,
                        state: state,
                    ),
                    destinationOwner: Self.destinationOwner(
                        afterPath: target.rawAfter,
                        projectionOwner: projectionOwner,
                        rootPath: normalizedRoot,
                        state: state,
                    ),
                )
            }
        // 새 전이로 덮기 전에 이전 staging을 폴더에 반영한다: cursor는 이미 증가했으므로
        // 버리면 후속 generic batch에서 누락 항목이 생긴다.
        if !state.entryViewLayout.isIdentityReplacementActive {
            state.entryViewLayout.hierarchy.commitDeferredFolderReplacementsOnCancel()
        }
        state.pendingIdentityTransition = .init(
            recordID: record.id,
            beforePath: move.before,
            afterPath: move.after,
            rootPath: normalizedRoot,
            refreshGeneration: state.entryViewLayout.entryOperations.loadingContext.generation,
            projectionOwner: projectionOwner,
            preservationOwner: preservationOwner,
            afterLexicalPath: move.rawAfter,
            beforeLexicalPath: move.rawBefore,
            additionalMoves: additionalMoves,
        )
        // EntryViewLayout installs the source hold in its pre-child reducer when the full
        // feature receives the operation action. Keep the direct preparation only for narrow
        // coordinator-only harnesses that intentionally bypass that child reducer.
        if !state.entryViewLayout.isIdentityReplacementActive {
            prepareSourceProjectionHolds(state: &state)
        }
        return .none
    }

    @discardableResult
    static func migrateSelection(
        entries: [EntryModel],
        projectionOwner: FileManagerContentState.EntryIdentityTransitionProjectionOwner,
        state: inout FileManagerContentState,
    ) -> Bool {
        guard var transition = state.pendingIdentityTransition else { return false }
        guard case let .folder(currentPath) = state.navigation.navigationState,
              canonicalizedPath(currentPath) == transition.rootPath
        else {
            discard(state: &state)
            return false
        }
        // 다중 이동 전이: 자체 destination owner를 가진 추가 이동은 해당 owner의 batch에서
        // 개별 migration한다. primary 검증에 앞서 폴더 경로로 정합성을 판정해 undo처럼
        // destination이 서로 다른 이동도 각자의 batch에서 선택을 옮길 수 있다.
        let migratedPair = migrateOwnerScopedPairs(entries: entries, batchOwner: projectionOwner, state: &state)
        if migratedPair {
            transition = state.pendingIdentityTransition ?? transition
            state.pendingIdentityTransition = transition
        }
        guard var transition = state.pendingIdentityTransition,
              validateProjectionOwner(
                  transition.projectionOwner,
                  actual: projectionOwner,
                  state: &state,
              )
        else {
            // owner-scoped migration 후 primary 소유자 불일치여도 소비는
            // additional destination terminal(resolveFolderTransition)이 담당한다.
            // 다만 이번 batch에서 migration된 pair의 source staging은 즉시 커밋한다.
            if migratedPair {
                commitMigratedSourceStagings(transition: transition, state: &state)
            }
            return false
        }
        // 다중 이동 전이: primary 소유자를 따르는 추가 이동은 primary 검증 뒤 이번 배치에서 함께 옮겨
        // buffered reload terminal의 projection reconcile이 남은 before ID를 지우지 않게 한다.
        // after 매칭은 primary와 동일하게 lexical 행 identity 기준이다(symlink rename 대응).
        let primaryOwnedMigrated = migratePrimaryOwnedPairs(entries: entries, state: &state)
        if let updated = state.pendingIdentityTransition {
            transition = updated
        }
        // primary before는 raw lexical ID로만 매칭한다. canonical 비교는 rename된 symlink와
        // 그 target을 같은 identity로 묶어 target 선택을 잘못 교체할 수 있다.
        // beforeLexicalPath가 없는 구형/direct 구성 전이는 기존 canonical 매칭을 유지한다.
        let matchedBeforeID: EntryModel.ID? = if transition.beforeLexicalPath.isEmpty {
            state.entryViewLayout.selectedIds.first {
                canonicalizedPath($0) == transition.beforePath
            }
        } else {
            state.entryViewLayout.selectedIds.first {
                standardizedPath($0) == standardizedPath(transition.beforeLexicalPath)
            }
        }
        guard let matchedBeforeID else {
            // primary가 이미 migration됐거나 선택이 없어도 pending destination pair가
            // 남아 있으면 전이를 유지한다(각자의 batch에서 마저 옮기기 위함).
            if !hasPendingDestinationPairs(state) {
                discard(state: &state)
            }
            return primaryOwnedMigrated
        }
        let standardizedAfter = standardizedPath(afterLexicalPath(transition))
        guard let matchedAfterID = entries.first(where: {
            standardizedPath($0.id) == standardizedAfter
        })?.id else { return primaryOwnedMigrated }

        state.entryViewLayout.selectedIds.remove(matchedBeforeID)
        state.entryViewLayout.selectedIds.insert(matchedAfterID)
        // anchor가 primary before를 가리킬 때만 after로 교체한다. pending additional
        // pair의 anchor까지 덮어쓰면 선택 집합은 유지되지만 기준 행이 틀어진다.
        if state.entryViewLayout.lastSelectedId == matchedBeforeID {
            state.entryViewLayout.lastSelectedId = matchedAfterID
        }
        if state.entryViewLayout.rangeAnchorId == matchedBeforeID {
            state.entryViewLayout.rangeAnchorId = matchedAfterID
        }
        // primary destination이 폴더일 때는 전이가 추가 terminal까지 생존하므로
        // primary migration 완료를 명시적으로 기록해 소비 판정에 사용한다.
        transition.primaryMigrated = true
        state.pendingIdentityTransition = transition
        commitMigratedSourceStagings(transition: transition, state: &state)
        if case .root = projectionOwner, !hasPendingDestinationPairs(state) {
            discard(state: &state)
        }
        return true
    }

    /// 아직 migration되지 않은 folder primary 또는 자체 destination의 additional 이동이 있는지 판정한다.
    /// before 선택이 이미 사라졌거나 primary owner가 terminal이면 해결된 것으로 본다.
    static func hasPendingDestinationPairs(_ state: FileManagerContentState) -> Bool {
        guard let transition = state.pendingIdentityTransition else { return false }
        let primaryBefore = transition.beforeLexicalPath.isEmpty
            ? transition.beforePath
            : transition.beforeLexicalPath
        if !transition.primaryMigrated,
           case .folder = transition.projectionOwner,
           ownerIsCurrent(transition.projectionOwner, state: state),
           !primaryOwnerIsTerminal(transition, state: state),
           state.entryViewLayout.selectedIds.contains(where: {
               standardizedPath($0) == standardizedPath(primaryBefore)
           })
        {
            return true
        }
        return transition.additionalMoves.contains { move in
            guard !move.migrated else { return false }
            let beforeIdentity = move.beforeLexicalPath.isEmpty ? move.beforePath : move.beforeLexicalPath
            return state.entryViewLayout.selectedIds.contains { selectedID in
                standardizedPath(selectedID) == standardizedPath(beforeIdentity)
            }
        }
    }

    static func ownerIsCurrent(
        _ owner: FileManagerContentState.EntryIdentityTransitionProjectionOwner,
        state: FileManagerContentState,
    ) -> Bool {
        switch owner {
        case let .root(generation):
            state.entryViewLayout.entryOperations.loadingContext.generation == generation
        case let .folder(id, generation):
            if let node = state.entryViewLayout.hierarchy.nodesByID[id] {
                // Multiple reload actions can be queued before their child reducer runs.
                // Any reserved future generation remains current until the node advances
                // past it; only an owner behind the node is stale.
                node.generation <= generation
            } else {
                false
            }
        }
    }

    static func rebaseForNextRootReload(state: inout FileManagerContentState) {
        guard var transition = state.pendingIdentityTransition else { return }
        func rebased(_ owner: FileManagerContentState.EntryIdentityTransitionProjectionOwner?)
            -> FileManagerContentState.EntryIdentityTransitionProjectionOwner?
        {
            guard case let .root(generation) = owner else { return owner }
            return .root(generation: generation &+ 1)
        }
        transition.projectionOwner = rebased(transition.projectionOwner) ?? transition.projectionOwner
        transition.preservationOwner = rebased(transition.preservationOwner)
        // additional 이동의 root 소유자(source/destination)도 같은 reload 경계에서 재기준화한다.
        for index in transition.additionalMoves.indices {
            transition.additionalMoves[index].sourceOwner = rebased(transition.additionalMoves[index].sourceOwner)
            transition.additionalMoves[index].destinationOwner = rebased(
                transition.additionalMoves[index].destinationOwner,
            )
        }
        state.pendingIdentityTransition = transition
    }

    static func rebaseForHierarchyInvalidation(
        affectedPaths: [String],
        state: inout FileManagerContentState,
    ) {
        guard var transition = state.pendingIdentityTransition else { return }
        let canonicalAffected = Set(affectedPaths.map(canonicalizedPath))
        func rebased(_ owner: FileManagerContentState.EntryIdentityTransitionProjectionOwner)
            -> FileManagerContentState.EntryIdentityTransitionProjectionOwner
        {
            guard case let .folder(id, generation) = owner,
                  canonicalAffected.contains(canonicalizedPath(id)),
                  let node = state.entryViewLayout.hierarchy.nodesByID[id],
                  // Each invalidation reserves one future startLoad generation. Preserve
                  // arbitrarily long queued bursts while rejecting already-stale owners.
                  node.generation <= generation
            else { return owner }
            return .folder(id: id, generation: generation &+ 1)
        }
        transition.projectionOwner = rebased(transition.projectionOwner)
        transition.preservationOwner = transition.preservationOwner.map(rebased)
        for index in transition.additionalMoves.indices {
            transition.additionalMoves[index].sourceOwner = transition.additionalMoves[index].sourceOwner.map(rebased)
            transition.additionalMoves[index].destinationOwner = transition.additionalMoves[index].destinationOwner
                .map(rebased)
        }
        state.pendingIdentityTransition = transition
    }

    /// primary migration이 완료된 뒤 남은 pending destination 소유자 중 현재 세대가 하나라도 있는지 판정한다.
    static func hasCurrentPendingDestinationOwner(
        _ transition: FileManagerContentState.EntryIdentityTransition,
        state: FileManagerContentState,
    ) -> Bool {
        transition.additionalMoves.contains { move in
            guard !move.migrated else { return false }
            let owner = move.destinationOwner ?? transition.projectionOwner
            return ownerIsCurrent(owner, state: state)
        }
    }

    static func transitionOverlaps(
        _ eventPath: String,
        _ transition: FileManagerContentState.EntryIdentityTransition,
    ) -> Bool {
        let normalizedEventPath = canonicalizedPath(eventPath)
        func overlaps(_ beforePath: String, _ afterPath: String) -> Bool {
            isSameOrDescendant(path: normalizedEventPath, of: beforePath)
                || isSameOrDescendant(path: normalizedEventPath, of: afterPath)
                || isSameOrDescendant(path: beforePath, of: normalizedEventPath)
                || isSameOrDescendant(path: afterPath, of: normalizedEventPath)
        }
        // 다중 이동: primary뿐 아니라 additional 이동 경로의 rename echo도 병합해
        // 명령 reload 위의 중복 refresh 예약을 막는다.
        if overlaps(transition.beforePath, transition.afterPath) { return true }
        return transition.additionalMoves.contains { overlaps($0.beforePath, $0.afterPath) }
    }

    static func discard(state: inout FileManagerContentState) {
        let transition = state.pendingIdentityTransition
        state.pendingIdentityTransition = nil
        // 취소된 전이의 folder staging은 버리지 않는다: staging 누적 동안 이미 증가한
        // batch cursor와 children 불일치가 남아 같은 세대 후속 batch가 어긋난다.
        state.entryViewLayout.hierarchy.commitDeferredFolderReplacementsOnCancel()
        guard let transition else { return }
        // staging 커밋으로 사라진 before 행의 선택·anchor를 폐기 경로에서도 정산한다.
        var beforeSources: [(identity: String, sourceFolderID: EntryModel.ID?)] = []
        if case let .folder(preservationID, _) = transition.preservationOwner {
            beforeSources.append((
                identity: transition.beforeLexicalPath.isEmpty
                    ? transition.beforePath
                    : transition.beforeLexicalPath,
                sourceFolderID: preservationID,
            ))
        }
        for move in transition.additionalMoves {
            let sourceFolderID: EntryModel.ID? = if case let .folder(id, _) = move.sourceOwner ?? transition
                .projectionOwner
            {
                id
            } else {
                nil
            }
            beforeSources.append((
                identity: move.beforeLexicalPath.isEmpty ? move.beforePath : move.beforeLexicalPath,
                sourceFolderID: sourceFolderID,
            ))
        }
        for before in beforeSources {
            settleStaleBeforeSelection(
                beforeIdentity: before.identity,
                sourceFolderID: before.sourceFolderID,
                state: &state,
            )
        }
        reconcileRemovedSourceSelections(
            sourceFolderIDs: Set(beforeSources.compactMap(\.sourceFolderID)),
            preservedAfterPaths: transitionAfterPaths(transition),
            state: &state,
        )
    }

    static func afterLexicalPath(
        _ transition: FileManagerContentState.EntryIdentityTransition,
    ) -> String {
        transition.afterLexicalPath.isEmpty ? transition.afterPath : transition.afterLexicalPath
    }

    static func standardizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }

    static func canonicalizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
    }

    static func commitMigratedSourceStagings(
        transition: FileManagerContentState.EntryIdentityTransition,
        state: inout FileManagerContentState,
    ) {
        commitMigratedSourceStagingsImpl(transition: transition, state: &state)
    }

    /// before identity가 source folder children에서 사라졌으면 선택과 anchor를 정산한다.
    private static func settleStaleBeforeSelection(
        beforeIdentity: String,
        sourceFolderID: EntryModel.ID?,
        state: inout FileManagerContentState,
    ) {
        guard let sourceFolderID,
              let node = state.entryViewLayout.hierarchy.nodesByID[sourceFolderID]
        else { return }
        let remainingPaths = Set(node.folder.children.map(\.id).map(standardizedPath))
        guard let staleID = state.entryViewLayout.selectedIds.first(where: {
            standardizedPath($0) == standardizedPath(beforeIdentity)
        }), !remainingPaths.contains(standardizedPath(staleID)) else { return }
        state.entryViewLayout.selectedIds.remove(staleID)
        if state.entryViewLayout.lastSelectedId == staleID {
            state.entryViewLayout.lastSelectedId = nil
        }
        if state.entryViewLayout.rangeAnchorId == staleID {
            state.entryViewLayout.rangeAnchorId = nil
        }
    }

    /// record 완료 시점의 hierarchy snapshot으로 source folder hold를 미리 설치한다.
    /// coreBatch 없이 coreFinished가 먼저 와도 child reducer 전에 retained projection을 보존한다.
    private static func prepareSourceProjectionHolds(state: inout FileManagerContentState) {
        guard let transition = state.pendingIdentityTransition else { return }
        var preparedFolderIDs = Set<EntryModel.ID>()
        if case let .folder(id, _) = transition.preservationOwner {
            preparedFolderIDs.insert(id)
            state.entryViewLayout.hierarchy.beginDeferredFolderReplacement(
                folderID: id,
                untilEntryID: afterLexicalPath(transition),
                holdsUntilMigration: true,
            )
        }
        for move in transition.additionalMoves where !move.migrated {
            guard case let .folder(id, _) = move.sourceOwner ?? transition.projectionOwner,
                  preparedFolderIDs.insert(id).inserted
            else { continue }
            let afterIdentity = move.afterLexicalPath.isEmpty ? move.afterPath : move.afterLexicalPath
            state.entryViewLayout.hierarchy.beginDeferredFolderReplacement(
                folderID: id,
                untilEntryID: afterIdentity,
                holdsUntilMigration: true,
            )
        }
    }

    /// 자체 destination owner가 이번 batch 소유자와 일치하는 additional pair를 migration한다.
    private static func migrateOwnerScopedPairs(
        entries: [EntryModel],
        batchOwner: FileManagerContentState.EntryIdentityTransitionProjectionOwner,
        state: inout FileManagerContentState,
    ) -> Bool {
        guard var transition = state.pendingIdentityTransition else { return false }
        var migratedPair = false
        for index in transition.additionalMoves.indices {
            guard let pairDestination = transition.additionalMoves[index].destinationOwner,
                  !transition.additionalMoves[index].migrated,
                  pairOwner(pairDestination, projectsBatch: batchOwner)
            else { continue }
            let move = transition.additionalMoves[index]
            let pairBefore = move.beforeLexicalPath.isEmpty ? move.beforePath : move.beforeLexicalPath
            guard let additionalBeforeID = state.entryViewLayout.selectedIds.first(where: {
                standardizedPath($0) == standardizedPath(pairBefore)
            }) else { continue }
            let additionalAfter = move.afterLexicalPath.isEmpty ? move.afterPath : move.afterLexicalPath
            guard let additionalAfterID = entries.first(where: {
                standardizedPath($0.id) == standardizedPath(additionalAfter)
            })?.id else { continue }
            state.entryViewLayout.selectedIds.remove(additionalBeforeID)
            state.entryViewLayout.selectedIds.insert(additionalAfterID)
            // owner-scoped pair도 anchor가 이 pair의 before를 가리킬 때만 after로 교체해
            // nil-owner pair와 동일한 anchor 계약을 유지한다.
            if state.entryViewLayout.lastSelectedId == additionalBeforeID {
                state.entryViewLayout.lastSelectedId = additionalAfterID
            }
            if state.entryViewLayout.rangeAnchorId == additionalBeforeID {
                state.entryViewLayout.rangeAnchorId = additionalAfterID
            }
            transition.additionalMoves[index].migrated = true
            migratedPair = true
        }
        if migratedPair {
            state.pendingIdentityTransition = transition
        }
        return migratedPair
    }

    /// primary destination을 따르는 additional pair를 이번 batch에서 migration한다.
    @discardableResult
    private static func migratePrimaryOwnedPairs(
        entries: [EntryModel],
        state: inout FileManagerContentState,
    ) -> Bool {
        guard var transition = state.pendingIdentityTransition else { return false }
        var migrated = false
        for index in transition.additionalMoves.indices
            where transition.additionalMoves[index].destinationOwner == nil
        {
            let move = transition.additionalMoves[index]
            let pairBefore = move.beforeLexicalPath.isEmpty ? move.beforePath : move.beforeLexicalPath
            guard let additionalBeforeID = state.entryViewLayout.selectedIds.first(where: {
                standardizedPath($0) == standardizedPath(pairBefore)
            }) else { continue }
            let additionalAfter = move.afterLexicalPath.isEmpty ? move.afterPath : move.afterLexicalPath
            guard let additionalAfterID = entries.first(where: {
                standardizedPath($0.id) == standardizedPath(additionalAfter)
            })?.id else { continue }
            state.entryViewLayout.selectedIds.remove(additionalBeforeID)
            state.entryViewLayout.selectedIds.insert(additionalAfterID)
            // anchor가 이 pair의 before를 가리킬 때만 after로 교체한다. 다른 pair의
            // identity를 무조건 덮어쓰면 Quick Look index와 Shift 범위 선택이 어긋난다.
            if state.entryViewLayout.lastSelectedId == additionalBeforeID {
                state.entryViewLayout.lastSelectedId = additionalAfterID
            }
            if state.entryViewLayout.rangeAnchorId == additionalBeforeID {
                state.entryViewLayout.rangeAnchorId = additionalAfterID
            }
            transition.additionalMoves[index].migrated = true
            migrated = true
        }
        if migrated {
            state.pendingIdentityTransition = transition
        }
        return migrated
    }

    /// migration이 완료된 pair의 source 폴더 staging을 커밋한다.
    /// 아직 migration하지 않은 pair의 source는 보류해 before 선택이 조기에 제거되지 않게 한다.
    private static func commitMigratedSourceStagingsImpl(
        transition: FileManagerContentState.EntryIdentityTransition,
        state: inout FileManagerContentState,
    ) {
        func effectiveSourceFolderID(_ move: FileManagerContentState.EntryMovePair) -> EntryModel.ID? {
            guard case let .folder(id, _) = move.sourceOwner ?? transition.projectionOwner else { return nil }
            return id
        }
        var unmigratedSourceFolderIDs = Set(transition.additionalMoves.compactMap { move in
            move.migrated ? nil : effectiveSourceFolderID(move)
        })
        if !transition.primaryMigrated,
           case let .folder(preservationID, _) = transition.preservationOwner
        {
            unmigratedSourceFolderIDs.insert(preservationID)
        }
        var sourceFolderIDsToCommit = Set<EntryModel.ID>()
        if case let .folder(preservationID, _) = transition.preservationOwner,
           !unmigratedSourceFolderIDs.contains(preservationID)
        {
            sourceFolderIDsToCommit.insert(preservationID)
        }
        for move in transition.additionalMoves where move.migrated {
            guard let sourceID = effectiveSourceFolderID(move),
                  !unmigratedSourceFolderIDs.contains(sourceID)
            else { continue }
            sourceFolderIDsToCommit.insert(sourceID)
        }
        for sourceID in sourceFolderIDsToCommit {
            state.entryViewLayout.hierarchy.markDeferredFolderReplacementMigrationCompleted(folderID: sourceID)
            if state.entryViewLayout.hierarchy.nodesByID[sourceID]?.folder.hasAppliedContentBatch == true,
               state.entryViewLayout.hierarchy.deferredFolderReplacement(folderID: sourceID)?.stagedChildren.isEmpty
               == true
            {
                _ = state.entryViewLayout.hierarchy.takeDeferredFolderReplacement(folderID: sourceID)
            } else {
                commitPreservationStaging(sourceID, state: &state)
            }
            // staging 커밋 뒤 사라진 before 행은 선택·anchor에도 stale로 남는다.
            // 배치 migration은 swap이 먼저 일어나 이 정산의 대상이 아니다(자동 no-op).
            let remainingChildPaths = Set(
                (state.entryViewLayout.hierarchy.nodesByID[sourceID]?.folder.children.map(\.id) ?? [])
                    .map(standardizedPath),
            )
            var staleBeforeIdentities: [String] = []
            for move in transition.additionalMoves where move.migrated {
                guard effectiveSourceFolderID(move) == sourceID else { continue }
                staleBeforeIdentities.append(
                    move.beforeLexicalPath.isEmpty ? move.beforePath : move.beforeLexicalPath,
                )
            }
            // primary before도 committed staging에서 사라지면 동일하게 정산한다.
            if case let .folder(preservationID, _) = transition.preservationOwner,
               preservationID == sourceID
            {
                staleBeforeIdentities.append(
                    transition.beforeLexicalPath.isEmpty ? transition.beforePath : transition.beforeLexicalPath,
                )
            }
            for beforeIdentity in staleBeforeIdentities {
                guard let staleID = state.entryViewLayout.selectedIds.first(where: {
                    standardizedPath($0) == standardizedPath(beforeIdentity)
                }), !remainingChildPaths.contains(standardizedPath(staleID)) else { continue }
                state.entryViewLayout.selectedIds.remove(staleID)
                if state.entryViewLayout.lastSelectedId == staleID {
                    state.entryViewLayout.lastSelectedId = nil
                }
                if state.entryViewLayout.rangeAnchorId == staleID {
                    state.entryViewLayout.rangeAnchorId = nil
                }
            }
        }
        let committedSourceFolderIDs = sourceFolderIDsToCommit
        reconcileRemovedSourceSelections(
            sourceFolderIDs: committedSourceFolderIDs,
            preservedAfterPaths: transitionAfterPaths(transition),
            state: &state,
        )
    }

    private static func transitionAfterPaths(
        _ transition: FileManagerContentState.EntryIdentityTransition,
    ) -> Set<String> {
        var afterPaths: Set<String> = [standardizedPath(afterLexicalPath(transition))]
        afterPaths.formUnion(transition.additionalMoves.map { move in
            standardizedPath(move.afterLexicalPath.isEmpty ? move.afterPath : move.afterLexicalPath)
        })
        return afterPaths
    }

    /// Source staging can remove a selected sibling that is unrelated to the moved pair.
    /// Reconcile only direct children of the committed source and retain after identities that
    /// are still waiting for their destination projection; do not run the broad visible
    /// projection reconcile here because the destination row may not be materialized yet.
    private static func reconcileRemovedSourceSelections(
        sourceFolderIDs: Set<EntryModel.ID>,
        preservedAfterPaths: Set<String>,
        state: inout FileManagerContentState,
    ) {
        for sourceID in sourceFolderIDs {
            guard let node = state.entryViewLayout.hierarchy.nodesByID[sourceID] else { continue }
            let remainingChildren = Set(node.folder.children.map(\.id).map(standardizedPath))
            let staleIDs = state.entryViewLayout.selectedIds.filter { selectedID in
                guard standardizedPath(parentPath(for: selectedID)) == standardizedPath(sourceID),
                      !remainingChildren.contains(standardizedPath(selectedID))
                else { return false }
                return !preservedAfterPaths.contains(standardizedPath(selectedID))
            }
            guard !staleIDs.isEmpty else { continue }
            state.entryViewLayout.selectedIds.subtract(staleIDs)
            if let lastSelectedID = state.entryViewLayout.lastSelectedId,
               staleIDs.contains(lastSelectedID)
            {
                state.entryViewLayout.lastSelectedId = nil
            }
            if let rangeAnchorID = state.entryViewLayout.rangeAnchorId,
               staleIDs.contains(rangeAnchorID)
            {
                state.entryViewLayout.rangeAnchorId = nil
            }
        }
    }

    private static func commitPreservationStaging(
        _ preservationID: EntryModel.ID,
        state: inout FileManagerContentState,
    ) {
        guard var targetNode = state.entryViewLayout.hierarchy.nodesByID[preservationID],
              !targetNode.folder.hasAppliedContentBatch,
              state.entryViewLayout.hierarchy.deferredFolderReplacement(folderID: preservationID) != nil
        else { return }
        guard targetNode.folder.coreFinished else { return }
        guard let staged = state.entryViewLayout.hierarchy.takeDeferredFolderReplacement(folderID: preservationID)
        else { return }
        targetNode.folder.children = staged
        targetNode.folder.hasAppliedContentBatch = !staged.isEmpty
        targetNode.folder.retainsPreviousGenerationChildren = false
        state.entryViewLayout.hierarchy.nodesByID[preservationID] = targetNode
        // 이동 전 경로의 stale 로드 하위 node를 정리해 재확장 시 과거 캐시 재사용을 막는다.
        state.entryViewLayout.hierarchy.reconcileNodesAfterMigrationCommit(folderID: preservationID)
    }

    /// pair의 destination 소유자가 이번 batch 소유자와 같은 대상(종류+경로)인지 판정한다.
    /// 세대는 invalidation 재기준화 이후 어긋날 수 있어 경로만 비교한다.
    private static func pairOwner(
        _ owner: FileManagerContentState.EntryIdentityTransitionProjectionOwner,
        projectsBatch batchOwner: FileManagerContentState.EntryIdentityTransitionProjectionOwner,
    ) -> Bool {
        switch (owner, batchOwner) {
        case (.root, .root):
            true
        case let (.folder(id, generation), .folder(batchID, batchGeneration)):
            standardizedPath(id) == standardizedPath(batchID)
                && generation == batchGeneration
        default:
            false
        }
    }

    private static func destinationOwner(
        afterPath: String,
        projectionOwner: FileManagerContentState.EntryIdentityTransitionProjectionOwner,
        rootPath: String,
        state: FileManagerContentState,
    ) -> FileManagerContentState.EntryIdentityTransitionProjectionOwner? {
        let owner = makeProjectionOwner(afterPath: afterPath, rootPath: rootPath, state: state)
        return owner == projectionOwner ? nil : owner
    }

    private static func validateProjectionOwner(
        _ expected: FileManagerContentState.EntryIdentityTransitionProjectionOwner,
        actual: FileManagerContentState.EntryIdentityTransitionProjectionOwner,
        state: inout FileManagerContentState,
    ) -> Bool {
        switch (expected, actual) {
        case let (.root(expectedGeneration), .root(actualGeneration)):
            guard expectedGeneration == actualGeneration else {
                discard(state: &state)
                return false
            }
            return true
        case let (.folder(expectedID, expectedGeneration), .folder(actualID, actualGeneration)):
            guard standardizedPath(expectedID) == standardizedPath(actualID) else { return false }
            guard expectedGeneration == actualGeneration else {
                discard(state: &state)
                return false
            }
            return true
        case (.root, .folder), (.folder, .root):
            return false
        }
    }

    private static func makeProjectionOwner(
        afterPath: String,
        rootPath: String,
        state: FileManagerContentState,
    ) -> FileManagerContentState.EntryIdentityTransitionProjectionOwner {
        let rootOwner = FileManagerContentState.EntryIdentityTransitionProjectionOwner.root(
            generation: state.entryViewLayout.entryOperations.loadingContext.generation,
        )
        let directParentPath = standardizedPath(parentPath(for: afterPath))
        if directParentPath == rootPath || canonicalizedPath(directParentPath) == rootPath {
            return rootOwner
        }
        let expandedFolderIDs = state.entryViewLayout.hierarchy.expandedFolderIDs
        let folderID = state.entryViewLayout.hierarchy.nodesByID.keys.first(where: {
            expandedFolderIDs.contains($0) && standardizedPath($0) == directParentPath
        }) ?? state.entryViewLayout.hierarchy.nodesByID.keys.first(where: {
            expandedFolderIDs.contains($0) && canonicalizedPath($0) == directParentPath
        })
        guard let folderID,
              let node = state.entryViewLayout.hierarchy.nodesByID[folderID]
        else { return rootOwner }
        return .folder(id: folderID, generation: node.generation &+ 1)
    }

    private static func preservationOwner(
        beforePath: String,
        projectionOwner: FileManagerContentState.EntryIdentityTransitionProjectionOwner,
        rootPath: String,
        state: FileManagerContentState,
    ) -> FileManagerContentState.EntryIdentityTransitionProjectionOwner? {
        let sourceOwner = makeProjectionOwner(afterPath: beforePath, rootPath: rootPath, state: state)
        return sourceOwner == projectionOwner ? nil : sourceOwner
    }

    private static func isSameOrDescendant(path: String, of ancestor: String) -> Bool {
        URL(fileURLWithPath: path).pathComponents.starts(with: URL(fileURLWithPath: ancestor).pathComponents)
    }

    private static func parentPath(for path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.deletingLastPathComponent().path
    }
}
