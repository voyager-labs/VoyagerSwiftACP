import ComposableArchitecture
import Foundation
import VoyagerShared

func handleCollectionSaveFailure(
    state: inout FileManagerContentState,
) -> Effect<FileManagerContentAction> {
    if state.collectionSession.isWritingBackRefreshedSnapshot {
        state.collectionSession.failRefreshOrWriteBack()
    }
    return .send(.internal(.requestNavigation(.internal(.setPendingNavigation(nil)))))
}

func handleCollectionSaveSuccess(
    completion: CollectionSaveCompletion,
    state: inout FileManagerContentState,
) -> Effect<FileManagerContentAction> {
    let previousSnapshot = state.navigation.makeContentPageNavigationHistorySnapshot()
    let previousCollectionURL = state.collectionSession.openedURL
    let previousCollectionName = state.collectionSession.openedName
    let previousBaseline = state.collectionSession.baseline

    let payload = CollectionDocumentSessionFeature.writeBackSuccessPayload(
        state: &state.collectionSession,
        completion: completion,
        currentCollectionContext: state.collectionContext,
    )

    let url = payload.url

    var navigationEffects: [Effect<FileManagerContentAction>] = [
        .send(.internal(.requestNavigation(.internal(.setNavigationState(.collection(
            makeCollectionNavigation(state: state),
        )))))),
    ]

    if payload.shouldAppendHistory {
        if let historyEntry = previousCollectionHistoryEntryForRefreshSupport(
            baseline: previousBaseline,
            previousURL: previousCollectionURL,
            previousCollectionName: previousCollectionName,
            state: state,
        ) {
            navigationEffects.append(.send(.internal(.requestNavigation(.internal(.appendBackHistory(historyEntry))))))
        } else {
            navigationEffects
                .append(.send(.internal(.requestNavigation(.internal(.appendBackHistory(previousSnapshot))))))
        }
        navigationEffects.append(.send(.internal(.requestNavigation(.internal(.clearForwardHistory)))))
    }

    state.syncComposerCollectionState()

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
    guard state.collectionSession.isRefreshingHydratedSnapshot else {
        return .concatenate(
            searchEffect,
            .send(.delegate(.composerCollectionSearchSucceeded)),
        )
    }
    state.composer.lastFiltersResponse = response
    let payload = CollectionDocumentSessionFeature.refreshResponsePayload(
        state: &state.collectionSession,
        wasDirtyBeforeApplyingResponse: wasDirtyBeforeApplyingResponse,
        writeBackAllowed: state.collectionSession.openedCompatibility?.writeBackAllowed != false,
    )
    state.syncComposerCollectionState()

    if payload.shouldWriteBack {
        return .concatenate(
            searchEffect,
            .send(.composer(.saveCollection)),
            .send(.delegate(.composerCollectionSearchSucceeded)),
        )
    }

    return .concatenate(
        searchEffect,
        .send(.delegate(.composerCollectionSearchSucceeded)),
    )
}

func failCollectionRefreshIfNeeded(
    searchEffect: Effect<FileManagerContentAction>,
    state: inout FileManagerContentState,
) -> Effect<FileManagerContentAction> {
    if state.collectionSession.isRefreshingHydratedSnapshot {
        state.collectionSession.failRefreshOrWriteBack()
    }

    return .concatenate(
        searchEffect,
        .send(.delegate(.composerCollectionSearchFailed)),
    )
}

func previousCollectionHistoryEntryForRefreshSupport(
    baseline: CollectionBaseline?,
    previousURL: URL?,
    previousCollectionName: String?,
    state: FileManagerContentState,
) -> ContentPageNavigationHistorySnapshot? {
    guard let baseline,
          let previousURL
    else {
        return nil
    }

    let name = previousCollectionName
        ?? previousURL.deletingPathExtension().lastPathComponent
    let navigation = ContentPageCollectionNavigation(
        kind: .file(url: previousURL, name: name),
        context: baseline.context,
        sortKey: state.entryViewLayout.entryArrangements.sortKey,
        sortOrder: state.entryViewLayout.entryArrangements.sortOrder,
        viewLayout: state.entryViewLayout.mode,
        compatibility: state.collectionSession.openedCompatibility,
    )
    return ContentPageNavigationHistorySnapshot(
        navigationState: .collection(navigation),
    )
}
