import Foundation
import VoyagerShared

enum ComposerQueryFeedbackPolicy {
    static let conversionFailureMessage = "Couldn't interpret that query. Try being more specific."
    static let executionFailureMessage = "Couldn't complete that search. Please try again."

    static func failureMessage(for error: any Error) -> String {
        let code = parseErrorCode(from: error.localizedDescription)
        return code == "LLM_CONVERSION_FAILED" ? conversionFailureMessage : executionFailureMessage
    }

    static func normalizedFilters(
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

    static func isNoOp(
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
