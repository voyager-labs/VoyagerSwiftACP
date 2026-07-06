import AppKit
import ComposableArchitecture
import Foundation
import VoyagerEntitiesCollection
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
            guard case let .collection(.saveCompleted(result)) = action else {
                return .none
            }
            return handleCollectionSaveCompleted(result: result, state: &state)
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

        Reduce { state, action in
            handlePendingSelectionAfterEntryLayoutLoaded(action, state: &state)
        }

        FileManagerContentComposerReducer()

        FileManagerContentNavigationBridgeReducer()

        FileManagerContentEntryOperationsBridgeReducer()

        FileManagerContentKeyCommandReducer()

        FileManagerContentSyncReducer()

        Reduce { state, action in
            if let effect = handleCollectionOwnerAction(action, state: &state) {
                return effect
            }

            switch action {
            case .view(.openContextualAiChatTapped):
                return .send(.delegate(.openContextualAiChat))

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

    private func handlePendingSelectionAfterEntryLayoutLoaded(
        _ action: Action,
        state: inout State,
    ) -> Effect<Action> {
        guard case let .entryViewLayout(.entryOperations(.loading(.itemsLoaded(entries)))) = action else {
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
