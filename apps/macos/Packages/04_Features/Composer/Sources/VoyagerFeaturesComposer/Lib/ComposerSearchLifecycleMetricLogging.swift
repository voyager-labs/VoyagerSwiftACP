import ComposableArchitecture
import Foundation
import VoyagerShared

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
