import Foundation
import VoyagerShared
import XCTest

@MainActor
final class SearchFilterPayloadsTests: XCTestCase {
    func testSearchFiltersPayloadDecodesMissingExcludedScopesAsEmpty() throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "scopes": ["/Users/test/Documents"],
            "conditions": [],
        ])

        let decoded = try JSONDecoder().decode(SearchFiltersPayload.self, from: data)

        XCTAssertEqual(decoded.scopes, ["/Users/test/Documents"])
        XCTAssertEqual(decoded.excludedScopes, [])
        XCTAssertTrue(decoded.includeSubfolders)
        XCTAssertFalse(decoded.includeDirectories)
        XCTAssertEqual(decoded.conditions, [])
    }

    func testSearchFiltersPayloadRoundTripsExcludedScopes() throws {
        let payload = SearchFiltersPayload(
            scopes: ["/Users/test/Documents"],
            excludedScopes: ["/Users/test/Documents/Receipts"],
            includeSubfolders: true,
            includeDirectories: true,
            conditions: [],
        )

        let decoded = try JSONDecoder().decode(SearchFiltersPayload.self, from: JSONEncoder().encode(payload))

        XCTAssertEqual(decoded, payload)
    }

    func testAppliedFiltersPayloadDecodesMissingExcludedScopesAsEmpty() throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "scopes": ["/Users/test/Documents"],
            "conditions": [],
        ])

        let decoded = try JSONDecoder().decode(AppliedFiltersPayload.self, from: data)

        XCTAssertEqual(decoded.scopes, ["/Users/test/Documents"])
        XCTAssertEqual(decoded.excludedScopes, [])
        XCTAssertNil(decoded.includeSubfolders)
        XCTAssertNil(decoded.includeDirectories)
        XCTAssertEqual(decoded.conditions, [])
    }

    func testAppliedFiltersPayloadRoundTripsExcludedScopes() throws {
        let payload = AppliedFiltersPayload(
            scopes: ["/Users/test/Documents"],
            excludedScopes: ["/Users/test/Documents/Receipts"],
            includeSubfolders: false,
            includeDirectories: true,
            conditions: [],
        )

        let decoded = try JSONDecoder().decode(AppliedFiltersPayload.self, from: JSONEncoder().encode(payload))

        XCTAssertEqual(decoded, payload)
    }

    func testSearchResponsePayloadDecodesMissingQueryOutcomeAsNil() throws {
        let data = Data(#"{"itemCount":0,"appliedFilters":{"scopes":["/Users/test/Documents"],"conditions":[]},"items":null,"error":null}"#
            .utf8)

        let decoded = try JSONDecoder().decode(SearchResponsePayload.self, from: data)

        XCTAssertNil(decoded.queryOutcome)
    }

    func testSearchResponsePayloadRoundTripsQueryOutcome() throws {
        let payload = SearchResponsePayload(
            itemCount: 0,
            appliedFilters: AppliedFiltersPayload(
                scopes: ["/Users/test/Documents"],
                excludedScopes: ["/Users/test/Documents/Receipts"],
                includeSubfolders: true,
                includeDirectories: true,
                conditions: [],
            ),
            items: nil,
            error: nil,
            queryOutcome: .fallbackReuse,
        )

        let decoded = try JSONDecoder().decode(SearchResponsePayload.self, from: JSONEncoder().encode(payload))

        XCTAssertEqual(decoded, payload)
    }
}
