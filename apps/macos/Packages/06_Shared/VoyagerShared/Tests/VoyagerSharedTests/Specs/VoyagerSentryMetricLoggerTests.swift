import Foundation
@testable import VoyagerShared
import XCTest

final class VoyagerSentryMetricLoggerTests: XCTestCase {
    func testBuiltInLifecycleMetricsExcludeUserDataFromFinalAttributes() throws {
        VoyagerSentryMetricLogger.setUserId("private-device-id")
        defer { VoyagerSentryMetricLogger.setUserId(nil) }
        let metricNames = [
            "built_in_collection_ensure_started",
            "built_in_collection_item_ensured",
            "built_in_collection_item_deferred",
            "built_in_collection_item_repaired",
            "built_in_collection_item_failed",
            "built_in_pinned_seed_started",
            "built_in_pinned_item_seeded",
            "built_in_pinned_item_deferred",
            "built_in_pinned_item_suppressed",
            "built_in_pinned_item_failed",
        ]

        for name in metricNames {
            let attributes = VoyagerSentryMetricLogger.metricAttributes(
                name,
                value: 1,
                tags: ["identity": "recents", "outcome": "ensured"],
            )

            XCTAssertNil(attributes["metric.user_id"], name)
            XCTAssertEqual(
                Set(attributes.keys),
                Set([
                    "metric.name",
                    "metric.value",
                    "metric.tag.identity",
                    "metric.tag.outcome",
                ]),
                name,
            )
            XCTAssertEqual(try XCTUnwrap(attributes["metric.name"] as? String), name)
            XCTAssertEqual(try XCTUnwrap(attributes["metric.tag.identity"] as? String), "recents")
            XCTAssertEqual(try XCTUnwrap(attributes["metric.tag.outcome"] as? String), "ensured")
        }
    }

    func testNonBuiltInMetricPreservesExistingUserIdEnrichment() throws {
        VoyagerSentryMetricLogger.setUserId("private-device-id")
        defer { VoyagerSentryMetricLogger.setUserId(nil) }

        let attributes = VoyagerSentryMetricLogger.metricAttributes("existing_metric", value: 1)

        XCTAssertEqual(try XCTUnwrap(attributes["metric.user_id"] as? String), "private-device-id")
    }
}
