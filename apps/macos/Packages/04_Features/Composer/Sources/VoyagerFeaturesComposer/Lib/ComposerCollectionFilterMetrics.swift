import Foundation
import VoyagerShared

enum ComposerCollectionFilterMetrics {
    private struct TagsInput {
        let stage: String
        let outcome: String
        let reason: String
        let source: String
        let openedCollectionURL: URL?
        let filters: SearchFiltersPayload
        let itemCount: Int?
    }

    static let legacyComposerSubmit = "voyager_composer_submit"
    static let legacySearchSubmit = "voyager_search_submit"
    static let legacySearchResubmit = "voyager_search_resubmit"
    static let legacySearchResult = "voyager_search_result"
    static let legacySearchCancel = "voyager_search_cancel"
    static let legacyFiltersApply = "voyager_composer_filters_apply"
    static let legacySearchDuration = "voyager_search_roundtrip_duration_ms"
    static let legacyApplyDuration = "voyager_filters_roundtrip_duration_ms"

    static let queryResult = "voyager_collection_filter_query_result"
    static let applyResult = "voyager_collection_filter_apply_result"
    static let queryDuration = "voyager_collection_filter_query_duration_ms"
    static let applyDuration = "voyager_collection_filter_apply_duration_ms"

    static let sourcePostQueryApply = "post_query_apply"
    static let sourceManualApply = "manual_apply"

    static func legacySearchResultTags(
        itemCount: Int,
        queryOutcome: SearchQueryOutcome?,
    ) -> [String: String] {
        [
            "result": itemCount > 0 ? "success" : "empty",
            "query_outcome": queryOutcomeTag(queryOutcome),
        ]
    }

    static func legacySearchFailureTags() -> [String: String] {
        ["result": "error"]
    }

    static func legacyCancelTags(type: String) -> [String: String] {
        ["type": type]
    }

    static func queryResultTags(
        outcome: SearchQueryOutcome?,
        openedCollectionURL: URL?,
        filters: SearchFiltersPayload,
        itemCount: Int,
        reason: String = "none",
    ) -> [String: String] {
        commonTags(
            TagsInput(
                stage: "query",
                outcome: queryOutcomeTag(outcome),
                reason: reason,
                source: "query_submit",
                openedCollectionURL: openedCollectionURL,
                filters: filters,
                itemCount: itemCount,
            ),
        )
    }

    static func queryFailureTags(
        reason: String,
        openedCollectionURL: URL?,
        filters: SearchFiltersPayload,
    ) -> [String: String] {
        commonTags(
            TagsInput(
                stage: "query",
                outcome: "conversion_failure",
                reason: reason,
                source: "query_submit",
                openedCollectionURL: openedCollectionURL,
                filters: filters,
                itemCount: nil,
            ),
        )
    }

    static func applyResultTags(
        outcome: String,
        source: String,
        openedCollectionURL: URL?,
        filters: SearchFiltersPayload,
        itemCount: Int?,
        reason: String = "none",
    ) -> [String: String] {
        commonTags(
            TagsInput(
                stage: "apply",
                outcome: outcome,
                reason: reason,
                source: source,
                openedCollectionURL: openedCollectionURL,
                filters: filters,
                itemCount: itemCount,
            ),
        )
    }

    private static func commonTags(_ input: TagsInput) -> [String: String] {
        [
            "stage": input.stage,
            "outcome": input.outcome,
            "reason": input.reason,
            "source": input.source,
            "opened_collection": input.openedCollectionURL == nil ? "false" : "true",
            "result_set": resultSetBucket(input.itemCount),
            "condition_count_bucket": countBucket(input.filters.conditions.count),
            "scope_count_bucket": countBucket(input.filters.scopes.count),
            "has_excluded_scopes": input.filters.excludedScopes.isEmpty ? "false" : "true",
            "include_subfolders": input.filters.includeSubfolders ? "true" : "false",
            "has_snapshot": "false",
        ]
    }

    private static func queryOutcomeTag(_ outcome: SearchQueryOutcome?) -> String {
        switch outcome {
        case .convertedChanged:
            SearchQueryOutcome.convertedChanged.rawValue
        case .unchangedResult:
            SearchQueryOutcome.unchangedResult.rawValue
        case .fallbackReuse:
            SearchQueryOutcome.fallbackReuse.rawValue
        case nil:
            "legacy_unknown"
        }
    }

    private static func resultSetBucket(_ itemCount: Int?) -> String {
        if let itemCount {
            itemCount == 0 ? "empty" : "nonempty"
        } else {
            "not_run"
        }
    }

    private static func countBucket(_ count: Int) -> String {
        switch count {
        case 0:
            "0"
        case 1:
            "1"
        case 2 ... 4:
            "2_4"
        default:
            "5_plus"
        }
    }
}
