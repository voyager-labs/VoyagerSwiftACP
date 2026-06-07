import Foundation
@testable import Voyager
@testable import VoyagerFeaturesComposer
import VoyagerShared
import XCTest

/// Composer 쿼리 피드백 정책 — 중복 쿼리 no-op 및 실패 코드 매핑을 검증.
@MainActor
final class ComposerQueryFeedbackPolicyTests: XCTestCase {
    /// testIdenticalBaselineAndAppliedFiltersAreNoOp 테스트 동작을 검증한다.
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

    func testNormalizedFiltersPreservesExcludedScopes() {
        let baseline = VoyagerShared.SearchFiltersPayload(
            scopes: ["/tmp"],
            excludedScopes: ["/tmp/ignored"],
            includeSubfolders: true,
            conditions: [],
        )
        let applied = VoyagerShared.AppliedFiltersPayload(
            scopes: ["/tmp"],
            excludedScopes: ["/tmp/Receipts"],
            includeSubfolders: false,
            conditions: [],
        )

        let normalized = ComposerQueryFeedbackPolicy.normalizedFilters(appliedFilters: applied, fallback: baseline)

        XCTAssertEqual(normalized.scopes, ["/tmp"])
        XCTAssertEqual(normalized.excludedScopes, ["/tmp/Receipts"])
        XCTAssertFalse(normalized.includeSubfolders)
        XCTAssertEqual(normalized.conditions, [])
    }

    func testNormalizedFiltersRestoresBaselineExcludedScopesWhenAppliedPayloadOmitsKey() throws {
        let baseline = VoyagerShared.SearchFiltersPayload(
            scopes: ["/tmp"],
            excludedScopes: ["/tmp/ignored"],
            includeSubfolders: true,
            conditions: [],
        )
        let data = Data(#"{"scopes":["/tmp"],"includeSubfolders":true,"conditions":[]}"#.utf8)
        let applied = try JSONDecoder().decode(VoyagerShared.AppliedFiltersPayload.self, from: data)

        let normalized = ComposerQueryFeedbackPolicy.normalizedFilters(appliedFilters: applied, fallback: baseline)

        XCTAssertEqual(normalized.scopes, ["/tmp"])
        XCTAssertEqual(normalized.excludedScopes, ["/tmp/ignored"])
        XCTAssertTrue(normalized.includeSubfolders)
        XCTAssertEqual(normalized.conditions, [])
        XCTAssertTrue(ComposerQueryFeedbackPolicy.isNoOp(baseline: baseline, appliedFilters: applied))
    }

    func testBuildFiltersIncludesExcludedScopesFromSelection() {
        var state = ComposerState()
        state.scopeEditor.selection = .explicit(
            bases: [ComposerScopeBase(path: "/tmp")],
            exceptions: [ComposerScopeException(path: "/tmp/Receipts")],
        )
        state.scopeEditor.includeSubfolders = true

        let filters = buildFilters(from: state)

        XCTAssertEqual(filters.scopes, ["/tmp"])
        XCTAssertEqual(filters.excludedScopes, ["/tmp/Receipts"])
        XCTAssertTrue(filters.includeSubfolders)
        XCTAssertEqual(filters.conditions, [])
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
