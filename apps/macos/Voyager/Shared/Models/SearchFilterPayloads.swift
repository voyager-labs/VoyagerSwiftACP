import Foundation

nonisolated struct SearchRequestPayload: Codable, Equatable, Sendable {
    let query: String
    let filters: SearchFiltersPayload
}

nonisolated struct SearchFiltersPayload: Codable, Equatable, Sendable {
    let scopes: [String]
    let includeSubfolders: Bool
    let conditions: [SearchConditionPayload]

    enum CodingKeys: String, CodingKey {
        case scopes
        case includeSubfolders
        case conditions
    }

    init(scopes: [String], includeSubfolders: Bool = true, conditions: [SearchConditionPayload]) {
        self.scopes = scopes
        self.includeSubfolders = includeSubfolders
        self.conditions = conditions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        scopes = try container.decode([String].self, forKey: .scopes)
        includeSubfolders = try container.decodeIfPresent(Bool.self, forKey: .includeSubfolders) ?? true
        conditions = try container.decode([SearchConditionPayload].self, forKey: .conditions)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(scopes, forKey: .scopes)
        try container.encode(includeSubfolders, forKey: .includeSubfolders)
        try container.encode(conditions, forKey: .conditions)
    }
}

nonisolated struct SearchConditionPayload: Codable, Equatable, Sendable {
    let propertyKey: String
    let `operator`: String
    let value: JSONValue?

    enum CodingKeys: String, CodingKey {
        case propertyKey
        case `operator`
        case value
    }
}

nonisolated struct FiltersOnlyRequestPayload: Codable, Equatable, Sendable {
    let filters: SearchFiltersPayload
}

nonisolated struct SearchResponsePayload: Codable, Equatable, Sendable {
    let itemCount: Int
    let appliedFilters: AppliedFiltersPayload?
    let items: [JSONValue]?
    let error: SearchErrorPayload?
}

nonisolated struct AppliedFiltersPayload: Codable, Equatable, Sendable {
    let scopes: [String]?
    let includeSubfolders: Bool?
    let conditions: [SearchConditionPayload]?

    init(scopes: [String]? = nil, includeSubfolders: Bool? = nil, conditions: [SearchConditionPayload]? = nil) {
        self.scopes = scopes
        self.includeSubfolders = includeSubfolders
        self.conditions = conditions
    }
}

nonisolated struct SearchErrorPayload: Codable, Equatable, Sendable {
    let code: String
    let details: String?
}

nonisolated enum RecentTagSearchScopeModePayload: String, Codable, Equatable, Sendable {
    case allIndexed
    case scopedPaths
}

nonisolated enum RecentTagSearchSortPayload: String, Codable, Equatable, Sendable {
    case lastUsedDateDescending
}

nonisolated struct RecentSearchRequestPayload: Codable, Equatable, Sendable {
    let scopeMode: RecentTagSearchScopeModePayload
    let scopes: [String]
    let resultCap: Int
    let includeHidden: Bool
    let sort: RecentTagSearchSortPayload
}

nonisolated struct TagSearchRequestPayload: Codable, Equatable, Sendable {
    let requestedTag: String
    let scopeMode: RecentTagSearchScopeModePayload
    let scopes: [String]
    let resultCap: Int
    let includeHidden: Bool
    let sort: RecentTagSearchSortPayload
    let exactTagVerification: Bool
}

nonisolated struct SearchTagPayload: Codable, Equatable, Sendable {
    let name: String
    let colorCode: Int
}

nonisolated enum SearchEntrySupplementaryMetadataPayload: Codable, Equatable, Sendable {
    case folderItemCount(Int)
    case imageResolution(width: Int, height: Int)
    case compressedFileSize(Int64)

    private enum CodingKeys: String, CodingKey {
        case kind
        case itemCount
        case width
        case height
        case fileSize
    }

    private enum Kind: String, Codable {
        case folderItemCount
        case imageResolution
        case compressedFileSize
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .folderItemCount:
            self = try .folderItemCount(container.decode(Int.self, forKey: .itemCount))
        case .imageResolution:
            self = try .imageResolution(
                width: container.decode(Int.self, forKey: .width),
                height: container.decode(Int.self, forKey: .height),
            )
        case .compressedFileSize:
            self = try .compressedFileSize(container.decode(Int64.self, forKey: .fileSize))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .folderItemCount(itemCount):
            try container.encode(Kind.folderItemCount, forKey: .kind)
            try container.encode(itemCount, forKey: .itemCount)
        case let .imageResolution(width, height):
            try container.encode(Kind.imageResolution, forKey: .kind)
            try container.encode(width, forKey: .width)
            try container.encode(height, forKey: .height)
        case let .compressedFileSize(fileSize):
            try container.encode(Kind.compressedFileSize, forKey: .kind)
            try container.encode(fileSize, forKey: .fileSize)
        }
    }
}

nonisolated struct SearchEntryPayload: Codable, Equatable, Sendable {
    let name: String
    let fullPath: String
    let isFolder: Bool
    let isHidden: Bool
    let size: Int64
    let modifiedDate: Date
    let fileExtension: String
    let createdDate: Date
    let addedDate: Date
    let lastOpenedDate: Date?
    let kind: String
    let creatorApplication: String?
    let tags: [SearchTagPayload]?
    let supplementaryMetadata: SearchEntrySupplementaryMetadataPayload?
}

nonisolated struct RecentSearchResponsePayload: Codable, Equatable, Sendable {
    let items: [SearchEntryPayload]
}

nonisolated struct TagSearchResponsePayload: Codable, Equatable, Sendable {
    let requestedTag: String
    let items: [SearchEntryPayload]
}

nonisolated enum JSONValue: Codable, Equatable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case array([JSONValue])
    case object([String: JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let stringValue = try? container.decode(String.self) {
            self = .string(stringValue)
        } else if let boolValue = try? container.decode(Bool.self) {
            self = .bool(boolValue)
        } else if let numberValue = try? container.decode(Double.self) {
            self = .number(numberValue)
        } else if let arr = try? container.decode([JSONValue].self) {
            self = .array(arr)
        } else if let obj = try? container.decode([String: JSONValue].self) {
            self = .object(obj)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSONValue")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(value):
            try container.encode(value)
        case let .number(value):
            try container.encode(value)
        case let .bool(value):
            try container.encode(value)
        case let .array(value):
            try container.encode(value)
        case let .object(value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
}
