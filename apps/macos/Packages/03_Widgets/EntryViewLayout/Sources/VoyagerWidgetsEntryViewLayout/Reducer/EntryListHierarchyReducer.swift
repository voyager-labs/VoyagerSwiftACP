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

            case .coarseHierarchyRefreshRequested:
                return reloadFoldersForPresentationChange(state: &state)

            case .restartUnfinishedExpandedFolderLoads:
                // cross-window content tab 이동 등으로 소스 window의 folder load가 취소된 뒤,
                // target window/owner에서 unfinished(.loadingCore/.enriching) expanded folder만 재시작한다.
                // startLoad가 generation 증가 + partial stream snapshot 초기화를 수행하며,
                // .loaded 노드의 캐시와 parent/expansion 상태는 그대로 보존한다.
                var effects: [Effect<Action>] = []
                for id in state.hierarchy.nodesByID.keys {
                    guard let nodeState = state.hierarchy.nodesByID[id],
                          nodeState.expansionIntent,
                          nodeState.loadPhase == .loadingCore || nodeState.loadPhase == .enriching,
                          let folder = folder(id: id, in: state)
                    else { continue }
                    effects.append(startLoad(folder: folder, id: id, state: &state))
                }
                return .merge(effects)

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
                let previousSelectedIds = state.selectedIds
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
                        guard previousSelectedIds != state.selectedIds else { return .none }
                        return .send(.delegate(.selectionChanged))
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
