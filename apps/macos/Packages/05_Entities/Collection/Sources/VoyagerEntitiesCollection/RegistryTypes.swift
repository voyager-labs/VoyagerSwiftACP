import Foundation

// MARK: - SystemPropertyTypeKey

public enum SystemPropertyTypeKey: String, Equatable, Sendable {
    case string
    case number
    case date
    case boolean
    case stringList = "string_list"
    case categorical
    case unknown

    public var valueType: String { rawValue }
    var operatorKey: String { rawValue }
    var operatorKeyOrNil: String? { self == .unknown ? nil : rawValue }

    public init(rawType: String) {
        switch rawType.lowercased() {
        case "string": self = .string
        case "number": self = .number
        case "date": self = .date
        case "boolean": self = .boolean
        case "string_list": self = .stringList
        case "categorical": self = .categorical
        default: self = .unknown
        }
    }

    public static func normalizedValueType(from rawType: String) -> String {
        SystemPropertyTypeKey(rawType: rawType).valueType
    }

    static func operatorKey(from rawType: String) -> String {
        SystemPropertyTypeKey(rawType: rawType).operatorKey
    }

    static func operatorKeyOrNil(from rawType: String) -> String? {
        SystemPropertyTypeKey(rawType: rawType).operatorKeyOrNil
    }
}

// MARK: - SystemPropertyDefinition

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
        case uiLabel = "ui_label"; case description; case type
        case searchAliases = "search_aliases"; case legacyKeys = "legacy_keys"
        case systemKeys = "system_keys"; case availability
        case unitSpec = "unit_spec"; case dbIndexed = "db_indexed"
        case uiPinned = "ui_pinned"; case uiHidden = "ui_hidden"
    }
}

// MARK: - SystemPropertyUnitSpec

public struct SystemPropertyUnitSpec: Decodable, Equatable, Sendable {
    public let canonicalUnit: String
    public let units: [SystemPropertyUnitOption]
    public let defaultDisplayUnit: String

    private enum CodingKeys: String, CodingKey {
        case canonicalUnit = "canonical_unit"; case units
        case defaultDisplayUnit = "default_display_unit"
    }
}

public struct SystemPropertyUnitOption: Decodable, Equatable, Sendable {
    public let code: String
    public let label: String
    public let factorToCanonical: String

    private enum CodingKeys: String, CodingKey {
        case code; case label; case factorToCanonical = "factor_to_canonical"
    }
}

// MARK: - OperatorDefinition

public struct OperatorDefinition: Decodable, Equatable, Sendable {
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
        uiValueKind: [String: String]? = nil
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
        case uiLabel = "ui_label"; case mdqueryOperator = "mdquery_operator"
        case valueShape = "value_shape"; case valueCount = "value_count"
        case allowedTypes = "allowed_types"; case inverseOf = "inverse_of"
        case aliases; case uiValueKind = "ui_value_kind"
    }
}

public enum ValueShape: String, Decodable, Sendable {
    case none; case single; case list; case range
}

public enum ValueCount: Decodable, Equatable, Sendable {
    case fixed(Int); case multiple

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intValue = try? container.decode(Int.self) {
            self = .fixed(intValue); return
        }
        let text = try container.decode(String.self)
        if text == "n" { self = .multiple; return }
        throw DecodingError.dataCorruptedError(
            in: container, debugDescription: "Unsupported value_count: \(text)"
        )
    }
}

// MARK: - PropertyConditionRegistry

public struct PropertyConditionRegistry: Decodable, Sendable {
    public let kind: String?
    public let version: String?
    public let propertyTypes: [String: PropertyType]
    public let operators: [String: OperatorDefinition]

    private enum CodingKeys: String, CodingKey {
        case kind = "$kind"; case version = "$version"
        case propertyTypes = "property_types"; case operators
    }
}

public struct PropertyType: Decodable, Sendable {
    public let operators: [String]
}

// MARK: - SystemPropertyRegistry

public struct SystemPropertyRegistry: Decodable, Sendable {
    public let kind: String?
    public let version: String?
    public let categories: [String: [String: SystemPropertyDefinition]]

    private enum CodingKeys: String, CodingKey {
        case kind = "$kind"; case version = "$version"; case categories
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decodeIfPresent(String.self, forKey: .kind)
        version = try container.decodeIfPresent(String.self, forKey: .version)
        categories = try container.decodeIfPresent(
            [String: [String: SystemPropertyDefinition]].self, forKey: .categories
        ) ?? [:]
    }
}
