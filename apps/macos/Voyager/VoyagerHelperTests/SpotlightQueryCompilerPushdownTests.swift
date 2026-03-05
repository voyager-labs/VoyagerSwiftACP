import Foundation
@testable import VoyagerHelper
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
        XCTAssertEqual(plan.postFilterConditions.count, 0)
    }

    func testCompilePlanKeepsMdimporterLabelPropertyInPostFilter() throws {
        let compiler = try makeCompiler()
        let condition = SearchConditionPayload(
            propertyKey: "removed_notification",
            operator: "eq",
            value: .string("true"),
        )

        let plan = try compiler.compilePlan(conditions: [condition])

        XCTAssertEqual(plan.pushdownConditions.count, 0)
        XCTAssertEqual(plan.postFilterConditions.count, 1)
    }

    func testCompilePlanKeepsNsurlOnlyPropertyInPostFilter() throws {
        let compiler = try makeCompiler()
        let condition = SearchConditionPayload(
            propertyKey: "is_directory",
            operator: "eq",
            value: .bool(true),
        )

        let plan = try compiler.compilePlan(conditions: [condition])

        XCTAssertEqual(plan.pushdownConditions.count, 0)
        XCTAssertEqual(plan.postFilterConditions.count, 1)
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
