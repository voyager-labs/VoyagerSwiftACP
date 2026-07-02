import AppKit
import ComposableArchitecture
import Foundation
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
