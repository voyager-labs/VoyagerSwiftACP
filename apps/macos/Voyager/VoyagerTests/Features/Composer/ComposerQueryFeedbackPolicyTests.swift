import Foundation
@testable import Voyager
@testable import VoyagerFeaturesComposer
import VoyagerShared
import XCTest

@MainActor
/// Composer 쿼리 피드백 정책 — 중복 쿼리 no-op 및 실패 코드 매핑을 검증.
final class ComposerQueryFeedbackPolicyTests: XCTestCase {
    /// testIdenticalBaselineAndAppliedFiltersAreNoOp 테스트 동작을 검증한다.
    func testIdenticalBaselineAndAppliedFiltersAreNoOp() {
        let baseline = VoyagerShared.SearchFiltersPayload(
            scopes: ["/tmp"],
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

    /// testFailureCodesMapToDistinctMessages 테스트 동작을 검증한다.
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
