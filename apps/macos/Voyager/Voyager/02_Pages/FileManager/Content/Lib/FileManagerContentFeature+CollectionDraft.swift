import ComposableArchitecture
import Foundation

extension FileManagerContentFeature {
    func handleCollectionDraftAction(
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
