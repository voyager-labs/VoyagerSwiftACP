import Foundation
@testable import VoyagerHelper
import VoyagerShared
import XCTest

@MainActor
final class SpotlightQueryCompilerTodayTests: XCTestCase {
    func testCompilePlanPushesDownCategoricalTagNamesToColoredUserTags() throws {
        let compiler = try makeCompiler()
        let condition = SearchConditionPayload(
            propertyKey: "tag_names",
            operator: "any",
            value: .array([.string("Work")]),
        )

        let plan = try compiler.compilePlan(conditions: [condition])

        XCTAssertEqual(plan.pushdownConditions.count, 1)
        XCTAssertTrue(plan.predicate.contains("kMDItemUserTags == \"Work\"c"))
        XCTAssertTrue(plan.predicate.contains("kMDItemUserTags == \"Work\n*\"c"))
    }

    func testCompilePlanPushesDownCategoricalTagNamesNoneToColoredUserTagsNegation() throws {
        let compiler = try makeCompiler()
        let condition = SearchConditionPayload(
            propertyKey: "tag_names",
            operator: "none",
            value: .array([.string("Work")]),
        )

        let plan = try compiler.compilePlan(conditions: [condition])

        XCTAssertEqual(plan.pushdownConditions.count, 1)
        XCTAssertTrue(plan.predicate.contains("!("))
        XCTAssertTrue(plan.predicate.contains("kMDItemUserTags == \"Work\"c"))
        XCTAssertTrue(plan.predicate.contains("kMDItemUserTags == \"Work\n*\"c"))
    }

    func testCompilePlanPreservesTodayLiteralForRecentComparison() throws {
        let compiler = try makeCompiler()
        let condition = SearchConditionPayload(
            propertyKey: "last_used_date",
            operator: "gt",
            value: .string(SearchDateUtils.recentsTodayLiteral),
        )

        let plan = try compiler.compilePlan(conditions: [condition])

        XCTAssertEqual(plan.pushdownConditions.count, 1)
        XCTAssertTrue(plan.predicate.contains("kMDItemLastUsedDate > \(SearchDateUtils.recentsTodayLiteral)"))
    }

    func testTodayOffsetLiteralUsesDayBoundsForDateEquality() throws {
        let compiler = try makeCompiler()
        let condition = SearchConditionPayload(
            propertyKey: "creation_date",
            operator: "eq",
            value: .string("$time.today(0)"),
        )

        let plan = try compiler.compilePlan(conditions: [condition])

        XCTAssertTrue(plan.predicate.contains("kMDItemContentCreationDate >= $time.today(0)"))
        XCTAssertTrue(plan.predicate.contains("kMDItemContentCreationDate < $time.today(1)"))
        XCTAssertFalse(plan.predicate.contains("kMDItemContentCreationDate == $time.today(0)"))
    }

    func testTodayOffsetLiteralUsesNextDayBoundForGreaterThan() throws {
        let compiler = try makeCompiler()
        let condition = SearchConditionPayload(
            propertyKey: "creation_date",
            operator: "gt",
            value: .string("$time.today(0)"),
        )

        let plan = try compiler.compilePlan(conditions: [condition])

        XCTAssertTrue(plan.predicate.contains("kMDItemContentCreationDate >= $time.today(1)"))
        XCTAssertFalse(plan.predicate.contains("kMDItemContentCreationDate > $time.today(0)"))
    }

    func testTodayOffsetLiteralParsesIntoSignedOffset() {
        XCTAssertEqual(SearchDateUtils.todayOffset(for: SearchDateUtils.recentsTodayLiteral), SearchDateUtils.recentsTodayOffset)
        XCTAssertNotNil(SearchDateUtils.parseDateLiteral(SearchDateUtils.recentsTodayLiteral))
    }
}

private extension SpotlightQueryCompilerTodayTests {
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
