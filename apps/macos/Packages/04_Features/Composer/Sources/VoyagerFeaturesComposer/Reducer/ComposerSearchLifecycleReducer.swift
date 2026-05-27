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
                return handleSubmit(state: &state, searchClient: searchClient, composerMetricClient: composerMetricClient)

            case .view(.cancelSearch):
                return handleCancelSearch(state: &state, composerMetricClient: composerMetricClient)

            case .view(.cancelFilters):
                return handleCancelFilters(state: &state, composerMetricClient: composerMetricClient)

            case .view(.applyFilters):
                return handleApplyFilters(state: &state, searchClient: searchClient, composerMetricClient: composerMetricClient)

            case let .internal(.searchResponse(requestID, response)):
                guard state.activeSearchRequestID == requestID else {
                    return .none
                }
                state.lastAcceptedSearchRequestID = requestID
                switch response {
                case let .success(response):
                    let baselineFilters = feedbackBaseline(from: state)
                    let normalizedAppliedFilters = feedbackAppliedFilters(
                        appliedFilters: response.appliedFilters,
                        baseline: baselineFilters
                    )
                    let isNoOpResponse = ComposerQueryFeedbackPolicy.isNoOp(
                        baseline: baselineFilters,
                        appliedFilters: response.appliedFilters
                    )
                    state.isLoadingSearch = false
                    state.activeSearchRequestID = nil
                    state.lastSearchResponse = response
                    state.lastFiltersResponse = nil
                    applyQueryPhaseTransition(.searchSucceeded, state: &state)
                    applyAppliedFilters(normalizedAppliedFilters, state: &state, registryClient: registryClient)
                    if let startedAt = state.searchStartedAt {
                        composerMetricClient.logMetric(
                            "voyager_search_roundtrip_duration_ms",
                            value: round((Date().timeIntervalSince(startedAt)) * 1000)
                        )
                    }
                    composerMetricClient.logMetric(
                        "voyager_search_result",
                        value: 1,
                        tags: ["result": response.itemCount > 0 ? "success" : "empty"]
                    )
                    state.searchStartedAt = nil
                    if isNoOpResponse, state.openedCollectionURL == nil {
                        kComposerSearchLifecycleLogger.debug("Composer query search resolved to no-op filters")
                        state.isLoadingFilters = false
                        state.isFilteringInFlight = false
                        state.activeFiltersRequestID = nil
                        state.filtersStartedAt = nil
                        state.pendingSearchQuery = nil
                        applyQueryPhaseTransition(.reset, state: &state)
                        state.resolveScopeChangeFeedback(.search(requestID), phase: .visible)
                        return .none
                    }
                    state.isLoadingFilters = true
                    state.isFilteringInFlight = true
                    let filtersRequestID = UUID()
                    let executionFilters = buildFilters(from: state)
                    state.activeFiltersRequestID = filtersRequestID
                    state.filtersStartedAt = Date()
                    state.retargetScopeChangeFeedbackPending(
                        from: .search(requestID),
                        to: .filters(filtersRequestID),
                    )
                    return .run { send in
                        do {
                            let executionResponse = try await searchClient.applyFilters(
                                .init(filters: executionFilters)
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

                case let .failure(error):
                    state.isLoadingSearch = false
                    state.activeSearchRequestID = nil
                    state.resolveScopeChangeFeedback(.search(requestID), phase: .failed)
                    let feedbackEffect = presentTransientFeedback(
                        kind: .error,
                        message: feedbackFailureMessage(for: error),
                        state: &state,
                        clock: clock
                    )
                    applyQueryPhaseTransition(.searchFailed, state: &state)
                    composerMetricClient.logMetric(
                        "voyager_search_result",
                        value: 1,
                        tags: ["result": "error"],
                        level: .warn
                    )
                    state.searchStartedAt = nil
                    kComposerSearchLifecycleLogger.warning(
                        "Composer query search failed: \(feedbackFailureMessage(for: error))"
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
                    applyAppliedFilters(response.appliedFilters, state: &state, registryClient: registryClient)
                    state.scopeEditor.committedSelection = state.scopeEditor.selection
                    state.scopeEditor.committedIncludeSubfolders = state.scopeEditor.includeSubfolders
                    state.resolveScopeChangeFeedback(.filters(requestID), phase: .visible)
                    if let startedAt = state.filtersStartedAt {
                        composerMetricClient.logMetric(
                            "voyager_filters_roundtrip_duration_ms",
                            value: round((Date().timeIntervalSince(startedAt)) * 1000)
                        )
                    }
                    state.filtersStartedAt = nil
                    return .none

                case let .failure(error):
                    state.isLoadingFilters = false
                    state.isFilteringInFlight = false
                    state.activeFiltersRequestID = nil
                    state.filtersStartedAt = nil
                    state.resolveScopeChangeFeedback(.filters(requestID), phase: .failed)
                    applyQueryPhaseTransition(.reset, state: &state)
                    let feedbackEffect = presentTransientFeedback(
                        kind: .error,
                        message: feedbackFailureMessage(for: error),
                        state: &state,
                        clock: clock
                    )
                    kComposerSearchLifecycleLogger.warning(
                        "Composer filter application failed: \(feedbackFailureMessage(for: error))"
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
    composerMetricClient: ComposerMetricClient
) -> Effect<ComposerFeature.Action> {
    let query = state.text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else { return .none }
    let filters = buildFilters(from: state)
    let searchRequestID = UUID()
    composerMetricClient.logMetric(
        "voyager_composer_submit",
        value: 1
    )
    composerMetricClient.logMetric(
        "voyager_search_submit",
        value: 1
    )
    if state.hasSubmittedInSession {
        composerMetricClient.logMetric(
            "voyager_search_resubmit",
            value: 1
        )
    }
    state.hasSubmittedInSession = true
    state.searchStartedAt = Date()
    state.isLoadingSearch = true
    state.isLoadingFilters = false
    state.submittedSearchFilters = filters
    state.activeSearchRequestID = searchRequestID
    state.activeFiltersRequestID = nil
    state.lastAcceptedSearchRequestID = nil
    state.lastAcceptedFiltersRequestID = nil
    state.lastFiltersResponse = nil
    state.markScopeChangeFeedbackPending(.search(searchRequestID))
    applyQueryPhaseTransition(.startSearch, state: &state)
    state.text = ""

    let searchEffect: Effect<ComposerFeature.Action> = .run { send in
        do {
            let response = try await searchClient.search(
                .init(query: query, filters: filters)
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
        searchEffect
    )
}

private func handleCancelSearch(
    state: inout ComposerFeature.State,
    composerMetricClient: ComposerMetricClient
) -> Effect<ComposerFeature.Action> {
    let requestID = state.activeSearchRequestID
    state.isLoadingSearch = false
    state.activeSearchRequestID = nil
    if let requestID {
        state.resolveScopeChangeFeedback(.search(requestID), phase: .visible)
    }
    applyQueryPhaseTransition(.reset, state: &state)
    composerMetricClient.logMetric(
        "voyager_search_cancel",
        value: 1,
        tags: ["type": "search"]
    )
    return .cancel(id: ComposerFeature.CancelID.search)
}

private func handleCancelFilters(
    state: inout ComposerFeature.State,
    composerMetricClient: ComposerMetricClient
) -> Effect<ComposerFeature.Action> {
    let requestID = state.activeFiltersRequestID
    state.isLoadingFilters = false
    state.isFilteringInFlight = false
    state.activeFiltersRequestID = nil
    state.pendingSearchQuery = nil
    if let requestID {
        state.resolveScopeChangeFeedback(.filters(requestID), phase: .visible)
    }
    applyQueryPhaseTransition(.reset, state: &state)
    composerMetricClient.logMetric(
        "voyager_search_cancel",
        value: 1,
        tags: ["type": "filters"]
    )
    return .cancel(id: ComposerFeature.CancelID.filters)
}

private func handleApplyFilters(
    state: inout ComposerFeature.State,
    searchClient: SearchClient,
    composerMetricClient: ComposerMetricClient
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
        "voyager_composer_filters_apply",
        value: 1
    )
    state.filtersStartedAt = Date()
    return .concatenate(
        .cancel(id: ComposerFeature.CancelID.search),
        applyFiltersIfNeeded(state: &state, searchClient: searchClient, requestID: filtersRequestID)
    )
}

private func feedbackBaseline(from state: ComposerFeature.State) -> VoyagerShared.SearchFiltersPayload {
    state.submittedSearchFilters ?? VoyagerShared.SearchFiltersPayload(
        scopes: state.scopeEditor.selection.legacyScopePaths,
        excludedScopes: state.scopeEditor.selection.exceptions.map(\.path),
        includeSubfolders: state.scopeEditor.effectiveIncludeSubfolders,
        conditions: buildFilters(from: state).conditions,
    )
}

private func feedbackAppliedFilters(
    appliedFilters: VoyagerShared.AppliedFiltersPayload?,
    baseline: VoyagerShared.SearchFiltersPayload
) -> VoyagerShared.AppliedFiltersPayload {
    let normalizedFilters = ComposerQueryFeedbackPolicy.normalizedFilters(
        appliedFilters: appliedFilters,
        fallback: baseline
    )
    return VoyagerShared.AppliedFiltersPayload(
        scopes: normalizedFilters.scopes,
        excludedScopes: normalizedFilters.excludedScopes,
        includeSubfolders: normalizedFilters.includeSubfolders,
        conditions: normalizedFilters.conditions,
    )
}

private func feedbackFailureMessage(for error: any Error) -> String {
    ComposerQueryFeedbackPolicy.failureMessage(for: error)
}

private func presentTransientFeedback(
    kind: ComposerTransientFeedbackKind,
    message: String,
    state: inout ComposerFeature.State,
    clock: any Clock<Duration>
) -> Effect<ComposerFeature.Action> {
    if let currentFeedback = state.transientFeedback,
       currentFeedback.kind == kind,
       currentFeedback.message == message
    {
        return .none
    }

    let feedback = ComposerTransientFeedback(
        id: UUID(),
        kind: kind,
        message: message
    )
    state.transientFeedback = feedback

    return .concatenate(
        .cancel(id: ComposerFeature.CancelID.feedbackDismiss),
        .run { send in
            try await clock.sleep(for: .seconds(4))
            await send(.dismissTransientFeedback(id: feedback.id))
        }
        .cancellable(id: ComposerFeature.CancelID.feedbackDismiss, cancelInFlight: true)
    )
}
