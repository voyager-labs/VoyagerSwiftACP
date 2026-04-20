import ComposableArchitecture
import Foundation
import VoyagerShared

struct RefreshedSnapshotWriteBackRequest {
    let payload: SaveRequestPayload
    let url: URL
}

func handleCollectionSaveFailure(
    state: inout FileManagerContentState,
) -> Effect<FileManagerContentAction> {
    if state.collectionSession.isWritingBackRefreshedSnapshot {
        state.collectionSession.isWritingBackRefreshedSnapshot = false
        state.collectionSession.isStale = true
        if state.collectionSession.staleReason == nil {
            state.collectionSession.staleReason = .snapshotHydratedOnOpen
        }
        state.collectionSession.lastRefreshAt = nil
    }
    return .send(.internal(.requestNavigation(.internal(.setPendingNavigation(nil)))))
}

func handleCollectionSaveSuccess(
    completion: CollectionSaveCompletion,
    state: inout FileManagerContentState,
    currentDate: Date,
) -> Effect<FileManagerContentAction> {
    let url = completion.url
    let previousSnapshot = state.navigation.makeContentPageNavigationHistorySnapshot()
    let previousCollectionURL = state.collectionSession.openedURL
    let previousCollectionName = state.collectionSession.openedName
    let previousBaseline = state.collectionSession.baseline
    let shouldAppendHistory = previousCollectionURL?.path != url.path

    if state.collectionSession.isWritingBackRefreshedSnapshot {
        guard state.isCollectionMode,
              state.collectionSession.openedURL?.path == url.path
        else {
            state.collectionSession.isWritingBackRefreshedSnapshot = false
            return .none
        }
        applyWriteBackSuccessState(state: &state, currentDate: currentDate)
    }

    applySavedCollectionSessionState(completion: completion, state: &state)

    var navigationEffects: [Effect<FileManagerContentAction>] = [
        .send(.internal(.requestNavigation(.internal(.setNavigationState(.collection(
            makeCollectionNavigation(state: state),
        )))))),
    ]

    if shouldAppendHistory {
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

func applySavedCollectionSessionState(
    completion: CollectionSaveCompletion,
    state: inout FileManagerContentState,
) {
    let url = completion.url
    let compatibility = VoyagerCollectionFileCompatibilityOwner.compatibilityForCurrentFile(completion.file)
    state.collectionSession.openedURL = url
    state.collectionSession.openedName = url.deletingPathExtension().lastPathComponent
    state.collectionSession.originURL = url
    state.collectionSession.baseline = state.collectionContext.map(CollectionBaseline.init(context:))
    state.collectionSession.openedCompatibility = compatibility
}

func applyWriteBackSuccessState(
    state: inout FileManagerContentState,
    currentDate: Date,
) {
    state.collectionSession.isWritingBackRefreshedSnapshot = false
    state.collectionSession.isStale = false
    state.collectionSession.staleReason = nil
    state.collectionSession.lastRefreshAt = currentDate
}

func finalizeCollectionRefreshIfNeeded(
    searchEffect: Effect<FileManagerContentAction>,
    state: inout FileManagerContentState,
    currentDate: Date,
) -> Effect<FileManagerContentAction> {
    guard state.collectionSession.isRefreshingHydratedSnapshot else {
        return .concatenate(
            searchEffect,
            .send(.delegate(.composerCollectionSearchSucceeded)),
        )
    }

    state.collectionSession.isRefreshingHydratedSnapshot = false

    guard !state.isOpenedCollectionDirty,
          state.collectionSession.openedCompatibility?.writeBackAllowed != false,
          let writeBack = makeRefreshedSnapshotWriteBackRequest(state: state, currentDate: currentDate)
    else {
        state.collectionSession.isWritingBackRefreshedSnapshot = false
        state.collectionSession.lastRefreshAt = nil
        return .concatenate(
            searchEffect,
            .send(.delegate(.composerCollectionSearchSucceeded)),
        )
    }

    state.collectionSession.isWritingBackRefreshedSnapshot = true

    return .concatenate(
        searchEffect,
        .send(.composer(.collection(.saveToExisting(writeBack.payload, writeBack.url)))),
        .send(.delegate(.composerCollectionSearchSucceeded)),
    )
}

func failCollectionRefreshIfNeeded(
    searchEffect: Effect<FileManagerContentAction>,
    state: inout FileManagerContentState,
) -> Effect<FileManagerContentAction> {
    if state.collectionSession.isRefreshingHydratedSnapshot {
        state.collectionSession.isRefreshingHydratedSnapshot = false
        state.collectionSession.isWritingBackRefreshedSnapshot = false
        state.collectionSession.lastRefreshAt = nil
    }

    return .concatenate(
        searchEffect,
        .send(.delegate(.composerCollectionSearchFailed)),
    )
}

func makeRefreshedSnapshotWriteBackRequest(
    state: FileManagerContentState,
    currentDate: Date,
) -> RefreshedSnapshotWriteBackRequest? {
    guard let context = state.collectionContext,
          let url = state.collectionSession.openedURL,
          let snapshotItems = CollectionSnapshotHydration.snapshotItems(from: state.composer.lastFiltersResponse?.items)
    else {
        return nil
    }

    let payload = SaveRequestPayload(
        context: context,
        isSearchLoading: false,
        isFiltersLoading: false,
        snapshotItems: snapshotItems,
        definitionFingerprint: CollectionSnapshotHydration.definitionFingerprint(
            query: context.query,
            scopes: context.scopes,
            conditions: context.conditions,
        ),
        capturedAt: currentDate,
        relevanceRoots: context.scopes.map { URL(fileURLWithPath: $0).standardizedFileURL.path }.sorted(),
    )

    return .init(payload: payload, url: url)
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
