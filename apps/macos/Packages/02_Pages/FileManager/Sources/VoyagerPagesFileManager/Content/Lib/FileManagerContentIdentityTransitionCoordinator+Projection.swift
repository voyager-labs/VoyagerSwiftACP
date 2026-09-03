import Foundation
import VoyagerEntitiesEntry
import VoyagerFeaturesContentPageNavigation

extension FileManagerContentIdentityTransitionCoordinator {
    static func beginDeferredFolderReplacementIfNeeded(
        folderID: EntryModel.ID,
        items: [EntryModel],
        state: inout FileManagerContentState,
    ) {
        guard let transition = state.pendingIdentityTransition else { return }
        var shouldDefer: Bool?
        var holdsUntilMigration = false
        var untilEntryID: EntryModel.ID?
        // nil sourceOwner는 primary projectionOwner와 같은 source라는 sentinel이다.
        if transition.additionalMoves.contains(where: { move in
            guard !move.migrated,
                  case let .folder(ownerID, _) = move.sourceOwner ?? transition.projectionOwner
            else { return false }
            return standardizedPath(ownerID) == standardizedPath(folderID)
        }) {
            shouldDefer = true
            holdsUntilMigration = true
        }
        var pendingAfters: [String] = []
        if !transition.primaryMigrated,
           case let .folder(ownerID, _) = transition.projectionOwner,
           standardizedPath(ownerID) == standardizedPath(folderID)
        {
            pendingAfters.append(afterLexicalPath(transition))
        }
        for move in transition.additionalMoves where !move.migrated {
            guard case let .folder(ownerID, _) = move.destinationOwner ?? transition.projectionOwner,
                  standardizedPath(ownerID) == standardizedPath(folderID)
            else { continue }
            pendingAfters.append(
                move.afterLexicalPath.isEmpty ? move.afterPath : move.afterLexicalPath,
            )
        }
        if let nextUntil = pendingAfters.first(where: { after in
            !items.contains { standardizedPath($0.id) == standardizedPath(after) }
        }) {
            shouldDefer = true
            untilEntryID = nextUntil
            if state.entryViewLayout.hierarchy.deferredFolderReplacement(folderID: folderID) != nil {
                state.entryViewLayout.hierarchy.upsertDeferredFolderReplacement(
                    folderID: folderID,
                    untilEntryID: nextUntil,
                )
            }
        }
        if case let .folder(ownerID, _) = transition.preservationOwner,
           standardizedPath(ownerID) == standardizedPath(folderID),
           shouldDefer == nil
        {
            shouldDefer = true
            // 보존(소스) 폴더는 destination migration까지 staging을 보류한다.
            // 소스 coreFinished가 먼저 도착해도 retained before 행을 유지해 선택 깜빡임을 막는다.
            holdsUntilMigration = true
        }
        if shouldDefer == nil {
            // 다중 이동: additional 이동의 source 폴더도 primary 보존과 동일하게 보류한다.
            for move in transition.additionalMoves where !move.migrated {
                guard case let .folder(ownerID, _) = move.sourceOwner ?? transition.projectionOwner,
                      standardizedPath(ownerID) == standardizedPath(folderID)
                else { continue }
                shouldDefer = true
                holdsUntilMigration = true
                break
            }
        }
        guard shouldDefer == true else { return }
        state.entryViewLayout.hierarchy.beginDeferredFolderReplacement(
            folderID: folderID,
            untilEntryID: untilEntryID ?? afterLexicalPath(transition),
            holdsUntilMigration: holdsUntilMigration,
        )
    }

