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

            case let .coarseHierarchyInvalidated(removedPrefixes, retainsCompleteSnapshots):
                return invalidateHierarchy(
                    affectedPaths: [],
                    removedPrefixes: removedPrefixes,
                    retainsCompleteSnapshots: retainsCompleteSnapshots,
                    reloadCachedFolders: true,
                    state: &state,
                )

            case let .rootSnapshotCompleted(rootContextGeneration, rootFolders):
                // generation이 일치하지 않으면 NO-OP: stale root completion을 무시한다.
                guard rootContextGeneration == state.hierarchy.rootContextGeneration else { return .none }
                let previousSelectedIds = state.selectedIds
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
                for folder in rootFolders where state.hierarchy.nodesByID[folder.id] == nil {
                    state.hierarchy.nodesByID[folder.id] = FolderNodeState()
                }
                // visible expanded intent 중 reload가 필요한 folder를 restart한다.
                // startLoad와 같은 retained-snapshot 초기화 경로: root-first 응답 순서에서
                // 완전 child snapshot을 비우지 않는다(중간 blank/flicker 방지).
                var effects: [Effect<Action>] = []
                for folder in rootFolders {
                    guard let nodeState = state.hierarchy.nodesByID[folder.id],
                          nodeState.expansionIntent,
                          nodeState.loadPhase != .loaded
                    else { continue }
                    // startLoad와 동일하게 세대 재시작 전 이전 세대의 deferred staging을 폐기한다.
                    state.hierarchy.discardDeferredFolderReplacement(folderID: folder.id)
                    state.hierarchy.nodesByID[folder.id] = reloadedNodeState(for: nodeState)
                    effects.append(.send(.delegate(.expandRequested(folder.id))))
                }
                state.reconcileSelectionWithVisibleEntries()

                // root snapshot 재조정 후 rename 대상이 최종 visible hierarchy projection에
                // 더 이상 없으면 rename을 취소한다. root-only snapshot은 중첩 child 가시성을
                // 알 수 없으므로, expanded·loaded child가 여전히 visible하면 rename을 보존한다.
                var renameEffects: [Effect<Action>] = []
                if let renamingID = state.entryOperations.renamingItemId {
                    let visibleIDs = Set(state.visibleSelectableEntryIDs(
                        isNormalDirectoryPage: state.selectionProjectionIsHierarchyEnabled,
                    ))
                    if !visibleIDs.contains(renamingID) {
                        renameEffects.append(.send(.delegate(.renameCanceled)))
                    }
                }
                if previousSelectedIds != state.selectedIds {
                    renameEffects.append(.send(.delegate(.selectionChanged)))
                }
                return .merge(effects + renameEffects)

            case let .rootSnapshotReconciled(rootContextGeneration, rootFolders):
                guard rootContextGeneration == state.hierarchy.rootContextGeneration else { return .none }
                let previousSelectedIds = state.selectedIds
                let rootFolderIDs = Set(rootFolders.map(\.id))
                let removedRootIDs = state.hierarchy.nodesByID.keys.filter { id in
                    isImmediateRootFolder(id, rootPath: state.hierarchy.rootPath)
                        && !rootFolderIDs.contains(id)
                }
                var idsToRemove = Set(removedRootIDs)
                for id in removedRootIDs {
                    let descendants = state.hierarchy.nodesByID.keys.filter {
                        isDescendantViaParentID($0, of: id, in: state.hierarchy.nodesByID)
                    }
                    idsToRemove.formUnion(descendants)
                }
                for id in idsToRemove {
                    state.hierarchy.nodesByID[id] = nil
                }
                for folder in rootFolders where state.hierarchy.nodesByID[folder.id] == nil {
                    state.hierarchy.nodesByID[folder.id] = FolderNodeState()
                }
                state.reconcileSelectionWithVisibleEntries()
                var effects: [Effect<Action>] = []
                if let renamingID = state.entryOperations.renamingItemId,
                   previousSelectedIds.contains(renamingID),
                   !state.selectedIds.contains(renamingID)
                {
                    effects.append(.send(.delegate(.renameCanceled)))
                }
                if previousSelectedIds != state.selectedIds {
                    effects.append(.send(.delegate(.selectionChanged)))
                }
                return .merge(effects)

            case .coarseHierarchyRefreshRequested:
                return reloadFoldersForPresentationChange(state: &state)

            case .restartUnfinishedExpandedFolderLoads:
                // cross-window content tab 이동 등으로 소스 window의 folder load가 취소된 뒤,
                // target window/owner에서 unfinished(.loadingCore/.enriching) expanded folder만 재시작한다.
                // startLoad가 generation 증가 + partial stream snapshot 초기화를 수행하며,
                // .loaded 노드의 캐시와 parent/expansion 상태는 그대로 보존한다.
                let previousSelectedIds = state.selectedIds
                var effects: [Effect<Action>] = []
                for id in state.hierarchy.nodesByID.keys {
                    guard let nodeState = state.hierarchy.nodesByID[id],
                          nodeState.expansionIntent,
                          nodeState.loadPhase == .loadingCore || nodeState.loadPhase == .enriching,
                          let folder = folder(id: id, in: state)
                    else { continue }
                    effects.append(startLoad(folder: folder, id: id, state: &state))
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
                return .merge(effects + reconcileEffects)

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
                let previousSelectedIds = state.selectedIds
                let startLoadEffect = startLoad(folder: folder, id: id, state: &state)
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
                return .concatenate([startLoadEffect] + reconcileEffects)

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
                let previousSelectedIds = state.selectedIds
                let wasCoreFinished = nodeState.folder.coreFinished
                if case let .event(.coreBatch(items, batchIndex)) = response,
                   !nodeState.folder.hasAppliedContentBatch,
                   !nodeState.folder.children.isEmpty,
                   var replacement = state.hierarchy.deferredFolderReplacements[folderID]
                {
                    guard batchIndex == nodeState.folder.expectedBatchIndex else { return .none }
                    let standardizedItems = items.map { item in
                        (item, URL(fileURLWithPath: item.id).standardizedFileURL.path)
                    }
                    let standardizedDeferred = URL(fileURLWithPath: replacement.untilEntryID)
                        .standardizedFileURL.path
                    replacement.stagedChildren.append(contentsOf: items)
                    nodeState.folder.expectedBatchIndex &+= 1
                    if !standardizedItems.contains(where: { $0.1 == standardizedDeferred }) {
                        state.hierarchy.deferredFolderReplacements[folderID] = replacement
                        state.hierarchy.nodesByID[folderID] = nodeState
                        return .none
                    }
                    state.hierarchy.deferredFolderReplacements[folderID] = nil
                    nodeState.folder.children = replacement.stagedChildren
                    nodeState.folder.hasAppliedContentBatch = true
                    nodeState.folder.retainsPreviousGenerationChildren = false
                    state.hierarchy.nodesByID[folderID] = nodeState
                    return .none
                }
                if case let .event(.coreFinished(batchCount)) = response,
                   let replacement = state.hierarchy.deferredFolderReplacements[folderID]
                {
                    guard batchCount == nodeState.folder.expectedBatchIndex else { return .none }
                    if replacement.holdsUntilMigration {
                        // 보존(소스) 폴더: destination migration까지 retained projection을 유지한다.
                        // coreFinished는 terminal만 기록하고 children·staging은 건드리지 않는다.
                        // 실제 staging 커밋은 migrateSelection이 담당한다.
                        nodeState.folder.coreFinished = true
                        state.hierarchy.nodesByID[folderID] = nodeState
                        return .none
                    }
                    nodeState.folder.children = replacement.stagedChildren
                    nodeState.folder.hasAppliedContentBatch = !replacement.stagedChildren.isEmpty
                    nodeState.folder.retainsPreviousGenerationChildren = false
                    nodeState.folder.coreFinished = true
                    state.hierarchy.deferredFolderReplacements[folderID] = nil
                    state.hierarchy.nodesByID[folderID] = nodeState
                    state.hierarchy.reconcileNodesAfterMigrationCommit(folderID: folderID)
                    return .none
                }
                if case let .event(.metadataPatches(patches)) = response,
                   var replacement = state.hierarchy.deferredFolderReplacements[folderID]
                {
                    // migration까지 보류 중인 staging에도 같은 patch를 적용해
                    // 커밋 시 metadata가 core 값으로 되돌아가지 않게 한다.
                    replacement.stagedChildren = applyMetadataPatches(patches, to: replacement.stagedChildren)
                    state.hierarchy.deferredFolderReplacements[folderID] = replacement
                }
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
                    for childID in childIDs where state.hierarchy.nodesByID[childID] != nil {
                        state.hierarchy.nodesByID[childID]?.parentID = folderID
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
                        var reconcileEffects: [Effect<Action>] = []
                        let visibleIDs = Set(state.visibleSelectableEntryIDs(
                            isNormalDirectoryPage: state.selectionProjectionIsHierarchyEnabled,
                        ))
                        if let renamingID = state.entryOperations.renamingItemId,
                           !visibleIDs.contains(renamingID)
                        {
                            reconcileEffects.append(.send(.delegate(.renameCanceled)))
                        }
                        if previousSelectedIds != state.selectedIds {
                            reconcileEffects.append(.send(.delegate(.selectionChanged)))
                        }
                        guard !reconcileEffects.isEmpty else { return .none }
                        return .merge(reconcileEffects)
                    }
                }

                state.reconcileSelectionWithVisibleEntries()
                if state.outlineProjectionRevision == previousRevision {
                    state.advanceOutlineProjectionRevision()
                }
                guard previousSelectedIds != state.selectedIds else { return .none }
                return .send(.delegate(.selectionChanged))
            }
        }
    }
}
