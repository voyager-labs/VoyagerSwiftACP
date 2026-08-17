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
                    guard Condition.UnitContract(systemPropertyUnitSpec: unitSpec) != nil else {
                        preconditionFailure("Invalid unit factor: \(key)")
                    }
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
            let propertyType = SystemPropertyTypeKey(rawType: property.definition.type)
            let options = operatorDefaults.operators.compactMap { code -> String? in
                guard let definition = conditionRegistry.operators[code] else {
                    preconditionFailure("operator 정의 누락: \(property.key) / \(code) / \(typeKey)")
                }
                do {
                    _ = try validateConditionContract(
                        propertyKey: property.key,
                        operatorCode: code,
                        type: propertyType,
                        definition: definition,
                    )
                    return code
                } catch {
                    preconditionFailure(String(describing: error))
                }
            }
            operatorMap[property.key] = options
        }
        return operatorMap
    }

    static func validateConditionContract(
        propertyKey: String,
        operatorCode: String,
        type: SystemPropertyTypeKey,
        definition: OperatorDefinition,
    ) throws -> Condition.ValueContract {
        let error: (String) -> RegistryContractValidationError = { reason in
            RegistryContractValidationError(
                propertyKey: propertyKey,
                operatorCode: operatorCode,
                type: type,
                reason: reason,
            )
        }
        guard let label = definition.uiLabel, !label.isEmpty else {
            throw error("ui_label is missing")
        }
        guard let allowedTypes = definition.allowedTypes, allowedTypes.contains(type.rawValue) else {
            throw error("allowed_types does not include the property type")
        }
        guard let shape = definition.valueShape, let count = definition.valueCount else {
            throw error("value_shape or value_count is missing")
        }
        guard let inputRaw = definition.uiValueKind?[type.rawValue],
              let input = Condition.ValueInputKind(registryValue: inputRaw)
        else {
            throw error("ui_value_kind is missing or unsupported")
        }

        let isLegal = switch (shape, count, input) {
        case (.none, .fixed(0), .none),
             (.single, .fixed(1), .singleText),
             (.single, .fixed(1), .singleNumber),
             (.single, .fixed(1), .singleDate),
             (.single, .fixed(1), .toggle),
             (.range, .fixed(2), .rangeDate),
             (.range, .fixed(2), .rangeNumber),
             (.list, .multiple, .listText),
             (.list, .multiple, .listNumber):
            true
        default:
            false
        }
        guard isLegal else {
            throw error("value_shape/value_count/ui_value_kind combination is illegal")
        }
        return Condition.ValueContract(shape: shape, count: count, input: input)
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
