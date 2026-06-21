import Foundation
import VoyagerEntitiesAi
@testable import VoyagerHelper
import VoyagerShared
import XCTest

@MainActor
final class SearchQueryServiceTests: XCTestCase {
    func testQuerySearchPreservesExcludedScopesInPlannedFilters() async {
        let service = SearchQueryService(
            searchService: SearchExecutionServiceStub(),
            convertQuery: { _ in
                await MainActor.run {
                    QueryConversionResult(
                        conditions: [
                            SearchConditionPayload(
                                propertyKey: "extension",
                                operator: "eq",
                                value: .string("pdf"),
                            ),
                        ],
                        scopes: ["  /tmp/root  ", "/tmp/root/sub", "   "],
                        error: nil,
                        outcome: .generatedChangeSet,
                        providerId: "openai",
                    )
                }
            },
        )
        let request = SearchRequestPayload(
            query: "find receipts",
            filters: SearchFiltersPayload(
                scopes: ["/tmp/fallback"],
                excludedScopes: ["/tmp/root/excluded"],
                includeSubfolders: true,
                conditions: [],
            ),
        )

        let response = await service.querySearch(request)

        XCTAssertNil(response.error)
        XCTAssertEqual(response.queryConversion?.outcome, .generatedChangeSet)
        XCTAssertEqual(
            response.appliedFilters,
            AppliedFiltersPayload(
                scopes: ["/tmp/root", "/tmp/root/sub"],
                excludedScopes: ["/tmp/root/excluded"],
                includeSubfolders: true,
                conditions: [
                    SearchConditionPayload(propertyKey: "extension", operator: "eq", value: .string("pdf")),
                ],
            ),
        )
    }

    func testQuerySearchForwardsCollectionSearchSettingsToConverter() async {
        let requestBox = RequestCaptureBox()
        let settings = CollectionSearchAISettingsPayload(
            provider: .specific("openai"),
            model: .auto,
            thinking: .providerDefault,
        )
        let service = SearchQueryService(
            searchService: SearchExecutionServiceStub(),
            convertQuery: { request in
                await requestBox.store(request)
                return await MainActor.run {
                    QueryConversionResult(
                        conditions: [],
                        scopes: nil,
                        error: nil,
                        outcome: .generatedChangeSet,
                    )
                }
            },
        )
        let request = SearchRequestPayload(
            query: "find receipts",
            filters: SearchFiltersPayload(
                scopes: ["/tmp/fallback"],
                excludedScopes: [],
                includeSubfolders: true,
                conditions: [],
            ),
            collectionSearchAISettings: settings,
        )

        _ = await service.querySearch(request)

        let seenRequest = await requestBox.request
        XCTAssertEqual(seenRequest?.collectionSearchAISettings, settings)
    }

    func testQuerySearchScopeOnlyChangeReportsGeneratedChangeSet() async {
        let service = SearchQueryService(
            searchService: SearchExecutionServiceStub(),
            convertQuery: { _ in
                await MainActor.run {
                    QueryConversionResult(
                        conditions: [],
                        scopes: ["/tmp/new-root"],
                        error: nil,
                        outcome: .fallbackReuse,
                        providerId: "openai",
                    )
                }
            },
        )
        let request = SearchRequestPayload(
            query: "downloads folder",
            filters: SearchFiltersPayload(
                scopes: ["/tmp/old-root"],
                excludedScopes: ["/tmp/old-root/excluded"],
                includeSubfolders: true,
                conditions: [],
            ),
        )

        let response = await service.querySearch(request)

        XCTAssertNil(response.error)
        XCTAssertEqual(response.queryConversion?.outcome, .generatedChangeSet)
        XCTAssertEqual(
            response.appliedFilters,
            AppliedFiltersPayload(
                scopes: ["/tmp/new-root"],
                excludedScopes: ["/tmp/old-root/excluded"],
                includeSubfolders: true,
                conditions: [],
            ),
        )
    }

    func testQuerySearchEmptyQueryPreservesExcludedScopes() async {
        let service = SearchQueryService(
            searchService: SearchExecutionServiceStub(),
            convertQuery: { _ in
                XCTFail("convertQuery should not run for empty query")
                return await MainActor.run {
                    QueryConversionResult(conditions: [], scopes: nil, error: nil, outcome: .generatedChangeSet)
                }
            },
        )
        let request = SearchRequestPayload(
            query: "   ",
            filters: SearchFiltersPayload(
                scopes: ["/tmp/root"],
                excludedScopes: ["/tmp/root/excluded"],
                includeSubfolders: false,
                conditions: [
                    SearchConditionPayload(propertyKey: "extension", operator: "eq", value: .string("txt")),
                ],
            ),
        )

        let response = await service.querySearch(request)

        XCTAssertNil(response.error)
        XCTAssertNil(response.queryConversion)
        XCTAssertEqual(
            response.appliedFilters,
            AppliedFiltersPayload(
                scopes: ["/tmp/root"],
                excludedScopes: ["/tmp/root/excluded"],
                includeSubfolders: false,
                conditions: [
                    SearchConditionPayload(propertyKey: "extension", operator: "eq", value: .string("txt")),
                ],
            ),
        )
    }

