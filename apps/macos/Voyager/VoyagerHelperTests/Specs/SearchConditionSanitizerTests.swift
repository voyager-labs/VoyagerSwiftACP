import Foundation
import VoyagerEntitiesCollection
@testable import VoyagerHelper
import VoyagerShared
import XCTest

@MainActor
final class SearchConditionSanitizerTests: XCTestCase {
    func testNormalizeAndValidateConvertsOperatorAliasesToCanonical() throws {
        let sanitizer = try makeSanitizer()
        let conditions: [SearchConditionPayload] = [
            .init(propertyKey: "name_stem", operator: "is", value: .string("report")),
            .init(propertyKey: "name_stem", operator: "starts with", value: .string("rep")),
            .init(propertyKey: "size", operator: "between", value: .array([.number(1), .number(10)])),
        ]

        let result = sanitizer.normalizeAndValidate(conditions)

        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result[0].operator, "eq")
        XCTAssertEqual(result[1].operator, "sw")
        XCTAssertEqual(result[2].operator, "btw")
    }

    func testNormalizeAndValidateConvertsEndsWithAndNotBetweenAliases() throws {
        let sanitizer = try makeSanitizer()
        let conditions: [SearchConditionPayload] = [
            .init(propertyKey: "name_stem", operator: "ends with", value: .string("log")),
            .init(
                propertyKey: "size",
                operator: "not between",
                value: .array([.number(10), .number(20)]),
            ),
        ]

        let result = sanitizer.normalizeAndValidate(conditions)

        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].operator, "ew")
        XCTAssertEqual(result[1].operator, "nbtw")
    }

    func testNormalizeAndValidateConvertsContainsAndNotContainsAliases() throws {
        let sanitizer = try makeSanitizer()
        let conditions: [SearchConditionPayload] = [
            .init(propertyKey: "name_stem", operator: "contains", value: .string("report")),
            .init(propertyKey: "name_stem", operator: "not contains", value: .string("draft")),
        ]

        let result = sanitizer.normalizeAndValidate(conditions)

        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].operator, "cn")
        XCTAssertEqual(result[1].operator, "nc")
    }

    func testNormalizeAndValidateConvertsEqualAliasAndRejectsTypeMismatch() throws {
        let sanitizer = try makeSanitizer()
        let conditions: [SearchConditionPayload] = [
            .init(propertyKey: "name_stem", operator: "equals", value: .string("report")),
            .init(propertyKey: "size", operator: "starts with", value: .string("1")),
        ]

        let result = sanitizer.normalizeAndValidate(conditions)

        XCTAssertEqual(result.count, 1)
        if let first = result.first {
            XCTAssertEqual(first.operator, "eq")
            XCTAssertEqual(first.propertyKey, "name_stem")
        }
    }

    func testNormalizeAndValidateDropsUnknownAndInvalidOperators() throws {
        let sanitizer = try makeSanitizer()
        let conditions: [SearchConditionPayload] = [
            .init(propertyKey: "name_stem", operator: "unknown-op", value: .string("x")),
            .init(propertyKey: "name_stem", operator: "eq", value: nil),
            .init(propertyKey: "name_stem", operator: "eq", value: .string("report")),
        ]

        let result = sanitizer.normalizeAndValidate(conditions)

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.propertyKey, "name_stem")
    }

    func testNormalizeAndValidateRequiresRangeShapeForBetweenAlias() throws {
        let sanitizer = try makeSanitizer()
        let conditions: [SearchConditionPayload] = [
            .init(propertyKey: "size", operator: "between", value: .array([.number(1)])),
        ]

        let result = sanitizer.normalizeAndValidate(conditions)
        XCTAssertTrue(result.isEmpty)
    }

    func testNormalizeAndValidateRequiresRangeShapeForNotBetweenAlias() throws {
        let sanitizer = try makeSanitizer()
        let conditions: [SearchConditionPayload] = [
            .init(propertyKey: "size", operator: "not between", value: .array([.number(10)])),
        ]

        let result = sanitizer.normalizeAndValidate(conditions)
        XCTAssertTrue(result.isEmpty)
    }

    func testNormalizeAndValidateSupportsComparisonOperatorsAndDropsUnsupportedRegex() throws {
        let sanitizer = try makeSanitizer()
        let conditions: [SearchConditionPayload] = [
            .init(propertyKey: "name_stem", operator: "regex", value: .string("report.*2026")),
            .init(propertyKey: "size", operator: "!=", value: .number(100)),
            .init(propertyKey: "size", operator: ">=", value: .number(1024)),
            .init(propertyKey: "creation_date", operator: "before", value: .string("2026-01-01")),
        ]

        let result = sanitizer.normalizeAndValidate(conditions)

        XCTAssertEqual(result.count, 3)
        XCTAssertFalse(result.contains(where: { $0.operator == "rx" }))

        XCTAssertEqual(result.first(where: {
            $0.propertyKey == "creation_date"
                && $0.value == .string("2026-01-01")
        })?.operator, "lt")
        XCTAssertTrue(result.contains(where: {
            $0.propertyKey == "size"
                && $0.operator == "gte"
                && $0.value == .number(1024)
        }))
        XCTAssertTrue(result.contains(where: {
            $0.propertyKey == "size"
                && $0.operator == "neq"
                && $0.value == .number(100)
        }))
    }

    func testNormalizeAndValidateSupportsExistenceAndListOperators() throws {
        let sanitizer = try makeSanitizer()
        let conditions: [SearchConditionPayload] = [
            .init(propertyKey: "extension", operator: "exists", value: nil),
            .init(propertyKey: "extension", operator: "empty", value: nil),
            .init(propertyKey: "extension", operator: "any", value: .array([.string("pdf"), .string("jpg")])),
            .init(propertyKey: "keywords", operator: "none", value: .array([.string("draft")])),
            .init(propertyKey: "keywords", operator: "miss", value: .array([.string("archived")])),
        ]

        let result = sanitizer.normalizeAndValidate(conditions)

        XCTAssertEqual(result.count, 5)
        let operators = Set(result.map(\.operator))
        XCTAssertEqual(operators, Set(["exists", "empty", "any", "none", "miss"]))
    }

    func testNormalizeAndValidateRejectsInvalidValueShapeForExistenceAndListOperators() throws {
        let sanitizer = try makeSanitizer()
        let conditions: [SearchConditionPayload] = [
            .init(propertyKey: "extension", operator: "exists", value: .string("x")),
            .init(propertyKey: "extension", operator: "any", value: .array([])),
            .init(propertyKey: "name_stem", operator: "miss", value: .string("x")),
        ]

        let result = sanitizer.normalizeAndValidate(conditions)
        XCTAssertTrue(result.isEmpty)
    }
}

private extension SearchConditionSanitizerTests {
    func makeSanitizer() throws -> SearchConditionSanitizer {
        let conditionRegistry: PropertyConditionRegistry =
            try loadRegistry(fileName: "property_condition_registry.json")
        let systemRegistry: SystemPropertyRegistry = try loadRegistry(fileName: "system_property_registry.json")
        let builder = SearchConditionBuilder(registry: conditionRegistry, systemRegistry: systemRegistry)
        return SearchConditionSanitizer(conditionBuilder: builder)
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
