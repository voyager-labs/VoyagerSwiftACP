import ComposableArchitecture
import Foundation
import VoyagerEntitiesEntry
import VoyagerShared

extension EntryListHierarchyReducer {
    func startLoad(
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

    func invalidateHierarchy(
        affectedPaths: [String],
        removedPrefixes: [String],
        reloadCachedFolders: Bool,
        state: inout State,
    ) -> Effect<Action> {
        let previousSelectedIds = state.selectedIds
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
        appendReloadEffects(for: reloadIDs, into: &effects, state: &state)

        state.reconcileSelectionWithVisibleEntries()
        var reconcileEffects: [Effect<Action>] = []
        if let renamingID = state.entryOperations.renamingItemId,
           previousSelectedIds.contains(renamingID),
           !state.selectedIds.contains(renamingID)
        {
            reconcileEffects.append(.send(.delegate(.renameCanceled)))
        }
        if previousSelectedIds != state.selectedIds {
            reconcileEffects.append(.send(.delegate(.selectionChanged)))
        }
        return .merge(effects + reconcileEffects)
    }

    private func appendReloadEffects(
        for reloadIDs: Set<EntryModel.ID>,
        into effects: inout [Effect<Action>],
        state: inout State,
    ) {
        for id in reloadIDs {
            guard let folder = folder(id: id, in: state) else { continue }
            guard folder.supportsListHierarchyExpansion else { continue }
            if state.hierarchy.expandedFolderIDs.contains(id) {
                effects.append(startLoad(folder: folder, id: id, state: &state))
            } else {
                resetIdleNodeState(folderID: id, state: &state)
            }
        }
    }

    private func resetIdleNodeState(folderID: EntryModel.ID, state: inout State) {
        var nodeState = state.hierarchy.nodesByID[folderID] ?? FolderNodeState()
        nodeState.folder = FolderSnapshot()
        nodeState.loadPhase = FolderLoadPhase.idle
        nodeState.generation &+= 1
        state.hierarchy.nodesByID[folderID] = nodeState
    }

    func reloadFoldersForPresentationChange(state: inout State) -> Effect<Action> {
        let folderIDs = Array(state.hierarchy.nodesByID.keys)
        let expandedFolders = state.hierarchy.expandedFolderIDs
            .compactMap { id in
                folder(id: id, in: state)
            }
            .filter { folder in
                folder.supportsListHierarchyExpansion && folderIsWithinCurrentRoot(folder.id, state: state)
            }

        // startLoad가 child snapshot을 비우며 선택을 동기적으로 재조정하므로,
        // 뒤의 reconcileHierarchySelection은 이미 빈 선택만 보게 된다. 따라서 재로드 전
        // 선택을 보존해 두고 이 함수에서 delegate를 직접 병합한다.
        let previousSelectedIds = state.selectedIds

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
        var reconcileEffects: [Effect<Action>] = []
        if let renamingID = state.entryOperations.renamingItemId,
           previousSelectedIds.contains(renamingID),
           !state.selectedIds.contains(renamingID)
        {
            reconcileEffects.append(.send(.delegate(.renameCanceled)))
        }
        if previousSelectedIds != state.selectedIds {
            reconcileEffects.append(.send(.delegate(.selectionChanged)))
        }
        return .concatenate(
            .merge(restartEffects),
            .send(.internal(.reconcileHierarchySelection)),
            .merge(reconcileEffects),
        )
    }

    func folder(id: EntryModel.ID, in state: State) -> EntryModel? {
        state.entries.first(where: { $0.id == id })
            ?? state.hierarchy.nodesByID.values.lazy
            .flatMap(\.folder.children)
            .first(where: { $0.id == id })
    }

    func hierarchyInteractionsAreEnabled(in state: State) -> Bool {
        state.mode == .list
            && !state.isCollectionMode
            && state.entryArrangements.groupKey == .none
            && !state.hierarchy.rootPath.isEmpty
    }

    func folderIsWithinCurrentRoot(_ id: EntryModel.ID, state: State) -> Bool {
        isLexicallySameOrDescendant(path: id, of: state.hierarchy.rootPath)
    }

    func isImmediateRootFolder(_ id: EntryModel.ID, rootPath: String) -> Bool {
        let rootComponents = pathComponents(for: rootPath)
        let folderComponents = pathComponents(for: id)
        return folderComponents.count == rootComponents.count + 1
            && folderComponents.starts(with: rootComponents)
    }

    func isImmediateChildFolder(_ id: EntryModel.ID, parentID: EntryModel.ID) -> Bool {
        let parentComponents = pathComponents(for: parentID)
        let childComponents = pathComponents(for: id)
        return childComponents.count == parentComponents.count + 1
            && childComponents.starts(with: parentComponents)
    }

    /// parentID edge를 따라 `ancestor`가 `id`의 조상인지 확인한다.
    /// nodesByID의 parentID chain을 따라 올라가며 ancestor를 찾는다.
    func isDescendantViaParentID(
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

    static func metadataPriority(
        for sortKey: VoyagerShared.SortKey,
    ) -> EntryMetadataPriority {
        .active([
            EntryViewLayoutFeature.metadataProbe(for: sortKey),
        ].compactMap(\.self))
    }

    func apply(
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

    func applyCoreBatch(
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

    func applyCoreFinished(
        _ batchCount: Int,
        to snapshot: inout FolderSnapshot,
    ) -> Bool {
        guard !snapshot.coreFinished, batchCount == snapshot.expectedBatchIndex else { return false }
        snapshot.coreFinished = true
        return true
    }

    func applyMetadataPatches(
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

    func metadataPatchEntryID(_ patch: EntryMetadataPatch) -> EntryModel.ID {
        switch patch {
        case let .spotlight(id, _, _, _),
             let .tags(id, _),
             let .supplementaryMetadata(id, _):
            id
        }
    }

    func nearestLoadedParentID(for path: String, state: State) -> EntryModel.ID? {
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

    func isLoadedOrLoading(_ phase: FolderLoadPhase) -> Bool {
        switch phase {
        case .loadingCore, .enriching, .loaded: true
        case .idle, .failed: false
        }
    }

    func isSameOrDescendant(path: String, of ancestor: String) -> Bool {
        // 이벤트 경로는 canonical(real)일 수 있으므로 양쪽을 symlink-resolve한 공간에서 비교한다.
        // node/request ID 자체는 lexical 경로로 보존된다.
        isLexicallySameOrDescendant(
            path: normalizedPath(path),
            of: normalizedPath(ancestor),
        )
    }

    func isLexicallySameOrDescendant(path: String, of ancestor: String) -> Bool {
        let candidateComponents = pathComponents(for: path)
        let ancestorComponents = pathComponents(for: ancestor)
        return candidateComponents.starts(with: ancestorComponents)
    }

    func normalizedPath(_ path: String) -> String {
        guard !path.isEmpty else { return path }
        return URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
    }

    func pathComponents(for path: String) -> [String] {
        URL(fileURLWithPath: path).standardizedFileURL.pathComponents
    }
}
