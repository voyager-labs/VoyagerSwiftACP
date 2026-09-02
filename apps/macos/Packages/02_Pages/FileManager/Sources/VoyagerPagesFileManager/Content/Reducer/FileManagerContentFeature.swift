import AppKit
import ComposableArchitecture
import Foundation
import VoyagerEntitiesAi
import VoyagerEntitiesCollection
import VoyagerEntitiesEntry
import VoyagerFeaturesAiChat
import VoyagerFeaturesComposer
import VoyagerFeaturesContentPageNavigation
import VoyagerFeaturesEntryArrangements
import VoyagerFeaturesEntryOperations
import VoyagerFeaturesEntryThumbnail
import VoyagerShared
import VoyagerWidgetsEntryViewLayout

@Reducer
public struct FileManagerContentFeature {
    public typealias State = FileManagerContentState
    public typealias Action = FileManagerContentAction

    @Dependency(\.fileManagerClient)
    private var fileManagerClient
    @Dependency(\.entryOpenClient)
    private var entryOpenClient

    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .internal(.setPendingEntrySelection(entryID, destinationPath)):
                state.setPendingEntrySelection(entryID: entryID, destinationPath: destinationPath)
                return .none
            case let .collection(.saveCompleted(result)):
                return handleCollectionSaveCompleted(result: result, state: &state)
            case let .entryViewLayout(.entryOperations(.lifecycle(.windowIDChanged(windowID)))):
                state.composer.cancellationOwnerID = windowID
                return .none
            case let .entryViewLayout(.entryOperations(.lifecycle(.resetForDuplicate(windowID)))):
                state.composer.cancellationOwnerID = windowID
                return .none
            case let .entryViewLayout(.entryArrangements(.setSortKey(key))):
                guard state.entryViewLayout.entryArrangements.sortKey != key else { return .none }
                return arrangementMetadataReloadEffect(
                    priority: FileManagerContentEntryOpsCoordinator.rootMetadataPriority(
                        sortKey: key,
                        groupKey: state.entryViewLayout.entryArrangements.groupKey,
                    ),
                    state: &state,
                )
            case let .entryViewLayout(.entryArrangements(.setGroupKey(key))):
                guard state.entryViewLayout.entryArrangements.groupKey != key else { return .none }
                return arrangementMetadataReloadEffect(
                    priority: FileManagerContentEntryOpsCoordinator.rootMetadataPriority(
                        sortKey: state.entryViewLayout.entryArrangements.sortKey,
                        groupKey: key,
                    ),
                    state: &state,
                )
            case .internal(.checkRootCandidateAfterTerminal):
                guard !FileManagerContentIdentityTransitionCoordinator.hasPendingRootSourceMigration(state)
                else { return .none }
                return .send(.internal(.commitRootCandidateAfterMigration))
            case .internal(.reloadDirectoryListing):
                guard case .folder = state.navigation.navigationState else { return .none }
                // entryActionCompleted가 예약한 identity reload가 같은 root의 현재 또는 다음
                // 세대를 소유 중이면 aggregate outcome의 중복 reload를 생략한다. 두 번째
                // loadItems는 cancelInFlight로 identity stream을 취소해 세대를 다시 올리고
                // 재기준화된 전이 소유자를 어기게 된다.
                if FileManagerContentFeature.identityReloadOwnsActiveDirectory(state: state) { return .none }
                return FileManagerContentEntryOpsCoordinator.reloadEntryItemsEffect(state: state)
            case .internal(.flushPendingExternalRefresh):
                return Self.flushPendingExternalRefresh(state: &state)
            case let .internal(.applyNavigationState(navigationState)):
                // 실제 네비게이션·root 변경 시 대기 중인 identity 전이를 즉시 만료한다.
                // 같은 root로의 재적용은 유지하고, 다른 root·비폴더 라우트로 이동하면
                // stale 전이가 되살아나 선택을 잘못 옮기지 않게 한다.
                let expiredIdentityTransitionID = state.pendingIdentityTransition?.recordID
                let keepsExternalRefreshScope: Bool = switch (
                    state.navigation.navigationState,
                    navigationState,
                ) {
                case let (.folder(current), .folder(next)):
                    FileManagerContentIdentityTransitionCoordinator.standardizedPath(current)
                        == FileManagerContentIdentityTransitionCoordinator.standardizedPath(next)
                default:
                    false
                }
                if !keepsExternalRefreshScope {
                    state.pendingExternalRefresh = nil
                }
                FileManagerContentIdentityTransitionCoordinator.expireOnNavigation(
                    navigationState,
                    state: &state,
                )
                guard let expiredIdentityTransitionID,
                      state.pendingIdentityTransition == nil
                else { return .none }
                return .send(.entryViewLayout(.identityReplacement(.cancel(
                    id: expiredIdentityTransitionID,
                    reason: .navigationChanged,
                ))))
            default:
                return .none
            }
        }

        Scope(state: \.composer, action: \.composer) {
            ComposerFeature()
        }

        Scope(state: \.collection, action: \.collection) {
            CollectionFeature()
        }

        FileManagerContentPendingSelectionReducer(phase: .beforeEntryViewLayout)

        Reduce { state, action in
            let effect = handleIdentityTransitionBeforeEntryLayoutLoaded(action, state: &state)
            if case .entryViewLayout(.hierarchy(.restartUnfinishedExpandedFolderLoads)) = action {
                // Content-tab transfer restarts unfinished hierarchy folders in the child
                // reducer and advances their generations. Rebase the page transition before
                // that child action so a pending identity migration follows the restart.
                let restartedFolderIDs = state.entryViewLayout.hierarchy.nodesByID
                    .filter { _, node in
                        node.expansionIntent
                            && (node.loadPhase == .loadingCore || node.loadPhase == .enriching)
                    }
                    .map(\.key)
                FileManagerContentIdentityTransitionCoordinator.rebaseForHierarchyInvalidation(
                    affectedPaths: restartedFolderIDs,
                    state: &state,
                )
            }
            FileManagerContentIdentityTransitionCoordinator.markReplacementSelection(
                on: action,
                state: &state,
            )
            return effect
        }

        Scope(state: \.entryViewLayout, action: \.entryViewLayout) {
            EntryViewLayoutFeature()
        }

        Scope(state: \.aiChat, action: \.aiChat) {
            AiChatFeature()
        }

        FileManagerContentPendingSelectionReducer(phase: .afterEntryViewLayout)

        Reduce { state, action in
            if case let .entryViewLayout(.delegate(.identityReplacementSettled(id, _))) = action {
                guard state.pendingIdentityTransition?.recordID == id else { return .none }
                state.pendingIdentityTransition = nil
                guard state.pendingExternalRefresh != nil else { return .none }
                return .send(.internal(.flushPendingExternalRefresh))
            }
            let selectionBefore = state.entryViewLayout.selectedIds
            let lastSelectedBefore = state.entryViewLayout.lastSelectedId
            let anchorBefore = state.entryViewLayout.rangeAnchorId
            let hadPendingIdentityTransition = state.pendingIdentityTransition != nil
            let settledIdentityTransitionID = state.pendingIdentityTransition?.recordID
            let identityMigrated = resolveRootIdentityTransitionAfterEntryLayoutLoaded(
                action,
                state: &state,
            )
            FileManagerContentIdentityTransitionCoordinator.rebaseFolderOwnersAfterRootSnapshot(
                on: action,
                state: &state,
            )
            FileManagerContentIdentityTransitionCoordinator.resolveReplacementSelection(
                on: action,
                state: &state,
            )
            FileManagerContentIdentityTransitionCoordinator.resolveFolderTransition(
                on: action,
                state: &state,
            )
            // terminal 정산(discard·collapse)도 선택을 바꾸므로 migration과 동일하게
            // selectionChanged를 발행해 syncSelectedEntryIDs·Quick Look 동기화를 보장한다.
            let selectionSettled = state.entryViewLayout.selectedIds != selectionBefore
                || state.entryViewLayout.lastSelectedId != lastSelectedBefore
                || state.entryViewLayout.rangeAnchorId != anchorBefore
            let identityTransitionSettled = hadPendingIdentityTransition
                && state.pendingIdentityTransition == nil
            var effects: [Effect<Action>] = []
            if identityMigrated || selectionSettled {
                effects.append(.send(.entryViewLayout(.delegate(.selectionChanged))))
            }
            if identityTransitionSettled, let settledIdentityTransitionID {
                effects.append(.send(.entryViewLayout(.identityReplacement(.settle(
                    id: settledIdentityTransitionID,
                    outcome: .completed,
                )))))
                if state.pendingExternalRefresh != nil {
                    effects.append(.send(.internal(.flushPendingExternalRefresh)))
                }
            }
            return .merge(effects)
        }

        FileManagerContentComposerReducer()

        FileManagerContentNavigationBridgeReducer()

        FileManagerContentEntryOperationsBridgeReducer()

        FileManagerContentKeyCommandReducer()

        FileManagerContentSyncReducer()

        FileManagerHomeSelectionReducer()

        // Feature → Widget projection (replaces catch-all sync)
        Reduce { state, action in
            let shouldProject = FileManagerContentFeature.shouldProjectContent(action, state: state)
            guard shouldProject else { return .none }

            let isClearingCollection = FileManagerContentFeature.isClearingCollectionMode(action)
            let useCollectionItems = state.isCollectionMode && !isClearingCollection
            let loadedProjectionEntries = useCollectionItems
                ? Array(state.entryViewLayout.collectionItems)
                : Array(state.entryViewLayout.entryOperations.items)
            let isFolderRoute = if case .folder = state.navigation.navigationState { true } else { false }
            let isRetainedProjectionTrigger = switch action {
            case .entryViewLayout(.entryOperations(.loading(.streamEvent))),
                 .entryViewLayout(.entryOperations(.loading(.streamFailed))),
                 // streamFinished는 buffered candidate를 items로 커밋하는 경계다. preservation
                 // owner가 root인 동안에는 커밋 목록으로 projection을 교체하면 destination
                 // migration 전에 before 행이 사라지므로 hold 트리거에 포함한다.
                 .entryViewLayout(.entryOperations(.loading(.streamFinished))):
                true
            case let .entryViewLayout(.entryOperations(.loading(.loadItems(path, _, _)))):
                // operationFinished가 예약한 같은 폴더 재로드의 실제 loadItems 시작 시점에도
                // 마지막 완전 root projection을 유지한다(isReloading=false로 items가 비워지는 창).
                isSameRootFolderReload(path: path, state: state)
            default:
                false
            }
            // 대기 중인 identity 전이의 after-path가 아직 배치에 없으면 부분 교체 대신
            // 마지막 완전 projection을 유지한다. 물리 row 없는 논리 선택은 표시가
            // 깜빡이므로, after-path 도착 또는 accepted completion에서 한 번에 교체한다.
            let transitionHoldsProjection = FileManagerContentIdentityTransitionCoordinator
                .holdsRootProjection(on: action, state: state)
            let projectionEntries = if !useCollectionItems,
                                       isFolderRoute,
                                       isRetainedProjectionTrigger,
                                       loadedProjectionEntries.isEmpty || transitionHoldsProjection,
                                       !state.entryViewLayout.entryOperations.loadingContext.coreFinished
                                       || transitionHoldsProjection,
                                       !state.entryViewLayout.entries.isEmpty
            {
                state.entryViewLayout.entries
            } else {
                loadedProjectionEntries
            }
            _ = EntryArrangementsFeature().reduce(
                into: &state.entryViewLayout.entryArrangements,
                action: .apply(items: projectionEntries, isCollectionMode: useCollectionItems),
            )
            var seenEntryIDs = Set<EntryModel.ID>()
            let arrangedEntries = state.entryViewLayout.entryArrangements.groupedItems
                .flatMap(\.items)
                .filter { seenEntryIDs.insert($0.id).inserted }
            let projectionSections = FileManagerContentFeature.makeSections(
                groupedItems: state.entryViewLayout.entryArrangements.groupedItems,
                collapsedGroups: state.entryViewLayout.entryArrangements.collapsedGroups,
            )
            let projection = ContentProjection(
                entries: arrangedEntries,
                isLoading: state.entryViewLayout.entryOperations.isLoading,
                sortKey: .fromShared(state.entryViewLayout.entryArrangements.sortKey),
                sortOrder: state.entryViewLayout.entryArrangements.sortOrder,
                groupKey: .fromShared(state.entryViewLayout.entryArrangements.groupKey.rawValue),
                collapsedGroups: state.entryViewLayout.entryArrangements.collapsedGroups,
                sections: projectionSections,
                renamingItemId: state.entryViewLayout.entryOperations.renamingItemId,
                renamingText: state.entryViewLayout.entryOperations.renamingText,
                clipboardCutPaths: state.entryViewLayout.entryOperations.clipboardOperation == .cut
                    ? Set(state.entryViewLayout.entryOperations.clipboardItems)
                    : [],
                hasClipboardItems: !state.entryViewLayout.entryOperations.clipboardItems.isEmpty,
                busyEntryPaths: Set(state.entryViewLayout.entryOperations.itemStates.filter(\.value.isBusy).map(\.key)),
                openWithApplications: state.entryViewLayout.entryOperations.commonApplicationsForSelectedFiles,
                restorableTrashPaths: state.entryViewLayout.entryOperations.restorableTrashPaths,
                trashDirectoryPath: entryOpenClient.trashDirectoryPath(),
                collectionWindowID: state.entryViewLayout.entryOperations.windowID,
                collectionLoadingCancellationOwnerID: state.entryViewLayout.entryOperations.loadingCancellationOwnerID,
            )
            if case .internal(.commitRootCandidateAfterMigration) = action {
                let rootFolders = arrangedEntries.filter(\.supportsListHierarchyExpansion)
                return .concatenate(
                    .send(.entryViewLayout(.view(.applyContentProjection(projection)))),
                    .send(.entryViewLayout(.hierarchy(.rootSnapshotReconciled(
                        rootContextGeneration: state.entryViewLayout.hierarchy.rootContextGeneration,
                        rootFolders: rootFolders,
                    )))),
                )
            }
            // hierarchy root가 설정된 경우에만 root completion을 전송한다.
            let isRootCompletion = FileManagerContentFeature.isRootCompletion(action, state: &state)
                && !state.entryViewLayout.hierarchy.rootPath.isEmpty
            if isRootCompletion {
                let rootFolders = arrangedEntries.filter(\.supportsListHierarchyExpansion)
                return .concatenate(
                    .send(.entryViewLayout(.view(.applyContentProjection(projection)))),
                    .send(.entryViewLayout(.hierarchy(.rootSnapshotCompleted(
                        rootContextGeneration: state.entryViewLayout.hierarchy.rootContextGeneration,
                        rootFolders: rootFolders,
                    )))),
                )
            }
            var projectionEffects: [Effect<Action>] = [
                .send(.entryViewLayout(.view(.applyContentProjection(projection)))),
            ]
            // stream failure는 root completion이 아니므로 rootSnapshotCompleted를 보내지 않지만,
            // partial projection이 선택을 보존한 상태이므로 현재 visible projection 기준으로
            // 선택·rename delegate를 동기화한다. 이전 generation의 stale failure는
            // EntryOperationsLoadingReducer가 무시하므로, 여기서도 현재 loading generation과
            // 일치할 때만 재조정을 발행해 진행 중인 새 batch의 선택·rename을 조기에 제거하지 않는다.
            if case let .entryViewLayout(.entryOperations(.loading(.streamFailed(generation)))) = action,
               generation == state.entryViewLayout.entryOperations.loadingContext.generation,
               !state.entryViewLayout.hierarchy.rootPath.isEmpty
            {
                projectionEffects.append(.send(.entryViewLayout(.internal(.reconcileHierarchySelection))))
            }
            return .concatenate(projectionEffects)
        }

        Reduce { state, action in
            if let effect = handleCollectionOwnerAction(action, state: &state) {
                return effect
            }

            switch action {
            case let .aiChat(.executionEvent(event)):
                return handleBackgroundAiChatExecutionEvent(event, state: &state)

            case let .aiChat(.persistenceFailed(lock, _)):
                return handleBackgroundAiChatPersistenceEvent(sessionID: lock.context.sessionID, state: &state)

            case let .aiChat(.persistenceRecoverySucceeded(lock)):
                return handleBackgroundAiChatPersistenceEvent(sessionID: lock.context.sessionID, state: &state)

            case let .aiChat(.persistenceRecoveryRetryFailed(lock, _)):
                return handleBackgroundAiChatPersistenceEvent(sessionID: lock.context.sessionID, state: &state)

            case let .aiChat(.sessionSnapshotSaved(summary, _, _, _)):
                return handleBackgroundAiChatPersistenceEvent(sessionID: summary.sessionID, state: &state)

            case .aiChat(.cancelInFlightWork):
                return .none

            case .view(.newChatTapped):
                return .send(.delegate(.newChatRequested))

            case .view(.aiChatNewChatTapped):
                return .send(.delegate(.durableNewChatRequested))

            case .view(.showChatHistoryTapped):
                return .send(.delegate(.showChatHistoryRequested))

            case .aiChat(.delegate(.openAISettings)):
                return .send(.delegate(.openAISettings))

            case let .aiChat(.newChatCreated(snapshot)):
                return .send(.delegate(.aiChatSessionCreated(snapshot.sessionID)))

            case let .aiChat(.restoreOutcome(requestedSessionID, result, restoreFailure)):
                guard restoreFailure == nil,
                      case let .restored(snapshot) = result,
                      state.aiChat.mode == .chat,
                      state.aiChat.sessionID == requestedSessionID,
                      isAiChatNavigationRoute(state.navigation.navigationState)
                else { return .none }
                let title = restoredAiChatSessionTitle(
                    sessionID: requestedSessionID,
                    restoredSnapshot: snapshot,
                    state: state.aiChat,
                )
                return .send(.delegate(.aiChatSessionRestored(sessionID: requestedSessionID, title: title)))

            case let .aiChat(.sessionRowTapped(sessionID)):
                guard state.aiChat.executionPhase.isProcessing,
                      state.aiChat.mode == .chat,
                      state.aiChat.sessionID == sessionID,
                      case .aiChatSessions = state.navigation.navigationState,
                      let title = state.aiChat.sessionList.allRows.first(where: { $0.sessionID == sessionID })?.title
                else { return .none }
                return .send(.delegate(.aiChatSessionRestored(sessionID: sessionID, title: title)))

            case let .internal(.setAutomaticRefreshFeedbackSuppressed(isSuppressed)):
                state.suppressAutomaticRefreshFeedback = isSuppressed
                return .none

            case .internal(.clearCollectionMode), .internal(.exitCollectionMode):
                return handleCollectionModeAction(
                    action,
                    state: &state,
                    computerName: fileManagerClient.displayName("/"),
                )

            case .entryViewLayout(.entryArrangements(.delegate(.requestApply))):
                let items = Array(state.entryViewLayout.entryOperations.items)
                let isCollectionMode = state.entryViewLayout.isCollectionMode
                return .send(.entryViewLayout(.entryArrangements(.apply(
                    items: items,
                    isCollectionMode: isCollectionMode,
                ))))

            default:
                return .none
            }
        }
    }

    private func arrangementMetadataReloadEffect(
        priority: EntryMetadataPriority,
        state: inout State,
    ) -> Effect<Action> {
        guard !priority.probes.isEmpty else { return .none }
        if !state.entryViewLayout.isCollectionMode {
            // folder route의 metadata reload도 세대를 올리므로 대기 전이를 재기준화한다.
            FileManagerContentIdentityTransitionCoordinator.rebaseForSameRootReload(
                navigationState: state.navigation.navigationState,
                state: &state,
            )
        }
        let rootReloadEffect: Effect<Action>
        if state.entryViewLayout.isCollectionMode {
            let basePaths = state.entryViewLayout.activeCollectionReplacePaths.isEmpty
                ? state.entryViewLayout.collectionItems.map(\.id)
                : state.entryViewLayout.activeCollectionReplacePaths
            let appendPaths = state.entryViewLayout.activeCollectionAppendPaths.keys.sorted().flatMap {
                state.entryViewLayout.activeCollectionAppendPaths[$0] ?? []
            }
            var seenPaths = Set<String>()
            let sourcePaths = (basePaths + appendPaths).filter { seenPaths.insert($0).inserted }
            rootReloadEffect = .send(.entryViewLayout(.internal(.applyCollectionSearchPaths(
                paths: sourcePaths,
                showHidden: state.entryViewLayout.showHiddenFiles,
                priority: priority,
            ))))
        } else {
            rootReloadEffect = FileManagerContentEntryOpsCoordinator.reloadEntryItemsEffect(
                navigationState: state.navigation.navigationState,
                showHidden: state.entryViewLayout.showHiddenFiles,
                priority: priority,
            )
        }
        return .concatenate(
            rootReloadEffect,
            .send(.entryViewLayout(.hierarchy(.arrangementMetadataPriorityChanged))),
        )
    }

    static func flushPendingExternalRefresh(
        state: inout State,
    ) -> Effect<Action> {
        guard let pending = state.pendingExternalRefresh else { return .none }
        state.pendingExternalRefresh = nil
        guard case let .folder(currentPath) = state.navigation.navigationState,
              FileManagerContentIdentityTransitionCoordinator.canonicalizedPath(currentPath)
              == FileManagerContentIdentityTransitionCoordinator.canonicalizedPath(pending.rootPath)
        else { return .none }

        FileManagerContentIdentityTransitionCoordinator.rebaseForNextRootReload(state: &state)
        FileManagerContentIdentityTransitionCoordinator.rebaseForHierarchyInvalidation(
            affectedPaths: pending.requiresCoarseHierarchyReload
                ? Array(state.entryViewLayout.hierarchy.expandedFolderIDs)
                : pending.affectedPaths,
            state: &state,
            removedPrefixes: pending.removedPrefixes,
        )
        let hierarchyAction: EntryListHierarchyAction = pending.requiresCoarseHierarchyReload
            ? .coarseHierarchyInvalidated(
                removedPrefixes: pending.removedPrefixes,
                retainsCompleteSnapshots: true,
            )
            : .hierarchyInvalidated(
                affectedPaths: pending.affectedPaths,
                removedPrefixes: pending.removedPrefixes,
            )
        return .concatenate(
            .send(.entryViewLayout(.hierarchy(hierarchyAction))),
            FileManagerContentEntryOpsCoordinator.reloadEntryItemsEffect(state: state),
        )
    }

    private func handleIdentityTransitionBeforeEntryLayoutLoaded(
        _ action: Action,
        state: inout State,
    ) -> Effect<Action> {
        let hadPendingRootSourceMigration = FileManagerContentIdentityTransitionCoordinator
            .hasPendingRootSourceMigration(state)
        let isRootCandidateTerminalAction = switch action {
        case .entryViewLayout(.entryOperations(.loading(.streamFinished))),
             .entryViewLayout(.hierarchy(.folderCollapseRequested)):
            true
        case let .entryViewLayout(.hierarchy(.folderChildrenResponse(_, _, _, response))):
            switch response {
            case .event(.coreFinished), .streamCompleted, .failed:
                true
            case .event(.coreBatch), .event(.metadataPatches):
                false
            }
        default:
            false
        }
        let shouldCheckRootCandidateAfterTerminal = hadPendingRootSourceMigration
            && isRootCandidateTerminalAction
        let terminalCheckEffect: Effect<Action> = shouldCheckRootCandidateAfterTerminal
            ? .send(.internal(.checkRootCandidateAfterTerminal))
            : .none
        let entries: [EntryModel]
        let projectionOwner: FileManagerContentState.EntryIdentityTransitionProjectionOwner
        switch action {
        case let .entryViewLayout(.entryOperations(.loading(.itemsLoaded(items)))):
            entries = items
            projectionOwner = .root(
                generation: state.entryViewLayout.entryOperations.loadingContext.generation,
            )

        case let .entryViewLayout(.entryOperations(.loading(.streamEvent(streamEvent)))):
            guard case let .coreBatch(items: items, batchIndex: batchIndex) = streamEvent.event,
                  streamEvent.generation == state.entryViewLayout.entryOperations.loadingContext.generation,
                  batchIndex == state.entryViewLayout.entryOperations.loadingContext.expectedCoreBatchIndex
            else { return terminalCheckEffect }
            // 보존 reload buffering 중 배치는 candidate에만 누적되고 streamFinished에서 커밋된다.
            // 커밋 전 selection migration은 화면의 before snapshot과 어긋나므로 terminal 커밋으로 미룬다.
            guard !state.entryViewLayout.entryOperations.loadingContext.isBufferingPreservedDirectoryReload
            else { return .none }
            if state.pendingIdentityTransition != nil { return .none }
            entries = items
            projectionOwner = .root(generation: streamEvent.generation)

        case let .entryViewLayout(.hierarchy(.folderChildrenResponse(
            rootContextGeneration,
            folderID,
            folderGeneration,
            response,
        ))):
            guard rootContextGeneration == state.entryViewLayout.hierarchy.rootContextGeneration,
                  let node = state.entryViewLayout.hierarchy.nodesByID[folderID],
                  node.generation == folderGeneration,
                  node.loadPhase == .loadingCore || node.loadPhase == .enriching,
                  case let .event(.coreBatch(items: items, batchIndex: batchIndex)) = response,
                  batchIndex == node.folder.expectedBatchIndex
            else { return terminalCheckEffect }
            entries = items
            projectionOwner = .folder(id: folderID, generation: folderGeneration)
            FileManagerContentIdentityTransitionCoordinator.beginDeferredFolderReplacementIfNeeded(
                folderID: folderID,
                items: items,
                state: &state,
            )

        default:
            return terminalCheckEffect
        }

        let identityMigrated = FileManagerContentIdentityTransitionCoordinator.migrateSelection(
            entries: entries,
            projectionOwner: projectionOwner,
            state: &state,
        )
        // 자체 destination owner를 가진 additional 이동이 이번 batch에서 migration됐으면
        // primary 검증 결과와 무관하게 selection 동기화를 발행한다.
        let additionalMigrated = state.pendingIdentityTransition?.additionalMoves
            .contains { $0.destinationOwner != nil && $0.migrated } == true
        guard identityMigrated || additionalMigrated else { return .none }
        let releasedRootSource = hadPendingRootSourceMigration
            && !FileManagerContentIdentityTransitionCoordinator.hasPendingRootSourceMigration(state)
        guard releasedRootSource else {
            return .send(.entryViewLayout(.delegate(.selectionChanged)))
        }
        return .concatenate(
            .send(.entryViewLayout(.delegate(.selectionChanged))),
            .send(.internal(.commitRootCandidateAfterMigration)),
        )
    }

    private func resolveRootIdentityTransitionAfterEntryLayoutLoaded(
        _ action: Action,
        state: inout State,
    ) -> Bool {
        guard let transition = state.pendingIdentityTransition else { return false }
        // primary가 folder여도 root를 destination으로 하는 additional pair가 있으면
        // buffered root reload의 terminal 커밋에서 해당 pair를 migration해야 한다.
        var rootGeneration: Int?
        if case let .root(generation) = transition.projectionOwner {
            rootGeneration = generation
        }
        if rootGeneration == nil {
            for move in transition.additionalMoves {
                if case let .root(generation) = move.destinationOwner {
                    rootGeneration = generation
                    break
                }
            }
        }
        guard let generation = rootGeneration else { return false }
        let hadRootPair = transition.additionalMoves.contains { move in
            if case .root = move.destinationOwner { return true }
            return false
        }

        switch action {
        case let .entryViewLayout(.entryOperations(.loading(.streamEvent(streamEvent)))):
            guard case let .coreBatch(items, batchIndex) = streamEvent.event,
                  streamEvent.generation == generation,
                  streamEvent.generation == state.entryViewLayout.entryOperations.loadingContext.generation,
                  state.entryViewLayout.entryOperations.loadingContext.expectedCoreBatchIndex > batchIndex,
                  !state.entryViewLayout.entryOperations.loadingContext.isBufferingPreservedDirectoryReload
            else { return false }
            let previousSelectedIDs = state.entryViewLayout.selectedIds
            if transition.preserveSelectionForReplacementBatch,
               let preservedBeforeID = transition.preservedLexicalBeforeID
            {
                state.entryViewLayout.selectedIds.insert(preservedBeforeID)
            }
            let primaryBefore = transition.beforeLexicalPath.isEmpty
                ? transition.beforePath
                : transition.beforeLexicalPath
            let primaryAfter = FileManagerContentIdentityTransitionCoordinator.afterLexicalPath(transition)
            if transition.preserveSelectionForReplacementBatch,
               items.contains(where: {
                   FileManagerContentIdentityTransitionCoordinator.standardizedPath($0.id)
                       == FileManagerContentIdentityTransitionCoordinator.standardizedPath(primaryAfter)
               }),
               !state.entryViewLayout.selectedIds.contains(where: {
                   FileManagerContentIdentityTransitionCoordinator.standardizedPath($0)
                       == FileManagerContentIdentityTransitionCoordinator.standardizedPath(primaryBefore)
               })
            {
                state.entryViewLayout.selectedIds.insert(primaryBefore)
            }
            _ = FileManagerContentIdentityTransitionCoordinator.migrateSelection(
                entries: items,
                projectionOwner: .root(generation: streamEvent.generation),
                state: &state,
            )
            return state.entryViewLayout.selectedIds != previousSelectedIDs

        case let .entryViewLayout(.entryOperations(.loading(.streamFinished(streamGeneration)))):
            guard streamGeneration == generation,
                  state.entryViewLayout.entryOperations.loadingContext.streamTerminal,
                  state.entryViewLayout.entryOperations.loadingContext.coreFinished
            else { return false }
            let migrated = FileManagerContentIdentityTransitionCoordinator.migrateSelection(
                entries: Array(state.entryViewLayout.entryOperations.items),
                projectionOwner: .root(generation: streamGeneration),
                state: &state,
            )
            let terminalized = FileManagerContentIdentityTransitionCoordinator.resolveRootDestinationSuccess(
                generation: streamGeneration,
                state: &state,
            )
            // migration 성공 여부와 무관하게 root pair가 있으면 terminal 처리 후 동기화를 발행하고
            // 대기 pair가 없으면 전이를 닫는다.
            if !FileManagerContentIdentityTransitionCoordinator.hasPendingDestinationPairs(state) {
                FileManagerContentIdentityTransitionCoordinator.discard(state: &state)
            }
            return migrated || hadRootPair || terminalized

        case let .entryViewLayout(.entryOperations(.loading(.streamFailed(streamGeneration)))):
            guard streamGeneration == generation,
                  state.entryViewLayout.entryOperations.loadingContext.streamTerminal,
                  state.entryViewLayout.entryOperations.loadingContext.isIncomplete
            else { return false }
            // root failure도 success terminal과 같은 primary 정산 경계를 사용한다.
            // folder additional pair가 남아 있으면 primary source만 정산하고 전이는 유지한다.
            guard case .root = transition.projectionOwner else { return false }
            let terminalized = FileManagerContentIdentityTransitionCoordinator.resolveRootDestinationSuccess(
                generation: streamGeneration,
                state: &state,
            )
            let hasFolderPairs = state.pendingIdentityTransition?.additionalMoves.contains { move in
                guard case .folder = move.destinationOwner else { return false }
                return !move.migrated
            } == true
            if !hasFolderPairs {
                FileManagerContentIdentityTransitionCoordinator.discard(state: &state)
            }
            return terminalized

        default:
            return false
        }
    }

    /// loadItems 시작이 현재 표시 중인 완전 projection과 같은 root의 재로드인지 판정한다.
    /// 표시 항목이 모두 대상 경로의 직속 하위일 때만 유지한다(다른 폴더 이동과 구분).
    private static func identityReloadOwnsActiveDirectory(state: State) -> Bool {
        guard let transition = state.pendingIdentityTransition,
              case let .root(generation) = transition.projectionOwner,
              case let .folder(currentPath) = state.navigation.navigationState
        else { return false }
        guard FileManagerContentIdentityTransitionCoordinator.ownerIsCurrent(
            .root(generation: generation),
            state: state,
        ) else { return false }
        return FileManagerContentIdentityTransitionCoordinator.canonicalizedPath(currentPath) == transition.rootPath
    }

    private func isSameRootFolderReload(path: String, state: State) -> Bool {
        guard case let .folder(currentPath) = state.navigation.navigationState else { return false }
        let normalizedRoot = canonicalizedPath(currentPath)
        guard canonicalizedPath(path) == normalizedRoot,
              !state.entryViewLayout.entries.isEmpty
        else { return false }
        let lexicalRoot = URL(fileURLWithPath: currentPath).standardizedFileURL.path
        return state.entryViewLayout.entries.allSatisfy { entry in
            URL(fileURLWithPath: entry.id).standardizedFileURL.deletingLastPathComponent().path == lexicalRoot
        }
    }

    private func canonicalizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
    }

    // MARK: - Projection Bridge

    static func shouldProjectContent(_ action: Action, state: State) -> Bool {
        // 보존 디렉터리 reload buffering 중에는 core stream 진행 상황을 projection에 노출하지 않는다.
        if state.entryViewLayout.entryOperations.loadingContext.isBufferingPreservedDirectoryReload,
           case let .entryViewLayout(.entryOperations(.loading(.streamEvent(streamEvent)))) = action
        {
            switch streamEvent.event {
            case .coreBatch, .coreFinished, .metadataPatches:
                return false
            }
        }
        switch action {
        case .entryViewLayout(.entryOperations(.loading(.loadItems))),
             .entryViewLayout(.entryOperations(.loading(.loadRecentItems))),
             .entryViewLayout(.entryOperations(.loading(.loadTagItems))),
             .entryViewLayout(.entryOperations(.loading(.loadComputerItems))),
             .entryViewLayout(.entryOperations(.loading(.cancelAndClearItems))),
             .entryViewLayout(.entryOperations(.loading(.itemsLoaded))),
             .entryViewLayout(.entryOperations(.loading(.streamEvent))),
             .entryViewLayout(.entryOperations(.loading(.streamFinished))),
             .entryViewLayout(.entryOperations(.loading(.streamFailed))),
             .entryViewLayout(.entryOperations(.loading(.itemsLoadFailed))),
             .entryViewLayout(.entryOperations(.lifecycle(.operationStarted))),
             .entryViewLayout(.entryOperations(.lifecycle(.operationFinished))),
             .entryViewLayout(.entryOperations(.lifecycle(.entryActionCompleted))),
             .entryViewLayout(.entryOperations(.lifecycle(.emptyTrashCompleted))),
             .entryViewLayout(.entryOperations(.edit(.commitRename))),
             .entryViewLayout(.entryOperations(.edit(.startRename))),
             .entryViewLayout(.entryOperations(.edit(.cancelRename))),
             .entryViewLayout(.entryOperations(.openWith(.loadCommonApplicationsForFiles))),
             .entryViewLayout(.entryOperations(.openWith(.commonApplicationsLoaded))),
             .entryViewLayout(.entryOperations(.lifecycle(.syncClipboardState))),
             .entryViewLayout(.entryOperations(.lifecycle(.restorableTrashPathsLoaded))),
             .entryViewLayout(.entryOperations(.lifecycle(.pathsMutated))),
             .entryViewLayout(.entryOperations(.clipboard(.copySelectedItems))),
             .entryViewLayout(.entryOperations(.clipboard(.setClipboardOperation))),
             .entryViewLayout(.entryArrangements(.delegate(.applied))),
             .entryViewLayout(.entryArrangements(.toggleCollapsedGroup)),
             .entryViewLayout(.internal(.setCollectionMode)),
             .entryViewLayout(.internal(.setCollectionItems)),
             .entryViewLayout(.internal(.applyCollectionSearchPaths)),
             .entryViewLayout(.internal(.collectionReplaceEvent)),
             .entryViewLayout(.internal(.collectionAppendEvent)),
             .entryViewLayout(.internal(.removeCollectionPaths)),
             .externalFileSystemChanged,
             .internal(.commitRootCandidateAfterMigration),
             .internal(.clearCollectionMode),
             .internal(.exitCollectionMode):
            return true
        default:
            return false
        }
    }

    static func isRootCompletion(_ action: Action, state: inout State) -> Bool {
        switch action {
        case .entryViewLayout(.entryOperations(.loading(.itemsLoaded))):
            return true
        case let .entryViewLayout(.entryOperations(.loading(.streamEvent(streamEvent)))):
            guard case .coreFinished = streamEvent.event,
                  state.entryViewLayout.entryOperations.loadingContext.acceptedCoreFinishedGeneration == streamEvent
                  .generation,
                  !state.entryViewLayout.entryOperations.loadingContext.isBufferingPreservedDirectoryReload
            else { return false }
            state.entryViewLayout.entryOperations.loadingContext.acceptedCoreFinishedGeneration = nil
            return true
        case let .entryViewLayout(.entryOperations(.loading(.streamFinished(generation)))):
            guard state.entryViewLayout.entryOperations.loadingContext.acceptedCoreFinishedGeneration == generation
            else { return false }
            state.entryViewLayout.entryOperations.loadingContext.acceptedCoreFinishedGeneration = nil
            return true
        default:
            return false
        }
    }

    static func isClearingCollectionMode(_ action: Action) -> Bool {
        switch action {
        case .internal(.clearCollectionMode),
             .internal(.exitCollectionMode):
            true
        default:
            false
        }
    }

    static func makeSections(
        groupedItems: [GroupedItems],
        collapsedGroups: Set<String>,
    ) -> [EntryViewLayoutSection] {
        groupedItems.map { group in
            EntryViewLayoutSection(
                id: group.groupName,
                title: group.groupName.isEmpty ? nil : group.groupName,
                colorCode: group.colorCode,
                items: group.items,
                isCollapsed: collapsedGroups.contains(group.groupName),
            )
        }
    }
}

