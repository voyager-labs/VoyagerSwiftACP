import ComposableArchitecture
import Foundation

@Reducer
struct ComposerSearchLifecycleReducer {
    @Dependency(\.searchClient)
    var searchClient
    @Dependency(\.registryClient)
    var registryClient

    typealias State = ComposerState
    typealias Action = ComposerAction

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .view(.submit):
                return handleSubmit(state: &state, searchClient: searchClient)

            case .view(.cancelSearch):
                return handleCancelSearch(state: &state)

            case .view(.cancelFilters):
                return handleCancelFilters(state: &state)

            case .view(.applyFilters):
                return handleApplyFilters(state: &state, searchClient: searchClient)

            case let .internal(.searchResponse(response)):
                switch response {
                case let .success(response):
                    state.isLoadingSearch = false
                    state.lastSearchResponse = response
                    state.lastFiltersResponse = nil
                    applyQueryPhaseTransition(.searchSucceeded, state: &state)
                    applyAppliedFilters(response.appliedFilters, state: &state, registryClient: registryClient)
                    state.isLoadingFilters = true
                    state.isFilteringInFlight = true
                    state.filtersStartedAt = Date()
                    let executionFilters = buildFilters(from: state)
                    if let startedAt = state.searchStartedAt {
                        VoyagerSentryMetricLogger.logMetric(
                            "voyager_search_roundtrip_duration_ms",
                            value: round((Date().timeIntervalSince(startedAt)) * 1000),
                        )
                    }
                    VoyagerSentryMetricLogger.logMetric(
                        "voyager_search_result",
                        value: 1,
                        tags: ["result": response.itemCount > 0 ? "success" : "empty"],
                    )
                    state.searchStartedAt = nil
                    return .run { send in
                        do {
                            let executionResponse = try await searchClient.applyFilters(
                                .init(filters: executionFilters),
                            )
                            await send(.filtersResponse(.success(executionResponse)))
                        } catch {
                            await send(.filtersResponse(.failure(error)))
                        }
                    }
                    .cancellable(id: ComposerFeature.CancelID.filters, cancelInFlight: true)

                case .failure:
                    state.isLoadingSearch = false
                    applyQueryPhaseTransition(.searchFailed, state: &state)
                    VoyagerSentryMetricLogger.logMetric(
                        "voyager_search_result",
                        value: 1,
                        tags: ["result": "error"],
                        level: .warn,
                    )
                    state.searchStartedAt = nil
                    return .none
                }

            case let .internal(.filtersResponse(response)):
                switch response {
                case let .success(response):
                    state.isLoadingFilters = false
                    state.isFilteringInFlight = false
                    state.lastFiltersResponse = response
                    applyAppliedFilters(response.appliedFilters, state: &state, registryClient: registryClient)
                    if let startedAt = state.filtersStartedAt {
                        VoyagerSentryMetricLogger.logMetric(
                            "voyager_filters_roundtrip_duration_ms",
                            value: round((Date().timeIntervalSince(startedAt)) * 1000),
                        )
                    }
                    state.filtersStartedAt = nil
                    return .none

                case .failure:
                    state.isLoadingFilters = false
                    state.isFilteringInFlight = false
                    state.filtersStartedAt = nil
                    return .none
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
) -> Effect<ComposerFeature.Action> {
    let query = state.text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else { return .none }
    let filters = buildFilters(from: state)
    VoyagerSentryMetricLogger.logMetric(
        "voyager_composer_submit",
        value: 1,
    )
    VoyagerSentryMetricLogger.logMetric(
        "voyager_search_submit",
        value: 1,
    )
    if state.hasSubmittedInSession {
        VoyagerSentryMetricLogger.logMetric(
            "voyager_search_resubmit",
            value: 1,
        )
    }
    state.hasSubmittedInSession = true
    state.searchStartedAt = Date()
    state.isLoadingSearch = true
    state.isLoadingFilters = false
    state.lastFiltersResponse = nil
    applyQueryPhaseTransition(.startSearch, state: &state)
    state.text = ""

    let searchEffect: Effect<ComposerFeature.Action> = .run { send in
        do {
            let response = try await searchClient.search(
                .init(query: query, filters: filters),
            )
            await send(.searchResponse(.success(response)))
        } catch {
            await send(.searchResponse(.failure(error)))
        }
    }
    .cancellable(id: ComposerFeature.CancelID.search, cancelInFlight: true)

    return .concatenate(
        .cancel(id: ComposerFeature.CancelID.filters),
        searchEffect,
    )
}

private func handleCancelSearch(state: inout ComposerFeature.State) -> Effect<ComposerFeature.Action> {
    state.isLoadingSearch = false
    applyQueryPhaseTransition(.reset, state: &state)
    VoyagerSentryMetricLogger.logMetric(
        "voyager_search_cancel",
        value: 1,
        tags: ["type": "search"],
    )
    return .cancel(id: ComposerFeature.CancelID.search)
}

private func handleCancelFilters(state: inout ComposerFeature.State) -> Effect<ComposerFeature.Action> {
    state.isLoadingFilters = false
    state.isFilteringInFlight = false
    VoyagerSentryMetricLogger.logMetric(
        "voyager_search_cancel",
        value: 1,
        tags: ["type": "filters"],
    )
    return .cancel(id: ComposerFeature.CancelID.filters)
}

private func handleApplyFilters(
    state: inout ComposerFeature.State,
    searchClient: SearchClient,
) -> Effect<ComposerFeature.Action> {
    state.isLoadingSearch = false
    state.lastSearchResponse = nil
    state.isLoadingFilters = true
    state.isFilteringInFlight = true
    applyQueryPhaseTransition(.reset, state: &state)
    VoyagerSentryMetricLogger.logMetric(
        "voyager_composer_filters_apply",
        value: 1,
    )
    state.filtersStartedAt = Date()
    return .concatenate(
        .cancel(id: ComposerFeature.CancelID.search),
        applyFiltersIfNeeded(state: &state, searchClient: searchClient),
    )
}