    static func holdsRootProjection(
        on action: FileManagerContentAction,
        state: FileManagerContentState,
    ) -> Bool {
        guard let transition = state.pendingIdentityTransition else { return false }
        if case .root = transition.preservationOwner {
            return true
        }
        // 다중 이동: 아직 migration되지 않은 additional pair의 source가 root면
        // 해당 pair의 destination batch가 선택을 옮길 때까지 root projection을 유지한다.
        if transition.additionalMoves.contains(where: { move in
            guard !move.migrated, case .root = move.sourceOwner ?? transition.projectionOwner else { return false }
            return true
        }) {
            return true
        }
        // after 행이 오기 전 스트림 실패에서도 마지막 root projection을 유지한다:
        // 실패는 partial loading으로의 강등이 아니라 retained snapshot 보존 사유다.
        if case .entryViewLayout(.entryOperations(.loading(.streamFailed))) = action {
            return true
        }
        guard case let .entryViewLayout(.entryOperations(.loading(.streamEvent(streamEvent)))) = action,
              case let .coreBatch(items, _) = streamEvent.event
        else { return false }
        return !items.contains {
            standardizedPath($0.id) == standardizedPath(afterLexicalPath(transition))
        }
    }

    static func hasPendingRootSourceMigration(_ state: FileManagerContentState) -> Bool {
        guard let transition = state.pendingIdentityTransition else { return false }
        if !transition.primaryMigrated,
           case .root = transition.preservationOwner,
           !primaryOwnerIsTerminal(transition, state: state)
        {
            return true
        }
        return transition.additionalMoves.contains { move in
            guard !move.migrated, case .root = move.sourceOwner ?? transition.projectionOwner else { return false }
            return true
        }
    }

    static func resolveRootDestinationSuccess(
        generation: Int,
        state: inout FileManagerContentState,
    ) -> Bool {
        guard var transition = state.pendingIdentityTransition else { return false }
        var resolved = false
        if !transition.primaryMigrated,
           case let .root(ownerGeneration) = transition.projectionOwner,
           ownerGeneration == generation
        {
            transition.primaryMigrated = true
            resolved = true
        }
        for index in transition.additionalMoves.indices where !transition.additionalMoves[index].migrated {
            let owner = transition.additionalMoves[index].destinationOwner ?? transition.projectionOwner
            guard case let .root(ownerGeneration) = owner, ownerGeneration == generation else { continue }
            transition.additionalMoves[index].migrated = true
            resolved = true
        }
        guard resolved else { return false }
        state.pendingIdentityTransition = transition
        commitMigratedSourceStagings(transition: transition, state: &state)
        return true
    }

    static func markReplacementSelection(
        on action: FileManagerContentAction,
        state: inout FileManagerContentState,
    ) {
        guard var transition = state.pendingIdentityTransition else { return }
        guard let trigger = replacementTrigger(action, transition: transition) else { return }
        let triggerOwner = switch trigger {
        case .migration: transition.projectionOwner
        case .preservation: transition.preservationOwner ?? transition.projectionOwner
        }
        guard case let .folder(currentPath) = state.navigation.navigationState,
              canonicalizedPath(currentPath) == transition.rootPath,
              ownerIsCurrent(triggerOwner, state: state)
        else {
            discard(state: &state)
            return
        }
        if case .root = transition.projectionOwner,
           state.entryViewLayout.entryOperations.loadingContext.coreFinished
        {
            return
        }
        let beforePath = standardizedPath(transition.beforePath)
        let afterPath = standardizedPath(afterLexicalPath(transition))
        let selectedPaths = Set(state.entryViewLayout.selectedIds.map(standardizedPath))
        guard selectedPaths.contains(beforePath), !selectedPaths.contains(afterPath) else { return }
        guard !replacementProjectionPaths(owner: triggerOwner, state: state).contains(afterPath) else { return }
        transition.preservedLexicalBeforeID = state.entryViewLayout.selectedIds.first {
            standardizedPath($0) == beforePath
        }
        transition.preserveSelectionForReplacementBatch = true
        state.pendingIdentityTransition = transition
    }

