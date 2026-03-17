import ComposableArchitecture
import Foundation

extension FileManagerContentState {
    mutating func restoreCollectionDraftFromBaseline() -> Effect<FileManagerContentAction> {
        guard let baseline = collectionSession.baseline,
              entryViewLayout.entryOperations.loadingContext.isCollectionMode,
              isOpenedCollectionDirty
        else {
            return .none
        }

        let trimmedQuery = baseline.context.query.trimmingCharacters(in: .whitespacesAndNewlines)
        composer.pendingSearchQuery = trimmedQuery.isEmpty ? nil : trimmedQuery
        collectionContext = baseline.context
        syncComposerCollectionState()

        if collectionSession.openedURL == nil {
            composer.text = baseline.context.query
        } else {
            composer.text = ""
        }
        composer.scopes = baseline.context.scopes
        composer.conditions = baseline.context.conditions
        composer.propertyPicker = ConditionPropertyPickerFeature.State()
        composer.operatorPicker = OperatorPickerFeature.State()
        composer.valuePicker = ValuePickerFeature.State()
        composer.clearHistory()

        return .none
    }
}
