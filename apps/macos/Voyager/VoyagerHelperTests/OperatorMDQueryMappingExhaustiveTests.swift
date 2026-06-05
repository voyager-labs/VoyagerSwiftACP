import Foundation
@testable import VoyagerHelper
import VoyagerShared
import XCTest

@MainActor
final class OperatorMDQueryMappingExhaustiveTests: XCTestCase {
    func testAllNonNSURLVisiblePropertiesCompileExpectedOperatorSemantics() throws {
        let registries = try loadRegistries()
        let builder = SearchConditionBuilder(registry: registries.condition, systemRegistry: registries.system)
        let compiler = SpotlightQueryCompiler(conditionBuilder: builder)
        let properties = allTargetProperties(from: registries.system)

        XCTAssertGreaterThan(properties.count, 100)

        var validated = 0
        var failures: [String] = []

        for (propertyKey, definition) in properties {
            let result = validateProperty(
                key: propertyKey,
                definition: definition,
                builder: builder,
                registry: registries.condition,
                compiler: compiler,
            )
            validated += result.validated
            failures.append(contentsOf: result.failures)
        }

        XCTAssertGreaterThan(validated, 500)
        XCTAssertTrue(failures.isEmpty, failures.joined(separator: "\n"))
    }

    private func validateProperty(
        key propertyKey: String,
        definition: SystemPropertyDefinition,
        builder: SearchConditionBuilder,
        registry: PropertyConditionRegistry,
        compiler: SpotlightQueryCompiler,
    ) -> (validated: Int, failures: [String]) {
        guard let typeKey = builder.conditionTypeKey(for: definition.type),
              let propertyType = registry.propertyTypes[typeKey],
              let attribute = resolveAttributeName(systemKeys: definition.systemKeys)
        else {
            return (0, ["\(propertyKey): missing type mapping or attribute"])
        }

        var validated = 0
        var failures: [String] = []

        for operatorCode in propertyType.operators {
            guard let operatorDefinition = registry.operators[operatorCode] else {
                failures.append("\(propertyKey).\(operatorCode): missing operator definition")
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
                value: sampleValue(
                    typeKey: typeKey,
                    valueCount: operatorDefinition.valueCount,
                    operatorCode: operatorCode,
                ),
            )

            let plan: SpotlightQueryCompiler.CompilePlan
            do {
                plan = try compiler.compilePlan(conditions: [condition])
            } catch {
                failures.append("\(propertyKey).\(operatorCode): compile failed with \(error)")
                continue
            }

            validated += 1

            if let failure = planValidationFailure(
                plan: plan,
                propertyKey: propertyKey,
                operatorCode: operatorCode,
                typeKey: typeKey,
                attribute: attribute,
            ) {
                failures.append(failure)
            }
        }

        return (validated, failures)
    }

    private func allTargetProperties(
        from registry: SystemPropertyRegistry,
    ) -> [(key: String, definition: SystemPropertyDefinition)] {
        var entries: [(key: String, definition: SystemPropertyDefinition)] = []
        for (_, category) in registry.categories {
            for (key, definition) in category {
                if definition.uiHidden == true || definition.systemKeys.contains(where: { $0.hasPrefix("nsurl:") }) {
                    continue
                }
                entries.append((key: key, definition: definition))
            }
        }
        return entries.sorted { $0.key < $1.key }
    }

    private func resolveAttributeName(systemKeys: [String]) -> String? {
        var mdimporterCandidate: String?

        for rawKey in systemKeys {
            let parts = rawKey.split(separator: ":", maxSplits: 1).map(String.init)
            let prefix: String
            let symbol: String
            if parts.count == 2 {
                prefix = parts[0]
                symbol = parts[1]
            } else {
                prefix = ""
                symbol = rawKey
            }

            if symbol.hasPrefix("kMDItem") {
                if prefix == "mditem" {
                    return symbol
                }
                if prefix == "mdimporter", mdimporterCandidate == nil {
                    mdimporterCandidate = symbol
                }
                if prefix.isEmpty {
                    return symbol
                }
            }
        }

        return mdimporterCandidate
    }

    private func sampleValue(typeKey: String, valueCount: ValueCount?, operatorCode: String) -> JSONValue? {
        guard let valueCount else { return nil }

        switch valueCount {
        case .fixed(0):
            return nil
        case .fixed(1):
            return scalar(typeKey: typeKey, operatorCode: operatorCode)
        case .fixed(2):
            return .array([
                scalar(typeKey: typeKey, operatorCode: operatorCode),
                secondaryScalar(typeKey: typeKey),
            ])
        case .multiple:
            return .array([
                scalar(typeKey: typeKey, operatorCode: operatorCode),
                secondaryScalar(typeKey: typeKey),
            ])
        default:
            return scalar(typeKey: typeKey, operatorCode: operatorCode)
        }
    }

