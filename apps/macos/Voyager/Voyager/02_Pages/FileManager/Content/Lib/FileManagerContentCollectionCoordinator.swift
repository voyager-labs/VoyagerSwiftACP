import ComposableArchitecture

enum FileManagerContentCollectionCoordinator {
    static func handleCollectionOwnerAction(
        _ action: FileManagerContentAction,
        state: inout FileManagerContentState,
    ) -> Effect<FileManagerContentAction>? {
        guard case let .collection(collectionAction) = action else {
            return nil
        }
        return handleCollectionAction(collectionAction, state: &state)
    }

    private static func handleCollectionAction(
        _ action: CollectionAction,
        state: inout FileManagerContentState,
    ) -> Effect<FileManagerContentAction> {
        switch action {
        case let .saveCompleted(.success(completion)):
            return .send(.collection(.writeBackCompleted(completion)))

        case let .delegate(.draftRestorePrepared(payload)):
            state.syncComposerCollectionState()
            state.composer.applyCollectionDraftRestorePayload(payload)
            return .none

        case let .delegate(.writeBackNavigationPrepared(payload)):
            return handleCollectionWriteBackPrepared(
                payload: payload,
                state: &state,
            )

        case let .delegate(delegateAction):
            return FileManagerContentComposerCoordinator.handleCollectionDelegate(
                delegateAction,
                state: &state,
            )

        case .saveCompleted(.failure):
            return handleCollectionSaveFailure(state: &state)

        case let .navigationStateApplied(payload):
            state.composer.applyCollectionNavigationComposerPayload(payload)
            state.syncComposerCollectionState()
            return .none

        case .openSearchPresentationCancelled:
            guard !state.composer.isFilteringInFlight else {
                return .none
            }
            state.syncComposerCollectionState()
            return .none

        case .temporaryContextResetRequested:
            state.syncComposerCollectionState()
            return .none

        default:
            return .none
        }
    }
}
