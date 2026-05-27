import Foundation

public struct RegistrySnapshot: Sendable {
    public let allProperties: [PropertyEntry]
    public let propertyKeyToLabel: [String: String]
    public let propertyKeyToType: [String: String]
    public let propertyKeyToUnitSpec: [String: SystemPropertyUnitSpec]
    public let legacyKeyMap: [String: String]
    public let operatorCodesByKey: [String: [String]]
    public let operatorDefinitions: [String: OperatorDefinition]
    public let propertyTypes: [String: PropertyType]

    private struct PropertyBuild {
        let properties: [PropertyEntry]
        let labels: [String: String]
        let types: [String: String]
        let unitSpecs: [String: SystemPropertyUnitSpec]
        let legacyKeyMap: [String: String]
    }

    public struct PropertyEntry: Sendable {
        public let key: String
        public let category: String
        public let definition: SystemPropertyDefinition

        public init(key: String, category: String, definition: SystemPropertyDefinition) {
            self.key = key
            self.category = category
            self.definition = definition
        }
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
        var unitSpecs: [String: SystemPropertyUnitSpec] = [:]
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
                if let unitSpec = definition.unitSpec {
                    unitSpecs[key] = unitSpec
                }
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
            unitSpecs: unitSpecs,
            legacyKeyMap: legacyKeyMap,
        )
    }

    private static func buildOperatorMap(
        properties: [PropertyEntry],
        conditionRegistry: PropertyConditionRegistry,
    ) -> [String: [String]] {
        var operatorMap: [String: [String]] = [:]
        for property in properties {
            let typeKey = SystemPropertyTypeKey.operatorKeyOrNil(from: property.definition.type)
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

    public static func load() -> RegistrySnapshot {
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
            propertyKeyToUnitSpec: propertyBuild.unitSpecs,
            legacyKeyMap: propertyBuild.legacyKeyMap,
            operatorCodesByKey: operatorMap,
            operatorDefinitions: conditionRegistry.operators,
            propertyTypes: conditionRegistry.propertyTypes,
        )
    }
}
