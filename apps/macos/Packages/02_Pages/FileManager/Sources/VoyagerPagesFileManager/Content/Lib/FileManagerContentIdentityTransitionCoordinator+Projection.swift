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
        if case let .folder(ownerID, _) = transition.projectionOwner,
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
        guard shouldDefer == true else { return }
        state.entryViewLayout.hierarchy.beginDeferredFolderReplacement(
            folderID: folderID,
            untilEntryID: afterLexicalPath(transition),
            holdsUntilMigration: holdsUntilMigration,
        )
    }

    static func holdsRootProjection(
        on action: FileManagerContentAction,
        state: FileManagerContentState,
    ) -> Bool {
        guard let transition = state.pendingIdentityTransition,
              case let .entryViewLayout(.entryOperations(.loading(.streamEvent(streamEvent)))) = action,
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
        let beforePath = canonicalizedPath(transition.beforePath)
        let afterPath = canonicalizedPath(afterLexicalPath(transition))
        let selectedPaths = Set(state.entryViewLayout.selectedIds.map(canonicalizedPath))
        guard selectedPaths.contains(beforePath), !selectedPaths.contains(afterPath) else { return }
        guard !replacementProjectionPaths(owner: triggerOwner, state: state).contains(afterPath) else { return }
        transition.preservedLexicalBeforeID = state.entryViewLayout.selectedIds.first {
            canonicalizedPath($0) == beforePath
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
                discard(state: &state)
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
            discard(state: &state)
            return
        }
        guard case .root = transition.projectionOwner,
              state.entryViewLayout.entryOperations.loadingContext.coreFinished,
              !visibleEntryPaths(in: state).contains(afterPath),
              !selectedPaths.contains(afterPath)
        else { return }
        discard(state: &state)
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
        state.pendingIdentityTransition = transition
    }

    static func resolveFolderTransition(
        on action: FileManagerContentAction,
        state: inout FileManagerContentState,
    ) {
        guard let transition = state.pendingIdentityTransition,
              case let .folder(expectedID, expectedGeneration) = transition.projectionOwner
        else { return }
        guard ownerIsCurrent(transition.projectionOwner, state: state) else {
            discard(state: &state)
            return
        }
        guard case let .entryViewLayout(.hierarchy(.folderChildrenResponse(
            _, folderID, folderGeneration, response,
        ))) = action,
            canonicalizedPath(folderID) == canonicalizedPath(expectedID),
            folderGeneration == expectedGeneration,
            let node = state.entryViewLayout.hierarchy.nodesByID[folderID]
        else { return }
        switch response {
        case .event(.coreFinished):
            guard node.folder.coreFinished else { return }
            discard(state: &state)
        case .streamCompleted:
            guard node.loadPhase == .loaded else { return }
            discard(state: &state)
        case .failed:
            guard case .failed = node.loadPhase else { return }
            discard(state: &state)
        case .event(.coreBatch), .event(.metadataPatches):
            break
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
            Set(state.entryViewLayout.entryOperations.loadingContext.items.map { canonicalizedPath($0.id) })
        case let .folder(id, _):
            Set(state.entryViewLayout.hierarchy.nodesByID[id]?.folder.children.map {
                canonicalizedPath($0.id)
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
