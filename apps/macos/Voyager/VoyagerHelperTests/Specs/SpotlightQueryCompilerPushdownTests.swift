import Foundation
import VoyagerEntitiesCollection
@testable import VoyagerHelper
import VoyagerShared
import XCTest

@MainActor
final class SpotlightQueryCompilerPushdownTests: XCTestCase {
    func testCompilePlanPushesDownMditemProperty() throws {
        let compiler = try makeCompiler()
        let condition = SearchConditionPayload(
            propertyKey: "name_stem",
            operator: "eq",
            value: .string("report"),
        )

        let plan = try compiler.compilePlan(conditions: [condition])

        XCTAssertEqual(plan.pushdownConditions.count, 1)
    }

    func testCompilePlanPushesDownMdimporterLabelProperty() throws {
        let compiler = try makeCompiler()
        let condition = SearchConditionPayload(
            propertyKey: "removed_notification",
            operator: "eq",
            value: .string("true"),
        )

        let plan = try compiler.compilePlan(conditions: [condition])

        XCTAssertEqual(plan.pushdownConditions.count, 1)
    }

    func testCompilePlanPushesDownDirectoryExclusionCondition() throws {
        let compiler = try makeCompiler()
        let condition = SearchConditionPayload(
            propertyKey: "content_type_tree",
            operator: "neq",
            value: .string("public.folder"),
        )

        let plan = try compiler.compilePlan(conditions: [condition])

        XCTAssertEqual(plan.pushdownConditions.count, 1)
        XCTAssertTrue(plan.predicate.contains("kMDItemContentTypeTree != \"public.folder\""), plan.predicate)
    }

    func testCompilePlanRejectsHiddenNsurlOnlyProperty() throws {
        let compiler = try makeCompiler()
        let condition = SearchConditionPayload(
            propertyKey: "is_directory",
            operator: "eq",
            value: .bool(true),
        )

        XCTAssertThrowsError(try compiler.compilePlan(conditions: [condition])) { error in
            guard case let SpotlightQueryCompiler.CompileError.hiddenPropertyKey(propertyKey) = error else {
                return XCTFail("Unexpected error: \(error)")
            }

            XCTAssertEqual(propertyKey, "is_directory")
        }
    }
}

private extension SpotlightQueryCompilerPushdownTests {
    func makeCompiler() throws -> SpotlightQueryCompiler {
        let conditionRegistry: PropertyConditionRegistry =
            try loadRegistry(fileName: "property_condition_registry.json")
        let systemRegistry: SystemPropertyRegistry = try loadRegistry(fileName: "system_property_registry.json")
        let builder = SearchConditionBuilder(registry: conditionRegistry, systemRegistry: systemRegistry)
        return SpotlightQueryCompiler(conditionBuilder: builder)
    }

    func loadRegistry<T: Decodable>(fileName: String) throws -> T {
        try RepositorySharedFixture.decode(fileName: fileName, sourceFilePath: #filePath)
    }
}
