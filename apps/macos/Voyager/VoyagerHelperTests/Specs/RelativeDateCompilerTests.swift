import Foundation
import VoyagerEntitiesCollection
@testable import VoyagerHelper
import VoyagerShared
import XCTest

@MainActor
final class RelativeDateCompilerTests: XCTestCase {
    func testSearchDateUtilsResolveDateLiteralParsesCanonicalRelativeDateLiteral() {
        let now = Date(timeIntervalSince1970: 1_747_433_600) // 2025-05-17T00:00:00Z
        let literal = "voyager.relativeDate:v1:past:3:day:2025-05-17"

        let resolved = SearchDateUtils.resolveDateLiteral(literal, now: now)

        XCTAssertEqual(resolved.map(SearchDateUtils.dayLiteral), "2025-05-14")
    }

    func testConditionCompilerEqOnRelativeDayLiteralUsesTodayBounds() throws {
        let compiler = try makeCompiler()
        let condition = SearchConditionPayload(
            propertyKey: "creation_date",
            operator: "eq",
            value: .string("voyager.relativeDate:v1:past:3:day:2025-05-17"),
        )

        let plan = try compiler.compilePlan(conditions: [condition])

        XCTAssertTrue(plan.predicate.contains("kMDItemContentCreationDate >= $time.today(-3)"))
        XCTAssertTrue(plan.predicate.contains("kMDItemContentCreationDate < $time.today(-2)"))
        XCTAssertEqual(plan.pushdownConditions, [condition])
    }

    func testConditionCompilerTodayOperatorBuildsTodayPredicateRange() throws {
        let compiler = try makeTodayCompiler()
        let condition = SearchConditionPayload(
            propertyKey: "creation_date",
            operator: "today",
            value: nil,
        )

        let plan = try compiler.compilePlan(conditions: [condition])

        XCTAssertTrue(plan.predicate.contains("kMDItemContentCreationDate >= $time.today(0)"))
        XCTAssertTrue(plan.predicate.contains("kMDItemContentCreationDate < $time.today(1)"))
        XCTAssertEqual(plan.pushdownConditions, [condition])
    }
}

private extension RelativeDateCompilerTests {
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
        let fileURL = rootURL.appendingPathComponent("shared").appendingPathComponent(fileName)
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(T.self, from: data)
    }

    func makeTodayCompiler() throws -> SpotlightQueryCompiler {
        let registryJSON = """
        {
          "property_types": {
            "date": {
              "operators": [
                "today"
              ]
            }
          },
          "operators": {
            "today": {
              "ui_label": "Is today",
              "mdquery_operator": "TODAY",
              "value_shape": "none",
              "value_count": 0,
              "allowed_types": [
                "date"
              ],
              "ui_value_kind": {
                "date": "none"
              }
            }
          }
        }
        """
        let systemJSON = """
        {
          "categories": {
            "common": {
              "creation_date": {
                "ui_label": "Creation date",
                "description": "File creation date",
                "type": "date",
                "system_keys": [
                  "mditem:kMDItemContentCreationDate"
                ]
              }
            }
          }
        }
        """

        let decoder = JSONDecoder()
        let conditionRegistry = try decoder.decode(PropertyConditionRegistry.self, from: Data(registryJSON.utf8))
        let systemRegistry = try decoder.decode(SystemPropertyRegistry.self, from: Data(systemJSON.utf8))
        let builder = SearchConditionBuilder(registry: conditionRegistry, systemRegistry: systemRegistry)
        return SpotlightQueryCompiler(conditionBuilder: builder)
    }
}
