import VoyagerShared

enum CollectionFilterSaveMetrics {
    static let saveResult = "voyager_collection_filter_save_result"

    static func tags(
        outcome: String,
        reason: String,
        source: String,
        payload: SaveRequestPayload,
    ) -> [String: String] {
        [
            "stage": "save",
            "outcome": outcome,
            "reason": reason,
            "source": source,
            "opened_collection": source == "save_existing" || source == "write_back" ? "true" : "false",
            "result_set": "not_run",
            "condition_count_bucket": countBucket(payload.context?.conditions.count ?? 0),
            "scope_count_bucket": countBucket(payload.context?.scopes.count ?? 0),
            "has_excluded_scopes": (payload.context?.excludedScopes.isEmpty == false) ? "true" : "false",
            "include_subfolders": (payload.context?.includeSubfolders ?? true) ? "true" : "false",
            "has_snapshot": (payload.snapshotItems?.isEmpty == false) ? "true" : "false",
        ]
    }

    static func tags(
        outcome: String,
        reason: String,
        source: String,
        snapshot: CollectionSaveSnapshot,
    ) -> [String: String] {
        [
            "stage": "save",
            "outcome": outcome,
            "reason": reason,
            "source": source,
            "opened_collection": source == "save_existing" || source == "write_back" ? "true" : "false",
            "result_set": "not_run",
            "condition_count_bucket": countBucket(snapshot.conditions.count),
            "scope_count_bucket": countBucket(snapshot.scopes.count),
            "has_excluded_scopes": snapshot.excludedScopes.isEmpty ? "false" : "true",
            "include_subfolders": snapshot.includeSubfolders ? "true" : "false",
            "has_snapshot": (snapshot.snapshotItems?.isEmpty == false) ? "true" : "false",
        ]
    }

    static func reasonForInFlightBlock(state: CollectionState, payload: SaveRequestPayload) -> String {
        if state.isSaving { return "save_inflight" }
        if payload.isSearchLoading { return "search_inflight" }
        if payload.isFiltersLoading { return "filters_inflight" }
        return "unknown"
    }

    static func reason(for error: CollectionSaveValidationError) -> String {
        switch error {
        case .emptyContent:
            "empty_content"
        case .incompleteCondition:
            "condition_incomplete"
        case .invalidConditionValue:
            "invalid_condition_value"
        case .saveBlockedFutureMinor:
            "future_minor_blocked"
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
