import VoyagerShared
import XCTest

final class SearchResponsePayloadTests: XCTestCase {
    func testSearchResponsePayloadRoundTripWithoutQueryConversion() throws {
        let original = SearchResponsePayload(
            itemCount: 7,
            appliedFilters: AppliedFiltersPayload(
                scopes: ["/tmp/root"],
                excludedScopes: ["/tmp/root/excluded"],
                includeSubfolders: true,
                conditions: [SearchConditionPayload(propertyKey: "extension", operator: "eq", value: .string("pdf"))],
            ),
            items: [.string("item-1")],
            error: nil,
        )

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SearchResponsePayload.self, from: encoded)

        XCTAssertEqual(decoded, original)
        XCTAssertNil(decoded.queryConversion)
    }

    func testSearchResponsePayloadRoundTripWithQueryConversion() throws {
        let original = SearchResponsePayload(
            itemCount: 0,
            appliedFilters: AppliedFiltersPayload(
                scopes: ["/tmp/root"],
                excludedScopes: [],
                includeSubfolders: false,
                conditions: [],
            ),
            items: nil,
            error: SearchErrorPayload(code: "LLM_CONVERSION_FAILED", details: "provider timeout"),
            queryConversion: SearchQueryConversionMetadataPayload(
                outcome: .generatedChangeSet,
            ),
        )

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SearchResponsePayload.self, from: encoded)

        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.queryConversion?.outcome, .generatedChangeSet)
    }
}
