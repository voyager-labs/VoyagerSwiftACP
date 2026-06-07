import Foundation
@testable import VoyagerShared
import XCTest

@MainActor
final class SearchFilterPayloadsTests: XCTestCase {
    func testSearchResponsePayloadDecodesMissingQueryOutcomeAsNil() throws {
        let data = Data(#"{"itemCount":0,"appliedFilters":{"scopes":["/tmp"],"conditions":[]},"items":null,"error":null}"#
            .utf8)

        let decoded = try JSONDecoder().decode(SearchResponsePayload.self, from: data)

        XCTAssertNil(decoded.queryOutcome)
    }

    func testSearchResponsePayloadRoundTripsQueryOutcome() throws {
        let payload = SearchResponsePayload(
            itemCount: 0,
            appliedFilters: AppliedFiltersPayload(
                scopes: ["/tmp"],
                excludedScopes: ["/tmp/excluded"],
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
