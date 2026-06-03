import Foundation
@testable import VoyagerHelper
import VoyagerShared
import XCTest

@MainActor
final class FilterSearchQueryBuilderTests: XCTestCase {
    func testScopeNormalizerNormalizesAndDedupesIdenticalScopes() {
        let normalized = SearchScopeNormalizer.normalizeScopes([
            "  /Users/test/Downloads/  ",
            "/Users/test/Downloads/subfolder",
            "/Users/test/Downloads",
            "",
        ])

        XCTAssertEqual(normalized, ["/Users/test/Downloads", "/Users/test/Downloads/subfolder"])
    }

    func testScopeNormalizerPreservesRootAndExplicitSubScopes() {
        let normalized = SearchScopeNormalizer.normalizeScopes([
            "/Users/test",
            "/",
            "/Users/test/Downloads",
        ])

        XCTAssertEqual(normalized, ["/Users/test", "/", "/Users/test/Downloads"])
    }

    func testScopeNormalizerExpandsTildeAndPreservesHomeSubScopes() {
        let homePath = FileManager.default.homeDirectoryForCurrentUser.path

        let normalized = SearchScopeNormalizer.normalizeScopes([
            "~/Documents",
            homePath + "/Documents/subfolder",
        ])

        XCTAssertEqual(normalized, [homePath + "/Documents", homePath + "/Documents/subfolder"])
    }

    func testScopeNormalizerReturnsEmptyWhenScopesAreBlank() {
        XCTAssertEqual(SearchScopeNormalizer.normalizeScopes(["", "   "]), [])
    }

    func testConditionCompilerEqOnNameStemIncludesBareAndExtensionForms() throws {
        let compiler = try makeCompiler()
        let condition = SearchConditionPayload(
            propertyKey: "name_stem",
            operator: "eq",
            value: .string("report"),
        )

        let plan = try compiler.compilePlan(conditions: [condition])

        XCTAssertTrue(plan.predicate.contains("kMDItemFSName == \"report\""))
        XCTAssertTrue(plan.predicate.contains("kMDItemFSName == \"report.*\""))
        XCTAssertEqual(plan.pushdownConditions, [condition])
    }

    func testConditionCompilerRangeOnSizeBuildsInclusiveBounds() throws {
        let compiler = try makeCompiler()
        let condition = SearchConditionPayload(
            propertyKey: "size",
            operator: "btw",
            value: .array([.number(100), .number(200)]),
        )

        let plan = try compiler.compilePlan(conditions: [condition])

        XCTAssertTrue(plan.predicate.contains("kMDItemFSSize >= 100"))
        XCTAssertTrue(plan.predicate.contains("kMDItemFSSize <= 200"))
        XCTAssertEqual(plan.pushdownConditions, [condition])
    }

    func testConditionCompilerEqOnExtensionUsesMditemAttribute() throws {
        let compiler = try makeCompiler()
        let condition = SearchConditionPayload(
            propertyKey: "extension",
            operator: "eq",
            value: .string("pdf"),
        )

        let plan = try compiler.compilePlan(conditions: [condition])

        XCTAssertTrue(plan.predicate.contains("kMDItemFSName == \"pdf\""))
        XCTAssertEqual(plan.pushdownConditions, [condition])
    }
}

private extension FilterSearchQueryBuilderTests {
    func makeCompiler() throws -> SpotlightQueryCompiler {
        let conditionRegistry: PropertyConditionRegistry =
            try loadRegistry(fileName: "property_condition_registry.json")
        let systemRegistry: SystemPropertyRegistry = try loadRegistry(fileName: "system_property_registry.json")
        let builder = SearchConditionBuilder(registry: conditionRegistry, systemRegistry: systemRegistry)
        return SpotlightQueryCompiler(conditionBuilder: builder)
    }

    func loadRegistry<T: Decodable>(fileName: String) throws -> T {
        let rootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let fileURL = rootURL.appendingPathComponent("shared").appendingPathComponent(fileName)
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(T.self, from: data)
    }
}

@MainActor
final class SearchQueryServiceTests: XCTestCase {
    func testQuerySearchPreservesExcludedScopesInPlannedFilters() async {
        let service = SearchQueryService(
            searchService: SearchExecutionServiceStub(),
            convertQuery: { _, _ in
                GatewayQueryResult(
                    conditions: [SearchConditionPayload(
                        propertyKey: "extension",
                        operator: "eq",
                        value: .string("pdf"),
                    )],
                    scopes: ["  /tmp/root  ", "/tmp/root/sub", "   "],
                    error: nil,
                )
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
        XCTAssertEqual(
            response.appliedFilters,
            AppliedFiltersPayload(
                scopes: ["/tmp/root", "/tmp/root/sub"],
                excludedScopes: ["/tmp/root/excluded"],
                includeSubfolders: true,
                conditions: [SearchConditionPayload(propertyKey: "extension", operator: "eq", value: .string("pdf"))],
            ),
        )
    }

    func testQuerySearchEmptyQueryPreservesExcludedScopes() async {
        let service = SearchQueryService(
            searchService: SearchExecutionServiceStub(),
            convertQuery: { _, _ in
                XCTFail("convertQuery should not run for empty query")
                return GatewayQueryResult(conditions: [], scopes: nil, error: nil)
            },
        )
        let request = SearchRequestPayload(
            query: "   ",
            filters: SearchFiltersPayload(
                scopes: ["/tmp/root"],
                excludedScopes: ["/tmp/root/excluded"],
                includeSubfolders: false,
                conditions: [SearchConditionPayload(propertyKey: "extension", operator: "eq", value: .string("txt"))],
            ),
        )

        let response = await service.querySearch(request)

        XCTAssertNil(response.error)
        XCTAssertEqual(
            response.appliedFilters,
            AppliedFiltersPayload(
                scopes: ["/tmp/root"],
                excludedScopes: ["/tmp/root/excluded"],
                includeSubfolders: false,
                conditions: [SearchConditionPayload(propertyKey: "extension", operator: "eq", value: .string("txt"))],
            ),
        )
    }

    func testQuerySearchErrorResponsePreservesExcludedScopes() async {
        let service = SearchQueryService(
            searchService: SearchExecutionServiceStub(),
            convertQuery: { _, _ in
                GatewayQueryResult(conditions: [], scopes: nil, error: "gateway failed")
            },
        )
        let request = SearchRequestPayload(
            query: "find receipts",
            filters: SearchFiltersPayload(
                scopes: ["/tmp/root"],
                excludedScopes: ["/tmp/root/excluded"],
                includeSubfolders: false,
                conditions: [SearchConditionPayload(propertyKey: "extension", operator: "eq", value: .string("txt"))],
            ),
        )

        let response = await service.querySearch(request)

        XCTAssertEqual(response.error, SearchErrorPayload(code: "LLM_CONVERSION_FAILED", details: "gateway failed"))
        XCTAssertEqual(
            response.appliedFilters,
            AppliedFiltersPayload(
                scopes: ["/tmp/root"],
                excludedScopes: ["/tmp/root/excluded"],
                includeSubfolders: false,
                conditions: [SearchConditionPayload(propertyKey: "extension", operator: "eq", value: .string("txt"))],
            ),
        )
    }

    func testAppliedFiltersPayloadDecodesMissingExcludedScopesAsDeterministicEmptyArray() throws {
        let data = Data(#"{"scopes":["/tmp/root"],"includeSubfolders":true,"conditions":[]}"#.utf8)

        let decoded = try JSONDecoder().decode(AppliedFiltersPayload.self, from: data)

        XCTAssertEqual(decoded.excludedScopes, [])
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