    static func resolveReplacementSelection(
        on action: FileManagerContentAction,
        state: inout FileManagerContentState,
    ) {
        guard var transition = state.pendingIdentityTransition else { return }
        guard replacementTrigger(action, transition: transition) != nil else { return }
        // after-path와 선택 비교는 symlink를 해석하지 않는 lexical identity로 판정한다.
        // canonical 비교는 rename된 symlink의 target 선택을 after 도착으로 오인해
        // 전이를 조기 폐기시킨다(migrateSelection의 lexical 1차 매칭과 동일 기준).
        let afterPath = standardizedPath(afterLexicalPath(transition))
        let selectedPaths = Set(state.entryViewLayout.selectedIds.map(standardizedPath))
        if transition.preserveSelectionForReplacementBatch {
            transition.preserveSelectionForReplacementBatch = false
            let preservedLexicalBeforeID = transition.preservedLexicalBeforeID
            transition.preservedLexicalBeforeID = nil
            state.pendingIdentityTransition = transition
            if selectedPaths.contains(afterPath) {
                if !hasPendingDestinationPairs(state) {
                    discard(state: &state)
                }
                return
            }
            let beforePath = standardizedPath(transition.beforePath)
            guard !selectedPaths.contains(beforePath), !selectedPaths.contains(afterPath) else { return }
            let restoredID = preservedLexicalBeforeID ?? transition.beforePath
            state.entryViewLayout.selectedIds.insert(restoredID)
            // anchor가 잠시 제거된 before 행을 가리킬 때만 복원 ID로 되돌린다. 다른
            // 선택 행의 Quick Look·Shift 기준 identity는 migrateSelection과 동일하게 유지한다.
            if !isSelectedPath(state.entryViewLayout.lastSelectedId, selectedPaths: selectedPaths) {
                state.entryViewLayout.lastSelectedId = restoredID
            }
            if !isSelectedPath(state.entryViewLayout.rangeAnchorId, selectedPaths: selectedPaths) {
                state.entryViewLayout.rangeAnchorId = restoredID
            }
            return
        }
        if selectedPaths.contains(afterPath) {
            // after 행은 destination folder의 첫 batch에서 먼저 보일 수 있다.
            // source staging을 커밋할 terminal까지 전이를 유지하고, 실제 owner가
            // terminal이 된 뒤에만 pending pair가 없으면 폐기한다.
            if !hasPendingDestinationPairs(state),
               primaryOwnerIsTerminal(transition, state: state)
            {
                discard(state: &state)
            }
            return
        }
        guard case .root = transition.projectionOwner,
              state.entryViewLayout.entryOperations.loadingContext.coreFinished,
              !visibleEntryPaths(in: state).contains(afterPath),
              !selectedPaths.contains(afterPath)
        else { return }
        if !hasPendingDestinationPairs(state) {
            discard(state: &state)
        }
    }

    /// anchor ID가 현재 선택에 남아 있는지 판정한다. nil은 reconcile이 비운 상태이므로 복원 대상이다.
    private static func isSelectedPath(
        _ anchorID: EntryModel.ID?,
        selectedPaths: Set<String>,
    ) -> Bool {
        guard let anchorID else { return false }
        return selectedPaths.contains(standardizedPath(anchorID))
    }

    /// 같은 root의 우회 reload(sort/group·hidden toggle)가 세대를 올리기 전에 전이 소유자를 재기준화한다.
    static func rebaseForSameRootReload(
        navigationState: ContentPageNavigationRoute,
        state: inout FileManagerContentState,
    ) {
        guard let transition = state.pendingIdentityTransition,
              case let .folder(currentPath) = navigationState,
              canonicalizedPath(currentPath) == transition.rootPath
        else { return }
        rebaseForNextRootReload(state: &state)
        // 이 reload는 모든 expanded folder도 재시작하므로 folder 소유자 세대도 동행한다.
        rebaseForHierarchyInvalidation(
            affectedPaths: Array(state.entryViewLayout.hierarchy.expandedFolderIDs),
            state: &state,
        )
    }

