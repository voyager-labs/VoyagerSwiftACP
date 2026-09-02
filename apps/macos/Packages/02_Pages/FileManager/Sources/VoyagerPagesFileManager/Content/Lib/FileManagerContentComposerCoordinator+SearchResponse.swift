import ComposableArchitecture
import Foundation
import VoyagerEntitiesCollection
import VoyagerFeaturesComposer
import VoyagerFeaturesContentPageNavigation
import VoyagerFeaturesEntryArrangements
import VoyagerShared

extension FileManagerContentComposerCoordinator {
    static func handleComposerSearchResponseAction(
        _ action: ComposerFeature.Action,
        state: inout FileManagerContentState,
        dependencies: Dependencies,
    ) -> Effect<FileManagerContentAction>? {
        switch action {
        case let .internal(.searchResponse(requestID, .success(response))):
            return handleSearchResponseSuccess(
                requestID: requestID,
                response: response,
                state: &state,
                dependencies: dependencies,
            )

        case let .internal(.filtersResponse(requestID, .success(response))):
            if let error = response.error {
                return handleFiltersResponseFailure(
                    requestID: requestID,
                    error: SearchResponsePayloadError(payload: error),
                    state: &state,
                    dependencies: dependencies,
                )
            }
            return handleFiltersResponseSuccess(
                requestID: requestID,
                response: response,
                state: &state,
            )

        case let .internal(.searchResponse(requestID, .failure(error))):
            return handleSearchResponseFailure(
                requestID: requestID,
                error: error,
                state: &state,
                dependencies: dependencies,
            )

        case let .internal(.filtersResponse(requestID, .failure(error))):
            return handleFiltersResponseFailure(
                requestID: requestID,
                error: error,
                state: &state,
                dependencies: dependencies,
            )

        default:
            return nil
        }
    }

    private static func handleSearchResponseSuccess(
        requestID: UUID,
        response: VoyagerShared.SearchResponsePayload,
        state: inout FileManagerContentState,
        dependencies: Dependencies,
    ) -> Effect<FileManagerContentAction>? {
        guard state.composer.lastAcceptedSearchRequestID == requestID else {
            return .none
        }
        guard let error = response.error else {
            guard state.isCollectionMode,
                  let baseline = state.composer.submittedSearchFilters,
                  ComposerQueryFeedbackPolicy.shouldSkipApplyFilters(response: response, baseline: baseline),
                  let nextContext = state.composer.collectionContext,
                  nextContext != state.collection.collectionContext
            else {
                return .none
            }
            // Query search returns a filter preview, so no-op success must update only the canonical draft.
            state.collection.collectionContext = nextContext
            return .none
        }

        let searchEffect = handleSearchFailure(
            error: SearchResponsePayloadError(payload: error),
            title: "Unable to Run Collection Search",
            state: &state,
            dependencies: dependencies,
        )
        return .concatenate(
            .send(.collection(.refreshFailed)),
            searchEffect,
            .send(.delegate(.composerCollectionSearchFailed)),
        )
    }

    private static func handleSearchResponseFailure(
        requestID: UUID,
        error: Error,
        state: inout FileManagerContentState,
        dependencies: Dependencies,
    ) -> Effect<FileManagerContentAction>? {
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
    }

    private static func handleFiltersResponseFailure(
        requestID: UUID,
        error: Error,
        state: inout FileManagerContentState,
        dependencies: Dependencies,
    ) -> Effect<FileManagerContentAction>? {
        guard state.composer.lastFailedFiltersRequestID == requestID else {
            return .none
        }
        state.composer.lastFailedFiltersRequestID = nil
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
    }

