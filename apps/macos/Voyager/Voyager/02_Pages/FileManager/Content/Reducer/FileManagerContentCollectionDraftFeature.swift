import ComposableArchitecture
import Foundation

@Reducer
struct FileManagerContentCollectionDraftFeature {
    typealias State = FileManagerContentState
    typealias Action = FileManagerContentAction

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            guard case .discardCollectionChanges = action else {
                return .none
            }

            return restoreCollectionDraft(state: &state)
        }
    }

    private func restoreCollectionDraft(state: inout State) -> Effect<Action> {
        guard let baseline = state.collectionSession.baseline,
              state.entryOperations.loadingContext.isCollectionMode,
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
    }
}
