import Foundation

struct SystemPropertyDefinition: Decodable, Equatable, Sendable {
    let uiLabel: String?
    let description: String
    let type: String
    let searchAliases: [String]?
    let systemKeys: [String]
    let availability: String?
    let valueFormat: String?
    let dbIndexed: Bool?
    let uiPinned: Bool?

    private enum CodingKeys: String, CodingKey {
        case uiLabel = "ui_label"
        case description
        case type
        case searchAliases = "search_aliases"
        case systemKeys = "system_keys"
        case availability
        case valueFormat = "value_format"
        case dbIndexed = "db_indexed"
        case uiPinned = "ui_pinned"
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
