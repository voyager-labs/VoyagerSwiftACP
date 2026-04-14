import ComposableArchitecture
import Foundation
import VoyagerShared

import VoyagerFeaturesEntryOperations
import VoyagerWidgetsEntryViewLayout

@Reducer
public struct FileManagerContentComposerReducer {
    public typealias State = FileManagerContentState
    public typealias Action = FileManagerContentAction

    @Dependency(\.collectionAlertClient)
    private var collectionAlertClient
    @Dependency(\.fileManagerClient)
    private var fileManagerClient

    public init() {}

    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            if let effect = handleComposerAction(action, state: &state) {
                return effect
            }

            if let effect = handleCollectionDraftAction(action, state: &state) {
                return effect
            }

            switch action {
            case .internal(.syncComposerCollectionState):
                state.syncComposerCollectionState()
                return .none

            default:
                return .none
            }
        }
    }

    private func handleComposerAction(
        _ action: Action,
        state: inout State,
    ) -> Effect<Action>? {
        guard case let .composer(composerAction) = action else {
            return nil
        }

        return FileManagerContentComposerCoordinator.reduce(
            composerAction,
            state: &state,
            dependencies: .init(
                collectionAlertClient: collectionAlertClient,
                computerName: fileManagerClient.displayName("/"),
            ),
        )
    }

    private func handleCollectionDraftAction(
        _ action: Action,
        state: inout State,
    ) -> Effect<Action>? {
        switch action {
        case .delegate(.discardCollectionChanges):
            guard let baseline = state.collectionSession.baseline,
                  state.isCollectionMode,
                  state.isOpenedCollectionDirty
            else {
                return .none
            }

            let trimmedQuery = baseline.context.query.trimmingCharacters(in: .whitespacesAndNewlines)
            state.composer.pendingSearchQuery = trimmedQuery.isEmpty ? nil : trimmedQuery
            state.collectionContext = baseline.context
            state.syncComposerCollectionState()

            if state.collectionSession.openedURL == nil {
                state.composer.text = baseline.context.query
            } else {
                state.composer.text = ""
            }
            state.composer.scopes = baseline.context.scopes
            state.composer.conditions = baseline.context.conditions
            state.composer.propertyPicker = ConditionPropertyPickerFeature.State()
            state.composer.operatorPicker = OperatorPickerFeature.State()
            state.composer.valuePicker = ValuePickerFeature.State()
            state.composer.clearHistory()
            return .none

        default:
            return nil
        }
    }
}
