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
                    restoreQueryOwnedFilters: { state in
                        guard state.activeFiltersMetricSource == ComposerCollectionFilterMetrics.sourcePostQueryApply
                        else { return }
                        restoreSubmittedSearchFilters(
                            state: &state,
                            registryClient: registryClient,
                            uuid: { uuid() },
                        )
                    },
                    composerMetricClient: composerMetricClient,
                )

            case .view(.cancelSearch):
                return handleCancelSearch(state: &state, composerMetricClient: composerMetricClient)

            case .view(.cancelFilters):
                return handleCancelFilters(
                    state: &state,
                    registryClient: registryClient,
                    uuid: { uuid() },
                    composerMetricClient: composerMetricClient,
                )

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
                        state.restoreQueryRecoveryIfEligible(for: .search(requestID))
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
                    state.lastFiltersResponseDefinitionFingerprint = nil
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
                        // no-op filters: 제출 쿼리를 collection draft 정의에 반영해 저장 계약을 유지한다.
                        // 제출 뒤 사용자 입력으로 revision이 바뀌었다면 최신 편집이 우선하므로
                        // canonical draft와 pending state를 덮지 않는다.
                        if let submittedQuery = state.uneditedQueryRecoveryRawText(for: .search(requestID)) {
                            let trimmedQuery = submittedQuery.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !trimmedQuery.isEmpty {
                                let existingContext = state.collectionContext
                                var nextContext = state.collectionContext(query: trimmedQuery)
                                if existingContext?.scopes.isEmpty == true, state.isSemanticallyRootOnly {
                                    nextContext.scopes = []
                                }
                                state.collectionContext = nextContext
                            }
                            state.pendingSearchQuery = nil
                        }
                        state.discardQueryRecovery()
                        kComposerSearchLifecycleLogger.debug("Composer query search resolved to no-op filters")
                        state.isLoadingFilters = false
                        state.isFilteringInFlight = false
                        state.activeFiltersRequestID = nil
                        state.activeFiltersRequestQuery = nil
                        state.activeFiltersMetricSource = nil
                        state.filtersStartedAt = nil
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
                    state.activeFiltersRequestQuery = state.queryRecoveryRawText(for: .search(requestID))
                        ?? state.pendingSearchQuery
                        ?? state.collectionContext?.query
                        ?? ""
                    state.retargetQueryRecovery(from: requestID, to: filtersRequestID)
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
                    state.restoreQueryRecoveryIfEligible(for: .search(requestID))
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
                switch response {
                case let .success(response):
                    if let error = response.error {
                        return handleFiltersFailure(
                            requestID: requestID,
                            message: ComposerQueryFeedbackPolicy.failureMessage(for: error),
                            state: &state,
                            dependencies: .init(
                                registryClient: registryClient,
                                uuid: { uuid() },
                                clock: clock,
                                composerMetricClient: composerMetricClient,
                            ),
                        )
                    }
                    let responseQuery = state.activeFiltersRequestQuery
                        ?? state.queryRecoveryRawText(for: .filters(requestID))
                        ?? state.pendingSearchQuery
                        ?? state.collectionContext?.query
                        ?? ""
                    if let submittedQuery = state.uneditedQueryRecoveryRawText(for: .filters(requestID)) {
                        let trimmedQuery = submittedQuery.trimmingCharacters(in: .whitespacesAndNewlines)
                        state.pendingSearchQuery = trimmedQuery.isEmpty ? nil : trimmedQuery
                    }
                    state.discardQueryRecovery()
                    state.lastAcceptedFiltersRequestID = requestID
                    state.lastFailedFiltersRequestID = nil
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
                    state.lastFiltersResponseDefinitionFingerprint = CollectionSnapshotHydration.definitionFingerprint(
                        query: responseQuery,
                        scopes: state.scopes,
                        excludedScopes: state.scopeEditor.selection.exceptions.map(\.path),
                        includeSubfolders: state.scopeEditor.effectiveIncludeSubfolders,
                        includeDirectories: state.includeDirectories,
                        conditions: state.conditions,
                    )
                    state.activeFiltersRequestQuery = nil
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
                    return handleFiltersFailure(
                        requestID: requestID,
                        message: feedbackFailureMessage(for: error),
                        state: &state,
                        dependencies: .init(
                            registryClient: registryClient,
                            uuid: { uuid() },
                            clock: clock,
                            composerMetricClient: composerMetricClient,
                        ),
                    )
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
    restoreQueryOwnedFilters: (inout ComposerFeature.State) -> Void,
    composerMetricClient: ComposerMetricClient,
) -> Effect<ComposerFeature.Action> {
    let query = state.text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else { return .none }
    restoreQueryOwnedFilters(&state)
    let filters = buildFilters(from: state)
    let searchRequestID = UUID()
    state.captureQueryRecovery(rawText: state.text, requestID: searchRequestID)
    logSubmitMetrics(
        hasSubmittedInSession: state.hasSubmittedInSession,
        composerMetricClient: composerMetricClient,
    )
    state.hasSubmittedInSession = true
    state.searchStartedAt = Date()
    state.isLoadingSearch = true
    state.isLoadingFilters = false
    state.isFilteringInFlight = false
    state.submittedSearchFilters = filters
    state.activeSearchRequestID = searchRequestID
    state.activeFiltersRequestID = nil
    state.activeFiltersRequestQuery = nil
    state.activeFiltersMetricSource = nil
    state.filtersStartedAt = nil
    state.lastFailedFiltersRequestID = nil
    state.lastAcceptedSearchRequestID = nil
    state.lastAcceptedFiltersRequestID = nil
    state.lastFiltersResponse = nil
    state.lastFiltersResponseDefinitionFingerprint = nil
    state.markScopeChangeFeedbackPending(.search(searchRequestID))
    applyQueryPhaseTransition(.startSearch, state: &state)
    state.clearTextForSubmit()

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
    state.activeFiltersRequestQuery = nil
    if let requestID {
        state.restoreQueryRecoveryIfEligible(for: .search(requestID))
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
    registryClient: RegistryClient,
    uuid: () -> UUID,
    composerMetricClient: ComposerMetricClient,
) -> Effect<ComposerFeature.Action> {
    let requestID = state.activeFiltersRequestID
    let metricSource = state.activeFiltersMetricSource ?? ComposerCollectionFilterMetrics.sourceManualApply
    let filters = buildFilters(from: state)
    if metricSource == ComposerCollectionFilterMetrics.sourcePostQueryApply {
        restoreSubmittedSearchFilters(
            state: &state,
            registryClient: registryClient,
            uuid: uuid,
        )
    }
    state.isLoadingFilters = false
    state.isFilteringInFlight = false
    state.activeFiltersRequestID = nil
    state.activeFiltersRequestQuery = nil
    state.activeFiltersMetricSource = nil
    state.lastFailedFiltersRequestID = nil
    state.pendingSearchQuery = nil
    if let requestID {
        if metricSource == ComposerCollectionFilterMetrics.sourcePostQueryApply {
            state.restoreQueryRecoveryIfEligible(for: .filters(requestID))
        } else {
            state.discardQueryRecovery()
        }
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

private func restoreSubmittedSearchFilters(
    state: inout ComposerFeature.State,
    registryClient: RegistryClient,
    uuid: () -> UUID,
) {
    guard let submittedSearchFilters = state.submittedSearchFilters else { return }
    applyAppliedFilters(
        .init(
            scopes: submittedSearchFilters.scopes,
            excludedScopes: submittedSearchFilters.excludedScopes,
            includeSubfolders: submittedSearchFilters.includeSubfolders,
            conditions: submittedSearchFilters.conditions,
        ),
        state: &state,
        registryClient: registryClient,
        uuid: uuid,
        preserveLocalMultiScope: false,
    )
}

private func handleApplyFilters(
    state: inout ComposerFeature.State,
    searchClient: SearchClient,
    composerMetricClient _: ComposerMetricClient,
) -> Effect<ComposerFeature.Action> {
    state.discardQueryRecovery()
    state.isLoadingSearch = false
    let filtersRequestID = UUID()
    state.activeSearchRequestID = nil
    state.lastSearchResponse = nil
    state.isLoadingFilters = true
    state.isFilteringInFlight = true
    state.activeFiltersRequestID = filtersRequestID
    state.activeFiltersRequestQuery = nil
    state.lastAcceptedFiltersRequestID = nil
    state.lastFailedFiltersRequestID = nil
    applyQueryPhaseTransition(.reset, state: &state)
    state.filtersStartedAt = Date()
    return .concatenate(
        .cancel(id: ComposerFeature.CancelID.search(ownerID: state.cancellationOwnerID)),
        applyFiltersIfNeeded(state: &state, searchClient: searchClient, requestID: filtersRequestID),
    )
}

private struct FilterFailureDependencies {
    let registryClient: RegistryClient
    let uuid: () -> UUID
    let clock: any Clock<Duration>
    let composerMetricClient: ComposerMetricClient
}

private func handleFiltersFailure(
    requestID: UUID,
    message: String,
    state: inout ComposerSearchLifecycleReducer.State,
    dependencies: FilterFailureDependencies,
) -> Effect<ComposerSearchLifecycleReducer.Action> {
    let metricSource = state.activeFiltersMetricSource ?? ComposerCollectionFilterMetrics.sourceManualApply
    let failedFilters = buildFilters(from: state)
    if metricSource == ComposerCollectionFilterMetrics.sourcePostQueryApply {
        restoreSubmittedSearchFilters(
            state: &state,
            registryClient: dependencies.registryClient,
            uuid: dependencies.uuid,
        )
    }
    state.restoreQueryRecoveryIfEligible(for: .filters(requestID))
    state.isLoadingFilters = false
    state.isFilteringInFlight = false
    state.activeFiltersRequestID = nil
    state.activeFiltersRequestQuery = nil
    state.lastFailedFiltersRequestID = requestID
    state.activeFiltersMetricSource = nil
    logFiltersDurationIfNeeded(
        state.filtersStartedAt,
        composerMetricClient: dependencies.composerMetricClient,
    )
    dependencies.composerMetricClient.logMetric(
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
    kComposerSearchLifecycleLogger.warning("Composer filter application failed: \(message)")
    return presentTransientFeedback(
        kind: .error,
        message: message,
        state: &state,
        clock: dependencies.clock,
    )
}
