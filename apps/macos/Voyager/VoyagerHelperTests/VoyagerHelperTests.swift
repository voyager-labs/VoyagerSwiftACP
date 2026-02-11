import StructuredQueries
@testable import VoyagerHelper
import XCTest

@MainActor
final class FilterSearchQueryBuilderTests: XCTestCase {
    func testScopePredicateBuildsSqlAndBindings() {
        let builder = FilterSearchScopeBuilder()
        let predicate = builder.buildScopePredicate(scopes: ["/Users/test/Downloads/"])
        let prepared = predicate.prepare { _ in "?" }

        XCTAssertTrue(prepared.sql.contains("\"files\".\"directory_id\""))
        XCTAssertTrue(prepared.sql.contains("FROM directories"))
        XCTAssertTrue(prepared.sql.contains("\"directories\".\"path\""))
        XCTAssertFalse(prepared.sql.contains("\"files\".\"dir_path\""))
        XCTAssertTrue(prepared.sql.contains("LIKE"))
        XCTAssertTrue(prepared.sql.contains("="))
        XCTAssertEqual(prepared.bindings.count, 2)
    }

    func testScopePredicateNormalizesAndReducesScopes() {
        let builder = FilterSearchScopeBuilder()
        let predicate = builder.buildScopePredicate(
            scopes: [
                "  /Users/test/Downloads/  ",
                "/Users/test/Downloads/subfolder",
                "/Users/test/Downloads",
                "",
            ],
        )
        let prepared = predicate.prepare { _ in "?" }

        XCTAssertTrue(prepared.sql.contains("\"directories\".\"path\""))
        XCTAssertFalse(prepared.sql.contains("\"files\".\"dir_path\""))
        XCTAssertEqual(prepared.bindings.count, 2)
    }

    func testScopePredicateHandlesRootScope() {
        let builder = FilterSearchScopeBuilder()
        let predicate = builder.buildScopePredicate(scopes: ["/"])
        let prepared = predicate.prepare { _ in "?" }

        XCTAssertTrue(prepared.sql.contains("LIKE"))
        XCTAssertEqual(prepared.bindings.count, 2)
    }

    func testConditionBuilderEqOnNameFull() throws {
        let builder = try makeConditionBuilder()
        let condition = SearchConditionPayload(
            propertyKey: "name_full",
            operator: "eq",
            value: .string("report"),
        )

        let predicate = try builder.buildWhere(conditions: [condition])
        let prepared = predicate.prepare { _ in "?" }

        XCTAssertTrue(prepared.sql.contains("\"files\".\"name_full\""))
        XCTAssertTrue(prepared.sql.contains(" = "))
        XCTAssertEqual(prepared.bindings.count, 1)
    }

    func testConditionBuilderRangeOnSize() throws {
        let builder = try makeConditionBuilder()
        let condition = SearchConditionPayload(
            propertyKey: "size",
            operator: "btw",
            value: .array([.number(100), .number(200)]),
        )

        let predicate = try builder.buildWhere(conditions: [condition])
        let prepared = predicate.prepare { _ in "?" }

        XCTAssertTrue(prepared.sql.contains("\"files\".\"size\""))
        XCTAssertTrue(prepared.sql.contains("BETWEEN"))
        XCTAssertEqual(prepared.bindings.count, 2)
    }

    func testConditionBuilderEqOnExtension() throws {
        let builder = try makeConditionBuilder()
        let condition = SearchConditionPayload(
            propertyKey: "extension",
            operator: "eq",
            value: .string("pdf"),
        )

        let predicate = try builder.buildWhere(conditions: [condition])
        let prepared = predicate.prepare { _ in "?" }

        XCTAssertTrue(prepared.sql.contains("\"files\".\"extension\""))
        XCTAssertTrue(prepared.sql.contains(" = "))
        XCTAssertEqual(prepared.bindings.count, 1)
    }

    func testConditionBuilderAnyOnExtension() throws {
        let builder = try makeConditionBuilder()
        let condition = SearchConditionPayload(
            propertyKey: "extension",
            operator: "any",
            value: .array([.string("pdf"), .string("docx")]),
        )

        let predicate = try builder.buildWhere(conditions: [condition])
        let prepared = predicate.prepare { _ in "?" }

        XCTAssertTrue(prepared.sql.contains("\"files\".\"extension\""))
        XCTAssertTrue(prepared.sql.contains(" IN "))
        XCTAssertEqual(prepared.bindings.count, 2)
    }
}

private extension FilterSearchQueryBuilderTests {
    func makeConditionBuilder() throws -> FilterSearchConditionBuilder {
        let registry = try loadRegistry(
            fileName: "property_condition_registry.json",
            type: PropertyConditionRegistry.self,
        )
        let systemRegistry = try loadRegistry(
            fileName: "system_property_registry.json",
            type: SystemPropertyRegistry.self,
        )
        return FilterSearchConditionBuilder(registry: registry, systemRegistry: systemRegistry)
    }

    func loadRegistry<T: Decodable>(fileName: String, type _: T.Type) throws -> T {
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
