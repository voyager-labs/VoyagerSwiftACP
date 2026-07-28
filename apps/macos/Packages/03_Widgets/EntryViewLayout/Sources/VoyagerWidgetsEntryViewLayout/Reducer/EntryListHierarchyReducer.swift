import ComposableArchitecture
import Foundation
import VoyagerEntitiesEntry
import VoyagerFeaturesEntryArrangements
import VoyagerFeaturesEntryOperations

@Reducer
struct EntryListHierarchyReducer {
    typealias State = EntryViewLayoutState
    typealias Action = EntryViewLayoutAction

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            guard case let .hierarchy(hierarchyAction) = action else { return .none }

            switch hierarchyAction {
            case let .rootContextChanged(path):
                let cancellationRequests = state.hierarchy.foldersByID.keys.map {
                    EntryFolderLoadRequest.RequestID(
                        rootContextGeneration: state.hierarchy.rootContextGeneration,
                        folderID: $0,
                    )
                }
                state.hierarchy.replaceRoot(path: path)
                return .merge(
                    cancellationRequests.map { .send(.entryOperations(.loading(.cancelFolderItems($0)))) }
                        + [.send(.internal(.applyClearSelection)), .send(.internal(.reconcileHierarchySelection))],
                )

            case let .hierarchyInvalidated(affectedPaths, removedPrefixes):
                return invalidateHierarchy(
                    affectedPaths: affectedPaths,
                    removedPrefixes: removedPrefixes,
                    state: &state,
                )

            case let .folderExpansionRequested(id):
                guard hierarchyInteractionsAreEnabled(in: state) else { return .none }
                guard let folder = folder(id: id, in: state),
                      folder.supportsListHierarchyExpansion else { return .none }
                guard folderIsWithinCurrentRoot(id, state: state) else { return .none }
                state.hierarchy.expandedFolderIDs.insert(id)

                let folderState = state.hierarchy.foldersByID[id] ?? .init()
                switch folderState.phase {
                case .loaded, .loading:
                    EntryViewLayoutFeature.reconcileSelectionWithVisibleEntries(&state)
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
                let shouldCancelLoad = folderState.phase != .loaded
                if shouldCancelLoad {
                    folderState.generation &+= 1
                    folderState.children = []
                    folderState.phase = .idle
                    folderState.expectedBatchIndex = 0
                    folderState.coreFinished = false
                }
                state.hierarchy.foldersByID[id] = folderState
                let requestID = EntryFolderLoadRequest.RequestID(
                    rootContextGeneration: state.hierarchy.rootContextGeneration,
                    folderID: id,
                )
                return .merge(
                    shouldCancelLoad ? .send(.entryOperations(.loading(.cancelFolderItems(requestID)))) : .none,
                    .send(.internal(.reconcileHierarchySelection)),
                )

            case let .folderChildrenResponse(rootContextGeneration, folderID, folderGeneration, response):
                guard rootContextGeneration == state.hierarchy.rootContextGeneration,
                      var folderState = state.hierarchy.foldersByID[folderID],
                      folderState.generation == folderGeneration,
                      folderState.phase == .loading
                else { return .none }

                guard apply(response: response, to: &folderState) else { return .none }
                state.hierarchy.foldersByID[folderID] = folderState
                EntryViewLayoutFeature.reconcileSelectionWithVisibleEntries(&state)
                return .none
            }
        }
    }

    private func startLoad(
        folder: EntryModel,
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
        EntryViewLayoutFeature.reconcileSelectionWithVisibleEntries(&state)

        return .send(.entryOperations(.loading(.loadFolderItems(.init(
            rootContextGeneration: state.hierarchy.rootContextGeneration,
            folderID: id,
            folderGeneration: folderState.generation,
            path: folder.fullPath,
            showHidden: state.showHiddenFiles,
            priority: Self.metadataPriority(for: state.entryArrangements),
        )))))
    }

    private func invalidateHierarchy(
        affectedPaths: [String],
        removedPrefixes: [String],
        state: inout State,
    ) -> Effect<Action> {
        let removedIDs = Set(state.hierarchy.foldersByID.keys.filter { id in
            removedPrefixes.contains { isSameOrDescendant(path: id, of: $0) }
        })
        let oldRootGeneration = state.hierarchy.rootContextGeneration
        var effects: [Effect<Action>] = removedIDs.map {
            .send(.entryOperations(.loading(.cancelFolderItems(.init(
                rootContextGeneration: oldRootGeneration,
                folderID: $0,
            )))))
        }

        for id in removedIDs {
            state.hierarchy.expandedFolderIDs.remove(id)
            state.hierarchy.foldersByID[id] = nil
        }

        var affectedIDs = Set<EntryModel.ID>()
        for path in affectedPaths {
            let normalizedPath = normalizedPath(path)
            if state.hierarchy.foldersByID[normalizedPath] != nil {
                affectedIDs.insert(normalizedPath)
            }
            if let parentID = nearestLoadedParentID(for: normalizedPath, state: state) {
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
                effects.append(.send(.entryOperations(.loading(.cancelFolderItems(.init(
                    rootContextGeneration: oldRootGeneration,
                    folderID: id,
                ))))))
            }
        }

        EntryViewLayoutFeature.reconcileSelectionWithVisibleEntries(&state)
        return .merge(effects)
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
            && state.entryArrangements.groupKey == .none
            && !state.hierarchy.rootPath.isEmpty
    }

    private func folderIsWithinCurrentRoot(_ id: EntryModel.ID, state: State) -> Bool {
        isSameOrDescendant(path: id, of: state.hierarchy.rootPath)
    }

    private static func metadataPriority(
        for arrangements: EntryArrangementsFeature.State,
    ) -> EntryMetadataPriority {
        .active([
            EntryViewLayoutFeature.metadataProbe(for: arrangements.sortKey),
            EntryViewLayoutFeature.metadataProbe(for: arrangements.groupKey),
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
        folderState.children = folderState.children.map { child in
            patches.reduce(child) { $0.applying($1) }
        }
        return true
    }

    private func nearestLoadedParentID(for path: String, state: State) -> EntryModel.ID? {
        state.hierarchy.foldersByID
            .filter { $0.value.phase == .loaded && isSameOrDescendant(path: path, of: $0.key) }
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
        URL(fileURLWithPath: path).standardizedFileURL.path
    }

    private func pathComponents(for path: String) -> [String] {
        URL(fileURLWithPath: normalizedPath(path)).pathComponents
    }
}