private func restoredAiChatSessionTitle(
    sessionID: AiChatSessionID,
    restoredSnapshot: AiChatSessionSnapshot,
    state: AiChatFeature.State,
) -> String {
    var canonicalSummary = state.sessionList.allRows.first { $0.sessionID == sessionID }
    if let finalSnapshot = state.executionPhase.lock?.finalSnapshot,
       finalSnapshot.sessionID == sessionID
    {
        let finalSummary = AiChatSessionSummary(snapshot: finalSnapshot)
        if let currentSummary = canonicalSummary {
            if finalSummary.isNewer(than: currentSummary) {
                canonicalSummary = finalSummary
            }
        } else {
            canonicalSummary = finalSummary
        }
    }
    if let title = canonicalSummary?.title.trimmingCharacters(in: .whitespacesAndNewlines),
       !title.isEmpty
    {
        return title
    }
    if state.sessionID == sessionID,
       let title = state.currentSessionCustomTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
       !title.isEmpty
    {
        return title
    }
    if state.sessionID == sessionID,
       let firstUserMessage = state.transcriptHistory.first(where: { $0.role == .user })?.content,
       !firstUserMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    {
        return AiChatSessionSummary.automaticTitle(from: firstUserMessage)
    }
    return AiChatSessionSummary.titleCandidate(from: restoredSnapshot) ?? ""
}

private func isAiChatNavigationRoute(_ route: ContentPageNavigationRoute) -> Bool {
    switch route {
    case .aiChat,
         .aiChatSessions:
        true
    default:
        false
    }
}

private func handleBackgroundAiChatExecutionEvent(
    _ event: AiChatEvent,
    state: inout FileManagerContentState,
) -> Effect<FileManagerContentAction> {
    let sessionID = aiChatEventSessionID(event)
    guard let sessionID, sessionID == state.aiChat.sessionID else {
        return .none
    }
    return .none
}

private func handleBackgroundAiChatPersistenceEvent(
    sessionID: AiChatSessionID?,
    state: inout FileManagerContentState,
) -> Effect<FileManagerContentAction> {
    guard let sessionID, sessionID == state.aiChat.sessionID else {
        return .none
    }
    return .none
}
