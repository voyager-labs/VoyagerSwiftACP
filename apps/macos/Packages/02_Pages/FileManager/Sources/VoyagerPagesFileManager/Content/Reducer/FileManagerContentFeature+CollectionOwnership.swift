import ComposableArchitecture
import Foundation
import VoyagerEntitiesCollection
import VoyagerFeaturesComposer
import VoyagerFeaturesContentPageNavigation
import VoyagerFeaturesEntryArrangements
import VoyagerShared

extension FileManagerContentFeature {
    func handleCollectionModeAction(
        _ action: Action,
        state: inout State,
        computerName: String,
    ) -> Effect<Action> {
        switch action {
        case .internal(.clearCollectionMode):
            return clearCollectionModeEffect()

        case .internal(.exitCollectionMode):
            let wasCollection = if case .collection = state.navigation.navigationState { true } else { false }
            let clearEffect = clearCollectionModeEffect()
            guard wasCollection else {
                return clearEffect
            }
            let navigationState = ContentPageNavigationRoute.fromPath(
                state.navigation.titlePath,
                computerName: computerName,
            )
            return .concatenate(
                .send(.internal(.requestNavigation(.internal(.setNavigationState(navigationState))))),
                clearEffect,
            )

        default:
            return .none
        }
    }

    func handleCollectionOwnerAction(
        _ action: Action,
        state: inout State,
    ) -> Effect<Action>? {
        switch action {
        case .view(.discardCollectionChanges):
            handleDiscardCollectionChanges(state: state)

        case let .collection(.delegate(.draftRestorePrepared(payload))):
            .concatenate(
                .send(.composer(.applyCollectionDraftRestore(payload))),
                syncComposerCollectionStateEffect(state),
            )

        case let .collection(.delegate(.writeBackNavigationPrepared(payload))):
            handleCollectionWriteBackPrepared(payload: payload, state: &state)

        case let .collection(.delegate(.saveFeedback(payload))):
            handleCollectionSaveFeedback(payload: payload, state: &state)

        case let .collection(.delegate(delegateAction)):
            handleCollectionDelegateAction(delegateAction, state: &state)

        case .collection(.navigationStateApplied):
            .none

        case .collection(.openSearchPresentationCancelled),
             .collection(.temporaryContextResetRequested):
            syncComposerCollectionStateEffect(state)

        case .collection(.sessionResetRequested):
            handleCollectionSessionReset(state: state)

        case .collection:
            .none

        default:
            nil
        }
    }

    func clearCollectionModeEffect() -> Effect<Action> {
        .concatenate(
            .send(.composer(.clearPendingSearchQuery)),
            .send(.entryViewLayout(.internal(.clearCollectionPresentation))),
            .send(.collection(.sessionResetRequested)),
            .send(.internal(.requestNavigation(.internal(.setPendingNavigation(nil))))),
            .cancel(id: "openCollectionFile"),
            .cancel(id: ComposerFeature.CancelID.search),
            .cancel(id: ComposerFeature.CancelID.filters),
        )
    }

    // MARK: - Private

    func handleCollectionSaveCompleted(
        result: Result<CollectionSaveCompletion, Error>,
        state: inout State,
    ) -> Effect<Action> {
        switch result {
        case let .success(completion):
            return .send(.collection(.writeBackCompleted(completion)))
        case .failure:
            if state.collection.collectionSession.phase.isInflightWriteBack {
                return .concatenate(
                    .send(.collection(.writeBackFailed)),
                    .send(.internal(.requestNavigation(.internal(.setPendingNavigation(nil))))),
                )
            }
            return .send(.internal(.requestNavigation(.internal(.setPendingNavigation(nil)))))
        }
    }

    private func handleDiscardCollectionChanges(state: State) -> Effect<Action> {
        guard state.isCollectionMode,
              state.isOpenedCollectionDirty
        else {
            return .none
        }
        return .concatenate(
            .send(.collection(.draftDiscardRequested)),
            .send(.delegate(.collectionChangesDiscarded)),
        )
    }

    private func handleCollectionSessionReset(state: State) -> Effect<Action> {
        resetComposerAndSyncEffect(state)
    }

    func resetComposerAndSyncEffect(_ state: State) -> Effect<Action> {
        .send(.composer(.resetComposerAndSync(
            context: state.collection.collectionContext,
            url: state.collection.collectionSession.document?.url,
            compatibility: state.collection.collectionSession.document?.compatibility,
            isCollectionMode: state.isCollectionMode,
        )))
    }

    private func handleCollectionDelegateAction(
        _ delegateAction: CollectionAction.Delegate,
        state: inout State,
    ) -> Effect<Action>? {
        switch delegateAction {
        case .draftRestorePrepared:
            .none

        case let .searchResultPrepared(payload):
            handleCollectionSearchResultPrepared(payload: payload, state: &state)

        case .writeBackNavigationPrepared:
            .none
        case .saveFeedback:
            .none
        }
    }

