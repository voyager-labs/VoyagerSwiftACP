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
                    state: state,
                )
            case let .entryViewLayout(.entryArrangements(.setGroupKey(key))):
                guard state.entryViewLayout.entryArrangements.groupKey != key else { return .none }
                return arrangementMetadataReloadEffect(
                    priority: FileManagerContentEntryOpsCoordinator.rootMetadataPriority(
                        sortKey: state.entryViewLayout.entryArrangements.sortKey,
                        groupKey: key,
                    ),
                    state: state,
                )
            case .internal(.reloadDirectoryListing):
                guard case .folder = state.navigation.navigationState else { return .none }
                return FileManagerContentEntryOpsCoordinator.reloadEntryItemsEffect(state: state)
            case let .internal(.applyNavigationState(navigationState)):
                // 실제 네비게이션·root 변경 시 대기 중인 identity 전이를 즉시 만료한다.
                // 같은 root로의 재적용은 유지하고, 다른 root·비폴더 라우트로 이동하면
                // stale 전이가 되살아나 선택을 잘못 옮기지 않게 한다.
                expireTransitionOnNavigation(navigationState, state: &state)
                return .none
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

        Reduce { state, action in
            let effect = handlePendingSelectionBeforeEntryLayoutLoaded(action, state: &state)
            markPreserveSelectionForReplacementProjection(on: action, state: &state)
            return effect
        }

        Scope(state: \.entryViewLayout, action: \.entryViewLayout) {
            EntryViewLayoutFeature()
        }

        Scope(state: \.aiChat, action: \.aiChat) {
            AiChatFeature()
        }

        Reduce { state, action in
            let effect = handlePendingSelectionAfterEntryLayoutLoaded(action, state: &state)
            rebaseFolderIdentityTransitionOwnersAfterRootSnapshot(on: action, state: &state)
            resolvePreserveSelectionForReplacementProjection(on: action, state: &state)
            resolveFolderIdentityTransition(on: action, state: &state)
            return effect
        }

        FileManagerContentComposerReducer()

        FileManagerContentNavigationBridgeReducer()

        FileManagerContentEntryOperationsBridgeReducer()

        FileManagerContentKeyCommandReducer()

        FileManagerContentSyncReducer()

        FileManagerHomeSelectionReducer()

        // Feature → Widget projection (replaces catch-all sync)
        Reduce { state, action in
            let shouldProject = FileManagerContentFeature.shouldProjectContent(action)
            guard shouldProject else { return .none }

            let isClearingCollection = FileManagerContentFeature.isClearingCollectionMode(action)
            let useCollectionItems = state.isCollectionMode && !isClearingCollection
            let loadedProjectionEntries = useCollectionItems
                ? Array(state.entryViewLayout.collectionItems)
                : Array(state.entryViewLayout.entryOperations.items)
            let isFolderRoute = if case .folder = state.navigation.navigationState { true } else { false }
            let isRetainedProjectionTrigger = switch action {
            case .entryViewLayout(.entryOperations(.loading(.streamEvent))),
                 .entryViewLayout(.entryOperations(.loading(.streamFailed))):
                true
            case let .entryViewLayout(.entryOperations(.loading(.loadItems(path, _, _)))):
                // operationFinished가 예약한 같은 폴더 재로드의 실제 loadItems 시작 시점에도
                // 마지막 완전 root projection을 유지한다(isReloading=false로 items가 비워지는 창).
                isSameRootFolderReload(path: path, state: state)
            default:
                false
            }
            let projectionEntries = if !useCollectionItems,
                                       isFolderRoute,
                                       isRetainedProjectionTrigger,
                                       loadedProjectionEntries.isEmpty,
                                       !state.entryViewLayout.entryOperations.loadingContext.coreFinished,
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
        state: State,
    ) -> Effect<Action> {
        guard !priority.probes.isEmpty else { return .none }
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

    private func handlePendingSelectionBeforeEntryLayoutLoaded(
        _ action: Action,
        state: inout State,
    ) -> Effect<Action> {
        let entries: [EntryModel]
        let projectionOwner: FileManagerContentState.EntryIdentityTransitionProjectionOwner
        let appliesPendingExternalSelection: Bool
        switch action {
        case let .entryViewLayout(.entryOperations(.loading(.itemsLoaded(items)))):
            entries = items
            projectionOwner = .root(
                generation: state.entryViewLayout.entryOperations.loadingContext.generation,
            )
            appliesPendingExternalSelection = true

        case let .entryViewLayout(.entryOperations(.loading(.streamEvent(streamEvent)))):
            guard case let .coreBatch(items: items, batchIndex: batchIndex) = streamEvent.event,
                  streamEvent.generation == state.entryViewLayout.entryOperations.loadingContext.generation,
                  batchIndex == state.entryViewLayout.entryOperations.loadingContext.expectedCoreBatchIndex
            else { return .none }
            entries = items
            projectionOwner = .root(generation: streamEvent.generation)
            appliesPendingExternalSelection = true

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
            else { return .none }
            entries = items
            projectionOwner = .folder(id: folderID, generation: folderGeneration)
            appliesPendingExternalSelection = false

        default:
            return .none
        }

        let pendingSelectionApplied = appliesPendingExternalSelection
            && FileManagerContentEntryOpsCoordinator.applyPendingSelectionForLoadedEntries(
                entries: entries,
                state: &state,
            )
        let identityMigrated = FileManagerContentEntryOpsCoordinator.migrateSelectionAlongIdentityTransition(
            entries: entries,
            projectionOwner: projectionOwner,
            state: &state,
        )
        guard pendingSelectionApplied || identityMigrated else { return .none }
        return .send(.entryViewLayout(.delegate(.selectionChanged)))
    }

    private func handlePendingSelectionAfterEntryLayoutLoaded(
        _ action: Action,
        state: inout State,
    ) -> Effect<Action> {
        let entries: [EntryModel]
        switch action {
        case let .entryViewLayout(.entryOperations(.loading(.itemsLoaded(loadedEntries)))):
            entries = loadedEntries
        case let .entryViewLayout(.entryOperations(.loading(.streamEvent(streamEvent)))):
            guard case .coreBatch = streamEvent.event else { return .none }
            entries = Array(state.entryViewLayout.entryOperations.loadingContext.items)
        default:
            return .none
        }
        guard FileManagerContentEntryOpsCoordinator.applyPendingSelectionForLoadedEntries(
            entries: entries,
            state: &state,
        ) else {
            return .none
        }
        return .send(.entryViewLayout(.delegate(.selectionChanged)))
    }

    /// 비종료 대체 projection이 reconcile로 before-path 선택을 지우기 직전에 transient 표시를 세운다.
    /// 종료(accepted) projection 또는 사용자가 이미 선택을 바꾼 경우에는 세우지 않아
    /// deselect를 되돌리지 않는다.
    private func markPreserveSelectionForReplacementProjection(
        on action: Action,
        state: inout State,
    ) {
        guard var transition = state.pendingIdentityTransition else { return }
        guard let trigger = identityReplacementTrigger(action, transition: transition) else { return }
        let triggerOwner = switch trigger {
        case .migration: transition.projectionOwner
        case .preservation: transition.preservationOwner ?? transition.projectionOwner
        }
        guard case let .folder(currentPath) = state.navigation.navigationState,
              canonicalizedPath(currentPath) == transition.rootPath,
              FileManagerContentEntryOpsCoordinator.identityTransitionOwnerIsCurrent(
                  triggerOwner,
                  state: state,
              )
        else {
            state.pendingIdentityTransition = nil
            return
        }
        if case .root = transition.projectionOwner,
           state.entryViewLayout.entryOperations.loadingContext.coreFinished
        {
            return
        }
        let beforePath = canonicalizedPath(transition.beforePath)
        let afterPath = canonicalizedPath(transition.afterPath)
        let selectedPaths = Set(state.entryViewLayout.selectedIds.map(canonicalizedPath))
        guard selectedPaths.contains(beforePath),
              !selectedPaths.contains(afterPath)
        else { return }
        let loadedPaths = replacementProjectionPaths(owner: triggerOwner, state: state)
        guard !loadedPaths.contains(afterPath) else { return }
        // 재선택은 canonical이 아닌 현재 선택의 원본 lexical ID로 수행해야 표기가 유지된다.
        transition.preservedLexicalBeforeID = state.entryViewLayout.selectedIds.first {
            canonicalizedPath($0) == beforePath
        }
        transition.preserveSelectionForReplacementBatch = true
        state.pendingIdentityTransition = transition
    }

    /// reconcile 후 transient 표시가 있으면 before-path 선택을 복원하고, 종료(accepted) projection에서
    /// after-path가 끝내 없으면 전이를 소비해 기존 선택 reconcile이 이기게 한다.
    private func resolvePreserveSelectionForReplacementProjection(
        on action: Action,
        state: inout State,
    ) {
        guard var transition = state.pendingIdentityTransition else { return }
        guard identityReplacementTrigger(action, transition: transition) != nil else { return }
        let afterPath = canonicalizedPath(transition.afterPath)
        let selectedPaths = Set(state.entryViewLayout.selectedIds.map(canonicalizedPath))

        if transition.preserveSelectionForReplacementBatch {
            transition.preserveSelectionForReplacementBatch = false
            let preservedLexicalBeforeID = transition.preservedLexicalBeforeID
            transition.preservedLexicalBeforeID = nil
            state.pendingIdentityTransition = transition
            let beforePath = canonicalizedPath(transition.beforePath)
            guard !selectedPaths.contains(beforePath), !selectedPaths.contains(afterPath) else { return }
            // canonical이 아닌 보존된 원본 lexical ID를 재선택해 표기·표시 선택이 유지되게 한다.
            let restoredID = preservedLexicalBeforeID ?? transition.beforePath
            state.entryViewLayout.selectedIds.insert(restoredID)
            state.entryViewLayout.lastSelectedId = restoredID
            state.entryViewLayout.rangeAnchorId = restoredID
            return
        }

        guard case .root = transition.projectionOwner,
              state.entryViewLayout.entryOperations.loadingContext.coreFinished
        else { return }
        let visiblePaths = visibleEntryPaths(in: state)
        guard !visiblePaths.contains(afterPath), !selectedPaths.contains(afterPath) else { return }
        state.pendingIdentityTransition = nil
    }

    /// action이 전이 관련 replacement projection인지와 어느 소유자 기준인지 판정한다.
    /// applyContentProjection은 root 투영을 대표하고, folderChildrenResponse coreBatch는
    /// migration 소유자 또는 preservation(소스) 소유자 세대와 일치할 때만 관련이다.
    private func identityReplacementTrigger(
        _ action: Action,
        transition: FileManagerContentState.EntryIdentityTransition,
    ) -> IdentityReplacementTrigger? {
        switch action {
        case .entryViewLayout(.view(.applyContentProjection)):
            return .migration
        case .entryViewLayout(.hierarchy(.rootSnapshotCompleted)):
            if case .folder = transition.projectionOwner { return .migration }
            return nil
        case let .entryViewLayout(.hierarchy(.folderChildrenResponse(
            _,
            folderID,
            folderGeneration,
            .event(.coreBatch),
        ))):
            if case let .folder(expectedID, expectedGeneration) = transition.projectionOwner,
               canonicalizedPath(folderID) == canonicalizedPath(expectedID),
               folderGeneration == expectedGeneration
            {
                return .migration
            }
            if let preservationOwner = transition.preservationOwner,
               case let .folder(preservedID, preservedGeneration) = preservationOwner,
               canonicalizedPath(folderID) == canonicalizedPath(preservedID),
               folderGeneration == preservedGeneration
            {
                return .preservation
            }
            return nil
        default:
            return nil
        }
    }

    /// 소유자별 현재 투영 경로 집합. after-path 부재가 reconcile 삭제를 유발하는지 판정한다.
    private func replacementProjectionPaths(
        owner: FileManagerContentState.EntryIdentityTransitionProjectionOwner,
        state: State,
    ) -> Set<String> {
        switch owner {
        case .root:
            Set(state.entryViewLayout.entryOperations.loadingContext.items.map { canonicalizedPath($0.id) })
        case let .folder(id, _):
            Set(state.entryViewLayout.hierarchy.nodesByID[id]?.folder.children.map {
                canonicalizedPath($0.id)
            } ?? [])
        }
    }

    private enum IdentityReplacementTrigger {
        case migration
        case preservation
    }

    private func rebaseFolderIdentityTransitionOwnersAfterRootSnapshot(
        on action: Action,
        state: inout State,
    ) {
        guard case .entryViewLayout(.hierarchy(.rootSnapshotCompleted)) = action,
              var transition = state.pendingIdentityTransition
        else { return }

        func rebasedOwner(
            _ owner: FileManagerContentState.EntryIdentityTransitionProjectionOwner,
        ) -> FileManagerContentState.EntryIdentityTransitionProjectionOwner {
            guard case let .folder(id, generation) = owner,
                  let currentGeneration = state.entryViewLayout.hierarchy.nodesByID[id]?.generation,
                  currentGeneration == generation &+ 1
            else { return owner }
            return .folder(id: id, generation: currentGeneration)
        }

        transition.projectionOwner = rebasedOwner(transition.projectionOwner)
        if let preservationOwner = transition.preservationOwner {
            transition.preservationOwner = rebasedOwner(preservationOwner)
        }
        state.pendingIdentityTransition = transition
    }

    private func resolveFolderIdentityTransition(
        on action: Action,
        state: inout State,
    ) {
        guard let transition = state.pendingIdentityTransition,
              case let .folder(expectedID, expectedGeneration) = transition.projectionOwner
        else { return }
        guard FileManagerContentEntryOpsCoordinator.identityTransitionOwnerIsCurrent(
            transition.projectionOwner,
            state: state,
        ) else {
            state.pendingIdentityTransition = nil
            return
        }
        guard case let .entryViewLayout(.hierarchy(.folderChildrenResponse(
            _,
            folderID,
            folderGeneration,
            response,
        ))) = action,
            canonicalizedPath(folderID) == canonicalizedPath(expectedID)
        else { return }
        guard folderGeneration == expectedGeneration else { return }
        switch response {
        case .failed, .streamCompleted, .event(.coreFinished):
            state.pendingIdentityTransition = nil
        case .event(.coreBatch), .event(.metadataPatches):
            break
        }
    }

    private func visibleEntryPaths(in state: State) -> Set<String> {
        let flatPaths = state.entryViewLayout.entries.map(\.id).map(canonicalizedPath)
        let hierarchyPaths = state.entryViewLayout.hierarchy.nodesByID.values
            .flatMap(\.folder.children)
            .map(\.id)
            .map(canonicalizedPath)
        return Set(flatPaths + hierarchyPaths)
    }

    /// loadItems 시작이 현재 표시 중인 완전 projection과 같은 root의 재로드인지 판정한다.
    /// 표시 항목이 모두 대상 경로의 직속 하위일 때만 유지한다(다른 폴더 이동과 구분).
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

    /// 실제 네비게이션·root 변경 시 대기 중인 identity 전이를 만료한다.
    /// 같은 root로의 재적용은 유지하고, 다른 root 또는 비폴더 라우트로 이동하면
    /// 만료해 stale 전이가 선택을 되살리거나 잘못 옮기지 않게 한다.
    private func expireTransitionOnNavigation(_ navigationState: ContentPageNavigationRoute, state: inout State) {
        guard let transition = state.pendingIdentityTransition else { return }
        switch navigationState {
        case let .folder(newPath):
            if canonicalizedPath(newPath) != transition.rootPath {
                state.pendingIdentityTransition = nil
            }
        default:
            state.pendingIdentityTransition = nil
        }
    }

    // MARK: - Projection Bridge

    static func shouldProjectContent(_ action: Action) -> Bool {
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
             .internal(.clearCollectionMode),
             .internal(.exitCollectionMode):
            true
        default:
            false
        }
    }

    static func isRootCompletion(_ action: Action, state: inout State) -> Bool {
        switch action {
        case .entryViewLayout(.entryOperations(.loading(.itemsLoaded))):
            return true
        case let .entryViewLayout(.entryOperations(.loading(.streamEvent(streamEvent)))):
            guard case .coreFinished = streamEvent.event,
                  state.entryViewLayout.entryOperations.loadingContext.acceptedCoreFinishedGeneration == streamEvent
                  .generation
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
