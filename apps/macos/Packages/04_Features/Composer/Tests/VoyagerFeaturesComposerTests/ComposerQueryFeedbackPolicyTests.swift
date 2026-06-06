import Foundation
@testable import VoyagerFeaturesComposer
import VoyagerShared
import XCTest

@MainActor
final class ComposerQueryFeedbackPolicyTests: XCTestCase {
    func testIdenticalBaselineAndAppliedFiltersAreNoOp() {
        let baseline = VoyagerShared.SearchFiltersPayload(
            scopes: ["/tmp"],
            excludedScopes: ["/tmp/excluded"],
            includeSubfolders: true,
            includeDirectories: true,
            conditions: [
                VoyagerShared.SearchConditionPayload(
                    propertyKey: "name",
                    operator: "contains",
                    value: .string("draft"),
                ),
            ],
        )

        let applied = VoyagerShared.AppliedFiltersPayload(
            scopes: ["/tmp"],
            excludedScopes: ["/tmp/excluded"],
            includeSubfolders: true,
            includeDirectories: true,
            conditions: [
                VoyagerShared.SearchConditionPayload(
                    propertyKey: "name",
                    operator: "contains",
                    value: .string("draft"),
                ),
            ],
        )

        XCTAssertTrue(ComposerQueryFeedbackPolicy.isNoOp(baseline: baseline, appliedFilters: applied))
    }

    func testFailureCodesMapToDistinctMessages() {
        XCTAssertEqual(
            ComposerQueryFeedbackPolicy
                .failureMessage(for: MockLocalizedError("LLM_CONVERSION_FAILED: gateway timeout")),
            ComposerQueryFeedbackPolicy.conversionFailureMessage,
        )
        XCTAssertEqual(
            ComposerQueryFeedbackPolicy.failureMessage(for: MockLocalizedError("HELPER_UNAVAILABLE: xpc disconnected")),
            ComposerQueryFeedbackPolicy.executionFailureMessage,
        )
        XCTAssertEqual(
            ComposerQueryFeedbackPolicy.executionFailureMessage,
            "Couldn't complete that search. Please try again.",
        )
    }

    func testShouldApplyFiltersTreatsFallbackReuseAndUnchangedAsNoOp() {
        XCTAssertFalse(ComposerQueryFeedbackPolicy.shouldApplyFilters(for: .fallbackReuse))
        XCTAssertFalse(ComposerQueryFeedbackPolicy.shouldApplyFilters(for: .unchangedResult))
        XCTAssertTrue(ComposerQueryFeedbackPolicy.shouldApplyFilters(for: .convertedChanged))
        XCTAssertTrue(ComposerQueryFeedbackPolicy.shouldApplyFilters(for: nil))
        XCTAssertEqual(
            ComposerQueryFeedbackPolicy.fallbackReuseMessage,
            "No new filters were generated, so Voyager kept the current filters.",
        )
    }
}

private struct MockLocalizedError: LocalizedError {
    let rawMessage: String

    init(_ rawMessage: String) {
        self.rawMessage = rawMessage
    }

    var errorDescription: String? {
        rawMessage
    }
}
