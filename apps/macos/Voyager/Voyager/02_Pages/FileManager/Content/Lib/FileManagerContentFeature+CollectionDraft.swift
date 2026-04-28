import ComposableArchitecture
import Foundation

extension FileManagerContentFeature {
    func handleCollectionDraftAction(
        _ action: Action,
        state: inout State,
    ) -> Effect<Action>? {
        switch action {
        case .delegate(.discardCollectionChanges):
            guard state.isCollectionMode,
                  state.isOpenedCollectionDirty
            else {
                return .none
            }
            return .send(.collection(.draftDiscardRequested))
        default:
            return nil
        }
    }
}
