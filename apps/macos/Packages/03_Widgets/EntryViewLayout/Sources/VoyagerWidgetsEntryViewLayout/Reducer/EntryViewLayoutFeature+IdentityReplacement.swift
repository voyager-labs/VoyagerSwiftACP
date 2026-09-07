import ComposableArchitecture
import Foundation
import VoyagerEntitiesEntry
import VoyagerFeaturesEntryOperations

extension EntryViewLayoutFeature {
    func beginIdentityReplacementFromRecord(
        _ record: EntryActionRecord,
        state: inout State,
    ) -> Effect<Action> {
        guard !state.isCollectionMode,
              !state.hierarchy.rootPath.isEmpty,
              record.operationKind == .rename || record.operationKind == .pasteFileMove
        else {
            return .none
        }
        let lexicalRootPath = standardizedPath(state.hierarchy.rootPath)
        let rootPath = canonicalizedPath(lexicalRootPath)
        let selectedPaths = Set(state.selectedIds.map(canonicalizedPath))
        let pairs = record.targets.compactMap { target -> EntryIdentityReplacementPair? in
            guard let beforePath = target.beforePath,
                  let afterPath = target.afterPath,
                  selectedPaths.contains(canonicalizedPath(beforePath)),
                  isSameOrDescendant(path: standardizedPath(beforePath), of: lexicalRootPath),
                  record.targets.count(where: {
                      guard let candidate = $0.beforePath else { return false }
                      return canonicalizedPath(candidate) == canonicalizedPath(beforePath)
                  }) == 1,
                  canonicalizedPath(beforePath) != canonicalizedPath(afterPath)
            else { return nil }
            return .init(
                beforePath: canonicalizedPath(beforePath),
                afterPath: canonicalizedPath(afterPath),
                beforeLexicalPath: beforePath,
                afterLexicalPath: afterPath,
            )
        }
        guard !pairs.isEmpty else { return .none }
        return handleIdentityReplacementAction(
            .begin(.init(
                transactionID: record.id,
                rootPath: canonicalizedPath(rootPath),
                pairs: pairs,
            )),
            state: &state,
        )
    }

    func handleIdentityReplacementAction(
        _ action: EntryIdentityReplacementAction,
        state: inout State,
    ) -> Effect<Action> {
        switch action {
        case let .begin(plan):
            beginIdentityReplacement(plan, state: &state)

        case let .cancel(id, _):
            finishIdentityReplacement(id: id, state: &state)

        case let .settle(id, _):
            finishIdentityReplacement(id: id, state: &state)
        }
    }

    private func beginIdentityReplacement(
        _ plan: EntryIdentityReplacementPlan,
        state: inout State,
    ) -> Effect<Action> {
        guard !plan.pairs.isEmpty,
              !state.hierarchy.rootPath.isEmpty,
              canonicalizedPath(plan.rootPath) == canonicalizedPath(state.hierarchy.rootPath)
        else { return .none }
        var supersededEffect: Effect<Action> = .none
        if let existingTransactionID = state.identityReplacement?.plan.transactionID {
            supersededEffect = handleIdentityReplacementAction(
                .cancel(id: existingTransactionID, reason: .superseded),
                state: &state,
            )
        }
        state.identityReplacement = .init(plan: plan)
        for pair in plan.pairs {
            let beforePath = pair.beforeLexicalPath.isEmpty ? pair.beforePath : pair.beforeLexicalPath
            guard let sourceID = state.hierarchy.nodesByID.keys.first(where: {
                standardizedPath(parentPath(for: beforePath)) == standardizedPath($0)
            }) else { continue }
            let afterPath = pair.afterLexicalPath.isEmpty ? pair.afterPath : pair.afterLexicalPath
            let destinationPath = standardizedPath(parentPath(for: afterPath))
            guard standardizedPath(sourceID) != destinationPath else { continue }
            state.identityReplacement?.sourceFolderIDs.insert(sourceID)
            state.hierarchy.beginDeferredFolderReplacement(
                folderID: sourceID,
                untilEntryID: afterPath,
                holdsUntilMigration: true,
            )
        }
        return supersededEffect
    }