    static func rebaseFolderOwnersAfterRootSnapshot(on action: FileManagerContentAction,
                                                    state: inout FileManagerContentState)
    {
        guard case .entryViewLayout(.hierarchy(.rootSnapshotCompleted)) = action,
              var transition = state.pendingIdentityTransition
        else { return }
        func rebased(_ owner: FileManagerContentState.EntryIdentityTransitionProjectionOwner)
            -> FileManagerContentState.EntryIdentityTransitionProjectionOwner
        {
            guard case let .folder(id, generation) = owner,
                  let currentGeneration = state.entryViewLayout.hierarchy.nodesByID[id]?.generation,
                  currentGeneration == generation &+ 1
            else { return owner }
            return .folder(id: id, generation: currentGeneration)
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

    static func resolveFolderTransition(
        on action: FileManagerContentAction,
        state: inout FileManagerContentState,
    ) {
        if resolveDestinationCollapse(on: action, state: &state) {
            return
        }
        if resolveAdditionalRootDestinationFailure(on: action, state: &state) {
            return
        }
        _ = resolvePrimaryOwnedDestinationTerminal(on: action, state: &state)
        if resolveAdditionalDestinationTerminal(on: action, state: &state) {
            return
        }
        if resolvePreservationOwnerTerminal(on: action, state: &state) {
            return
        }
        guard case let .entryViewLayout(.hierarchy(.folderChildrenResponse(
            _, folderID, folderGeneration, response,
        ))) = action,
            let transition = state.pendingIdentityTransition,
            case let .folder(expectedID, expectedGeneration) = transition.projectionOwner
        else { return }
        guard ownerIsCurrent(transition.projectionOwner, state: state) else {
            discard(state: &state)
            return
        }
        guard standardizedPath(folderID) == standardizedPath(expectedID),
              folderGeneration == expectedGeneration,
              let node = state.entryViewLayout.hierarchy.nodesByID[folderID]
        else { return }
        let isTerminal = switch response {
        case .event(.coreFinished):
            node.folder.coreFinished
        case .streamCompleted:
            node.loadPhase == .loaded
        case .failed:
            if case .failed = node.loadPhase { true } else { false }
        case .event(.coreBatch), .event(.metadataPatches):
            false
        }
        guard isTerminal else { return }
        if !transition.primaryMigrated {
            var terminalTransition = transition
            terminalTransition.primaryMigrated = true
            state.pendingIdentityTransition = terminalTransition
            commitMigratedSourceStagings(transition: terminalTransition, state: &state)
        }
        guard !hasPendingDestinationPairs(state) else { return }
        discard(state: &state)
    }

    /// A destination batch may migrate the selection before the source folder finishes.
    /// When that source owner reaches its terminal, release its held staging as well; otherwise
    /// the identity transition survives forever because the generic destination path is no
    /// longer the action's folder owner.
    private static func resolvePreservationOwnerTerminal(
        on action: FileManagerContentAction,
        state: inout FileManagerContentState,
    ) -> Bool {
        guard case let .entryViewLayout(.hierarchy(.folderChildrenResponse(
            rootContextGeneration,
            folderID,
            folderGeneration,
            response,
        ))) = action,
            rootContextGeneration == state.entryViewLayout.hierarchy.rootContextGeneration,
            let transition = state.pendingIdentityTransition,
            let node = state.entryViewLayout.hierarchy.nodesByID[folderID],
            node.generation == folderGeneration,
            sourceFolderIDs(transition: transition).contains(folderID)
        else { return false }
        let isTerminal = switch response {
        case .event(.coreFinished):
            node.folder.coreFinished
        case .streamCompleted:
            node.loadPhase == .loaded
        case .failed:
            if case .failed = node.loadPhase { true } else { false }
        case .event(.coreBatch), .event(.metadataPatches):
            false
        }
        guard isTerminal else { return false }

        // The source hold is only meaningful while a destination pair still waits for its
        // after row. Once all destinations have projected, this terminal owns the final source
        // commit. Failed source loads release the hold without replacing the retained snapshot.
        state.pendingIdentityTransition = transition
        commitMigratedSourceStagings(transition: transition, state: &state)
        if case .failed = node.loadPhase {
            state.entryViewLayout.hierarchy.commitDeferredFolderReplacementsOnCancel()
        }
        guard !hasPendingDestinationPairs(state) else { return true }
        // Any source hold that is still loading is now generic reload state; discard converts
        // migration-specific holds before removing the page transition.
        discard(state: &state)
        return true
    }

    private static func sourceFolderIDs(
        transition: FileManagerContentState.EntryIdentityTransition,
    ) -> Set<EntryModel.ID> {
        var sourceIDs: Set<EntryModel.ID> = []
        if case let .folder(ownerID, _) = transition.preservationOwner {
            sourceIDs.insert(ownerID)
        }
        for move in transition.additionalMoves {
            if case let .folder(ownerID, _) = move.sourceOwner ?? transition.projectionOwner {
                sourceIDs.insert(ownerID)
            }
        }
        return sourceIDs
    }

    /// collapsed folder가 소유한 destination을 response 없는 cancellation terminal로 종결한다.
    private static func resolveDestinationCollapse(
        on action: FileManagerContentAction,
        state: inout FileManagerContentState,
    ) -> Bool {
        guard case let .entryViewLayout(.hierarchy(.folderCollapseRequested(folderID))) = action,
              var transition = state.pendingIdentityTransition
        else { return false }
        var resolved = false
        if !transition.primaryMigrated,
           case let .folder(primaryID, _) = transition.projectionOwner,
           standardizedPath(primaryID) == standardizedPath(folderID)
        {
            transition.primaryMigrated = true
            resolved = true
        }
        for index in transition.additionalMoves.indices where !transition.additionalMoves[index].migrated {
            let owner = transition.additionalMoves[index].destinationOwner ?? transition.projectionOwner
            guard case let .folder(ownerID, _) = owner,
                  standardizedPath(ownerID) == standardizedPath(folderID)
            else { continue }
            transition.additionalMoves[index].migrated = true
            resolved = true
        }
        guard resolved else { return false }
        if state.entryViewLayout.hierarchy.deferredFolderReplacement(folderID: folderID)?.holdsUntilMigration == false {
            _ = state.entryViewLayout.hierarchy.takeDeferredFolderReplacement(folderID: folderID)
        }
        state.pendingIdentityTransition = transition
        commitMigratedSourceStagings(transition: transition, state: &state)
        if transition.primaryMigrated || primaryOwnerIsTerminal(transition, state: state),
           !hasPendingDestinationPairs(state)
        {
            discard(state: &state)
        }
        return true
    }

    /// primary folder terminal을 공유하는 nil-owner additional pair를 함께 종결한다.
    private static func resolvePrimaryOwnedDestinationTerminal(
        on action: FileManagerContentAction,
        state: inout FileManagerContentState,
    ) -> Bool {
        guard case let .entryViewLayout(.hierarchy(.folderChildrenResponse(
            rootContextGeneration, folderID, folderGeneration, response,
        ))) = action,
            rootContextGeneration == state.entryViewLayout.hierarchy.rootContextGeneration,
            var transition = state.pendingIdentityTransition,
            case let .folder(expectedID, expectedGeneration) = transition.projectionOwner,
            standardizedPath(folderID) == standardizedPath(expectedID),
            folderGeneration == expectedGeneration,
            let node = state.entryViewLayout.hierarchy.nodesByID[folderID],
            node.generation == folderGeneration,
            transition.additionalMoves.contains(where: { $0.destinationOwner == nil && !$0.migrated })
        else { return false }
        let isTerminal = switch response {
        case .event(.coreFinished):
            node.folder.coreFinished
        case .streamCompleted:
            node.loadPhase == .loaded
        case .failed:
            if case .failed = node.loadPhase { true } else { false }
        case .event(.coreBatch), .event(.metadataPatches):
            false
        }
        guard isTerminal else { return false }
        for index in transition.additionalMoves.indices
            where transition.additionalMoves[index].destinationOwner == nil
            && !transition.additionalMoves[index].migrated
        {
            transition.additionalMoves[index].migrated = true
        }
        state.pendingIdentityTransition = transition
        commitMigratedSourceStagings(transition: transition, state: &state)
        if transition.primaryMigrated || primaryOwnerIsTerminal(transition, state: state),
           !hasPendingDestinationPairs(state)
        {
            discard(state: &state)
        }
        return true
    }

    /// current root 실패를 matching additional root destination의 terminal로 기록한다.
    private static func resolveAdditionalRootDestinationFailure(
        on action: FileManagerContentAction,
        state: inout FileManagerContentState,
    ) -> Bool {
        guard case let .entryViewLayout(.entryOperations(.loading(.streamFailed(streamGeneration)))) = action,
              state.entryViewLayout.entryOperations.loadingContext.generation == streamGeneration,
              state.entryViewLayout.entryOperations.loadingContext.streamTerminal,
              state.entryViewLayout.entryOperations.loadingContext.isIncomplete,
              var transition = state.pendingIdentityTransition,
              transition.additionalMoves.contains(where: { move in
                  guard !move.migrated else { return false }
                  // nil destinationOwner는 primary projectionOwner를 공유하는 sentinel이다.
                  let owner = move.destinationOwner ?? transition.projectionOwner
                  guard case let .root(generation) = owner else { return false }
                  return generation == streamGeneration
              })
        else { return false }
        for index in transition.additionalMoves.indices {
            guard !transition.additionalMoves[index].migrated else { continue }
            let owner = transition.additionalMoves[index].destinationOwner ?? transition.projectionOwner
            guard case let .root(generation) = owner,
                  generation == streamGeneration
            else { continue }
            transition.additionalMoves[index].migrated = true
        }
        state.pendingIdentityTransition = transition
        commitMigratedSourceStagings(transition: transition, state: &state)
        if transition.primaryMigrated || primaryOwnerIsTerminal(transition, state: state),
           !hasPendingDestinationPairs(state)
        {
            discard(state: &state)
        }
        return true
    }

    /// additional destination의 성공·실패 terminal을 pair 상태에 반영한다.
    private static func resolveAdditionalDestinationTerminal(
        on action: FileManagerContentAction,
        state: inout FileManagerContentState,
    ) -> Bool {
        guard case let .entryViewLayout(.hierarchy(.folderChildrenResponse(
            rootContextGeneration, folderID, folderGeneration, response,
        ))) = action,
            rootContextGeneration == state.entryViewLayout.hierarchy.rootContextGeneration,
            var transition = state.pendingIdentityTransition,
            transition.additionalMoves.contains(where: { pair in
                guard case let .folder(id, generation) = pair.destinationOwner else { return false }
                return standardizedPath(id) == standardizedPath(folderID)
                    && generation == folderGeneration
            }),
            let node = state.entryViewLayout.hierarchy.nodesByID[folderID],
            node.generation == folderGeneration
        else { return false }
        let isTerminal = switch response {
        case .event(.coreFinished):
            node.folder.coreFinished
        case .failed:
            if case .failed = node.loadPhase { true } else { false }
        case .event(.coreBatch), .event(.metadataPatches), .streamCompleted:
            false
        }
        guard isTerminal else { return false }
        markDestinationPairsResolved(
            folderID: folderID,
            folderGeneration: folderGeneration,
            transition: &transition,
        )
        state.pendingIdentityTransition = transition
        // terminalized pair의 source staging을 즉시 정산한다. 다른 destination이
        // pending이어도 해당 source의 ghost before 행을 유지하면 안 된다.
        commitMigratedSourceStagings(transition: transition, state: &state)
        if transition.primaryMigrated || primaryOwnerIsTerminal(transition, state: state),
           !hasPendingDestinationPairs(state)
        {
            discard(state: &state)
        }
        return true
    }

    /// reducer 적용 후 primary owner가 성공·실패 terminal에 도달했는지 판정한다.
    static func primaryOwnerIsTerminal(
        _ transition: FileManagerContentState.EntryIdentityTransition,
        state: FileManagerContentState,
    ) -> Bool {
        switch transition.projectionOwner {
        case .root:
            return state.entryViewLayout.entryOperations.loadingContext.streamTerminal
        case let .folder(id, generation):
            guard let node = state.entryViewLayout.hierarchy.nodesByID[id],
                  node.generation == generation
            else { return false }
            if node.folder.coreFinished || node.loadPhase == .loaded {
                return true
            }
            if case .failed = node.loadPhase {
                return true
            }
            return false
        }
    }

    /// destination 폴더에 속한 미해소 pair들을 해소 처리한다.
    private static func markDestinationPairsResolved(
        folderID: EntryModel.ID,
        folderGeneration: Int,
        transition: inout FileManagerContentState.EntryIdentityTransition,
    ) {
        for index in transition.additionalMoves.indices {
            guard case let .folder(id, generation) = transition.additionalMoves[index].destinationOwner,
                  standardizedPath(id) == standardizedPath(folderID),
                  generation == folderGeneration,
                  !transition.additionalMoves[index].migrated
            else { continue }
            transition.additionalMoves[index].migrated = true
        }
    }

    static func expireOnNavigation(
        _ navigationState: ContentPageNavigationRoute,
        state: inout FileManagerContentState,
    ) {
        guard state.pendingIdentityTransition != nil else { return }
        if case let .folder(newPath) = navigationState,
           case let .folder(currentPath) = state.navigation.navigationState,
           standardizedPath(newPath) == standardizedPath(currentPath)
        {
            return
        }
        discard(state: &state)
    }

    private static func replacementTrigger(
        _ action: FileManagerContentAction,
        transition: FileManagerContentState.EntryIdentityTransition,
    ) -> ReplacementTrigger? {
        switch action {
        case .entryViewLayout(.entryOperations(.loading(.itemsLoaded))):
            return .migration
        case let .entryViewLayout(.entryOperations(.loading(.streamEvent(streamEvent)))):
            guard case .coreBatch = streamEvent.event else { return nil }
            return .migration
        case .entryViewLayout(.view(.applyContentProjection)):
            return .migration
        case .entryViewLayout(.hierarchy(.rootSnapshotCompleted)):
            if case .folder = transition.projectionOwner { return .migration }
            return nil
        case let .entryViewLayout(.hierarchy(.folderChildrenResponse(
            _, folderID, folderGeneration, .event(.coreBatch),
        ))):
            if case let .folder(expectedID, expectedGeneration) = transition.projectionOwner,
               standardizedPath(folderID) == standardizedPath(expectedID),
               folderGeneration == expectedGeneration
            {
                return .migration
            }
            if case let .folder(preservedID, preservedGeneration) = transition.preservationOwner,
               standardizedPath(folderID) == standardizedPath(preservedID),
               folderGeneration == preservedGeneration
            {
                return .preservation
            }
            return nil
        default:
            return nil
        }
    }

    private static func replacementProjectionPaths(
        owner: FileManagerContentState.EntryIdentityTransitionProjectionOwner,
        state: FileManagerContentState,
    ) -> Set<String> {
        switch owner {
        case .root:
            Set(state.entryViewLayout.entryOperations.loadingContext.items.map { standardizedPath($0.id) })
        case let .folder(id, _):
            Set(state.entryViewLayout.hierarchy.nodesByID[id]?.folder.children.map {
                standardizedPath($0.id)
            } ?? [])
        }
    }

    private static func visibleEntryPaths(in state: FileManagerContentState) -> Set<String> {
        let flatPaths = state.entryViewLayout.entries.map(\.id).map(standardizedPath)
        let hierarchyPaths = state.entryViewLayout.hierarchy.nodesByID.values
            .flatMap(\.folder.children)
            .map(\.id)
            .map(standardizedPath)
        return Set(flatPaths + hierarchyPaths)
    }

    private enum ReplacementTrigger {
        case migration
        case preservation
    }
}
