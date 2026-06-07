import Foundation
@testable import VoyagerFeaturesComposer
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
                .failureMessage(for: MockLocalizedError("LLM_CONVERSION_FAILED: provider timeout")),
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

    func testQueryConversionOutcomeMapsToExpectedFeedbackCopy() {
        let response = VoyagerShared.SearchResponsePayload(
            itemCount: 0,
            appliedFilters: VoyagerShared.AppliedFiltersPayload(scopes: [], conditions: []),
            items: nil,
            error: VoyagerShared.SearchErrorPayload(code: "AI_PROVIDER_NOT_CONFIGURED", details: "missing provider"),
            queryConversion: VoyagerShared.SearchQueryConversionMetadataPayload(
                outcome: VoyagerShared.SearchQueryConversionOutcomePayload.providerNotConfigured,
            ),
        )

        let feedback = ComposerQueryFeedbackPolicy.feedback(for: response)

        XCTAssertEqual(feedback?.kind, .error)
        XCTAssertEqual(feedback?.message, ComposerQueryFeedbackPolicy.providerNotConfiguredMessage)
    }

    func testFallbackReuseOutcomeProducesInfoFeedback() {
        let response = VoyagerShared.SearchResponsePayload(
            itemCount: 0,
            appliedFilters: VoyagerShared.AppliedFiltersPayload(scopes: [], conditions: []),
            items: nil,
            error: nil,
            queryConversion: VoyagerShared.SearchQueryConversionMetadataPayload(
                outcome: VoyagerShared.SearchQueryConversionOutcomePayload.fallbackReuse,
            ),
        )

        let feedback = ComposerQueryFeedbackPolicy.feedback(for: response)

        XCTAssertEqual(feedback?.kind, .info)
        XCTAssertEqual(feedback?.message, ComposerQueryFeedbackPolicy.fallbackReuseMessage)
    }

    func testGeneratedScopeOnlyChangeDoesNotSkipApplyFilters() {
        let baseline = VoyagerShared.SearchFiltersPayload(scopes: ["/tmp/old"], conditions: [])
        let response = VoyagerShared.SearchResponsePayload(
            itemCount: 0,
            appliedFilters: VoyagerShared.AppliedFiltersPayload(scopes: ["/tmp/new"], conditions: []),
            items: nil,
            error: nil,
            queryConversion: VoyagerShared.SearchQueryConversionMetadataPayload(
                outcome: VoyagerShared.SearchQueryConversionOutcomePayload.generatedChangeSet,
            ),
        )

        XCTAssertFalse(ComposerQueryFeedbackPolicy.shouldSkipApplyFilters(response: response, baseline: baseline))
    }

    func testSkipApplyFiltersUsesMetadataOutcome() {
        let baseline = VoyagerShared.SearchFiltersPayload(scopes: ["/tmp"], conditions: [])
        let response = VoyagerShared.SearchResponsePayload(
            itemCount: 0,
            appliedFilters: VoyagerShared.AppliedFiltersPayload(scopes: ["/tmp"], conditions: []),
            items: nil,
            error: nil,
            queryConversion: VoyagerShared.SearchQueryConversionMetadataPayload(
                outcome: VoyagerShared.SearchQueryConversionOutcomePayload.unchangedResult,
            ),
        )

        XCTAssertTrue(ComposerQueryFeedbackPolicy.shouldSkipApplyFilters(response: response, baseline: baseline))
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
