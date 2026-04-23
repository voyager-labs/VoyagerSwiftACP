import ComposableArchitecture
import Foundation

extension FileManagerContentFeature {
    func handleCollectionDraftAction(
        _ action: Action,
        state: inout State,
    ) -> Effect<Action>? {
        switch action {
        case .delegate(.discardCollectionChanges):
            var sessionState = state.collectionSession
            guard let payload = CollectionDocumentSessionFeature.restoreDraftPayload(
                state: &sessionState,
                baseline: state.collectionSession.baseline,
                isCollectionMode: state.isCollectionMode,
                isDirty: state.isOpenedCollectionDirty,
            ) else {
                state.collectionSession = sessionState
                return .none
            }

            state.collectionContext = payload.context
            state.syncComposerCollectionState()
            state.composer.applyCollectionDraftRestorePayload(payload)
            state.collectionSession = sessionState
            return .none
        default:
            return nil
        }
    }
}
