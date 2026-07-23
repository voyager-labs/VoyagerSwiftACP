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
            return clearCollectionModeEffect(state: state)

        case .internal(.exitCollectionMode):
            let wasCollection = if case .collection = state.navigation.navigationState { true } else { false }
            let clearEffect = clearCollectionModeEffect(state: state)
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
            handleDiscardCollectionChanges(state: &state)

        case let .collection(.delegate(.draftRestorePrepared(payload))):
            .concatenate(
                .send(.composer(.applyCollectionDraftRestore(payload))),
                syncComposerCollectionStateEffect(state),
                restoredCollectionSearchEffect(payload: payload),
            )

        case let .collection(.delegate(.writeBackNavigationPrepared(payload))):
            handleCollectionWriteBackPrepared(payload: payload, state: &state)

        case let .collection(.delegate(.saveFeedback(payload))):
            handleCollectionSaveFeedback(payload: payload, state: &state)

        case let .collection(.delegate(delegateAction)):
            handleCollectionDelegateAction(delegateAction, state: &state)

        case .collection(.navigationStateApplied):
            .none

        case .collection(.refreshFailed):
            handleCollectionRefreshFailed(state: &state)

        case .collection(.writeBackFailed):
            handleCollectionWriteBackFailed(state: &state)

        case let .collection(.refreshResponseReceived(_, wasDirtyBeforeApplyingResponse)):
            handleCollectionRefreshResponse(
                wasDirtyBeforeApplyingResponse: wasDirtyBeforeApplyingResponse,
                state: &state,
            )

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

    func clearCollectionModeEffect(state: State) -> Effect<Action> {
        .concatenate(
            .send(.composer(.clearPendingSearchQuery)),
            .send(.entryViewLayout(.internal(.clearCollectionPresentation))),
            .send(.collection(.sessionResetRequested)),
            .send(.internal(.requestNavigation(.internal(.setPendingNavigation(nil))))),
            .cancel(id: OpenCollectionFileCancelID(windowID: state.entryOperations.windowID)),
            .cancel(id: ComposerFeature.CancelID.search(ownerID: state.composer.cancellationOwnerID)),
            .cancel(id: ComposerFeature.CancelID.filters(ownerID: state.composer.cancellationOwnerID)),
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

    private func handleDiscardCollectionChanges(state: inout State) -> Effect<Action> {
        guard state.isCollectionMode,
              state.isOpenedCollectionDirty
        else {
            return .none
        }

        state.suppressAutomaticRefreshFeedback = true
        state.composer.transientFeedback = nil

        return .concatenate(
            .cancel(id: ComposerFeature.CancelID.feedbackDismiss),
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

    private func restoredCollectionSearchEffect(payload: CollectionDraftRestorePayload) -> Effect<Action> {
        let query = payload.context.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return .send(.composer(.view(.applyFilters)))
        }
        return .concatenate(
            .send(.composer(.view(.setText(query)))),
            .send(.composer(.view(.submit))),
        )
    }

    private func handleCollectionRefreshFailed(state: inout State) -> Effect<Action> {
        if state.suppressAutomaticRefreshFeedback {
            state.suppressAutomaticRefreshFeedback = false
            return .none
        }
        guard state.composer.transientFeedback == nil else {
            return .none
        }
        return presentCollectionRefreshFeedback(
            kind: .error,
            message: "Refresh failed. Try again.",
            recoveryHint: "The collection is still stale until refresh succeeds.",
            stage: .queryExecution,
            category: .executionFailure,
            state: &state,
        )
    }

    private func handleCollectionWriteBackFailed(state: inout State) -> Effect<Action> {
        if state.suppressAutomaticRefreshFeedback {
            state.suppressAutomaticRefreshFeedback = false
            return .none
        }
        return presentCollectionRefreshFeedback(
            kind: .error,
            message: "Could not save refreshed collection snapshot.",
            recoveryHint: "The latest results may be visible, but this collection will stay stale until saving succeeds.",
            stage: .save,
            category: .saveFailed,
            state: &state,
        )
    }

    private func handleCollectionRefreshResponse(
        wasDirtyBeforeApplyingResponse: Bool,
        state: inout State,
    ) -> Effect<Action> {
        let shouldSuppressFeedback = state.suppressAutomaticRefreshFeedback
        let compatibility = state.collection.collectionSession.document?.compatibility
        let writeBackAllowed = compatibility?.writeBackAllowed != false
        let shouldWaitForWriteBack = shouldSuppressFeedback && !wasDirtyBeforeApplyingResponse && writeBackAllowed
        if shouldWaitForWriteBack {
            return .none
        }

        state.suppressAutomaticRefreshFeedback = false
        guard !shouldSuppressFeedback,
              !wasDirtyBeforeApplyingResponse,
              !writeBackAllowed,
              let writeBackReason = compatibility?.writeBackReason,
              writeBackReason != .allowed
        else {
            return .none
        }
        return presentCollectionRefreshFeedback(
            kind: .info,
            message: compatibilityBlockedRefreshMessage(
                reason: writeBackReason,
            ),
            recoveryHint: "Save as a new collection to keep refreshed results.",
            stage: .save,
            category: .saveBlocked,
            state: &state,
        )
    }

    private func presentCollectionRefreshFeedback(
        kind: ComposerTransientFeedbackKind,
        message: String,
        recoveryHint: String,
        stage: ComposerTransientFeedbackStage,
        category: ComposerTransientFeedbackCategory,
        state: inout State,
    ) -> Effect<Action> {
        let feedback = ComposerTransientFeedback(
            id: UUID(),
            kind: kind,
            message: message,
            stage: stage,
            category: category,
            recoveryHint: recoveryHint,
        )
        state.composer.isPresented = true
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

    private func compatibilityBlockedRefreshMessage(
        reason: CollectionWriteBackEligibility?,
    ) -> String {
        switch reason {
        case .blockedLegacyVersionUpgrade:
            "Results were refreshed, but this older collection format cannot be updated."
        case .blockedDefinitionFallback:
            "Results were refreshed, but this collection was opened from a fallback definition and cannot be updated."
        case .blockedFutureMinorVersion, .blockedUnsupportedFutureVersion:
            "Results were refreshed, but this collection was created by a newer app version and cannot be updated."
        case .allowed, .none:
            "Results were refreshed, but the saved collection snapshot could not be updated."
        }
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
        state.composer.isPresented = true
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
                sortKey: state.entryArrangements.sortKey,
                sortOrder: state.entryArrangements.sortOrder,
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
        state.suppressAutomaticRefreshFeedback = false
        let previousSnapshot = state.navigation.makeContentPageNavigationHistorySnapshot()
        let nextNavigationState = ContentPageNavigationRoute.collection(
            ContentPageCollectionNavigationFactory.makeCollectionNavigation(
                payload.nextNavigation,
                sortKey: state.entryArrangements.sortKey,
                sortOrder: state.entryArrangements.sortOrder,
                viewLayout: state.entryViewLayout.mode,
            ),
        )

        state.navigation.navigationState = nextNavigationState

        var navigationEffects: [Effect<Action>] = [
            .send(.internal(.requestNavigation(.internal(.setNavigationState(nextNavigationState))))),
        ]

        if payload.shouldAppendHistory {
            if let historyNavigation = payload.previousHistoryNavigation {
                let historyEntry = ContentPageNavigationHistorySnapshot(
                    navigationState: .collection(
                        ContentPageCollectionNavigationFactory.makeCollectionNavigation(
                            historyNavigation,
                            sortKey: state.entryArrangements.sortKey,
                            sortOrder: state.entryArrangements.sortOrder,
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
                syncComposerCollectionStateEffect(payload: payload, isCollectionMode: state.isCollectionMode),
                .send(.internal(.requestNavigation(.internal(.setPendingNavigation(nil))))),
                .send(.internal(.performPendingNavigation(pending))),
            )
        }

        return .concatenate(
            .concatenate(navigationEffects),
            syncComposerCollectionStateEffect(payload: payload, isCollectionMode: state.isCollectionMode),
        )
    }

    private func syncComposerCollectionStateEffect(
        payload: CollectionWriteBackNavigationPayload,
        isCollectionMode: Bool,
    ) -> Effect<Action> {
        let openedURL: URL? = switch payload.nextNavigation.kind {
        case .temporary:
            nil
        case let .file(url, _):
            url
        }
        return .send(.composer(.syncCollectionState(
            context: payload.nextNavigation.context,
            url: openedURL,
            compatibility: payload.nextNavigation.compatibility,
            isCollectionMode: isCollectionMode,
        )))
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
