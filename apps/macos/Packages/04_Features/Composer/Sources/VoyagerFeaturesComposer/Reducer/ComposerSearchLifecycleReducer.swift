import ComposableArchitecture
import Foundation
import Logging
import VoyagerEntitiesCollection
import VoyagerShared

private let kComposerSearchLifecycleLogger = Logger(label: "Voyager")

@Reducer
struct ComposerSearchLifecycleReducer {
    typealias State = ComposerState
    typealias Action = ComposerAction

    @Dependency(\.searchClient)
    var searchClient
    @Dependency(\.registryClient)
    var registryClient
    @Dependency(\.continuousClock)
    var clock
    @Dependency(\.composerMetricClient)
    var composerMetricClient
    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .view(.submit):
                return handleSubmit(
                    state: &state,
                    searchClient: searchClient,
                    composerMetricClient: composerMetricClient,
                )

            case .view(.cancelSearch):
                return handleCancelSearch(state: &state, composerMetricClient: composerMetricClient)

            case .view(.cancelFilters):
                return handleCancelFilters(state: &state, composerMetricClient: composerMetricClient)

            case .view(.applyFilters):
                return handleApplyFilters(
                    state: &state,
                    searchClient: searchClient,
                    composerMetricClient: composerMetricClient,
                )

            case let .internal(.searchResponse(requestID, response)):
                guard state.activeSearchRequestID == requestID else {
                    return .none
                }
                state.lastAcceptedSearchRequestID = requestID
                switch response {
                case let .success(response):
                    state.isLoadingSearch = false
                    state.activeSearchRequestID = nil
                    state.lastSearchResponse = response
                    state.lastFiltersResponse = nil
                    let queryOutcome = response.queryOutcome
                    let startedAt = state.searchStartedAt
                    state.searchStartedAt = nil
                    switch queryOutcome {
                    case .fallbackReuse where state.openedCollectionURL == nil:
                        state.isLoadingFilters = false
                        state.isFilteringInFlight = false
                        state.activeFiltersRequestID = nil
                        state.activeFiltersMetricSource = nil
                        state.filtersStartedAt = nil
                        state.pendingSearchQuery = nil
                        applyQueryPhaseTransition(.reset, state: &state)
                        state.resolveScopeChangeFeedback(.search(requestID), phase: .visible)
                        logSearchDurationIfNeeded(startedAt, composerMetricClient: composerMetricClient)
                        let baselineFilters = feedbackBaseline(from: state)
                        logCollectionFilterQueryResult(
                            response: response,
                            queryOutcome: queryOutcome,
                            filters: baselineFilters,
                            openedCollectionURL: state.openedCollectionURL,
                            composerMetricClient: composerMetricClient,
                        )
                        composerMetricClient.logMetric(
                            ComposerCollectionFilterMetrics.legacySearchResult,
                            value: 1,
                            tags: ComposerCollectionFilterMetrics.legacySearchResultTags(
                                itemCount: response.itemCount,
                                queryOutcome: queryOutcome,
                            ),
                        )
                        kComposerSearchLifecycleLogger.debug("Composer query search resolved to fallback reuse")
                        return presentTransientFeedback(
                            kind: .info,
                            message: ComposerQueryFeedbackPolicy.fallbackReuseMessage,
                            state: &state,
                            clock: clock,
                        )

                    case .unchangedResult where state.openedCollectionURL == nil:
                        state.isLoadingFilters = false
                        state.isFilteringInFlight = false
                        state.activeFiltersRequestID = nil
                        state.activeFiltersMetricSource = nil
                        state.filtersStartedAt = nil
                        state.pendingSearchQuery = nil
                        applyQueryPhaseTransition(.reset, state: &state)
                        state.resolveScopeChangeFeedback(.search(requestID), phase: .visible)
                        logSearchDurationIfNeeded(startedAt, composerMetricClient: composerMetricClient)
                        let baselineFilters = feedbackBaseline(from: state)
                        logCollectionFilterQueryResult(
                            response: response,
                            queryOutcome: queryOutcome,
                            filters: baselineFilters,
                            openedCollectionURL: state.openedCollectionURL,
                            composerMetricClient: composerMetricClient,
                        )
                        composerMetricClient.logMetric(
                            ComposerCollectionFilterMetrics.legacySearchResult,
                            value: 1,
                            tags: ComposerCollectionFilterMetrics.legacySearchResultTags(
                                itemCount: response.itemCount,
                                queryOutcome: queryOutcome,
                            ),
                        )
                        kComposerSearchLifecycleLogger.debug("Composer query search resolved to unchanged result")
                        return .none

                    case .convertedChanged, .fallbackReuse, .unchangedResult, nil:
                        let baselineFilters = feedbackBaseline(from: state)
                        let normalizedAppliedFilters = feedbackAppliedFilters(
                            appliedFilters: response.appliedFilters,
                            baseline: baselineFilters,
                        )
                        applyQueryPhaseTransition(.searchSucceeded, state: &state)
                        applyAppliedFilters(normalizedAppliedFilters, state: &state, registryClient: registryClient)
                        logSearchDurationIfNeeded(startedAt, composerMetricClient: composerMetricClient)
                        logCollectionFilterQueryResult(
                            response: response,
                            queryOutcome: queryOutcome,
                            filters: feedbackFilters(from: normalizedAppliedFilters),
                            openedCollectionURL: state.openedCollectionURL,
                            composerMetricClient: composerMetricClient,
                        )
                        composerMetricClient.logMetric(
                            ComposerCollectionFilterMetrics.legacySearchResult,
                            value: 1,
                            tags: ComposerCollectionFilterMetrics.legacySearchResultTags(
                                itemCount: response.itemCount,
                                queryOutcome: queryOutcome,
                            ),
                        )
                        state.isLoadingFilters = true
                        state.isFilteringInFlight = true
                        let filtersRequestID = UUID()
                        let executionFilters = buildFilters(from: state)
                        state.activeFiltersRequestID = filtersRequestID
                        state.activeFiltersMetricSource = ComposerCollectionFilterMetrics.sourcePostQueryApply
                        state.filtersStartedAt = Date()
                        state.retargetScopeChangeFeedbackPending(
                            from: .search(requestID),
                            to: .filters(filtersRequestID),
                        )
                        let applyEffect: Effect<ComposerFeature.Action> = .run { send in
                            do {
                                let executionResponse = try await searchClient.applyFilters(
                                    .init(filters: executionFilters),
                                )
                                await send(.filtersResponse(filtersRequestID, .success(executionResponse)))
                            } catch is CancellationError {
                                return
                            } catch {
                                guard !Task.isCancelled else { return }
                                await send(.filtersResponse(filtersRequestID, .failure(error)))
                            }
                        }
                        .cancellable(id: ComposerFeature.CancelID.filters, cancelInFlight: true)

                        if queryOutcome == .fallbackReuse {
                            return .merge(
                                applyEffect,
                                presentTransientFeedback(
                                    kind: .info,
                                    message: ComposerQueryFeedbackPolicy.fallbackReuseMessage,
                                    state: &state,
                                    clock: clock,
                                ),
                            )
                        }
                        return applyEffect
                    }

                case let .failure(error):
                    state.isLoadingSearch = false
                    state.activeSearchRequestID = nil
                    state.resolveScopeChangeFeedback(.search(requestID), phase: .failed)
                    let feedbackEffect = presentTransientFeedback(
                        kind: .error,
                        message: feedbackFailureMessage(for: error),
                        state: &state,
                        clock: clock,
                    )
                    applyQueryPhaseTransition(.searchFailed, state: &state)
                    let baselineFilters = feedbackBaseline(from: state)
                    logSearchDurationIfNeeded(state.searchStartedAt, composerMetricClient: composerMetricClient)
                    composerMetricClient.logMetric(
                        ComposerCollectionFilterMetrics.queryResult,
                        value: 1,
                        tags: ComposerCollectionFilterMetrics.queryFailureTags(
                            reason: "conversion_error",
                            openedCollectionURL: state.openedCollectionURL,
                            filters: baselineFilters,
                        ),
                        level: .warn,
                    )
                    composerMetricClient.logMetric(
                        ComposerCollectionFilterMetrics.legacySearchResult,
                        value: 1,
                        tags: ComposerCollectionFilterMetrics.legacySearchFailureTags(),
                        level: .warn,
                    )
                    state.searchStartedAt = nil
                    kComposerSearchLifecycleLogger.warning(
                        "Composer query search failed: \(feedbackFailureMessage(for: error))",
                    )
                    return feedbackEffect
                }

