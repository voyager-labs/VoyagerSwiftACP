import Foundation

struct RegistrySnapshot: Sendable {
    struct PropertyEntry: Sendable {
        let key: String
        let category: String
        let definition: SystemPropertyDefinition
    }

    private struct PropertyBuild {
        let properties: [PropertyEntry]
        let labels: [String: String]
        let types: [String: String]
        let legacyKeyMap: [String: String]
    }

    let allProperties: [PropertyEntry]
    let propertyKeyToLabel: [String: String]
    let propertyKeyToType: [String: String]
    let legacyKeyMap: [String: String]
    let operatorCodesByKey: [String: [String]]
    let operatorDefinitions: [String: OperatorDefinition]
    let propertyTypes: [String: PropertyType]

    static func load() -> RegistrySnapshot {
        let systemRegistry: SystemPropertyRegistry = loadRegistry(resourceName: "system_property_registry")
        let conditionRegistry: PropertyConditionRegistry = loadRegistry(
            resourceName: "property_condition_registry",
        )

        let propertyBuild = buildProperties(from: systemRegistry)
        let operatorMap = buildOperatorMap(
            properties: propertyBuild.properties,
            conditionRegistry: conditionRegistry,
        )

        return RegistrySnapshot(
            allProperties: propertyBuild.properties,
            propertyKeyToLabel: propertyBuild.labels,
            propertyKeyToType: propertyBuild.types,
            legacyKeyMap: propertyBuild.legacyKeyMap,
            operatorCodesByKey: operatorMap,
            operatorDefinitions: conditionRegistry.operators,
            propertyTypes: conditionRegistry.propertyTypes,
        )
    }

    private static func loadRegistry<T: Decodable>(resourceName: String) -> T {
        do {
            return try RegistryLoader.load(resourceName: resourceName)
        } catch {
            preconditionFailure("\(resourceName) 로드 실패: \(error)")
        }
    }

    private static func buildProperties(from systemRegistry: SystemPropertyRegistry) -> PropertyBuild {
        var properties: [PropertyEntry] = []
        var labels: [String: String] = [:]
        var types: [String: String] = [:]
        var legacyKeyMap: [String: String] = [:]

        for (categoryKey, entries) in systemRegistry.categories {
            for (key, definition) in entries {
                guard let label = definition.uiLabel, !label.isEmpty else {
                    preconditionFailure("ui_label 누락: \(key)")
                }

                properties.append(
                    PropertyEntry(key: key, category: categoryKey, definition: definition),
                )
                labels[key] = label
                types[key] = definition.type
                if let legacyKeys = definition.legacyKeys {
                    for legacyKey in legacyKeys where legacyKeyMap[legacyKey] == nil {
                        legacyKeyMap[legacyKey] = key
                    }
                }
            }
        }

        properties.sort { lhs, rhs in
            let lhsLabel = lhs.definition.uiLabel ?? lhs.key
            let rhsLabel = rhs.definition.uiLabel ?? rhs.key
            return lhsLabel.localizedCaseInsensitiveCompare(rhsLabel) == .orderedAscending
        }

        return PropertyBuild(
            properties: properties,
            labels: labels,
            types: types,
            legacyKeyMap: legacyKeyMap,
        )
    }

    private static func buildOperatorMap(
        properties: [PropertyEntry],
        conditionRegistry: PropertyConditionRegistry,
    ) -> [String: [String]] {
        var operatorMap: [String: [String]] = [:]
        for property in properties {
            let typeKey = conditionTypeKey(for: property.definition.type)
            guard let typeKey else {
                preconditionFailure("지원하지 않는 타입: \(property.definition.type)")
            }
            guard let operatorDefaults = conditionRegistry.propertyTypes[typeKey] else {
                preconditionFailure("property_types 누락: \(typeKey)")
            }
            let options = operatorDefaults.operators.filter { code in
                guard let definition = conditionRegistry.operators[code] else {
                    return false
                }
                return isValidOperator(definition: definition, typeKey: typeKey)
            }
            operatorMap[property.key] = options
        }
        return operatorMap
    }

    private static func isValidOperator(
        definition: OperatorDefinition,
        typeKey: String,
    ) -> Bool {
        guard let label = definition.uiLabel, !label.isEmpty else {
            return false
        }
        guard let uiValueRaw = definition.uiValueKind?[typeKey], !uiValueRaw.isEmpty else {
            return false
        }
        _ = label
        return true
    }

    private static func conditionTypeKey(for rawType: String) -> String? {
        switch rawType.lowercased() {
        case "string": "string"
        case "number": "number"
        case "date", "datetime": "date"
        case "boolean": "boolean"
        case "string_list": "string_list"
        case "categorical": "categorical"
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
