import Foundation
@testable import Voyager
import VoyagerShared
import XCTest

@MainActor
final class ComposerQueryFeedbackPolicyTests: XCTestCase {
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
        XCTAssertEqual(normalized.includeSubfolders, false)
        XCTAssertEqual(normalized.conditions, [])
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
        XCTAssertEqual(filters.includeSubfolders, true)
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