            case let .internal(.filtersResponse(requestID, response)):
                guard state.activeFiltersRequestID == requestID else {
                    return .none
                }
                state.lastAcceptedFiltersRequestID = requestID
                switch response {
                case let .success(response):
                    state.isLoadingFilters = false
                    state.isFilteringInFlight = false
                    state.activeFiltersRequestID = nil
                    state.lastFiltersResponse = response
                    let metricSource = state.activeFiltersMetricSource ?? ComposerCollectionFilterMetrics
                        .sourceManualApply
                    state.activeFiltersMetricSource = nil
                    applyAppliedFilters(response.appliedFilters, state: &state, registryClient: registryClient)
                    state.scopeEditor.committedSelection = state.scopeEditor.selection
                    state.scopeEditor.committedIncludeSubfolders = state.scopeEditor.includeSubfolders
                    state.resolveScopeChangeFeedback(.filters(requestID), phase: .visible)
                    logFiltersDurationIfNeeded(state.filtersStartedAt, composerMetricClient: composerMetricClient)
                    composerMetricClient.logMetric(
                        ComposerCollectionFilterMetrics.applyResult,
                        value: 1,
                        tags: ComposerCollectionFilterMetrics.applyResultTags(
                            outcome: "applied",
                            source: metricSource,
                            openedCollectionURL: state.openedCollectionURL,
                            filters: buildFilters(from: state),
                            itemCount: response.itemCount,
                        ),
                    )
                    state.filtersStartedAt = nil
                    return .none

                case let .failure(error):
                    state.isLoadingFilters = false
                    state.isFilteringInFlight = false
                    state.activeFiltersRequestID = nil
                    let metricSource = state.activeFiltersMetricSource ?? ComposerCollectionFilterMetrics
                        .sourceManualApply
                    state.activeFiltersMetricSource = nil
                    logFiltersDurationIfNeeded(state.filtersStartedAt, composerMetricClient: composerMetricClient)
                    composerMetricClient.logMetric(
                        ComposerCollectionFilterMetrics.applyResult,
                        value: 1,
                        tags: ComposerCollectionFilterMetrics.applyResultTags(
                            outcome: "execution_failure",
                            source: metricSource,
                            openedCollectionURL: state.openedCollectionURL,
                            filters: buildFilters(from: state),
                            itemCount: nil,
                            reason: "execution_error",
                        ),
                        level: .warn,
                    )
                    state.filtersStartedAt = nil
                    state.resolveScopeChangeFeedback(.filters(requestID), phase: .failed)
                    applyQueryPhaseTransition(.reset, state: &state)
                    let feedbackEffect = presentTransientFeedback(
                        kind: .error,
                        message: feedbackFailureMessage(for: error),
                        state: &state,
                        clock: clock,
                    )
                    kComposerSearchLifecycleLogger.warning(
                        "Composer filter application failed: \(feedbackFailureMessage(for: error))",
                    )
                    return feedbackEffect
                }

