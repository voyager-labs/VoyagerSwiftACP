import ComposableArchitecture
import Foundation
import VoyagerEntitiesEntry
import VoyagerShared

@Reducer
struct EntryListHierarchyReducer {
    typealias State = EntryViewLayoutState
    typealias Action = EntryViewLayoutAction

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            guard case let .hierarchy(hierarchyAction) = action else { return .none }

            switch hierarchyAction {
            case let .rootContextChanged(path):
                state.hierarchy.replaceRoot(path: path)
                return .merge(
                    .send(.internal(.applyClearSelection)),
                    .send(.internal(.reconcileHierarchySelection)),
                )

            case .hiddenFilesSettingChanged:
                return reloadFoldersForPresentationChange(state: &state)

            case .arrangementMetadataPriorityChanged:
                return reloadFoldersForPresentationChange(state: &state)

            case let .hierarchyInvalidated(affectedPaths, removedPrefixes):
                return invalidateHierarchy(
                    affectedPaths: affectedPaths,
                    removedPrefixes: removedPrefixes,
                    reloadCachedFolders: false,
                    state: &state,
                )

            case let .coarseHierarchyInvalidated(removedPrefixes):
                return invalidateHierarchy(
                    affectedPaths: [],
                    removedPrefixes: removedPrefixes,
                    reloadCachedFolders: true,
                    state: &state,
                )

            case let .rootSnapshotCompleted(rootFolderIDs):
                let removedPrefixes = state.hierarchy.foldersByID.keys.filter {
                    isImmediateRootFolder($0, rootPath: state.hierarchy.rootPath)
                        && !rootFolderIDs.contains($0)
                }
                return invalidateHierarchy(
                    affectedPaths: [],
                    removedPrefixes: removedPrefixes,
                    state: &state,
                )

            case .showHiddenFilesRefreshRequested:
                return refreshHierarchyForShowHiddenFiles(state: &state)

            case .coarseHierarchyRefreshRequested:
                return refreshHierarchyForShowHiddenFiles(state: &state)

            case let .folderExpansionRequested(id):
                guard hierarchyInteractionsAreEnabled(in: state) else { return .none }
                guard let folder = folder(id: id, in: state),
                      folder.supportsListHierarchyExpansion else { return .none }
                guard folderIsWithinCurrentRoot(id, state: state) else { return .none }
                state.hierarchy.expandedFolderIDs.insert(id)

                let folderState = state.hierarchy.foldersByID[id] ?? .init()
                switch folderState.phase {
                case .loaded, .loading:
                    state.reconcileSelectionWithVisibleEntries()
                    return .none
                case .idle, .failed:
                    return startLoad(folder: folder, id: id, state: &state)
                }

            case let .folderRetryRequested(id):
                guard hierarchyInteractionsAreEnabled(in: state) else { return .none }
                guard let folder = folder(id: id, in: state),
                      folder.supportsListHierarchyExpansion else { return .none }
                guard folderIsWithinCurrentRoot(id, state: state) else { return .none }
                state.hierarchy.expandedFolderIDs.insert(id)
                return startLoad(folder: folder, id: id, state: &state)

            case let .folderCollapseRequested(id):
                state.hierarchy.expandedFolderIDs.remove(id)
                var folderState = state.hierarchy.foldersByID[id] ?? .init()
                if folderState.phase != .loaded {
                    folderState.generation &+= 1
                    folderState.children = []
                    folderState.phase = .idle
                    folderState.expectedBatchIndex = 0
                    folderState.coreFinished = false
                }
                state.hierarchy.foldersByID[id] = folderState
                return .send(.internal(.reconcileHierarchySelection))

            case let .folderChildrenResponse(rootContextGeneration, folderID, folderGeneration, response):
                guard rootContextGeneration == state.hierarchy.rootContextGeneration,
                      var folderState = state.hierarchy.foldersByID[folderID],
                      folderState.generation == folderGeneration,
                      folderState.phase == .loading
                else { return .none }

                let wasCoreFinished = folderState.coreFinished
                guard apply(response: response, to: &folderState) else { return .none }
                state.hierarchy.foldersByID[folderID] = folderState

                if !wasCoreFinished,
                   folderState.coreFinished,
                   case .event(.coreFinished) = response
                {
                    let childIDs = Set(
                        folderState.children
                            .filter(\.supportsListHierarchyExpansion)
                            .map(\.id),
                    )
                    let staleDescendants = state.hierarchy.foldersByID.keys.filter {
                        isImmediateChildFolder($0, parentID: folderID) && !childIDs.contains($0)
                    }
                    if !staleDescendants.isEmpty {
                        return invalidateHierarchy(
                            affectedPaths: [],
                            removedPrefixes: Array(staleDescendants),
                            state: &state,
                        )
                    }
                }

                state.reconcileSelectionWithVisibleEntries()
                return .none
            }
        }
    }

    private func startLoad(
        folder _: EntryModel,
        id: EntryModel.ID,
        state: inout State,
    ) -> Effect<Action> {
        var folderState = state.hierarchy.foldersByID[id] ?? .init()
        folderState.generation &+= 1
        folderState.phase = .loading
        folderState.children = []
        folderState.expectedBatchIndex = 0
        folderState.coreFinished = false
        state.hierarchy.foldersByID[id] = folderState
        state.reconcileSelectionWithVisibleEntries()

        return .send(.delegate(.expandRequested(id)))
    }

    private func invalidateHierarchy(
        affectedPaths: [String],
        removedPrefixes: [String],
        reloadCachedFolders: Bool,
        state: inout State,
    ) -> Effect<Action> {
        let removedIDs = Set(state.hierarchy.foldersByID.keys.filter { id in
            removedPrefixes.contains { isSameOrDescendant(path: id, of: $0) }
        })
        var effects: [Effect<Action>] = []

        for id in removedIDs {
            state.hierarchy.expandedFolderIDs.remove(id)
            state.hierarchy.foldersByID[id] = nil
        }

        if reloadCachedFolders {
            return .merge(effects + [reloadFoldersForPresentationChange(state: &state)])
        }

        var affectedIDs = Set<EntryModel.ID>()
        for path in affectedPaths {
            let canonicalPath = normalizedPath(path)
            if let folderID = state.hierarchy.foldersByID.keys.first(where: {
                normalizedPath($0) == canonicalPath
            }) {
                affectedIDs.insert(folderID)
            }
            if let parentID = nearestLoadedParentID(for: canonicalPath, state: state) {
                affectedIDs.insert(parentID)
            }
        }

        for id in affectedIDs.subtracting(removedIDs) {
            guard let folder = folder(id: id, in: state) else { continue }
            guard folder.supportsListHierarchyExpansion else { continue }
            if state.hierarchy.expandedFolderIDs.contains(id) {
                effects.append(startLoad(folder: folder, id: id, state: &state))
            } else {
                var folderState = state.hierarchy.foldersByID[id] ?? .init()
                folderState.children = []
                folderState.phase = .idle
                folderState.generation &+= 1
                folderState.expectedBatchIndex = 0
                folderState.coreFinished = false
                state.hierarchy.foldersByID[id] = folderState
            }
        }

        state.reconcileSelectionWithVisibleEntries()
        return .merge(effects)
    }

    private func reloadFoldersForPresentationChange(state: inout State) -> Effect<Action> {
        let folderIDs = Array(state.hierarchy.foldersByID.keys)
        let expandedFolders = state.hierarchy.expandedFolderIDs
            .compactMap { id in
                folder(id: id, in: state)
            }
            .filter { folder in
                folder.supportsListHierarchyExpansion && folderIsWithinCurrentRoot(folder.id, state: state)
            }

        for id in folderIDs {
            var folderState = state.hierarchy.foldersByID[id] ?? .init()
            folderState.generation &+= 1
            folderState.children = []
            folderState.phase = .idle
            folderState.expectedBatchIndex = 0
            folderState.coreFinished = false
            state.hierarchy.foldersByID[id] = folderState
        }

        let restartEffects: [Effect<Action>] = expandedFolders.map { folder in
            startLoad(folder: folder, id: folder.id, state: &state)
        }
        return .concatenate(
            .merge(restartEffects),
            .send(.internal(.reconcileHierarchySelection)),
        )
    }

    private func refreshHierarchyForShowHiddenFiles(state: inout State) -> Effect<Action> {
        reloadFoldersForPresentationChange(state: &state)
    }

    private func folder(id: EntryModel.ID, in state: State) -> EntryModel? {
        state.entries.first(where: { $0.id == id })
            ?? state.hierarchy.foldersByID.values.lazy
            .flatMap(\.children)
            .first(where: { $0.id == id })
    }

    private func hierarchyInteractionsAreEnabled(in state: State) -> Bool {
        state.mode == .list
            && !state.isCollectionMode
            && state.groupKey == .none
            && !state.hierarchy.rootPath.isEmpty
    }

    private func folderIsWithinCurrentRoot(_ id: EntryModel.ID, state: State) -> Bool {
        isSameOrDescendant(path: id, of: state.hierarchy.rootPath)
    }

    private func isImmediateRootFolder(_ id: EntryModel.ID, rootPath: String) -> Bool {
        let rootComponents = pathComponents(for: rootPath)
        let folderComponents = pathComponents(for: id)
        return folderComponents.count == rootComponents.count + 1
            && folderComponents.starts(with: rootComponents)
    }

    private func isImmediateChildFolder(_ id: EntryModel.ID, parentID: EntryModel.ID) -> Bool {
        let parentComponents = pathComponents(for: parentID)
        let childComponents = pathComponents(for: id)
        return childComponents.count == parentComponents.count + 1
            && childComponents.starts(with: parentComponents)
    }

    private static func metadataPriority(
        for sortKey: VoyagerShared.SortKey,
    ) -> EntryMetadataPriority {
        .active([
            EntryViewLayoutFeature.metadataProbe(for: sortKey),
        ].compactMap(\.self))
    }

    private func apply(
        response: EntryListFolderChildrenResponse,
        to folderState: inout EntryListHierarchyState.FolderChildrenState,
    ) -> Bool {
        switch response {
        case let .event(.coreBatch(items, batchIndex)):
            return applyCoreBatch(items, batchIndex: batchIndex, to: &folderState)

        case let .event(.coreFinished(batchCount)):
            return applyCoreFinished(batchCount, to: &folderState)

        case let .event(.metadataPatches(patches)):
            return applyMetadataPatches(patches, to: &folderState)

        case .streamCompleted:
            guard folderState.coreFinished else { return false }
            folderState.phase = .loaded
            return true

        case let .failed(failure):
            folderState.phase = .failed(failure)
            return true
        }
    }

    private func applyCoreBatch(
        _ items: [EntryModel],
        batchIndex: Int,
        to folderState: inout EntryListHierarchyState.FolderChildrenState,
    ) -> Bool {
        guard !folderState.coreFinished, batchIndex == folderState.expectedBatchIndex else { return false }
        for item in items {
            if let index = folderState.children.firstIndex(where: { $0.id == item.id }) {
                folderState.children[index] = item
            } else {
                folderState.children.append(item)
            }
        }
        folderState.expectedBatchIndex &+= 1
        return true
    }

    private func applyCoreFinished(
        _ batchCount: Int,
        to folderState: inout EntryListHierarchyState.FolderChildrenState,
    ) -> Bool {
        guard !folderState.coreFinished, batchCount == folderState.expectedBatchIndex else { return false }
        folderState.coreFinished = true
        return true
    }

    private func applyMetadataPatches(
        _ patches: [EntryMetadataPatch],
        to folderState: inout EntryListHierarchyState.FolderChildrenState,
    ) -> Bool {
        guard folderState.coreFinished else { return false }
        let patchesByEntryID = Dictionary(grouping: patches, by: metadataPatchEntryID)
        folderState.children = folderState.children.map { child in
            guard let childPatches = patchesByEntryID[child.id] else { return child }
            return childPatches.reduce(child) { $0.applying($1) }
        }
        return true
    }

    private func metadataPatchEntryID(_ patch: EntryMetadataPatch) -> EntryModel.ID {
        switch patch {
        case let .spotlight(id, _, _, _),
             let .tags(id, _),
             let .supplementaryMetadata(id, _):
            id
        }
    }

    private func nearestLoadedParentID(for path: String, state: State) -> EntryModel.ID? {
        state.hierarchy.foldersByID
            .filter {
                ($0.value.phase == .loaded || $0.value.phase == .loading)
                    && isSameOrDescendant(path: path, of: $0.key)
            }
            .map(\.key)
            .max { lhs, rhs in
                pathComponents(for: lhs).count < pathComponents(for: rhs).count
            }
    }

    private func isSameOrDescendant(path: String, of ancestor: String) -> Bool {
        let candidateComponents = pathComponents(for: path)
        let ancestorComponents = pathComponents(for: ancestor)
        return candidateComponents.starts(with: ancestorComponents)
    }

    private func normalizedPath(_ path: String) -> String {
        guard !path.isEmpty else { return path }
        return URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
    }

    private func pathComponents(for path: String) -> [String] {
        URL(fileURLWithPath: normalizedPath(path)).pathComponents
    }
}
