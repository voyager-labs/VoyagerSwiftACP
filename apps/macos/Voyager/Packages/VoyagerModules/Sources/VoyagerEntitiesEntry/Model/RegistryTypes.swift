import Foundation

// MARK: - System Property Registry Types

public struct SystemPropertyDefinition: Decodable, Equatable, Sendable {
    public let uiLabel: String?
    public let description: String
    public let type: String
    public let searchAliases: [String]?
    public let legacyKeys: [String]?
    public let systemKeys: [String]
    public let availability: String?
    public let unitSpec: SystemPropertyUnitSpec?
    public let dbIndexed: Bool?
    public let uiPinned: Bool?
    public let uiHidden: Bool?

    private enum CodingKeys: String, CodingKey {
        case uiLabel = "ui_label"
        case description
        case type
        case searchAliases = "search_aliases"
        case legacyKeys = "legacy_keys"
        case systemKeys = "system_keys"
        case availability
        case unitSpec = "unit_spec"
        case dbIndexed = "db_indexed"
        case uiPinned = "ui_pinned"
        case uiHidden = "ui_hidden"
    }
}

public struct SystemPropertyUnitSpec: Decodable, Equatable, Sendable {
    public let canonicalUnit: String
    public let units: [SystemPropertyUnitOption]
    public let defaultDisplayUnit: String

    private enum CodingKeys: String, CodingKey {
        case canonicalUnit = "canonical_unit"
        case units
        case defaultDisplayUnit = "default_display_unit"
    }
}

public struct SystemPropertyUnitOption: Decodable, Equatable, Sendable {
    public let code: String
    public let label: String
    public let factorToCanonical: String

    private enum CodingKeys: String, CodingKey {
        case code
        case label
        case factorToCanonical = "factor_to_canonical"
    }
}

struct SystemPropertyRegistry: Decodable, Sendable {
    let kind: String?
    let version: String?
    let categories: [String: [String: SystemPropertyDefinition]]

    private enum CodingKeys: String, CodingKey {
        case kind = "$kind"
        case version = "$version"
        case categories
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decodeIfPresent(String.self, forKey: .kind)
        version = try container.decodeIfPresent(String.self, forKey: .version)
        categories =
            try container.decodeIfPresent([String: [String: SystemPropertyDefinition]].self, forKey: .categories) ?? [:]
    }
}

// MARK: - Property Condition Registry Types

struct PropertyConditionRegistry: Decodable, Sendable {
    let kind: String?
    let version: String?
    let propertyTypes: [String: PropertyType]
    let operators: [String: OperatorDefinition]

    private enum CodingKeys: String, CodingKey {
        case kind = "$kind"
        case version = "$version"
        case propertyTypes = "property_types"
        case operators
    }
}

struct PropertyType: Decodable, Sendable {
    let operators: [String]
}

public struct OperatorDefinition: Decodable, Sendable {
    public let uiLabel: String?
    public let mdqueryOperator: String?
    public let valueShape: ValueShape?
    public let valueCount: ValueCount?
    public let allowedTypes: [String]?
    public let inverseOf: String?
    public let aliases: [String]?
    public let uiValueKind: [String: String]?

    public init(
        uiLabel: String? = nil,
        mdqueryOperator: String? = nil,
        valueShape: ValueShape? = nil,
        valueCount: ValueCount? = nil,
        allowedTypes: [String]? = nil,
        inverseOf: String? = nil,
        aliases: [String]? = nil,
        uiValueKind: [String: String]? = nil,
    ) {
        self.uiLabel = uiLabel
        self.mdqueryOperator = mdqueryOperator
        self.valueShape = valueShape
        self.valueCount = valueCount
        self.allowedTypes = allowedTypes
        self.inverseOf = inverseOf
        self.aliases = aliases
        self.uiValueKind = uiValueKind
    }

    private enum CodingKeys: String, CodingKey {
        case uiLabel = "ui_label"
        case mdqueryOperator = "mdquery_operator"
        case valueShape = "value_shape"
        case valueCount = "value_count"
        case allowedTypes = "allowed_types"
        case inverseOf = "inverse_of"
        case aliases
        case uiValueKind = "ui_value_kind"
    }
}

public enum ValueShape: String, Decodable, Sendable {
    case none
    case single
    case list
    case range
}

public enum ValueCount: Decodable, Equatable, Sendable {
    case fixed(Int)
    case multiple

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intValue = try? container.decode(Int.self) {
            self = .fixed(intValue)
            return
        }
        let text = try container.decode(String.self)
        if text == "n" {
            self = .multiple
            return
        }
        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "Unsupported value_count: \(text)",
        )
    }
}

// MARK: - Registry Loader

enum RegistryLoader {
    enum LoadError: Error {
        case resourceURLNotFound(name: String, fileExtension: String)
        case decodeFailed(path: String, type: String)
    }

    static func load<T: Decodable>(
        resourceName: String,
        fileExtension: String = "json",
        bundle: Bundle = .main,
    ) throws -> T {
        guard let bundleURL = bundle.url(
            forResource: resourceName,
            withExtension: fileExtension,
        ) else {
            throw LoadError.resourceURLNotFound(name: resourceName, fileExtension: fileExtension)
        }

        do {
            let data = try Data(contentsOf: bundleURL)
            let decoder = JSONDecoder()
            return try decoder.decode(T.self, from: data)
        } catch {
            throw LoadError.decodeFailed(path: bundleURL.path, type: String(describing: T.self))
        }
    }
}

// MARK: - Registry Snapshot

public struct RegistrySnapshot: Sendable {
    public let allProperties: [PropertyEntry]
    let propertyKeyToLabel: [String: String]
    let propertyKeyToType: [String: String]
    public let propertyKeyToUnitSpec: [String: SystemPropertyUnitSpec]
    let legacyKeyMap: [String: String]
    let operatorCodesByKey: [String: [String]]
    let operatorDefinitions: [String: OperatorDefinition]
    let propertyTypes: [String: PropertyType]

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
