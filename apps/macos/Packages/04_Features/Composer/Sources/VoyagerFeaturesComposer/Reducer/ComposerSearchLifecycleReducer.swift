import ComposableArchitecture
import Foundation
import Logging
import VoyagerEntitiesAppPreferences
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
    @Dependency(\.uuid)
    var uuid
    @Dependency(\.continuousClock)
    var clock
    @Dependency(\.composerMetricClient)
    var composerMetricClient
    @Dependency(\.collectionSearchAISettingsClient)
    var collectionSearchAISettingsClient
    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .view(.submit):
                return handleSubmit(
                    state: &state,
                    searchClient: searchClient,
                    collectionSearchAISettingsClient: collectionSearchAISettingsClient,
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
                    if let error = response.error {
                        state.isLoadingSearch = false
                        state.activeSearchRequestID = nil
                        state.resolveScopeChangeFeedback(.search(requestID), phase: .failed)
                        let feedback = ComposerQueryFeedbackPolicy.feedback(for: response)
                        let failureMessage = ComposerQueryFeedbackPolicy.failureMessage(for: error)
                        let feedbackEffect = presentTransientFeedback(
                            kind: feedback?.kind ?? .error,
                            message: feedback?.message ?? failureMessage,
                            state: &state,
                            clock: clock,
                        )
                        applyQueryPhaseTransition(.searchFailed, state: &state)
                        let baselineFilters = feedbackBaseline(from: state)
                        logSearchDurationIfNeeded(state.searchStartedAt, composerMetricClient: composerMetricClient)
                        composerMetricClient.logMetric(
                            ComposerCollectionFilterMetrics.queryResult,
                            value: 1,
                            tags: ComposerCollectionFilterMetrics.queryResultTags(
                                queryConversion: response.queryConversion,
                                openedCollectionURL: state.openedCollectionURL,
                                filters: baselineFilters,
                                itemCount: response.itemCount,
                                reason: "conversion_error",
                            ),
                            level: .warn,
                        )
                        state.searchStartedAt = nil
                        kComposerSearchLifecycleLogger.warning(
                            "Composer query search returned error payload: \(feedback?.message ?? failureMessage)",
                        )
                        return feedbackEffect
                    }

                    let baselineFilters = feedbackBaseline(from: state)
                    let normalizedAppliedFilters = feedbackAppliedFilters(
                        appliedFilters: response.appliedFilters,
                        baseline: baselineFilters,
                    )
                    let shouldSkipApplyFilters = ComposerQueryFeedbackPolicy.shouldSkipApplyFilters(
                        response: response,
                        baseline: baselineFilters,
                    )
                    state.isLoadingSearch = false
                    state.activeSearchRequestID = nil
                    state.lastSearchResponse = response
                    state.lastFiltersResponse = nil
                    applyQueryPhaseTransition(.searchSucceeded, state: &state)
                    applyAppliedFilters(
                        normalizedAppliedFilters,
                        state: &state,
                        registryClient: registryClient,
                        uuid: { uuid() },
                    )
                    logSearchDurationIfNeeded(state.searchStartedAt, composerMetricClient: composerMetricClient)
                    logCollectionFilterQueryResult(
                        response: response,
                        queryConversion: response.queryConversion,
                        filters: feedbackFilters(from: normalizedAppliedFilters),
                        openedCollectionURL: state.openedCollectionURL,
                        composerMetricClient: composerMetricClient,
                    )
                    state.searchStartedAt = nil
                    if shouldSkipApplyFilters {
                        kComposerSearchLifecycleLogger.debug("Composer query search resolved to no-op filters")
                        state.isLoadingFilters = false
                        state.isFilteringInFlight = false
                        state.activeFiltersRequestID = nil
                        state.activeFiltersMetricSource = nil
                        state.filtersStartedAt = nil
                        state.pendingSearchQuery = nil
                        applyQueryPhaseTransition(.reset, state: &state)
                        state.resolveScopeChangeFeedback(.search(requestID), phase: .visible)
                        if let feedback = ComposerQueryFeedbackPolicy.feedback(for: response) {
                            return presentTransientFeedback(
                                kind: feedback.kind,
                                message: feedback.message,
                                state: &state,
                                clock: clock,
                            )
                        }
                        return .none
                    }
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
                    .cancellable(
                        id: ComposerFeature.CancelID.filters(ownerID: state.cancellationOwnerID),
                        cancelInFlight: true,
                    )

                    if let feedback = ComposerQueryFeedbackPolicy.feedback(for: response) {
                        return .merge(
                            applyEffect,
                            presentTransientFeedback(
                                kind: feedback.kind,
                                message: feedback.message,
                                state: &state,
                                clock: clock,
                            ),
                        )
                    }
                    return applyEffect

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
                    applyAppliedFilters(
                        response.appliedFilters,
                        state: &state,
                        registryClient: registryClient,
                        uuid: { uuid() },
                    )
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
                            filters: response.appliedFilters.map(feedbackFilters(from:)) ?? buildFilters(from: state),
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
                    let failedFilters = buildFilters(from: state)
                    logFiltersDurationIfNeeded(state.filtersStartedAt, composerMetricClient: composerMetricClient)
                    composerMetricClient.logMetric(
                        ComposerCollectionFilterMetrics.applyResult,
                        value: 1,
                        tags: ComposerCollectionFilterMetrics.applyResultTags(
                            outcome: "execution_failure",
                            source: metricSource,
                            openedCollectionURL: state.openedCollectionURL,
                            filters: failedFilters,
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
    collectionSearchAISettingsClient: CollectionSearchAISettingsClient,
    composerMetricClient: ComposerMetricClient,
) -> Effect<ComposerFeature.Action> {
    let query = state.text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else { return .none }
    let filters = buildFilters(from: state)
    let searchRequestID = UUID()
    logSubmitMetrics(
        hasSubmittedInSession: state.hasSubmittedInSession,
        composerMetricClient: composerMetricClient,
    )
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

    let request = makeSearchRequest(
        query: query,
        filters: filters,
        collectionSearchAISettingsClient: collectionSearchAISettingsClient,
    )
    let searchEffect: Effect<ComposerFeature.Action> = .run { send in
        do {
            let response = try await searchClient.search(request)
            await send(.searchResponse(searchRequestID, .success(response)))
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            await send(.searchResponse(searchRequestID, .failure(error)))
        }
    }
    .cancellable(id: ComposerFeature.CancelID.search(ownerID: state.cancellationOwnerID), cancelInFlight: true)

    return .concatenate(
        .cancel(id: ComposerFeature.CancelID.filters(ownerID: state.cancellationOwnerID)),
        searchEffect,
    )
}

private func logSubmitMetrics(
    hasSubmittedInSession: Bool,
    composerMetricClient: ComposerMetricClient,
) {
    composerMetricClient.logMetric(
        ComposerCollectionFilterMetrics.querySubmit,
        value: 1,
        tags: ["source": hasSubmittedInSession ? "resubmit" : "submit"],
    )
}

private func makeSearchRequest(
    query: String,
    filters: SearchFiltersPayload,
    collectionSearchAISettingsClient: CollectionSearchAISettingsClient,
) -> SearchRequestPayload {
    SearchRequestPayload(
        query: query,
        filters: filters,
        collectionSearchAISettings: collectionSearchAISettingsClient.load().payload,
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
        ComposerCollectionFilterMetrics.queryResult,
        value: 1,
        tags: ["result": "cancelled", "type": "search"],
    )
    return .cancel(id: ComposerFeature.CancelID.search(ownerID: state.cancellationOwnerID))
}

private func handleCancelFilters(
    state: inout ComposerFeature.State,
    composerMetricClient: ComposerMetricClient,
) -> Effect<ComposerFeature.Action> {
    let requestID = state.activeFiltersRequestID
    let metricSource = state.activeFiltersMetricSource ?? ComposerCollectionFilterMetrics.sourceManualApply
    let filters = buildFilters(from: state)
    state.isLoadingFilters = false
    state.isFilteringInFlight = false
    state.activeFiltersRequestID = nil
    state.activeFiltersMetricSource = nil
    state.pendingSearchQuery = nil
    if let requestID {
        state.resolveScopeChangeFeedback(.filters(requestID), phase: .visible)
    }
    applyQueryPhaseTransition(.reset, state: &state)
    composerMetricClient.logMetric(
        ComposerCollectionFilterMetrics.applyResult,
        value: 1,
        tags: ComposerCollectionFilterMetrics.applyResultTags(
            outcome: "cancelled",
            source: metricSource,
            openedCollectionURL: state.openedCollectionURL,
            filters: filters,
            itemCount: nil,
        ),
    )
    return .cancel(id: ComposerFeature.CancelID.filters(ownerID: state.cancellationOwnerID))
}

private func handleApplyFilters(
    state: inout ComposerFeature.State,
    searchClient: SearchClient,
    composerMetricClient _: ComposerMetricClient,
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
    state.filtersStartedAt = Date()
    return .concatenate(
        .cancel(id: ComposerFeature.CancelID.search(ownerID: state.cancellationOwnerID)),
        applyFiltersIfNeeded(state: &state, searchClient: searchClient, requestID: filtersRequestID),
    )
}
