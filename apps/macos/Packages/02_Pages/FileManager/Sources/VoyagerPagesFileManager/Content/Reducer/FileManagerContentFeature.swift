import AppKit
import ComposableArchitecture
import Foundation
import VoyagerEntitiesAi
import VoyagerEntitiesCollection
import VoyagerEntitiesEntry
import VoyagerFeaturesAiChat
import VoyagerFeaturesComposer
import VoyagerFeaturesContentPageNavigation
import VoyagerFeaturesEntryOperations
import VoyagerShared
import VoyagerWidgetsEntryViewLayout

@Reducer
public struct FileManagerContentFeature {
    public typealias State = FileManagerContentState
    public typealias Action = FileManagerContentAction

    @Dependency(\.fileManagerClient)
    private var fileManagerClient

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

        Scope(state: \.entryViewLayout, action: \.entryViewLayout) {
            EntryViewLayoutFeature()
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
        let rootReloadEffect: Effect<Action> = if state.entryViewLayout.isCollectionMode {
            .send(.entryViewLayout(.internal(.applyCollectionSearchPaths(
                paths: state.entryViewLayout.collectionItems.map(\.id),
                showHidden: state.entryViewLayout.showHiddenFiles,
            ))))
        } else {
            FileManagerContentEntryOpsCoordinator.reloadEntryItemsEffect(
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