    func testQuerySearchErrorResponsePreservesExcludedScopes() async {
        let service = SearchQueryService(
            searchService: SearchExecutionServiceStub(),
            convertQuery: { _ in
                await MainActor.run {
                    QueryConversionResult(
                        conditions: [],
                        scopes: nil,
                        error: "provider failed",
                        outcome: .conversionFailure,
                        providerId: "openai",
                        errorCode: "AI_PROVIDER_UNAVAILABLE",
                        reason: "networkFailure",
                    )
                }
            },
        )
        let request = SearchRequestPayload(
            query: "find receipts",
            filters: SearchFiltersPayload(
                scopes: ["/tmp/root"],
                excludedScopes: ["/tmp/root/excluded"],
                includeSubfolders: false,
                conditions: [
                    SearchConditionPayload(propertyKey: "extension", operator: "eq", value: .string("txt")),
                ],
            ),
        )

        let response = await service.querySearch(request)

        XCTAssertEqual(response.error, SearchErrorPayload(code: "AI_PROVIDER_UNAVAILABLE", details: "provider failed"))
        XCTAssertEqual(response.queryConversion?.outcome, .conversionFailure)
        XCTAssertEqual(
            response.appliedFilters,
            AppliedFiltersPayload(
                scopes: ["/tmp/root"],
                excludedScopes: ["/tmp/root/excluded"],
                includeSubfolders: false,
                conditions: [
                    SearchConditionPayload(propertyKey: "extension", operator: "eq", value: .string("txt")),
                ],
            ),
        )
    }

    func testAppliedFiltersPayloadDecodesMissingExcludedScopesAsDeterministicEmptyArray() throws {
        let data = Data(#"{"scopes":["/tmp/root"],"includeSubfolders":true,"conditions":[]}"#.utf8)

        let decoded = try JSONDecoder().decode(AppliedFiltersPayload.self, from: data)

        XCTAssertEqual(decoded.excludedScopes, [])
    }

    func testQueryConversionInterpreterKeepsValidExtensionConditionAsGeneratedChangeSet() throws {
        let converter = QueryConversionInterpreter()
        let result = try converter.decodeAndNormalize(
            content: #"""
            {
              "conditions":[{"propertyKey":"extension","operator":"any","value":["png","jpg"]}],
              "scopes":null,
              "error":null
            }
            """#,
            existingFilters: SearchFiltersPayload(scopes: ["/tmp/root"], conditions: []),
        )

        XCTAssertNil(result.error)
        XCTAssertEqual(result.outcome, QueryConversionResultOutcome.generatedChangeSet)
        XCTAssertEqual(result.conditions, [
            SearchConditionPayload(
                propertyKey: "extension",
                operator: "any",
                value: .array([.string("png"), .string("jpg")]),
            ),
        ])
    }

    func testQueryConversionInterpreterScopeOnlyChangeIsGeneratedChangeSet() throws {
        let converter = QueryConversionInterpreter()
        let result = try converter.decodeAndNormalize(
            content: #"""
            {"conditions":[],"scopes":["/tmp/new-root"],"error":null}
            """#,
            existingFilters: SearchFiltersPayload(scopes: ["/tmp/old-root"], conditions: []),
        )

        XCTAssertNil(result.error)
        XCTAssertEqual(result.outcome, QueryConversionResultOutcome.generatedChangeSet)
        XCTAssertEqual(result.conditions, [])
        XCTAssertEqual(result.scopes, ["/tmp/new-root"])
    }

    func testQueryConversionInterpreterInvalidGeneratedConditionsReturnConversionFailure() throws {
        let converter = QueryConversionInterpreter()
        let result = try converter.decodeAndNormalize(
            content: #"""
            {
              "conditions":[{"propertyKey":"kind","operator":"eq","value":"image"}],
              "scopes":null,
              "error":null
            }
            """#,
            existingFilters: SearchFiltersPayload(scopes: ["/tmp/root"], conditions: []),
        )

        XCTAssertEqual(result.outcome, .conversionFailure)
        XCTAssertEqual(result.error, "Generated filters could not be validated.")
        XCTAssertEqual(result.conditions, [])
    }
}

private struct SearchExecutionServiceStub: SearchExecutionServicing {
    func applyFilters(_ filters: SearchFiltersPayload) async throws -> SearchResponsePayload {
        SearchResponsePayload(
            itemCount: 0,
            appliedFilters: AppliedFiltersPayload(
                scopes: filters.scopes,
                excludedScopes: filters.excludedScopes,
                includeSubfolders: filters.includeSubfolders,
                conditions: filters.conditions,
            ),
            items: [],
            error: nil,
        )
    }

    func searchRecent(_: RecentSearchRequestPayload) async throws -> RecentSearchResponsePayload {
        RecentSearchResponsePayload(items: [])
    }

    func searchTag(_ request: TagSearchRequestPayload) async throws -> TagSearchResponsePayload {
        TagSearchResponsePayload(requestedTag: request.requestedTag, items: [])
    }
}

private actor RequestCaptureBox {
    var request: SearchRequestPayload?

    func store(_ request: SearchRequestPayload) {
        self.request = request
    }
}
