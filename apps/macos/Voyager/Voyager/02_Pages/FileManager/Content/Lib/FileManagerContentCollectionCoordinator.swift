import ComposableArchitecture
import VoyagerEntitiesCollection

enum FileManagerContentCollectionCoordinator {
    static func handleCollectionOwnerAction(
        _ action: FileManagerContentAction,
        state: inout FileManagerContentState,
    ) -> Effect<FileManagerContentAction>? {
        switch action {
        case let .collection(.saveCompleted(.success(completion))):
            return .send(.collection(.writeBackCompleted(completion)))

        case let .collection(.delegate(.draftRestorePrepared(payload))):
            state.syncComposerCollectionState()
            state.composer.applyCollectionDraftRestorePayload(payload)
            return .none

        case let .collection(.delegate(.writeBackNavigationPrepared(payload))):
            return handleCollectionWriteBackPrepared(
                payload: payload,
                state: &state,
            )

        case let .collection(.delegate(delegateAction)):
            return FileManagerContentComposerCoordinator.handleCollectionDelegate(
                delegateAction,
                state: &state,
            )

        case .collection(.saveCompleted(.failure)):
            return handleCollectionSaveFailure(state: &state)

        case let .collection(.navigationStateApplied(payload)):
            state.composer.applyCollectionNavigationComposerPayload(payload)
            state.syncComposerCollectionState()
            return .none

        case .collection(.openSearchPresentationCancelled),
             .collection(.temporaryContextResetRequested):
            state.syncComposerCollectionState()
            return .none

        case .collection:
            return .none

        default:
            return nil
        }
    }
}
