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
        XCTAssertEqual(decoded.conditions, [])
    }

    func testSearchFiltersPayloadRoundTripsExcludedScopes() throws {
        let payload = SearchFiltersPayload(
            scopes: ["/Users/test/Documents"],
            excludedScopes: ["/Users/test/Documents/Receipts"],
            includeSubfolders: true,
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
        XCTAssertEqual(decoded.conditions, [])
    }

    func testAppliedFiltersPayloadRoundTripsExcludedScopes() throws {
        let payload = AppliedFiltersPayload(
            scopes: ["/Users/test/Documents"],
            excludedScopes: ["/Users/test/Documents/Receipts"],
            includeSubfolders: false,
            conditions: [],
        )

        let decoded = try JSONDecoder().decode(AppliedFiltersPayload.self, from: JSONEncoder().encode(payload))

        XCTAssertEqual(decoded, payload)
    }

    func testSearchResponsePayloadDecodesMissingQueryConversionAsNil() throws {
        let payload =
            #"{"itemCount":0,"appliedFilters":{"scopes":["#
                + #"/Users/test/Documents"],"conditions":[]},"items":null,"error":null}"#
        let data = Data(payload.utf8)

        let decoded = try JSONDecoder().decode(SearchResponsePayload.self, from: data)

        XCTAssertNil(decoded.queryConversion)
    }

    func testSearchResponsePayloadRoundTripsQueryConversion() throws {
        let payload = SearchResponsePayload(
            itemCount: 0,
            appliedFilters: AppliedFiltersPayload(
                scopes: ["/Users/test/Documents"],
                excludedScopes: ["/Users/test/Documents/Receipts"],
                includeSubfolders: true,
                conditions: [],
            ),
            items: nil,
            error: nil,
            queryConversion: SearchQueryConversionMetadataPayload(outcome: .fallbackReuse),
        )

        let decoded = try JSONDecoder().decode(SearchResponsePayload.self, from: JSONEncoder().encode(payload))

        XCTAssertEqual(decoded, payload)
    }
}
