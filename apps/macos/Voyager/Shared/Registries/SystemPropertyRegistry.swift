import Foundation

struct SystemPropertyDefinition: Decodable, Equatable {
    let uiLabel: String?
    let description: String
    let type: String
    let searchAliases: [String]?
    let legacyKeys: [String]?
    let systemKeys: [String]
    let availability: String?
    let unitSpec: SystemPropertyUnitSpec?
    let dbIndexed: Bool?
    let uiPinned: Bool?
    let uiHidden: Bool?

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

struct SystemPropertyUnitSpec: Decodable, Equatable {
    let canonicalUnit: String
    let units: [SystemPropertyUnitOption]
    let defaultDisplayUnit: String

    private enum CodingKeys: String, CodingKey {
        case canonicalUnit = "canonical_unit"
        case units
        case defaultDisplayUnit = "default_display_unit"
    }
}

struct SystemPropertyUnitOption: Decodable, Equatable {
    let code: String
    let label: String
    let factorToCanonical: String

    private enum CodingKeys: String, CodingKey {
        case code
        case label
        case factorToCanonical = "factor_to_canonical"
    }
}

struct SystemPropertyRegistry: Decodable {
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
