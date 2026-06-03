import Foundation
@testable import VoyagerHelper
import VoyagerShared
import XCTest

@MainActor
final class NonNSURLPropertyMDQueryMappingTests: XCTestCase {
    func testCompilePlanMapsAllNonNSURLPropertiesToMDQuery() throws {
        let registries = try loadRegistries()
        let builder = SearchConditionBuilder(registry: registries.condition, systemRegistry: registries.system)
        let compiler = SpotlightQueryCompiler(conditionBuilder: builder)
        let properties = allNonNSURLProperties(from: registries.system)

        XCTAssertGreaterThan(properties.count, 100)

        var failures: [String] = []
        var validatedConditionCount = 0

        for (propertyKey, definition) in properties {
            let result = validateProperty(
                key: propertyKey,
                definition: definition,
                builder: builder,
                registry: registries.condition,
                compiler: compiler,
            )
            validatedConditionCount += result.validatedConditionCount
            failures.append(contentsOf: result.failures)
        }

        XCTAssertGreaterThan(validatedConditionCount, 200)
        XCTAssertTrue(
            failures.isEmpty,
            "비-NSURL Property MDQuery 매핑 실패(\(failures.count)): \n\(failures.prefix(30).joined(separator: "\n"))",
        )
    }

    private func validateProperty(
        key propertyKey: String,
        definition: SystemPropertyDefinition,
        builder: SearchConditionBuilder,
        registry: PropertyConditionRegistry,
        compiler: SpotlightQueryCompiler,
    ) -> (validatedConditionCount: Int, failures: [String]) {
        guard let typeKey = builder.conditionTypeKey(for: definition.type),
              let propertyType = registry.propertyTypes[typeKey]
        else {
            return (0, ["\(propertyKey): missing property type mapping for '\(definition.type)'"])
        }

        var validated = 0
        var failures: [String] = []

        for operatorCode in propertyType.operators {
            guard let operatorDefinition = registry.operators[operatorCode] else {
                failures.append("\(propertyKey): missing operator definition '\(operatorCode)'")
                continue
            }

            if let allowedTypes = operatorDefinition.allowedTypes,
               allowedTypes.contains(typeKey) == false
            {
                continue
            }

            let condition = SearchConditionPayload(
                propertyKey: propertyKey,
                operator: operatorCode,
                value: sampleValue(typeKey: typeKey, valueCount: operatorDefinition.valueCount),
            )

            let plan: SpotlightQueryCompiler.CompilePlan
            do {
                plan = try compiler.compilePlan(conditions: [condition])
            } catch {
                failures.append("\(propertyKey).\(operatorCode): compile failed with \(error)")
                continue
            }

            validated += 1

            if plan.pushdownConditions.count != 1 {
                failures.append(
                    "\(propertyKey).\(operatorCode): expected pushdown=1, got \(plan.pushdownConditions.count)",
                )
                continue
            }

            if plan.predicate.contains(SpotlightQueryCompiler.basePredicate) == false {
                failures.append("\(propertyKey).\(operatorCode): missing base predicate")
            }
        }

        return (validated, failures)
    }

    private func loadRegistries() throws -> (condition: PropertyConditionRegistry, system: SystemPropertyRegistry) {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let voyagerURL = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sharedURL = voyagerURL
            .appendingPathComponent("../../../shared")
            .standardizedFileURL

        let conditionRegistryURL = sharedURL.appendingPathComponent("property_condition_registry.json")
        let systemRegistryURL = sharedURL.appendingPathComponent("system_property_registry.json")

        let decoder = JSONDecoder()
        let conditionRegistry = try decoder.decode(
            PropertyConditionRegistry.self,
            from: Data(contentsOf: conditionRegistryURL),
        )
        let systemRegistry = try decoder.decode(
            SystemPropertyRegistry.self,
            from: Data(contentsOf: systemRegistryURL),
        )

        return (condition: conditionRegistry, system: systemRegistry)
    }

    private func allNonNSURLProperties(
        from registry: SystemPropertyRegistry,
    ) -> [(key: String, definition: SystemPropertyDefinition)] {
        var entries: [(key: String, definition: SystemPropertyDefinition)] = []
        for (_, category) in registry.categories {
            for (key, definition) in category {
                guard definition.systemKeys.isEmpty == false else {
                    continue
                }
                if definition.systemKeys.contains(where: { $0.hasPrefix("nsurl:") }) == false {
                    entries.append((key: key, definition: definition))
                }
            }
        }
        return entries.sorted { $0.key < $1.key }
    }

    private func sampleValue(typeKey: String, valueCount: ValueCount?) -> JSONValue? {
        guard let valueCount else {
            return nil
        }

        switch valueCount {
        case .fixed(0):
            return nil
        case .fixed(1):
            return scalarSampleValue(typeKey: typeKey)
        case .fixed(2):
            return .array([
                scalarSampleValue(typeKey: typeKey),
                secondaryScalarSampleValue(typeKey: typeKey),
            ])
        case .multiple:
            return .array([scalarSampleValue(typeKey: typeKey)])
        default:
            return scalarSampleValue(typeKey: typeKey)
        }
    }

    private func scalarSampleValue(typeKey: String) -> JSONValue {
        switch typeKey {
        case "number":
            .number(10)
        case "boolean":
            .bool(true)
        case "date":
            .string("2026-01-01T00:00:00Z")
        default:
            .string("sample")
        }
    }

    private func secondaryScalarSampleValue(typeKey: String) -> JSONValue {
        switch typeKey {
        case "number":
            .number(20)
        case "boolean":
            .bool(false)
        case "date":
            .string("2026-12-31T23:59:59Z")
        default:
            .string("sample2")
        }
    }
}
