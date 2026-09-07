import Foundation

enum ComposerCollectionFilterMetrics {
    static let queryResult = "voyager_collection_filter_query_result"
    static let applyResult = "voyager_collection_filter_apply_result"
    static let sourcePostQueryApply = "post_query_apply"
    static let sourceManualApply = "manual_apply"
    static let sourceSurface = "composer"

    static func boundedDurationMilliseconds(startedAt: Date?, now: Date = Date()) -> Int? {
        guard let startedAt else { return nil }
        return max(0, min(Int.max, Int((now.timeIntervalSince(startedAt) * 1000).rounded())))
    }

    static func terminalTags(
        resultStatus: String,
        operationID: UUID,
        startedAt: Date?,
        failureReason: String? = nil,
        now: Date = Date(),
    ) -> [String: String] {
        var tags = [
            "result_status": resultStatus,
            "source_surface": sourceSurface,
            "operation_id": operationID.uuidString.lowercased(),
        ]
        if let startedAt {
            let milliseconds = max(
                0,
                min(
                    Int.max,
                    Int((now.timeIntervalSince(startedAt) * 1000).rounded()),
                ),
            )
            tags["duration_ms"] = String(milliseconds)
        }
        if let failureReason {
            tags["failure_reason"] = failureReason
        }
        return tags
    }
}
