import Foundation

public enum FileManagerTopNavigationItemID: Equatable, Hashable, Sendable, Codable {
    case location(String)
    case contentTab(ContentTabID)

    private enum CodingKeys: String, CodingKey {
        case kind
        case id
    }

    var isSyntacticallyValid: Bool {
        switch self {
        case let .location(id):
            Self.isValidRawID(id)
        case let .contentTab(id):
            Self.isValidRawID(id.rawValue)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(String.self, forKey: .kind)
        let id = try container.decode(String.self, forKey: .id)
        guard Self.isValidRawID(id) else {
            throw DecodingError.dataCorruptedError(
                forKey: .id,
                in: container,
                debugDescription: "Top navigation item ID must not be empty",
            )
        }

        switch kind {
        case "location":
            self = .location(id)
        case "contentTab":
            self = .contentTab(ContentTabID(rawValue: id))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .kind,
                in: container,
                debugDescription: "Unknown top navigation item kind",
            )
        }
    }

    static func isValidRawID(_ id: String) -> Bool {
        !id.isEmpty
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .location(id):
            try container.encode("location", forKey: .kind)
            try container.encode(id, forKey: .id)
        case let .contentTab(id):
            try container.encode("contentTab", forKey: .kind)
            try container.encode(id.rawValue, forKey: .id)
        }
    }
}

public struct FileManagerTopNavigationOrder: Equatable, Sendable, Codable {
    public var items: [FileManagerTopNavigationItemID]

    public init(items: [FileManagerTopNavigationItemID] = []) {
        self.items = items
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        items = try container.decode([FileManagerTopNavigationItemID].self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(items)
    }
}
