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
            return canonicalizedPath(ownerID) == canonicalizedPath(folderID)
        }) {
            shouldDefer = true
            holdsUntilMigration = true
        }
        if shouldDefer == nil,
           !transition.primaryMigrated,
           case let .folder(ownerID, _) = transition.projectionOwner,
           canonicalizedPath(ownerID) == canonicalizedPath(folderID)
        {
            let afterIdentity = afterLexicalPath(transition)
            shouldDefer = !items.contains {
                standardizedPath($0.id) == standardizedPath(afterIdentity)
            }
        }
        if case let .folder(ownerID, _) = transition.preservationOwner,
           canonicalizedPath(ownerID) == canonicalizedPath(folderID),
           shouldDefer == nil
        {
            shouldDefer = true
            // 보존(소스) 폴더는 destination migration까지 staging을 보류한다.
            // 소스 coreFinished가 먼저 도착해도 retained before 행을 유지해 선택 깜빡임을 막는다.
            holdsUntilMigration = true
        }
        if shouldDefer == nil {
            // 다중 이동: additional destination 폴더도 after 행 도착까지 retained children을 유지한다.
            // 같은 destination을 공유하는 pair가 여러 개면 모든 pending after가 도착했을 때만
            // combine하도록 untilEntryID를 미도착 after로 갱신해 누적한다.
            var pendingAfters: [String] = []
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
                state.entryViewLayout.hierarchy.upsertDeferredFolderReplacement(
                    folderID: folderID,
                    untilEntryID: nextUntil,
                )
            }
        }
        if shouldDefer == nil {
            // 다중 이동: additional 이동의 source 폴더도 primary 보존과 동일하게 보류한다.
            for move in transition.additionalMoves where !move.migrated {
                guard case let .folder(ownerID, _) = move.sourceOwner ?? transition.projectionOwner,
                      canonicalizedPath(ownerID) == canonicalizedPath(folderID)
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
            state.entryViewLayout.lastSelectedId = restoredID
            state.entryViewLayout.rangeAnchorId = restoredID
            return
        }
        if selectedPaths.contains(afterPath) {
            // 다중 이동: 다른 destination의 pending pair가 남아 있으면 전이를 유지한다.
            if !hasPendingDestinationPairs(state) {
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

    static func rebaseFolderOwnersAfterRootSnapshot(
        on action: FileManagerContentAction,
        state: inout FileManagerContentState,
    ) {
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
        if resolveAdditionalRootDestinationFailure(on: action, state: &state) {
            return
        }
        if resolveAdditionalDestinationTerminal(on: action, state: &state) {
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
        guard canonicalizedPath(folderID) == canonicalizedPath(expectedID),
              folderGeneration == expectedGeneration,
              let node = state.entryViewLayout.hierarchy.nodesByID[folderID]
        else { return }
        switch response {
        case .event(.coreFinished):
            guard node.folder.coreFinished else { return }
            guard !hasPendingDestinationPairs(state) else { return }
            discard(state: &state)
        case .streamCompleted:
            guard node.loadPhase == .loaded else { return }
            guard !hasPendingDestinationPairs(state) else { return }
            discard(state: &state)
        case .failed:
            guard case .failed = node.loadPhase else { return }
            guard !hasPendingDestinationPairs(state) else { return }
            discard(state: &state)
        case .event(.coreBatch), .event(.metadataPatches):
            break
        }
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
                  guard !move.migrated, case let .root(generation) = move.destinationOwner else { return false }
                  return generation == streamGeneration
              })
        else { return false }
        for index in transition.additionalMoves.indices {
            guard !transition.additionalMoves[index].migrated,
                  case let .root(generation) = transition.additionalMoves[index].destinationOwner,
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
        guard let transition = state.pendingIdentityTransition else { return }
        if case let .folder(newPath) = navigationState,
           canonicalizedPath(newPath) == transition.rootPath
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
               canonicalizedPath(folderID) == canonicalizedPath(expectedID),
               folderGeneration == expectedGeneration
            {
                return .migration
            }
            if case let .folder(preservedID, preservedGeneration) = transition.preservationOwner,
               canonicalizedPath(folderID) == canonicalizedPath(preservedID),
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