    private static func handleFiltersResponseSuccess(
        requestID: UUID,
        response: VoyagerShared.SearchResponsePayload,
        state: inout FileManagerContentState,
    ) -> Effect<FileManagerContentAction>? {
        guard state.composer.lastAcceptedFiltersRequestID == requestID else {
            return .none
        }
        let isInflightRefresh = state.collection.collectionSession.phase.isInflightRefresh
        let wasDirtyBeforeApplyingResponse = state.isOpenedCollectionDirty
        let shouldWriteBackAfterRefresh = state.collection.shouldWriteBackAfterRefresh(
            wasDirtyBeforeApplyingResponse: wasDirtyBeforeApplyingResponse,
        )
        let query = state.composer.pendingSearchQuery ?? ""
        let nextContext = state.composer.collectionContext(query: query)
        let searchEffect = handleSearchSuccess(
            items: response.items ?? [],
            query: query,
            state: &state,
            nextContext: nextContext,
        )
        return .concatenate(
            .send(.composer(.updateLastFiltersResponse(response))),
            isInflightRefresh
                ? .send(.collection(.refreshResponseReceived(
                    response,
                    wasDirtyBeforeApplyingResponse: wasDirtyBeforeApplyingResponse,
                )))
                : .none,
            searchEffect,
            .send(.composer(.syncCollectionState(
                context: nextContext,
                url: state.collection.collectionSession.document?.url,
                compatibility: state.collection.collectionSession.document?.compatibility,
                isCollectionMode: true,
            ))),
            .send(.delegate(.composerCollectionSearchSucceeded)),
            shouldWriteBackAfterRefresh ? .send(.composer(.saveCollection)) : .none,
        )
    }

    private static func handleSearchSuccess(
        items: [VoyagerShared.JSONValue],
        query: String,
        state: inout FileManagerContentState,
        nextContext: CollectionContext? = nil,
    ) -> Effect<FileManagerContentAction> {
        let previousNavigationState = state.navigation.navigationState
        let previousNavigationIsCollection = previousNavigationState.isCollection
        state.composer.pendingSearchQuery = nil
        let resolvedContext = nextContext ?? state.composer.collectionContext(query: query)
        let proposedNextNavigationState = ContentPageNavigationRoute.collection(
            ContentPageCollectionNavigationFactory.makeCollectionNavigation(
                state.collection.makeNavigationPresentationPayload(context: resolvedContext),
                sortKey: state.entryViewLayout.entryArrangements.sortKey,
                sortOrder: state.entryViewLayout.entryArrangements.sortOrder,
                viewLayout: state.entryViewLayout.mode,
            ),
        )
        let showHidden = state.entryViewLayout.showHiddenFiles
        let paths = searchResultPaths(from: items)
        let priority = FileManagerContentEntryOpsCoordinator
            .rootMetadataPriority(for: state.entryViewLayout.entryArrangements)

        return .concatenate(
            .send(.composer(.clearPendingSearchQuery)),
            .send(.collection(.searchSucceeded(
                context: resolvedContext,
                items: items,
                previousNavigationIsCollection: previousNavigationIsCollection,
                nextNavigationDiffers: previousNavigationState != proposedNextNavigationState,
            ))),
            .send(.entryViewLayout(.internal(.setCollectionMode(true)))),
            .send(.entryViewLayout(.internal(.applyCollectionSearchPaths(
                paths: paths,
                showHidden: showHidden,
                priority: priority,
            )))),
        )
    }

    private static func synchronizeOpenedCollectionDraftAfterFailure(
        state: inout FileManagerContentState,
    ) {
        guard state.isCollectionMode,
              state.collection.collectionSession.document?.url != nil,
              let composerContext = state.composer.collectionContext
        else {
            return
        }
        let query = state.composer.pendingSearchQuery ?? composerContext.query
        state.collection.collectionContext = state.composer.collectionContext(query: query)
    }

    private static func handleSearchFailure(
        error: Error,
        title: String,
        state: inout FileManagerContentState,
        dependencies: Dependencies,
    ) -> Effect<FileManagerContentAction> {
        guard state.collection.collectionSession.phase.isOpening else {
            synchronizeOpenedCollectionDraftAfterFailure(state: &state)
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

                        Check AI provider and Helper status, then try again.
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

private struct SearchResponsePayloadError: LocalizedError {
    let payload: SearchErrorPayload

    var errorDescription: String? {
        guard let details = payload.details?.trimmingCharacters(in: .whitespacesAndNewlines),
              details.isEmpty == false
        else {
            return payload.code
        }
        return "\(payload.code): \(details)"
    }
}
