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
                let previousGeneration = state.hierarchy.rootContextGeneration
                state.hierarchy.replaceRoot(path: path)
                guard state.hierarchy.rootContextGeneration != previousGeneration else { return .none }
                return .merge(
                    .send(.internal(.applyClearSelection)),
                    .send(.internal(.reconcileHierarchySelection)),
                    .send(.delegate(.rootContextChanged(path))),
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

            case let .rootSnapshotCompleted(rootContextGeneration, rootFolders):
                // generation이 일치하지 않으면 NO-OP: stale root completion을 무시한다.
                guard rootContextGeneration == state.hierarchy.rootContextGeneration else { return .none }
                let rootFolderIDs = Set(rootFolders.map(\.id))
                var removedPrefixes: [String] = []
                for id in state.hierarchy.nodesByID.keys {
                    guard isImmediateRootFolder(id, rootPath: state.hierarchy.rootPath),
                          !rootFolderIDs.contains(id)
                    else { continue }
                    removedPrefixes.append(id)
                }
                // recursive eviction via parentID edges
                var idsToRemove = Set<EntryModel.ID>()
                for id in removedPrefixes {
                    idsToRemove.insert(id)
                    let descendants = state.hierarchy.nodesByID.keys.filter {
                        isDescendantViaParentID($0, of: id, in: state.hierarchy.nodesByID)
                    }
                    idsToRemove.formUnion(descendants)
                }
                for id in idsToRemove {
                    state.hierarchy.nodesByID[id] = nil
                }
                // authoritative root folder가 nodesByID에 없으면 생성한다.
                for folder in rootFolders {
                    if state.hierarchy.nodesByID[folder.id] == nil {
                        state.hierarchy.nodesByID[folder.id] = FolderNodeState()
                    }
                }
                // visible expanded intent 중 reload가 필요한 folder를 restart한다.
                var effects: [Effect<Action>] = []
                for folder in rootFolders {
                    guard let nodeState = state.hierarchy.nodesByID[folder.id],
                          nodeState.expansionIntent,
                          nodeState.loadPhase != .loaded
                    else { continue }
                    var refreshedNode = nodeState
                    refreshedNode.generation &+= 1
                    refreshedNode.loadPhase = .loadingCore
                    refreshedNode.folder = FolderSnapshot()
                    state.hierarchy.nodesByID[folder.id] = refreshedNode
                    effects.append(.send(.delegate(.expandRequested(folder.id))))
                }
                state.reconcileSelectionWithVisibleEntries()
                return .merge(effects)

            case .coarseHierarchyRefreshRequested:
                return reloadFoldersForPresentationChange(state: &state)

            case let .folderExpansionRequested(id):
                guard hierarchyInteractionsAreEnabled(in: state) else { return .none }
                guard let folder = folder(id: id, in: state),
                      folder.supportsListHierarchyExpansion else { return .none }
                guard folderIsWithinCurrentRoot(id, state: state) else { return .none }

                var nodeState = state.hierarchy.nodesByID[id] ?? FolderNodeState()
                nodeState.expansionIntent = true
                state.hierarchy.nodesByID[id] = nodeState
                switch nodeState.loadPhase {
                case .loaded, .enriching, .loadingCore:
                    return .none
                case .idle, .failed:
                    return startLoad(folder: folder, id: id, state: &state)
                }

            case let .folderRetryRequested(id):
                guard hierarchyInteractionsAreEnabled(in: state) else { return .none }
                guard let folder = folder(id: id, in: state),
                      folder.supportsListHierarchyExpansion else { return .none }
                guard folderIsWithinCurrentRoot(id, state: state) else { return .none }
                state.hierarchy.nodesByID[id, default: FolderNodeState()].expansionIntent = true
                return startLoad(folder: folder, id: id, state: &state)

            case let .folderCollapseRequested(id):
                var nodeState = state.hierarchy.nodesByID[id] ?? FolderNodeState()
                nodeState.expansionIntent = false
                let shouldCancelLoad = nodeState.loadPhase == .loadingCore
                    || nodeState.loadPhase == .enriching
                if nodeState.loadPhase != .loaded {
                    nodeState.generation &+= 1
                    nodeState.folder = FolderSnapshot()
                    nodeState.loadPhase = FolderLoadPhase.idle
                }
                state.hierarchy.nodesByID[id] = nodeState
                let reconcileEffect = Effect<Action>.send(.internal(.reconcileHierarchySelection))
                guard shouldCancelLoad else { return reconcileEffect }
                return .concatenate(
                    .send(.delegate(.collapseRequested(id))),
                    reconcileEffect,
                )

            case let .folderChildrenResponse(rootContextGeneration, folderID, folderGeneration, response):
                guard rootContextGeneration == state.hierarchy.rootContextGeneration,
                      var nodeState = state.hierarchy.nodesByID[folderID],
                      nodeState.generation == folderGeneration,
                      nodeState.loadPhase == .loadingCore || nodeState.loadPhase == .enriching
                else { return .none }

                let previousRevision = state.outlineProjectionRevision
                let wasCoreFinished = nodeState.folder.coreFinished
                guard apply(response: response, to: &nodeState.folder) else { return .none }

                // Update load phase based on response type
                switch response {
                case .event(.coreFinished):
                    if nodeState.loadPhase == .loadingCore {
                        nodeState.loadPhase = .enriching
                    }
                case .streamCompleted:
                    guard nodeState.folder.coreFinished else { return .none }
                    nodeState.loadPhase = .loaded
                case let .failed(failure):
                    nodeState.loadPhase = .failed(failure)
                case .event(.coreBatch), .event(.metadataPatches):
                    break
                }

                state.hierarchy.nodesByID[folderID] = nodeState

                if !wasCoreFinished,
                   nodeState.folder.coreFinished,
                   case .event(.coreFinished) = response
                {
                    let childIDs = Set(
                        nodeState.folder.children
                            .filter(\.supportsListHierarchyExpansion)
                            .map(\.id),
                    )

                    // parentID edge를 설정한다: children 중 nodesByID에 있는 node에 parentID를 기록한다.
                    for childID in childIDs {
                        if state.hierarchy.nodesByID[childID] != nil {
                            state.hierarchy.nodesByID[childID]?.parentID = folderID
                        }
                    }

                    // parentID edge로 stale descendant를 찾는다.
                    // parentID가 없는 node는 path-based fallback(isImmediateChildFolder)으로 보완한다.
                    let staleDescendants = state.hierarchy.nodesByID.keys.filter {
                        (state.hierarchy.nodesByID[$0]?.parentID == folderID
                            || isImmediateChildFolder($0, parentID: folderID))
                            && !childIDs.contains($0)
                    }
                    if !staleDescendants.isEmpty {
                        // parentID edge를 따라 recursive eviction: 각 stale node의 모든 하위 node도 제거한다.
                        var idsToRemove = Set(staleDescendants)
                        for staleID in staleDescendants {
                            let descendants = state.hierarchy.nodesByID.keys.filter {
                                isDescendantViaParentID($0, of: staleID, in: state.hierarchy.nodesByID)
                            }
                            idsToRemove.formUnion(descendants)
                        }
                        for id in idsToRemove {
                            state.hierarchy.nodesByID[id] = nil
                        }
                        state.reconcileSelectionWithVisibleEntries()
                        if state.outlineProjectionRevision == previousRevision {
                            state.advanceOutlineProjectionRevision()
                        }
                        return .none
                    }
                }

                state.reconcileSelectionWithVisibleEntries()
                if state.outlineProjectionRevision == previousRevision {
                    state.advanceOutlineProjectionRevision()
                }
                return .none
            }
        }
    }

    private func startLoad(
        folder _: EntryModel,
        id: EntryModel.ID,
        state: inout State,
    ) -> Effect<Action> {
        var nodeState = state.hierarchy.nodesByID[id] ?? FolderNodeState()
        nodeState.generation &+= 1
        nodeState.loadPhase = FolderLoadPhase.loadingCore
        nodeState.folder = FolderSnapshot()
        // parentID를 설정한다: nodesByID에서 이 node를 children으로 포함하는 node를 찾는다.
        if nodeState.parentID == nil {
            nodeState.parentID = state.hierarchy.nodesByID.first(where: { _, node in
                node.folder.children.contains(where: { $0.id == id })
            })?.key
        }
        state.hierarchy.nodesByID[id] = nodeState
        let previousRevision = state.outlineProjectionRevision
        state.reconcileSelectionWithVisibleEntries()
        if state.outlineProjectionRevision == previousRevision {
            state.advanceOutlineProjectionRevision()
        }

        return .send(.delegate(.expandRequested(id)))
    }

    private func invalidateHierarchy(
        affectedPaths: [String],
        removedPrefixes: [String],
        reloadCachedFolders: Bool,
        state: inout State,
    ) -> Effect<Action> {
        let removedIDs = Set(state.hierarchy.nodesByID.keys.filter { id in
            removedPrefixes.contains { isSameOrDescendant(path: id, of: $0) }
        })
        var effects: [Effect<Action>] = []

        for id in removedIDs {
            state.hierarchy.nodesByID[id] = nil
        }

        if reloadCachedFolders {
            return .merge(effects + [reloadFoldersForPresentationChange(state: &state)])
        }

        var affectedIDs = Set<EntryModel.ID>()
        for path in affectedPaths {
            let canonicalPath = normalizedPath(path)
            if let folderID = state.hierarchy.nodesByID.keys.first(where: {
                normalizedPath($0) == canonicalPath
            }) {
                affectedIDs.insert(folderID)
            }
            if let parentID = nearestLoadedParentID(for: canonicalPath, state: state) {
                affectedIDs.insert(parentID)
            }
        }

        let reloadIDs = affectedIDs.subtracting(removedIDs)
        if !reloadIDs.isEmpty {
            state.advanceOutlineProjectionRevision()
        }
        for id in reloadIDs {
            guard let folder = folder(id: id, in: state) else { continue }
            guard folder.supportsListHierarchyExpansion else { continue }
            if state.hierarchy.expandedFolderIDs.contains(id) {
                effects.append(startLoad(folder: folder, id: id, state: &state))
            } else {
                var nodeState = state.hierarchy.nodesByID[id] ?? FolderNodeState()
                nodeState.folder = FolderSnapshot()
                nodeState.loadPhase = FolderLoadPhase.idle
                nodeState.generation &+= 1
                state.hierarchy.nodesByID[id] = nodeState
            }
        }

        state.reconcileSelectionWithVisibleEntries()
        return .merge(effects)
    }

    private func reloadFoldersForPresentationChange(state: inout State) -> Effect<Action> {
        let folderIDs = Array(state.hierarchy.nodesByID.keys)
        let expandedFolders = state.hierarchy.expandedFolderIDs
            .compactMap { id in
                folder(id: id, in: state)
            }
            .filter { folder in
                folder.supportsListHierarchyExpansion && folderIsWithinCurrentRoot(folder.id, state: state)
            }

        for id in folderIDs {
            var nodeState = state.hierarchy.nodesByID[id] ?? FolderNodeState()
            if !state.hierarchy.expandedFolderIDs.contains(id) {
                nodeState.generation &+= 1
            }
            nodeState.folder = FolderSnapshot()
            nodeState.loadPhase = FolderLoadPhase.idle
            state.hierarchy.nodesByID[id] = nodeState
        }
        if !folderIDs.isEmpty {
            state.advanceOutlineProjectionRevision()
        }

        let restartEffects: [Effect<Action>] = expandedFolders.map { folder in
            startLoad(folder: folder, id: folder.id, state: &state)
        }
        return .concatenate(
            .merge(restartEffects),
            .send(.internal(.reconcileHierarchySelection)),
        )
    }

    private func folder(id: EntryModel.ID, in state: State) -> EntryModel? {
        state.entries.first(where: { $0.id == id })
            ?? state.hierarchy.nodesByID.values.lazy
            .flatMap(\.folder.children)
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

    /// parentID edge를 따라 `ancestor`가 `id`의 조상인지 확인한다.
    /// nodesByID의 parentID chain을 따라 올라가며 ancestor를 찾는다.
    private func isDescendantViaParentID(
        _ id: EntryModel.ID,
        of ancestor: EntryModel.ID,
        in nodesByID: [EntryModel.ID: FolderNodeState],
    ) -> Bool {
        var current = id
        while let parentID = nodesByID[current]?.parentID {
            if parentID == ancestor {
                return true
            }
            current = parentID
        }
        return false
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
        to snapshot: inout FolderSnapshot,
    ) -> Bool {
        switch response {
        case let .event(.coreBatch(items, batchIndex)):
            return applyCoreBatch(items, batchIndex: batchIndex, to: &snapshot)

        case let .event(.coreFinished(batchCount)):
            return applyCoreFinished(batchCount, to: &snapshot)

        case let .event(.metadataPatches(patches)):
            return applyMetadataPatches(patches, to: &snapshot)

        case .streamCompleted:
            guard snapshot.coreFinished else { return false }
            return true

        case .failed:
            return true
        }
    }

    private func applyCoreBatch(
        _ items: [EntryModel],
        batchIndex: Int,
        to snapshot: inout FolderSnapshot,
    ) -> Bool {
        guard !snapshot.coreFinished, batchIndex == snapshot.expectedBatchIndex else { return false }
        for item in items {
            if let index = snapshot.children.firstIndex(where: { $0.id == item.id }) {
                snapshot.children[index] = item
            } else {
                snapshot.children.append(item)
            }
        }
        snapshot.expectedBatchIndex &+= 1
        return true
    }

    private func applyCoreFinished(
        _ batchCount: Int,
        to snapshot: inout FolderSnapshot,
    ) -> Bool {
        guard !snapshot.coreFinished, batchCount == snapshot.expectedBatchIndex else { return false }
        snapshot.coreFinished = true
        return true
    }

    private func applyMetadataPatches(
        _ patches: [EntryMetadataPatch],
        to snapshot: inout FolderSnapshot,
    ) -> Bool {
        guard snapshot.coreFinished else { return false }
        let patchesByEntryID = Dictionary(grouping: patches, by: metadataPatchEntryID)
        snapshot.children = snapshot.children.map { child in
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
        state.hierarchy.nodesByID
            .filter {
                isLoadedOrLoading($0.value.loadPhase)
                    && isSameOrDescendant(path: path, of: $0.key)
            }
            .map(\.key)
            .max { lhs, rhs in
                pathComponents(for: lhs).count < pathComponents(for: rhs).count
            }
    }

    private func isLoadedOrLoading(_ phase: FolderLoadPhase) -> Bool {
        switch phase {
        case .loadingCore, .enriching, .loaded: true
        case .idle, .failed: false
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
        URL(fileURLWithPath: path).standardizedFileURL.pathComponents
    }
}