            case .internal(.searchListApplied):
                applyQueryPhaseTransition(.listApplied, state: &state)
                return .none

            default:
                return .none
            }
        }
    }
}

private func handleSubmit(
    state: inout ComposerFeature.State,
    searchClient: SearchClient,
    composerMetricClient: ComposerMetricClient,
) -> Effect<ComposerFeature.Action> {
    let query = state.text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else { return .none }
    let filters = buildFilters(from: state)
    let searchRequestID = UUID()
    composerMetricClient.logMetric(
        ComposerCollectionFilterMetrics.legacyComposerSubmit,
        value: 1,
    )
    composerMetricClient.logMetric(
        ComposerCollectionFilterMetrics.legacySearchSubmit,
        value: 1,
    )
    if state.hasSubmittedInSession {
        composerMetricClient.logMetric(
            ComposerCollectionFilterMetrics.legacySearchResubmit,
            value: 1,
        )
    }
    state.hasSubmittedInSession = true
    state.searchStartedAt = Date()
    state.isLoadingSearch = true
    state.isLoadingFilters = false
    state.submittedSearchFilters = filters
    state.activeSearchRequestID = searchRequestID
    state.activeFiltersRequestID = nil
    state.activeFiltersMetricSource = nil
    state.lastAcceptedSearchRequestID = nil
    state.lastAcceptedFiltersRequestID = nil
    state.lastFiltersResponse = nil
    state.markScopeChangeFeedbackPending(.search(searchRequestID))
    applyQueryPhaseTransition(.startSearch, state: &state)
    state.text = ""

    let searchEffect: Effect<ComposerFeature.Action> = .run { send in
        do {
            let response = try await searchClient.search(
                .init(query: query, filters: filters),
            )
            await send(.searchResponse(searchRequestID, .success(response)))
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            await send(.searchResponse(searchRequestID, .failure(error)))
        }
    }
    .cancellable(id: ComposerFeature.CancelID.search, cancelInFlight: true)

    return .concatenate(
        .cancel(id: ComposerFeature.CancelID.filters),
        searchEffect,
    )
}

