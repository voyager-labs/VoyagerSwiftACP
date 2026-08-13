import ComposableArchitecture
import Foundation
import VoyagerShared

func logSearchDurationIfNeeded(
    _ startedAt: Date?,
    composerMetricClient: ComposerMetricClient,
) {
    guard let startedAt else { return }
    let duration = round((Date().timeIntervalSince(startedAt)) * 1000)
    composerMetricClient.logMetric(
        ComposerCollectionFilterMetrics.legacySearchDuration,
        value: duration,
    )
    composerMetricClient.logMetric(
        ComposerCollectionFilterMetrics.queryDuration,
        value: duration,
    )
}

func logFiltersDurationIfNeeded(
    _ startedAt: Date?,
    composerMetricClient: ComposerMetricClient,
) {
    guard let startedAt else { return }
    let duration = round((Date().timeIntervalSince(startedAt)) * 1000)
    composerMetricClient.logMetric(
        ComposerCollectionFilterMetrics.legacyApplyDuration,
        value: duration,
    )
    composerMetricClient.logMetric(
        ComposerCollectionFilterMetrics.applyDuration,
        value: duration,
    )
}

func logCollectionFilterQueryResult(
    response: SearchResponsePayload,
    queryConversion: SearchQueryConversionMetadataPayload?,
    filters: SearchFiltersPayload,
    openedCollectionURL: URL?,
    composerMetricClient: ComposerMetricClient,
) {
    composerMetricClient.logMetric(
        ComposerCollectionFilterMetrics.queryResult,
        value: 1,
        tags: ComposerCollectionFilterMetrics.queryResultTags(
            queryConversion: queryConversion,
            openedCollectionURL: openedCollectionURL,
            filters: filters,
            itemCount: response.itemCount,
        ),
    )
}

func feedbackFilters(from appliedFilters: VoyagerShared.AppliedFiltersPayload) -> VoyagerShared
    .SearchFiltersPayload
{
    VoyagerShared.SearchFiltersPayload(
        scopes: appliedFilters.scopes ?? [],
        excludedScopes: appliedFilters.excludedScopes,
        includeSubfolders: appliedFilters.includeSubfolders ?? true,
        conditions: appliedFilters.conditions ?? [],
    )
}

func feedbackBaseline(from state: ComposerFeature.State) -> VoyagerShared.SearchFiltersPayload {
    if let submittedSearchFilters = state.submittedSearchFilters {
        return submittedSearchFilters
    }
    return buildFilters(from: state)
}

func feedbackAppliedFilters(
    appliedFilters: VoyagerShared.AppliedFiltersPayload?,
    baseline: VoyagerShared.SearchFiltersPayload,
) -> VoyagerShared.AppliedFiltersPayload {
    let normalizedFilters = ComposerQueryFeedbackPolicy.normalizedFilters(
        appliedFilters: appliedFilters,
        fallback: baseline,
    )
    return VoyagerShared.AppliedFiltersPayload(
        scopes: normalizedFilters.scopes,
        excludedScopes: normalizedFilters.excludedScopes,
        includeSubfolders: normalizedFilters.includeSubfolders,
        conditions: normalizedFilters.conditions,
    )
}

func feedbackFailureMessage(for error: any Error) -> String {
    ComposerQueryFeedbackPolicy.failureMessage(for: error)
}

func presentTransientFeedback(
    kind: ComposerTransientFeedbackKind,
    message: String,
    state: inout ComposerFeature.State,
    clock: any Clock<Duration>,
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
        message: message,
    )
    state.transientFeedback = feedback
    let feedbackDismissID = ComposerFeature.CancelID.feedbackDismiss(ownerID: state.cancellationOwnerID)

    return .concatenate(
        .cancel(id: feedbackDismissID),
        .run { send in
            try await clock.sleep(for: .seconds(4))
            await send(.dismissTransientFeedback(id: feedback.id))
        }
        .cancellable(id: feedbackDismissID, cancelInFlight: true),
    )
}
