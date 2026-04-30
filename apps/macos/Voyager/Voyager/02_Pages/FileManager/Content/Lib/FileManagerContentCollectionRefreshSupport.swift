import ComposableArchitecture
import Foundation
import VoyagerEntitiesCollection
import VoyagerShared

func handleCollectionSaveFailure(
    state: inout FileManagerContentState,
) -> Effect<FileManagerContentAction> {
    if state.collectionSession.phase.inflightStatus == .writingBackRefreshedSnapshot {
        return .concatenate(
            .send(.collection(.writeBackFailed)),
            .send(.internal(.requestNavigation(.internal(.setPendingNavigation(nil))))),
        )
    }
    return .send(.internal(.requestNavigation(.internal(.setPendingNavigation(nil)))))
}

func handleCollectionWriteBackPrepared(
    payload: CollectionWriteBackNavigationPayload,
    state: inout FileManagerContentState,
) -> Effect<FileManagerContentAction> {
    let previousSnapshot = state.navigation.makeContentPageNavigationHistorySnapshot()
    let nextNavigationState = ContentPageNavigationRoute.collection(
        makeCollectionNavigation(payload.nextNavigation, state: state),
    )

    var navigationEffects: [Effect<FileManagerContentAction>] = [
        .send(.internal(.syncComposerCollectionState)),
        .send(.internal(.requestNavigation(.internal(.setNavigationState(nextNavigationState))))),
    ]

    if payload.shouldAppendHistory {
        if let historyNavigation = payload.previousHistoryNavigation {
            let historyEntry = ContentPageNavigationHistorySnapshot(
                navigationState: .collection(makeCollectionNavigation(historyNavigation, state: state)),
            )
            navigationEffects.append(.send(.internal(.requestNavigation(.internal(.appendBackHistory(historyEntry))))))
        } else {
            navigationEffects
                .append(.send(.internal(.requestNavigation(.internal(.appendBackHistory(previousSnapshot))))))
        }
        navigationEffects.append(.send(.internal(.requestNavigation(.internal(.clearForwardHistory)))))
    }

    if let pending = state.navigation.pendingNavigation {
        return .concatenate(
            .concatenate(navigationEffects),
            .send(.internal(.requestNavigation(.internal(.setPendingNavigation(nil))))),
            .send(.internal(.performPendingNavigation(pending))),
        )
    }

    return .concatenate(navigationEffects)
}

func finalizeCollectionRefreshIfNeeded(
    wasDirtyBeforeApplyingResponse: Bool,
    response: VoyagerShared.SearchResponsePayload,
    searchEffect: Effect<FileManagerContentAction>,
    state: inout FileManagerContentState,
) -> Effect<FileManagerContentAction> {
    guard state.collectionSession.phase.inflightStatus == .refreshingHydratedSnapshot else {
        return .concatenate(
            searchEffect,
            .send(.delegate(.composerCollectionSearchSucceeded)),
        )
    }
    state.composer.lastFiltersResponse = response
    var previewCollection = state.collection
    let shouldWriteBack = previewCollection.applyRefreshResponse(
        wasDirtyBeforeApplyingResponse: wasDirtyBeforeApplyingResponse,
    )
    state.syncComposerCollectionState()

    if shouldWriteBack {
        return .concatenate(
            .send(.collection(.refreshResponseReceived(
                response,
                wasDirtyBeforeApplyingResponse: wasDirtyBeforeApplyingResponse,
            ))),
            searchEffect,
            .send(.composer(.saveCollection)),
            .send(.delegate(.composerCollectionSearchSucceeded)),
        )
    }

    return .concatenate(
        .send(.collection(.refreshResponseReceived(
            response,
            wasDirtyBeforeApplyingResponse: wasDirtyBeforeApplyingResponse,
        ))),
        searchEffect,
        .send(.delegate(.composerCollectionSearchSucceeded)),
    )
}

func failCollectionRefreshIfNeeded(
    searchEffect: Effect<FileManagerContentAction>,
    state: inout FileManagerContentState,
) -> Effect<FileManagerContentAction> {
    let shouldNotifyOwner = state.collectionSession.phase.inflightStatus == .refreshingHydratedSnapshot

    if shouldNotifyOwner {
        return .concatenate(
            .send(.collection(.refreshFailed)),
            searchEffect,
            .send(.delegate(.composerCollectionSearchFailed)),
        )
    }

    return .concatenate(
        searchEffect,
        .send(.delegate(.composerCollectionSearchFailed)),
    )
}