    private func handleCollectionSaveFeedback(
        payload: CollectionSaveFeedback,
        state: inout State,
    ) -> Effect<Action> {
        let feedback = ComposerTransientFeedback(
            id: UUID(),
            kind: .error,
            message: "\(payload.title)\n\(payload.message)",
            stage: .save,
            category: payload.stage == .saveBlocked ? .saveBlocked : .saveFailed,
            recoveryHint: payload.recoveryHint,
        )
        state.composer.transientFeedback = feedback
        return .concatenate(
            .cancel(id: ComposerFeature.CancelID.feedbackDismiss),
            .run { [feedbackID = feedback.id] send in
                try await Task.sleep(for: .seconds(4))
                await send(.composer(.dismissTransientFeedback(id: feedbackID)))
            }
            .cancellable(id: ComposerFeature.CancelID.feedbackDismiss, cancelInFlight: true),
        )
    }

    private func handleCollectionSearchResultPrepared(
        payload: CollectionSearchResultPayload,
        state: inout State,
    ) -> Effect<Action> {
        let previousSnapshot = state.navigation.makeContentPageNavigationHistorySnapshot()
        let nextNavigationState = ContentPageNavigationRoute.collection(
            ContentPageCollectionNavigationFactory.makeCollectionNavigation(
                payload.navigation,
                sortKey: state.entryViewLayout.entryArrangements.sortKey,
                sortOrder: state.entryViewLayout.entryArrangements.sortOrder,
                viewLayout: state.entryViewLayout.mode,
            ),
        )
        var navigationEffects: [Effect<Action>] = []
        if payload.shouldAppendHistory {
            navigationEffects
                .append(.send(.internal(.requestNavigation(.internal(.appendBackHistory(previousSnapshot))))))
            navigationEffects.append(.send(.internal(.requestNavigation(.internal(.clearForwardHistory)))))
        }
        navigationEffects
            .append(.send(.internal(.requestNavigation(.internal(.setNavigationState(nextNavigationState))))))
        if payload.shouldLogDAU {
            logContentPageNavigationDAUIfNeeded(
                previous: state.navigation.navigationState,
                next: nextNavigationState,
            )
        }
        return .concatenate(
            .concatenate(navigationEffects),
            syncComposerCollectionStateEffect(state),
            .send(.composer(.searchListApplied)),
        )
    }

    private func handleCollectionWriteBackPrepared(
        payload: CollectionWriteBackNavigationPayload,
        state: inout State,
    ) -> Effect<Action> {
        let previousSnapshot = state.navigation.makeContentPageNavigationHistorySnapshot()
        let nextNavigationState = ContentPageNavigationRoute.collection(
            ContentPageCollectionNavigationFactory.makeCollectionNavigation(
                payload.nextNavigation,
                sortKey: state.entryViewLayout.entryArrangements.sortKey,
                sortOrder: state.entryViewLayout.entryArrangements.sortOrder,
                viewLayout: state.entryViewLayout.mode,
            ),
        )

        var navigationEffects: [Effect<Action>] = [
            .send(.internal(.requestNavigation(.internal(.setNavigationState(nextNavigationState))))),
        ]

        if payload.shouldAppendHistory {
            if let historyNavigation = payload.previousHistoryNavigation {
                let historyEntry = ContentPageNavigationHistorySnapshot(
                    navigationState: .collection(
                        ContentPageCollectionNavigationFactory.makeCollectionNavigation(
                            historyNavigation,
                            sortKey: state.entryViewLayout.entryArrangements.sortKey,
                            sortOrder: state.entryViewLayout.entryArrangements.sortOrder,
                            viewLayout: state.entryViewLayout.mode,
                        ),
                    ),
                )
                navigationEffects
                    .append(.send(.internal(.requestNavigation(.internal(.appendBackHistory(historyEntry))))))
            } else {
                navigationEffects
                    .append(.send(.internal(.requestNavigation(.internal(.appendBackHistory(previousSnapshot))))))
            }
            navigationEffects.append(.send(.internal(.requestNavigation(.internal(.clearForwardHistory)))))
        }

        if let pending = state.navigation.pendingNavigation {
            return .concatenate(
                .concatenate(navigationEffects),
                syncComposerCollectionStateEffect(state),
                .send(.internal(.requestNavigation(.internal(.setPendingNavigation(nil))))),
                .send(.internal(.performPendingNavigation(pending))),
            )
        }

        return .concatenate(
            .concatenate(navigationEffects),
            syncComposerCollectionStateEffect(state),
        )
    }

    func syncComposerCollectionStateEffect(_ state: State) -> Effect<Action> {
        .send(.composer(.syncCollectionState(
            context: state.collection.collectionContext,
            url: state.collection.collectionSession.document?.url,
            compatibility: state.collection.collectionSession.document?.compatibility,
            isCollectionMode: state.isCollectionMode,
        )))
    }
}
