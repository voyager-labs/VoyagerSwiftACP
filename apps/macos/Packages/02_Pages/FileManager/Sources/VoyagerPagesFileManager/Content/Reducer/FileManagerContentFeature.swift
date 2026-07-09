import AppKit
import ComposableArchitecture
import Foundation
import VoyagerEntitiesAi
import VoyagerEntitiesCollection
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

            case .view(.openContextualAiChatTapped):
                return .send(.delegate(.openContextualAiChat))

            case .aiChat(.delegate(.openAISettings)):
                return .send(.delegate(.openAISettings))

            case let .aiChat(.newChatCreated(snapshot)):
                return .send(.delegate(.aiChatSessionCreated(snapshot.sessionID)))

            case let .aiChat(.restoreOutcome(requestedSessionID, _, restoreFailure)):
                guard restoreFailure == nil,
                      state.aiChat.mode == .chat,
                      state.aiChat.sessionID == requestedSessionID,
                      case .aiChatSessions = state.navigation.navigationState
                else { return .none }
                return .send(.delegate(.aiChatSessionRestored(requestedSessionID)))

            case let .aiChat(.sessionRowTapped(sessionID)):
                guard state.aiChat.executionPhase.isProcessing,
                      state.aiChat.mode == .chat,
                      state.aiChat.sessionID == sessionID,
                      case .aiChatSessions = state.navigation.navigationState
                else { return .none }
                return .send(.delegate(.aiChatSessionRestored(sessionID)))

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