private func handleCancelSearch(
    state: inout ComposerFeature.State,
    composerMetricClient: ComposerMetricClient,
) -> Effect<ComposerFeature.Action> {
    let requestID = state.activeSearchRequestID
    state.isLoadingSearch = false
    state.activeSearchRequestID = nil
    if let requestID {
        state.resolveScopeChangeFeedback(.search(requestID), phase: .visible)
    }
    applyQueryPhaseTransition(.reset, state: &state)
    composerMetricClient.logMetric(
        ComposerCollectionFilterMetrics.legacySearchCancel,
        value: 1,
        tags: ComposerCollectionFilterMetrics.legacyCancelTags(type: "search"),
    )
    return .cancel(id: ComposerFeature.CancelID.search)
}

private func handleCancelFilters(
    state: inout ComposerFeature.State,
    composerMetricClient: ComposerMetricClient,
) -> Effect<ComposerFeature.Action> {
    let requestID = state.activeFiltersRequestID
    state.isLoadingFilters = false
    state.isFilteringInFlight = false
    state.activeFiltersRequestID = nil
    let metricSource = state.activeFiltersMetricSource ?? ComposerCollectionFilterMetrics.sourceManualApply
    state.activeFiltersMetricSource = nil
    state.pendingSearchQuery = nil
    if let requestID {
        state.resolveScopeChangeFeedback(.filters(requestID), phase: .visible)
    }
    applyQueryPhaseTransition(.reset, state: &state)
    composerMetricClient.logMetric(
        ComposerCollectionFilterMetrics.legacySearchCancel,
        value: 1,
        tags: ComposerCollectionFilterMetrics.legacyCancelTags(type: "filters"),
    )
    composerMetricClient.logMetric(
        ComposerCollectionFilterMetrics.applyResult,
        value: 1,
        tags: ComposerCollectionFilterMetrics.applyResultTags(
            outcome: "cancelled",
            source: metricSource,
            openedCollectionURL: state.openedCollectionURL,
            filters: buildFilters(from: state),
            itemCount: nil,
            reason: "none",
        ),
    )
    return .cancel(id: ComposerFeature.CancelID.filters)
}

private func handleApplyFilters(
    state: inout ComposerFeature.State,
    searchClient: SearchClient,
    composerMetricClient: ComposerMetricClient,
) -> Effect<ComposerFeature.Action> {
    state.isLoadingSearch = false
    let filtersRequestID = UUID()
    state.activeSearchRequestID = nil
    state.lastSearchResponse = nil
    state.isLoadingFilters = true
    state.isFilteringInFlight = true
    state.activeFiltersRequestID = filtersRequestID
    state.lastAcceptedFiltersRequestID = nil
    applyQueryPhaseTransition(.reset, state: &state)
    composerMetricClient.logMetric(
        ComposerCollectionFilterMetrics.legacyFiltersApply,
        value: 1,
    )
    state.filtersStartedAt = Date()
    return .concatenate(
        .cancel(id: ComposerFeature.CancelID.search),
        applyFiltersIfNeeded(state: &state, searchClient: searchClient, requestID: filtersRequestID),
    )
}
