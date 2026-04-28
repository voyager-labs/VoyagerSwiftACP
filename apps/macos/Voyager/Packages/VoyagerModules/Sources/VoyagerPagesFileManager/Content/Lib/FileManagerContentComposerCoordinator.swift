import ComposableArchitecture
import Foundation
import VoyagerShared

import VoyagerFeaturesEntryOperations

enum FileManagerContentComposerCoordinator {
    struct Dependencies: Sendable {
        let collectionAlertClient: CollectionAlertClient
        let computerName: String
    }

    static func reduce(
        _ action: ComposerFeature.Action,
        state: inout FileManagerContentState,
        dependencies: Dependencies,
    ) -> Effect<FileManagerContentAction> {
        if let effect = handleComposerLifecycleAction(action, state: &state, dependencies: dependencies) {
            return effect
        }

        if let effect = handleComposerDelegateAction(action) {
            return effect
        }

        return .none
    }

    static func handleCollectionDelegate(
        _ delegateAction: CollectionFeature.Action.Delegate,
        state: inout FileManagerContentState,
    ) -> Effect<FileManagerContentAction> {
        switch delegateAction {
        case .draftRestorePrepared:
            return .none

        case let .searchResultPrepared(payload):
            let previousSnapshot = state.navigation.makeContentPageNavigationHistorySnapshot()
            let nextNavigationState = ContentPageNavigationRoute.collection(
                makeCollectionNavigation(payload.navigation, state: state),
            )
            var navigationEffects: [Effect<FileManagerContentAction>] = []
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
                .send(.internal(.syncComposerCollectionState)),
                .send(.composer(.searchListApplied)),
            )

        case .writeBackNavigationPrepared:
            return .none
        }
    }

    private static func handleComposerLifecycleAction(
        _ action: ComposerFeature.Action,
        state: inout FileManagerContentState,
        dependencies: Dependencies,
    ) -> Effect<FileManagerContentAction>? {
        if let effect = handleComposerSearchResponseAction(action, state: &state, dependencies: dependencies) {
            return effect
        }

        switch action {
        case let .view(.setPresented(isPresented)):
            return handleSetPresented(isPresented, state: &state)

        case .view(.applyFilters):
            state.composer.isLoadingFilters = true
            return .none

        case let .view(.setText(text)):
            return handleSetText(text, state: &state, dependencies: dependencies)

        case .view(.cancelSearch):
            state.composer.pendingSearchQuery = nil
            return .send(.collection(.openSearchPresentationCancelled))

        case .view(.clearAll):
            if state.isCollectionMode {
                state.composer.pendingSearchQuery = nil
                return .concatenate(
                    .send(.collection(.temporaryContextResetRequested(rootScopePath: ComposerScopeUtils
                            .rootScopePath))),
                    .send(.internal(.syncComposerCollectionState)),
                )
            }
            return exitCollectionMode(state: &state, computerName: dependencies.computerName)

        default:
            return nil
        }
    }

    private static func handleComposerSearchResponseAction(
        _ action: ComposerFeature.Action,
        state: inout FileManagerContentState,
        dependencies: Dependencies,
    ) -> Effect<FileManagerContentAction>? {
        switch action {
        case let .internal(.filtersResponse(requestID, .success(response))):
            guard state.composer.lastAcceptedFiltersRequestID == requestID else {
                return .none
            }
            let wasDirtyBeforeApplyingResponse = state.isOpenedCollectionDirty
            state.composer.lastFiltersResponse = response
            let effect = handleSearchSuccess(
                items: response.items ?? [],
                query: state.composer.pendingSearchQuery ?? "",
                state: &state,
            )
            return finalizeCollectionRefreshIfNeeded(
                wasDirtyBeforeApplyingResponse: wasDirtyBeforeApplyingResponse,
                response: response,
                searchEffect: effect,
                state: &state,
            )

        case let .internal(.searchResponse(requestID, .failure(error))):
            guard state.composer.lastAcceptedSearchRequestID == requestID else {
                return .none
            }
            return handleBlockedCollectionSearchFailure(
                error: error,
                title: "Unable to Run Collection Search",
                state: &state,
                dependencies: dependencies,
            )

        case let .internal(.filtersResponse(requestID, .failure(error))):
            guard state.composer.lastAcceptedFiltersRequestID == requestID else {
                return .none
            }
            let title = state.composer.pendingSearchQuery == nil
                ? "Unable to Apply Collection Filters"
                : "Unable to Run Collection Search"
            return handleBlockedCollectionSearchFailure(
                error: error,
                title: title,
                state: &state,
                dependencies: dependencies,
            )

        default:
            return nil
        }
    }

    private static func handleComposerDelegateAction(
        _ action: ComposerFeature.Action,
    ) -> Effect<FileManagerContentAction>? {
        guard case let .delegate(delegateAction) = action else {
            return nil
        }
        switch delegateAction {
        case let .saveRequested(payload):
            return .send(.collection(.saveRequested(payload)))
        case let .saveToExisting(payload, url):
            return .send(.collection(.saveToExisting(payload, url)))
        }
    }

    private static func handleBlockedCollectionSearchFailure(
        error: Error,
        title: String,
        state: inout FileManagerContentState,
        dependencies: Dependencies,
    ) -> Effect<FileManagerContentAction> {
        let effect = handleSearchFailure(
            error: error,
            title: title,
            state: &state,
            dependencies: dependencies,
        )
        return failCollectionRefreshIfNeeded(
            searchEffect: effect,
            state: &state,
        )
    }

    private static func handleSetPresented(
        _ isPresented: Bool,
        state: inout FileManagerContentState,
    ) -> Effect<FileManagerContentAction> {
        guard isPresented else {
            state.composer.pendingSearchQuery = nil
            return .send(.collection(.openSearchPresentationCancelled))
        }

        if state.composer.scopes.isEmpty,
           state.composer.conditions.isEmpty,
           state.composer.text.isEmpty
        {
            state.composer.scopes = [state.navigation.currentPath]
        }

        VoyagerSentryMetricLogger.logMetric(
            "voyager_composer_open",
            value: 1,
        )
        return .none
    }

    private static func handleSetText(
        _ text: String,
        state: inout FileManagerContentState,
        dependencies: Dependencies,
    ) -> Effect<FileManagerContentAction> {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        state.composer.pendingSearchQuery = query.isEmpty ? nil : query
        if query.isEmpty, state.composer.conditions.isEmpty, state.composer.scopes.isEmpty {
            return exitCollectionMode(state: &state, computerName: dependencies.computerName)
        }
        return .none
    }

    private static func handleSearchSuccess(
        items: [VoyagerShared.JSONValue],
        query: String,
        state: inout FileManagerContentState,
    ) -> Effect<FileManagerContentAction> {
        let previousNavigationState = state.navigation.navigationState
        let previousNavigationIsCollection = previousNavigationState.isCollection
        state.composer.pendingSearchQuery = nil
        let nextContext = CollectionContext(
            query: query,
            scopes: state.composer.scopes,
            conditions: state.composer.conditions,
        )
        let proposedNextNavigationState = ContentPageNavigationRoute.collection(
            makeCollectionNavigation(
                state.collection.makeNavigationPresentationPayload(context: nextContext),
                state: state,
            ),
        )
        let showHidden = state.entryViewLayout.showHiddenFiles
        let paths = searchResultPaths(from: items)

        return .concatenate(
            .send(.collection(.searchSucceeded(
                context: nextContext,
                items: items,
                previousNavigationIsCollection: previousNavigationIsCollection,
                nextNavigationDiffers: previousNavigationState != proposedNextNavigationState,
            ))),
            .send(.entryViewLayout(.internal(.setCollectionMode(true)))),
            .send(.entryViewLayout(.internal(.applyCollectionSearchPaths(paths: paths, showHidden: showHidden)))),
        )
    }

    private static func handleSearchFailure(
        error: Error,
        title: String,
        state: inout FileManagerContentState,
        dependencies: Dependencies,
    ) -> Effect<FileManagerContentAction> {
        state.composer.pendingSearchQuery = nil
        guard state.collectionSession.phase.isOpening else {
            return .none
        }
        state.resetComposer()
        let exitEffect = exitCollectionMode(state: &state, computerName: dependencies.computerName)
        let collectionAlertClient = dependencies.collectionAlertClient
        return .concatenate(
            .send(.collection(.searchFailed)),
            .send(.internal(.requestNavigation(.internal(.rollbackBackHistoryOnce)))),
            .merge(
                exitEffect,
                .run { _ in
                    await collectionAlertClient.showCollectionOpenErrorAlert(
                        title,
                        """
                        \(error.localizedDescription)

                        Check Gateway/Helper status and try again.
                        """,
                    )
                },
            ),
        )
    }
}

