import ComposableArchitecture
import Foundation
import VoyagerEntitiesCollection
import VoyagerFeaturesEntryOperations
import VoyagerShared

enum FileManagerContentComposerCoordinator {
    struct Dependencies: Sendable {
        let collectionAlertClient: CollectionAlertClient
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
            return .send(.composer(.setLoadingFilters(true)))

        case let .view(.setText(text)):
            return handleSetText(text, state: &state, dependencies: dependencies)

        case .view(.cancelSearch):
            return .concatenate(
                .send(.composer(.clearPendingSearchQuery)),
                .send(.collection(.openSearchPresentationCancelled)),
            )

        case .view(.clearAll):
            if state.isCollectionMode {
                return .concatenate(
                    .send(.composer(.clearPendingSearchQuery)),
                    .send(.collection(.temporaryContextResetRequested(rootScopePath: ComposerScopeUtils
                            .rootScopePath))),
                )
            }
            return .send(.internal(.exitCollectionMode))

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
            return handleFiltersResponseSuccess(
                requestID: requestID,
                response: response,
                state: &state,
            )

        case let .internal(.searchResponse(requestID, .failure(error))):
            guard state.composer.lastAcceptedSearchRequestID == requestID else {
                return .none
            }
            let searchEffect = handleSearchFailure(
                error: error,
                title: "Unable to Run Collection Search",
                state: &state,
                dependencies: dependencies,
            )
            return .concatenate(
                .send(.collection(.refreshFailed)),
                searchEffect,
                .send(.delegate(.composerCollectionSearchFailed)),
            )

        case let .internal(.filtersResponse(requestID, .failure(error))):
            guard state.composer.lastAcceptedFiltersRequestID == requestID else {
                return .none
            }
            let title = state.composer.pendingSearchQuery == nil
                ? "Unable to Apply Collection Filters"
                : "Unable to Run Collection Search"
            let searchEffect = handleSearchFailure(
                error: error,
                title: title,
                state: &state,
                dependencies: dependencies,
            )
            return .concatenate(
                .send(.collection(.refreshFailed)),
                searchEffect,
                .send(.delegate(.composerCollectionSearchFailed)),
            )

        default:
            return nil
        }
    }

    private static func handleFiltersResponseSuccess(
        requestID: String,
        response: ComposerSearchResponse,
        state: inout FileManagerContentState,
    ) -> Effect<FileManagerContentAction>? {
        guard state.composer.lastAcceptedFiltersRequestID == requestID else {
            return .none
        }
        let wasDirtyBeforeApplyingResponse = state.isOpenedCollectionDirty
        let searchEffect = handleSearchSuccess(
            items: response.items ?? [],
            query: state.composer.pendingSearchQuery ?? "",
            state: &state,
        )
        return .concatenate(
            .send(.composer(.updateLastFiltersResponse(response))),
            .send(.collection(.refreshResponseReceived(
                response,
                wasDirtyBeforeApplyingResponse: wasDirtyBeforeApplyingResponse,
            ))),
            searchEffect,
            .send(.composer(.syncCollectionState(
                context: state.collection.collectionContext,
                url: state.collection.collectionSession.document?.url,
                compatibility: state.collection.collectionSession.document?.compatibility,
                isCollectionMode: state.isCollectionMode,
            ))),
            .send(.delegate(.composerCollectionSearchSucceeded)),
        )
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

    private static func handleSetPresented(
        _ isPresented: Bool,
        state: inout FileManagerContentState,
    ) -> Effect<FileManagerContentAction> {
        guard isPresented else {
            return .concatenate(
                .send(.composer(.clearPendingSearchQuery)),
                .send(.collection(.openSearchPresentationCancelled)),
            )
        }

        if state.composer.scopes.isEmpty,
           state.composer.conditions.isEmpty,
           state.composer.text.isEmpty
        {
            return .send(.composer(.setInitialScope(state.navigation.currentPath)))
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
        dependencies _: Dependencies,
    ) -> Effect<FileManagerContentAction> {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty, state.composer.conditions.isEmpty, state.composer.scopes.isEmpty {
            return .concatenate(
                .send(.composer(.setPendingSearchQuery(nil))),
                .send(.internal(.exitCollectionMode)),
            )
        }
        return .send(.composer(.setPendingSearchQuery(query.isEmpty ? nil : query)))
    }

    private static func handleSearchSuccess(
        items: [VoyagerShared.JSONValue],
        query: String,
        state: inout FileManagerContentState,
    ) -> Effect<FileManagerContentAction> {
        let previousNavigationState = state.navigation.navigationState
        let previousNavigationIsCollection = previousNavigationState.isCollection
        let nextContext = CollectionContext(
            query: query,
            scopes: state.composer.scopes,
            conditions: state.composer.conditions,
        )
        let proposedNextNavigationState = ContentPageNavigationRoute.collection(
            ContentPageCollectionNavigationFactory.makeCollectionNavigation(
                state.collection.makeNavigationPresentationPayload(context: nextContext),
                sortKey: state.entryViewLayout.entryArrangements.sortKey,
                sortOrder: state.entryViewLayout.entryArrangements.sortOrder,
                viewLayout: state.entryViewLayout.mode,
            ),
        )
        let showHidden = state.entryViewLayout.showHiddenFiles
        let paths = searchResultPaths(from: items)

        return .concatenate(
            .send(.composer(.clearPendingSearchQuery)),
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
        guard state.collection.collectionSession.phase.isOpening else {
            return .send(.composer(.clearPendingSearchQuery))
        }
        let collectionAlertClient = dependencies.collectionAlertClient
        return .concatenate(
            .send(.composer(.clearPendingSearchQuery)),
            .send(.composer(.resetComposerAndSync(
                context: state.collection.collectionContext,
                url: state.collection.collectionSession.document?.url,
                compatibility: state.collection.collectionSession.document?.compatibility,
                isCollectionMode: state.isCollectionMode,
            ))),
            .send(.collection(.searchFailed)),
            .send(.internal(.requestNavigation(.internal(.rollbackBackHistoryOnce)))),
            .merge(
                .send(.internal(.exitCollectionMode)),
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
