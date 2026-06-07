import Foundation
@testable import VoyagerShared
import XCTest

@MainActor
final class SearchFilterPayloadsTests: XCTestCase {
    func testSearchResponsePayloadDecodesMissingQueryConversionAsNil() throws {
        let data = Data(#"{"itemCount":0,"appliedFilters":{"scopes":["/tmp"],"conditions":[]},"items":null,"error":null}"#
            .utf8)

        let decoded = try JSONDecoder().decode(SearchResponsePayload.self, from: data)

        XCTAssertNil(decoded.queryConversion)
    }

    func testSearchResponsePayloadRoundTripsQueryConversion() throws {
        let payload = SearchResponsePayload(
            itemCount: 0,
            appliedFilters: AppliedFiltersPayload(
                scopes: ["/tmp"],
                excludedScopes: ["/tmp/excluded"],
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
