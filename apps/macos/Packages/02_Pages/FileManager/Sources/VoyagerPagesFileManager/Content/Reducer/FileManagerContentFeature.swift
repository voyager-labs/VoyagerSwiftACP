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

        Scope(state: \.entryViewLayout, action: \.entryViewLayout) {
            EntryViewLayoutFeature()
        }

        Scope(state: \.aiChat, action: \.aiChat) {
            AiChatFeature()
        }

        FileManagerContentPendingSelectionReducer(phase: .afterEntryViewLayout)

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
            let projectionEntries = useCollectionItems
                ? Array(state.entryViewLayout.collectionItems)
                : Array(state.entryViewLayout.entryOperations.items)
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
