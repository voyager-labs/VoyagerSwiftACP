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
            case let .entryOperations(.lifecycle(.windowIDChanged(windowID))):
                state.composer.cancellationOwnerID = windowID
                return .none
            case let .entryOperations(.lifecycle(.resetForDuplicate(windowID))):
                state.composer.cancellationOwnerID = windowID
                return .none
            case let .entryArrangements(.setSortKey(key)):
                guard state.entryArrangements.sortKey != key else { return .none }
                return arrangementMetadataReloadEffect(
                    priority: FileManagerContentEntryOpsCoordinator.rootMetadataPriority(
                        sortKey: key,
                        groupKey: state.entryArrangements.groupKey,
                    ),
                    state: state,
                )
            case let .entryArrangements(.setGroupKey(key)):
                guard state.entryArrangements.groupKey != key else { return .none }
                return arrangementMetadataReloadEffect(
                    priority: FileManagerContentEntryOpsCoordinator.rootMetadataPriority(
                        sortKey: state.entryArrangements.sortKey,
                        groupKey: key,
                    ),
                    state: state,
                )
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
            handlePendingSelectionBeforeEntryLayoutLoaded(action, state: &state)
        }

        Scope(state: \.entryViewLayout, action: \.entryViewLayout) {
            EntryViewLayoutFeature()
        }

        Scope(state: \.entryOperations, action: \.entryOperations) {
            EntryOperationsFeature()
        }

        Scope(state: \.entryArrangements, action: \.entryArrangements) {
            EntryArrangementsFeature()
        }

        Scope(state: \.entryThumbnail, action: \.entryThumbnail) {
            EntryThumbnailFeature()
        }

        Scope(state: \.aiChat, action: \.aiChat) {
            AiChatFeature()
        }

        Reduce { state, action in
            handlePendingSelectionAfterEntryLayoutLoaded(action, state: &state)
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
            let projectionEntries = useCollectionItems
                ? Array(state.entryViewLayout.collectionItems)
                : Array(state.entryOperations.items)
            _ = EntryArrangementsFeature().reduce(
                into: &state.entryArrangements,
                action: .apply(items: projectionEntries, isCollectionMode: useCollectionItems),
            )
            var seenEntryIDs = Set<EntryModel.ID>()
            let arrangedEntries = state.entryArrangements.groupedItems
                .flatMap(\.items)
                .filter { seenEntryIDs.insert($0.id).inserted }
            let projectionSections = FileManagerContentFeature.makeSections(
                groupedItems: state.entryArrangements.groupedItems,
                collapsedGroups: state.entryArrangements.collapsedGroups,
            )
            let projection = ContentProjection(
                entries: arrangedEntries,
                isLoading: state.entryOperations.isLoading,
                sortKey: .fromShared(state.entryArrangements.sortKey),
                sortOrder: state.entryArrangements.sortOrder,
                groupKey: .fromShared(state.entryArrangements.groupKey.rawValue),
                collapsedGroups: state.entryArrangements.collapsedGroups,
                sections: projectionSections,
                renamingItemId: state.entryOperations.renamingItemId,
                renamingText: state.entryOperations.renamingText,
                clipboardCutPaths: state.entryOperations.clipboardOperation == .cut
                    ? Set(state.entryOperations.clipboardItems)
                    : [],
                hasClipboardItems: !state.entryOperations.clipboardItems.isEmpty,
                busyEntryPaths: Set(state.entryOperations.itemStates.filter(\.value.isBusy).map(\.key)),
                openWithApplications: state.entryOperations.commonApplicationsForSelectedFiles,
                restorableTrashPaths: state.entryOperations.restorableTrashPaths,
                trashDirectoryPath: entryOpenClient.trashDirectoryPath(),
                collectionWindowID: state.entryOperations.windowID,
                collectionLoadingCancellationOwnerID: state.entryOperations.loadingCancellationOwnerID,
            )
            return .send(.entryViewLayout(.view(.applyContentProjection(projection))))
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

            case .entryArrangements(.delegate(.requestApply)):
                let items = Array(state.entryOperations.items)
                let isCollectionMode = state.entryViewLayout.isCollectionMode
                return .send(.entryArrangements(.apply(items: items, isCollectionMode: isCollectionMode)))

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
        guard case let .entryOperations(.loading(.streamEvent(streamEvent))) = action,
              case let .coreBatch(items: entries, batchIndex: batchIndex) = streamEvent.event,
              streamEvent.generation == state.entryOperations.loadingContext.generation,
              batchIndex == state.entryOperations.loadingContext.expectedCoreBatchIndex
        else {
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

    private func handlePendingSelectionAfterEntryLayoutLoaded(
        _ action: Action,
        state: inout State,
    ) -> Effect<Action> {
        let entries: [EntryModel]
        switch action {
        case let .entryOperations(.loading(.itemsLoaded(loadedEntries))):
            entries = loadedEntries
        case let .entryOperations(.loading(.streamEvent(streamEvent))):
            guard case .coreBatch = streamEvent.event else { return .none }
            entries = Array(state.entryOperations.loadingContext.items)
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

    // MARK: - Projection Bridge

    static func shouldProjectContent(_ action: Action) -> Bool {
        switch action {
        case .entryOperations(.loading(.cancelAndClearItems)),
             .entryOperations(.loading(.itemsLoaded)),
             .entryOperations(.loading(.streamEvent)),
             .entryOperations(.loading(.streamFinished)),
             .entryOperations(.loading(.streamFailed)),
             .entryOperations(.loading(.itemsLoadFailed)),
             .entryOperations(.lifecycle(.operationStarted)),
             .entryOperations(.lifecycle(.operationFinished)),
             .entryOperations(.lifecycle(.entryActionCompleted)),
             .entryOperations(.lifecycle(.emptyTrashCompleted)),
             .entryOperations(.edit(.commitRename)),
             .entryOperations(.edit(.startRename)),
             .entryOperations(.edit(.cancelRename)),
             .entryOperations(.openWith(.commonApplicationsLoaded)),
             .entryOperations(.lifecycle(.syncClipboardState)),
             .entryOperations(.lifecycle(.restorableTrashPathsLoaded)),
             .entryOperations(.lifecycle(.pathsMutated)),
             .entryOperations(.clipboard(.copySelectedItems)),
             .entryOperations(.clipboard(.setClipboardOperation)),
             .entryArrangements(.delegate(.applied)),
             .entryArrangements(.toggleCollapsedGroup),
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