    private func finishIdentityReplacement(
        id: UUID,
        state: inout State,
    ) -> Effect<Action> {
        guard state.identityReplacement?.plan.transactionID == id else { return .none }
        let previousSelection = state.selectedIds
        state.identityReplacement = nil
        state.hierarchy.commitDeferredFolderReplacementsOnCancel()
        state.reconcileSelectionWithVisibleEntries()
        guard previousSelection != state.selectedIds else { return .none }
        return .send(.delegate(.selectionChanged))
    }

    func handleIdentityReplacementEntryOperationsAction(
        _ action: EntryOperationsFeature.Action,
        state: inout State,
    ) -> Effect<Action> {
        guard case let .loading(.itemsLoaded(_, items)) = action else {
            return .none
        }
        return applyIdentityReplacementEntries(items, state: &state)
    }

    func handleIdentityReplacementHierarchyAction(
        _ action: EntryListHierarchyAction,
        state: inout State,
    ) -> Effect<Action> {
        guard case let .folderChildrenResponse(_, _, _, response) = action,
              case let .event(.coreBatch(items, _)) = response
        else { return .none }
        return applyIdentityReplacementEntries(items, state: &state)
    }

    func applyIdentityReplacementEntries(
        _ entries: [EntryModel],
        state: inout State,
    ) -> Effect<Action> {
        guard var replacement = state.identityReplacement else { return .none }
        let previousSelection = state.selectedIds
        let previousLastSelectedID = state.lastSelectedId
        let previousRangeAnchorID = state.rangeAnchorId

        projectIdentityReplacementEntries(entries, replacement: &replacement, state: &state)

        state.identityReplacement = replacement
        let allProjected = replacement.projectedPairIndexes.count == replacement.plan.pairs.count
        let hasOwnedDeferredReplacement = replacement.sourceFolderIDs.contains {
            state.hierarchy.deferredFolderReplacement(folderID: $0) != nil
        }
        guard allProjected, !hasOwnedDeferredReplacement else {
            guard previousSelection != state.selectedIds
                || previousLastSelectedID != state.lastSelectedId
                || previousRangeAnchorID != state.rangeAnchorId
            else { return .none }
            return .send(.delegate(.selectionChanged))
        }

        let transactionID = replacement.plan.transactionID
        state.identityReplacement = nil
        var effects: [Effect<Action>] = [
            .send(.delegate(.identityReplacementSettled(id: transactionID, outcome: .completed))),
        ]
        if previousSelection != state.selectedIds
            || previousLastSelectedID != state.lastSelectedId
            || previousRangeAnchorID != state.rangeAnchorId
        {
            effects.insert(.send(.delegate(.selectionChanged)), at: 0)
        }
        return .merge(effects)
    }

    private func projectIdentityReplacementEntries(
        _ entries: [EntryModel],
        replacement: inout EntryIdentityReplacementState,
        state: inout State,
    ) {
        for (index, pair) in replacement.plan.pairs.enumerated() {
            let afterPath = pair.afterLexicalPath.isEmpty ? pair.afterPath : pair.afterLexicalPath
            guard entries.contains(where: { standardizedPath($0.id) == standardizedPath(afterPath) }) else {
                continue
            }
            replacement.projectedPairIndexes.insert(index)

            let beforePath = pair.beforeLexicalPath.isEmpty ? pair.beforePath : pair.beforeLexicalPath
            guard let beforeID = state.selectedIds.first(where: {
                standardizedPath($0) == standardizedPath(beforePath)
            }),
                let afterID = entries.first(where: {
                    standardizedPath($0.id) == standardizedPath(afterPath)
                })?.id
            else { continue }
            state.selectedIds.remove(beforeID)
            state.selectedIds.insert(afterID)
            if state.lastSelectedId == beforeID {
                state.lastSelectedId = afterID
            }
            if state.rangeAnchorId == beforeID {
                state.rangeAnchorId = afterID
            }
        }
    }

    func canonicalizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
    }

    func parentPath(for path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.deletingLastPathComponent().path
    }

    func isSameOrDescendant(path: String, of ancestor: String) -> Bool {
        let pathComponents = URL(fileURLWithPath: path).pathComponents
        let ancestorComponents = URL(fileURLWithPath: ancestor).pathComponents
        return pathComponents.starts(with: ancestorComponents)
    }
}
