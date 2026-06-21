import Foundation
import VoyagerEntitiesCollection
import VoyagerShared

public enum ComposerQueryFeedbackPolicy {
    public static let conversionFailureMessage = "Couldn't interpret that query. Try being more specific."
    public static let executionFailureMessage = "Couldn't complete that search. Please try again."
    public static let providerNotConfiguredMessage =
        "Connect an AI provider in Settings to use natural-language search."
    public static let invalidCredentialMessage =
        "Reconnect your AI provider in Settings, then try again."
    public static let providerUnavailableMessage =
        "AI provider is unavailable. Check the connection and try again."
    public static let fallbackReuseMessage =
        "No new filters were generated. Refine the query and try again."

    public static func failureMessage(for error: any Error) -> String {
        let code = parseErrorCode(from: error.localizedDescription)
        return code == "LLM_CONVERSION_FAILED" ? conversionFailureMessage : executionFailureMessage
    }

    public static func failureMessage(for error: VoyagerShared.SearchErrorPayload) -> String {
        error.code == "LLM_CONVERSION_FAILED" ? conversionFailureMessage : executionFailureMessage
    }

    public static func feedback(
        for response: VoyagerShared.SearchResponsePayload,
    ) -> (kind: ComposerTransientFeedbackKind, message: String)? {
        if let error = response.error {
            return feedback(for: response.queryConversion?.outcome, error: error)
        }

        if response.queryConversion?.outcome == .fallbackReuse {
            return (.info, fallbackReuseMessage)
        }

        return nil
    }

    public static func feedback(
        for outcome: VoyagerShared.SearchQueryConversionOutcomePayload?,
        error: VoyagerShared.SearchErrorPayload,
    ) -> (kind: ComposerTransientFeedbackKind, message: String)? {
        switch outcome {
        case .providerNotConfigured:
            (.error, providerNotConfiguredMessage)
        case .invalidCredential:
            (.error, invalidCredentialMessage)
        case .providerUnavailable, .networkFailure:
            (.error, providerUnavailableMessage)
        case .fallbackReuse:
            (.info, fallbackReuseMessage)
        case .unchangedResult:
            nil
        case .generatedChangeSet:
            nil
        case .conversionFailure, nil:
            (
                .error,
                error.code == "LLM_CONVERSION_FAILED" ? conversionFailureMessage : executionFailureMessage,
            )
        }
    }

    public static func shouldSkipApplyFilters(
        response: VoyagerShared.SearchResponsePayload,
        baseline: VoyagerShared.SearchFiltersPayload,
    ) -> Bool {
        if let outcome = response.queryConversion?.outcome {
            switch outcome {
            case .generatedChangeSet:
                return normalizedFilters(appliedFilters: response.appliedFilters, fallback: baseline).conditions.isEmpty
            case .unchangedResult:
                return true
            case .fallbackReuse:
                return normalizedFilters(appliedFilters: response.appliedFilters, fallback: baseline) == baseline
            case .providerNotConfigured,
                 .invalidCredential,
                 .providerUnavailable,
                 .networkFailure,
                 .conversionFailure:
                return false
            }
        }

        return isNoOp(baseline: baseline, appliedFilters: response.appliedFilters)
    }

    public static func normalizedFilters(
        appliedFilters: VoyagerShared.AppliedFiltersPayload?,
        fallback baseline: VoyagerShared.SearchFiltersPayload,
    ) -> VoyagerShared.SearchFiltersPayload {
        let excludedScopes = normalizedExcludedScopes(appliedFilters: appliedFilters, fallback: baseline)
        return VoyagerShared.SearchFiltersPayload(
            scopes: appliedFilters?.scopes ?? baseline.scopes,
            excludedScopes: excludedScopes,
            includeSubfolders: appliedFilters?.includeSubfolders ?? baseline.includeSubfolders,
            conditions: appliedFilters?.conditions ?? baseline.conditions,
        )
    }

    public static func isNoOp(
        baseline: VoyagerShared.SearchFiltersPayload,
        appliedFilters: VoyagerShared.AppliedFiltersPayload?,
    ) -> Bool {
        normalizedFilters(appliedFilters: appliedFilters, fallback: baseline) == baseline
    }

    private static func parseErrorCode(from localizedDescription: String) -> String {
        localizedDescription
            .split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            .first
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            ?? localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizedExcludedScopes(
        appliedFilters: VoyagerShared.AppliedFiltersPayload?,
        fallback baseline: VoyagerShared.SearchFiltersPayload,
    ) -> [String] {
        guard let appliedFilters else {
            return baseline.excludedScopes
        }
        if appliedFilters.excludedScopes.isEmpty, !baseline.excludedScopes.isEmpty {
            return baseline.excludedScopes
        }
        return appliedFilters.excludedScopes
    }
}