    private func scalar(typeKey: String, operatorCode: String) -> JSONValue {
        switch typeKey {
        case "number":
            return .number(10)
        case "boolean":
            return .bool(true)
        case "date":
            return .string("2026-03-02")
        default:
            if operatorCode == "rx" {
                return .string("report*")
            }
            return .string("report")
        }
    }

    private func secondaryScalar(typeKey: String) -> JSONValue {
        switch typeKey {
        case "number":
            .number(20)
        case "boolean":
            .bool(false)
        case "date":
            .string("2026-03-05")
        default:
            .string("archive")
        }
    }

    private func planValidationFailure(
        plan: SpotlightQueryCompiler.CompilePlan,
        propertyKey: String,
        operatorCode: String,
        typeKey: String,
        attribute: String,
    ) -> String? {
        if plan.pushdownConditions.count != 1 {
            return "\(propertyKey).\(operatorCode): expected pushdown=1, got \(plan.pushdownConditions.count)"
        }
        if plan.predicate.contains(SpotlightQueryCompiler.basePredicate) == false {
            return "\(propertyKey).\(operatorCode): missing base predicate"
        }
        if plan.predicate.contains(attribute) == false {
            return "\(propertyKey).\(operatorCode): missing attribute '\(attribute)'"
        }
        if matchesSemanticHint(predicate: plan.predicate, operatorCode: operatorCode, typeKey: typeKey) == false {
            return "\(propertyKey).\(operatorCode): semantic hint mismatch"
        }
        return nil
    }

    private func matchesSemanticHint(predicate: String, operatorCode: String, typeKey: String) -> Bool {
        if let result = matchesTextOperatorHint(predicate: predicate, operatorCode: operatorCode) {
            return result
        }
        if let result = matchesComparisonOperatorHint(predicate: predicate, operatorCode: operatorCode) {
            return result
        }
        if let result = matchesListOperatorHint(predicate: predicate, operatorCode: operatorCode) {
            return result
        }

        if let result = matchesCoreOperatorHint(
            predicate: predicate,
            operatorCode: operatorCode,
            typeKey: typeKey,
        ) {
            return result
        }

        return true
    }

    private func matchesCoreOperatorHint(
        predicate: String,
        operatorCode: String,
        typeKey: String,
    ) -> Bool? {
        switch operatorCode {
        case "exists":
            predicate.contains(" != nil")
        case "empty":
            predicate.contains("== nil ||")
        case "btw":
            typeKey == "date"
                ? (predicate.contains(" >= ") && predicate.contains(" < "))
                : (predicate.contains(" >= ") && predicate.contains(" <= "))
        case "nbtw":
            predicate.contains(" || ")
        case "eq":
            typeKey == "date"
                ? (predicate.contains(" >= ") && predicate.contains(" < "))
                : predicate.contains(" == ")
        case "neq":
            typeKey == "date"
                ? (predicate.contains(" || ") && predicate.contains(" < ") && predicate.contains(" >= "))
                : predicate.contains(" != ")
        case "rx":
            predicate.contains("report")
        default:
            nil
        }
    }

    private func matchesTextOperatorHint(predicate: String, operatorCode: String) -> Bool? {
        switch operatorCode {
        case "sw":
            predicate.contains("\"report*\"")
        case "ew":
            predicate.contains("\"*report\"")
        case "cn":
            predicate.contains("\"*report*\"")
        case "nc":
            predicate.contains("!= \"*report*\"")
        default:
            nil
        }
    }

    private func matchesComparisonOperatorHint(predicate: String, operatorCode: String) -> Bool? {
        switch operatorCode {
        case "gt":
            predicate.contains(" > ")
        case "gte":
            predicate.contains(" >= ")
        case "lt":
            predicate.contains(" < ")
        case "lte":
            predicate.contains(" <= ")
        default:
            nil
        }
    }

    private func matchesListOperatorHint(predicate: String, operatorCode: String) -> Bool? {
        switch operatorCode {
        case "any":
            predicate.contains(" || ") && predicate.contains(" == ")
        case "all":
            predicate.contains(" && ") && predicate.contains(" == ")
        case "none":
            predicate.contains(" && ") && predicate.contains(" != ")
        case "miss":
            predicate.contains(" || ") && predicate.contains(" != ")
        default:
            nil
        }
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
}
