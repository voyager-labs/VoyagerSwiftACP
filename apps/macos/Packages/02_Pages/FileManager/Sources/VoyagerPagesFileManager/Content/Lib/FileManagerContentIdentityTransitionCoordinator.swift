import ComposableArchitecture
import Foundation
import VoyagerEntitiesEntry
import VoyagerFeaturesContentPageNavigation
import VoyagerFeaturesEntryOperations

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
        guard movedTargets.count(where: { $0.before == move.before }) == 1 else { return .none }
        guard isSameOrDescendant(path: move.before, of: normalizedRoot) else { return .none }

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
        state.entryViewLayout.hierarchy.discardAllDeferredFolderReplacements()
        state.pendingIdentityTransition = .init(
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

    @discardableResult
    static func migrateSelection(
        entries: [EntryModel],
        projectionOwner: FileManagerContentState.EntryIdentityTransitionProjectionOwner,
        state: inout FileManagerContentState,
    ) -> Bool {
        guard let transition = state.pendingIdentityTransition else { return false }
        guard case let .folder(currentPath) = state.navigation.navigationState,
              canonicalizedPath(currentPath) == transition.rootPath
        else {
            discard(state: &state)
            return false
        }
        guard validateProjectionOwner(
            transition.projectionOwner,
            actual: projectionOwner,
            state: &state,
        ) else { return false }
        let matchedBeforeID = state.entryViewLayout.selectedIds.first {
            canonicalizedPath($0) == transition.beforePath
        }
        guard let matchedBeforeID else {
            discard(state: &state)
            return false
        }
        let standardizedAfter = standardizedPath(afterLexicalPath(transition))
        guard let matchedAfterID = entries.first(where: {
            standardizedPath($0.id) == standardizedAfter
        })?.id else { return false }

        state.entryViewLayout.selectedIds.remove(matchedBeforeID)
        state.entryViewLayout.selectedIds.insert(matchedAfterID)
        state.entryViewLayout.lastSelectedId = matchedAfterID
        state.entryViewLayout.rangeAnchorId = matchedAfterID
        // takeDeferredFolderReplacement는 이미 staging을 제거하므로, 빈 snapshot도
        // authoritative 결과로 커밋해 retained before 행이 terminal 뒤에 남지 않게 한다.
        // 단 이번 세대에 generic 적용이 먼저 일어난 폴더(hasAppliedContentBatch=true)의
        // 실제 children을 빈 staging으로 덮어쓰지 않는다.
        if case let .folder(preservationID, _) = transition.preservationOwner,
           var targetNode = state.entryViewLayout.hierarchy.nodesByID[preservationID],
           let staged = state.entryViewLayout.hierarchy.takeDeferredFolderReplacement(folderID: preservationID),
           !targetNode.folder.hasAppliedContentBatch
        {
            targetNode.folder.children = staged
            targetNode.folder.hasAppliedContentBatch = true
            state.entryViewLayout.hierarchy.nodesByID[preservationID] = targetNode
        }
        if case .root = projectionOwner {
            discard(state: &state)
        }
        return true
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
                node.generation == generation || node.generation &+ 1 == generation
            } else {
                false
            }
        }
    }

    static func rebaseForNextRootReload(state: inout FileManagerContentState) {
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
                  node.generation == generation
            else { return owner }
            return .folder(id: id, generation: generation &+ 1)
        }
        transition.projectionOwner = rebased(transition.projectionOwner)
        transition.preservationOwner = transition.preservationOwner.map(rebased)
        state.pendingIdentityTransition = transition
    }

    static func transitionOverlaps(
        _ eventPath: String,
        _ transition: FileManagerContentState.EntryIdentityTransition,
    ) -> Bool {
        let normalizedEventPath = canonicalizedPath(eventPath)
        return isSameOrDescendant(path: normalizedEventPath, of: transition.beforePath)
            || isSameOrDescendant(path: normalizedEventPath, of: transition.afterPath)
            || isSameOrDescendant(path: transition.beforePath, of: normalizedEventPath)
            || isSameOrDescendant(path: transition.afterPath, of: normalizedEventPath)
    }

    static func discard(state: inout FileManagerContentState) {
        state.pendingIdentityTransition = nil
        state.entryViewLayout.hierarchy.discardAllDeferredFolderReplacements()
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
            guard canonicalizedPath(expectedID) == canonicalizedPath(actualID) else { return false }
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
        guard let folderID = state.entryViewLayout.hierarchy.nodesByID.keys.first(where: {
            standardizedPath($0) == directParentPath || canonicalizedPath($0) == directParentPath
        }),
            state.entryViewLayout.hierarchy.expandedFolderIDs.contains(folderID),
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
