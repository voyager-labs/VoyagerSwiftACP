import ComposableArchitecture
import Foundation
import VoyagerEntitiesEntry
import VoyagerShared

extension EntryListHierarchyReducer {
    /// 재로드 세대를 위한 공통 node 상태 전이. 모든 재시작 경로(explicit startLoad,
    /// root snapshot 완료 시 unfinished-folder 재시작)가 이 경로를 사용해야 한다.
    ///
    /// 마지막 완전 스냅샷(coreFinished 또는 loaded)이 있으면 유지하고, 배치 커서만 0으로
    /// 되돌려 다음 유효 배치가 retained children을 교체하게 표시한다(중간 빈 투영 방지).
    /// 초기 확장(idle)·부분 수신(loadingCore 중간)처럼 캐시가 없으면 오늘과 같이 비운다.
    /// 실패 재시도는 cursor가 아니라 content provenance로 이전 완전 세대와 부분 수신을 구분한다.
    func reloadedNodeState(for nodeState: FolderNodeState) -> FolderNodeState {
        var refreshedNode = nodeState
        var retainsCompleteSnapshot = refreshedNode.folder.coreFinished
            || refreshedNode.loadPhase == .loaded
            || refreshedNode.folder.retainsPreviousGenerationChildren
        if case .failed = refreshedNode.loadPhase {
            retainsCompleteSnapshot = refreshedNode.folder.retainsPreviousGenerationChildren
        }
        refreshedNode.generation &+= 1
        refreshedNode.loadPhase = FolderLoadPhase.loadingCore
        if retainsCompleteSnapshot {
            refreshedNode.folder.coreFinished = false
            refreshedNode.folder.expectedBatchIndex = 0
            refreshedNode.folder.hasAppliedContentBatch = false
            refreshedNode.folder.retainsPreviousGenerationChildren = true
        } else {
            refreshedNode.folder = FolderSnapshot()
        }
        return refreshedNode
    }

    func startLoad(
        folder _: EntryModel,
        id: EntryModel.ID,
        state: inout State,
    ) -> Effect<Action> {
        // 새 세대 진입 시 이전 세대의 deferred staging을 폐기한다. staging은 특정 세대의
        // batch 수신과 연관되므로, 세대가 재시작되면 남은 항목이 새 listing에 중복·stale로
        // 합쳐지지 않게 새로 초기화되어야 한다.
        state.hierarchy.discardDeferredFolderReplacement(folderID: id)
        var nodeState = reloadedNodeState(for: state.hierarchy.nodesByID[id] ?? FolderNodeState())
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
        retainsCompleteSnapshots: Bool = false,
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
            return .merge(effects + [reloadFoldersForPresentationChange(
                state: &state,
                retainsCompleteSnapshots: retainsCompleteSnapshots,
            )])
        }

        var affectedIDs = Set<EntryModel.ID>()
        for path in affectedPaths {
            let canonicalPath = normalizedPath(path)
            let matchingFolderIDs = state.hierarchy.nodesByID.keys.filter {
                normalizedPath($0) == canonicalPath
            }
            affectedIDs.formUnion(matchingFolderIDs)
            affectedIDs.formUnion(nearestLoadedParentIDs(for: canonicalPath, state: state))
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

    func reloadFoldersForPresentationChange(
        state: inout State,
        retainsCompleteSnapshots: Bool = false,
    ) -> Effect<Action> {
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
        let retainsExpandedSnapshots = retainsCompleteSnapshots || state.identityReplacement != nil

        for id in folderIDs {
            var nodeState = state.hierarchy.nodesByID[id] ?? FolderNodeState()
            let isExpanded = state.hierarchy.expandedFolderIDs.contains(id)
            // 보존 모드의 확장 폴더는 마커를 건드리지 않고 건너뛴다. 아래 startLoad의
            // reloadedNodeState가 완료 provenance를 보고 완전 스냅샷을 유지한 채
            // 세대만 올리고 커서를 되감는다.
            if retainsExpandedSnapshots, isExpanded {
                continue
            }
            if !isExpanded {
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
        guard !snapshot.coreFinished else { return false }
        // 아직 이번 세대 내용 배치를 받지 않은 상태에서 이전 세대 children이 남아 있으면
        // startLoad가 심은 retained 스냅샷(교체 대기)이다. 생산자는 빈 배치도 커서를 올리므로,
        // 빈 배치는 children을 유지한 채 커서만 소진하고, 첫 내용 배치가 retained children을 한 번에 교체한다.
        if !snapshot.hasAppliedContentBatch, !snapshot.children.isEmpty {
            guard batchIndex == snapshot.expectedBatchIndex else { return false }
            guard !items.isEmpty else {
                snapshot.expectedBatchIndex += 1
                return true
            }
            snapshot.children = items
            snapshot.hasAppliedContentBatch = true
            snapshot.retainsPreviousGenerationChildren = false
            snapshot.expectedBatchIndex += 1
            return true
        }
        guard batchIndex == snapshot.expectedBatchIndex else { return false }
        for item in items {
            if let index = snapshot.children.firstIndex(where: { $0.id == item.id }) {
                snapshot.children[index] = item
            } else {
                snapshot.children.append(item)
            }
        }
        if !items.isEmpty {
            snapshot.hasAppliedContentBatch = true
        }
        snapshot.expectedBatchIndex &+= 1
        return true
    }

    func applyCoreFinished(
        _ batchCount: Int,
        to snapshot: inout FolderSnapshot,
    ) -> Bool {
        guard !snapshot.coreFinished, batchCount == snapshot.expectedBatchIndex else { return false }
        // 이번 세대에서 내용 배치를 하나도 적용하지 못했다면(빈 배치뿐) 실제 빈 스냅샷으로 커밋해
        // retained children이 남는 것을 막는다.
        if !snapshot.hasAppliedContentBatch {
            snapshot.children = []
        }
        snapshot.retainsPreviousGenerationChildren = false
        snapshot.coreFinished = true
        return true
    }

    func applyMetadataPatches(
        _ patches: [EntryMetadataPatch],
        to snapshot: inout FolderSnapshot,
    ) -> Bool {
        guard snapshot.coreFinished else { return false }
        snapshot.children = applyMetadataPatches(patches, to: snapshot.children)
        return true
    }

    func applyMetadataPatches(
        _ patches: [EntryMetadataPatch],
        to children: [EntryModel],
    ) -> [EntryModel] {
        let patchesByEntryID = Dictionary(grouping: patches, by: metadataPatchEntryID)
        return children.map { child in
            guard let childPatches = patchesByEntryID[child.id] else { return child }
            return childPatches.reduce(child) { $0.applying($1) }
        }
    }

    func metadataPatchEntryID(_ patch: EntryMetadataPatch) -> EntryModel.ID {
        switch patch {
        case let .spotlight(id, _, _, _),
             let .tags(id, _),
             let .supplementaryMetadata(id, _):
            id
        }
    }

    func nearestLoadedParentIDs(for path: String, state: State) -> Set<EntryModel.ID> {
        let candidates = state.hierarchy.nodesByID
            .filter {
                isLoadedOrLoading($0.value.loadPhase)
                    && isSameOrDescendant(path: path, of: $0.key)
            }
        guard let deepestPathComponentCount = candidates.keys
            .map({ pathComponents(for: normalizedPath($0)).count })
            .max()
        else {
            return []
        }
        return Set(candidates.keys.filter {
            pathComponents(for: normalizedPath($0)).count == deepestPathComponentCount
        })
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
