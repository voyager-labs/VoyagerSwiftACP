import Foundation

struct RegistrySnapshot: Sendable {
    typealias PropertyEntry = (key: String, category: String, definition: SystemPropertyDefinition)

    let allProperties: [PropertyEntry]
    let propertyKeyToLabel: [String: String]
    let propertyKeyToType: [String: String]
    let operatorCodesByKey: [String: [String]]
    let operatorDefinitions: [String: OperatorDefinition]
    let propertyTypes: [String: PropertyType]

    static func load() -> RegistrySnapshot {
        let systemRegistry: SystemPropertyRegistry
        let conditionRegistry: PropertyConditionRegistry

        do {
            systemRegistry = try RegistryLoader.load(resourceName: "system_property_registry")
        } catch {
            preconditionFailure("SystemPropertyRegistry 로드 실패: \(error)")
        }

        do {
            conditionRegistry = try RegistryLoader.load(resourceName: "property_condition_registry")
        } catch {
            preconditionFailure("PropertyConditionRegistry 로드 실패: \(error)")
        }

        var properties: [PropertyEntry] = []
        var labels: [String: String] = [:]
        var types: [String: String] = [:]
        var operatorMap: [String: [String]] = [:]

        for (categoryKey, entries) in systemRegistry.categories {
            for (key, definition) in entries {
                guard let label = definition.uiLabel, !label.isEmpty else {
                    preconditionFailure("ui_label 누락: \(key)")
                }

                properties.append((key: key, category: categoryKey, definition: definition))
                labels[key] = label
                types[key] = definition.type
            }
        }

        properties.sort { lhs, rhs in
            let lhsLabel = lhs.definition.uiLabel ?? lhs.key
            let rhsLabel = rhs.definition.uiLabel ?? rhs.key
            return lhsLabel.localizedCaseInsensitiveCompare(rhsLabel) == .orderedAscending
        }

        for property in properties {
            let typeKey = conditionTypeKey(for: property.definition.type)
            guard let typeKey else {
                preconditionFailure("지원하지 않는 타입: \(property.definition.type)")
            }
            guard let operatorDefaults = conditionRegistry.propertyTypes[typeKey] else {
                preconditionFailure("property_types 누락: \(typeKey)")
            }
            let options: [String] = operatorDefaults.operators.compactMap { code in
                guard let definition = conditionRegistry.operators[code] else {
                    return nil
                }
                guard let label = definition.uiLabel, !label.isEmpty else {
                    return nil
                }
                guard let uiValueRaw = definition.uiValueKind?[typeKey],
                      !uiValueRaw.isEmpty
                else {
                    return nil
                }
                _ = label
                return code
            }
            operatorMap[property.key] = options
        }

        return RegistrySnapshot(
            allProperties: properties,
            propertyKeyToLabel: labels,
            propertyKeyToType: types,
            operatorCodesByKey: operatorMap,
            operatorDefinitions: conditionRegistry.operators,
            propertyTypes: conditionRegistry.propertyTypes,
        )
    }

    private static func conditionTypeKey(for rawType: String) -> String? {
        switch rawType.lowercased() {
        case "string": "string"
        case "number": "number"
        case "date", "datetime": "date"
        case "boolean": "boolean"
        case "string_list": "string_list"
        default: nil
        }
    }

    private static func valueArity(for kind: String) -> Int {
        switch kind {
        case "rangeNumber", "rangeDate":
            2
        case "none":
            0
        default:
            1
        }
    }
}