private func searchResultPaths(from items: [VoyagerShared.JSONValue]) -> [String] {
    items.compactMap { item in
        switch item {
        case let .string(path):
            return path
        case let .object(dict):
            guard case let .string(path) = dict["fullPath"] else { return nil }
            return path
        default:
            return nil
        }
    }
}

func makeCollectionNavigation(
    _ payload: CollectionNavigationPresentationPayload,
    state: FileManagerContentState,
) -> ContentPageCollectionNavigation {
    let kind: ContentPageCollectionKind = switch payload.kind {
    case .temporary:
        .temporary
    case let .file(url, name):
        .file(url: url, name: name)
    }

    return ContentPageCollectionNavigation(
        kind: kind,
        context: payload.context,
        sortKey: state.entryViewLayout.entryArrangements.sortKey,
        sortOrder: state.entryViewLayout.entryArrangements.sortOrder,
        viewLayout: state.entryViewLayout.mode,
        compatibility: payload.compatibility,
    )
}

func clearCollectionMode(state: inout FileManagerContentState) -> Effect<FileManagerContentAction> {
    state.composer.pendingSearchQuery = nil

    return .concatenate(
        .send(.collection(.sessionResetRequested)),
        .send(.internal(.requestNavigation(.internal(.setPendingNavigation(nil))))),
        .cancel(id: "openCollectionFile"),
        .cancel(id: ComposerFeature.CancelID.search),
        .cancel(id: ComposerFeature.CancelID.filters),
        .send(.entryViewLayout(.internal(.clearCollectionPresentation))),
        .send(.internal(.syncComposerCollectionState)),
    )
}

func exitCollectionMode(
    state: inout FileManagerContentState,
    computerName: String,
) -> Effect<FileManagerContentAction> {
    let wasCollection = if case .collection = state.navigation.navigationState { true } else { false }
    let clearEffect = clearCollectionMode(state: &state)

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
}
