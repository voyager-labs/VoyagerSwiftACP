import ComposableArchitecture

extension FileManagerContentFeature {
    func handleCollectionOwnerAction(
        _ action: Action,
        state: inout State,
    ) -> Effect<Action>? {
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

        case .collection(.navigationStateApplied),
             .collection(.openSearchPresentationCancelled),
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
