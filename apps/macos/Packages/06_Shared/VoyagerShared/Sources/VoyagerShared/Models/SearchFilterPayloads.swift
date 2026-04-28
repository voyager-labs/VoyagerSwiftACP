import Foundation

public nonisolated struct SearchRequestPayload: Codable, Equatable, Sendable {
    public let query: String
    public let filters: SearchFiltersPayload

    public init(query: String, filters: SearchFiltersPayload) {
        self.query = query
        self.filters = filters
    }
}

public nonisolated struct SearchFiltersPayload: Codable, Equatable, Sendable {
    public let scopes: [String]
    public let conditions: [SearchConditionPayload]

    public init(scopes: [String], conditions: [SearchConditionPayload]) {
        self.scopes = scopes
        self.conditions = conditions
    }
}

public nonisolated struct SearchConditionPayload: Codable, Equatable, Sendable {
    public let propertyKey: String
    public let `operator`: String
    public let value: JSONValue?

    public enum CodingKeys: String, CodingKey {
        case propertyKey
        case `operator`
        case value
    }

    public init(propertyKey: String, operator: String, value: JSONValue? = nil) {
        self.propertyKey = propertyKey
        self.operator = `operator`
        self.value = value
    }
}

public nonisolated struct FiltersOnlyRequestPayload: Codable, Equatable, Sendable {
    public let filters: SearchFiltersPayload

    public init(filters: SearchFiltersPayload) {
        self.filters = filters
    }
}

public nonisolated struct SearchResponsePayload: Codable, Equatable, Sendable {
    public let itemCount: Int
    public let appliedFilters: AppliedFiltersPayload?
    public let items: [JSONValue]?
    public let error: SearchErrorPayload?

    public init(
        itemCount: Int,
        appliedFilters: AppliedFiltersPayload? = nil,
        items: [JSONValue]? = nil,
        error: SearchErrorPayload? = nil,
    ) {
        self.itemCount = itemCount
        self.appliedFilters = appliedFilters
        self.items = items
        self.error = error
    }
}

public nonisolated struct AppliedFiltersPayload: Codable, Equatable, Sendable {
    public let scopes: [String]?
    public let conditions: [SearchConditionPayload]?

    public init(scopes: [String]? = nil, conditions: [SearchConditionPayload]? = nil) {
        self.scopes = scopes
        self.conditions = conditions
    }
}

public nonisolated struct SearchErrorPayload: Codable, Equatable, Sendable {
    public let code: String
    public let details: String?

    public init(code: String, details: String? = nil) {
        self.code = code
        self.details = details
    }
}

public nonisolated enum RecentTagSearchScopeModePayload: String, Codable, Equatable, Sendable {
    case allIndexed
    case scopedPaths
}

public nonisolated enum RecentTagSearchSortPayload: String, Codable, Equatable, Sendable {
    case lastUsedDateDescending
}

public nonisolated struct RecentSearchRequestPayload: Codable, Equatable, Sendable {
    public let scopeMode: RecentTagSearchScopeModePayload
    public let scopes: [String]
    public let resultCap: Int
    public let includeHidden: Bool
    public let sort: RecentTagSearchSortPayload

    public init(
        scopeMode: RecentTagSearchScopeModePayload,
        scopes: [String],
        resultCap: Int,
        includeHidden: Bool,
        sort: RecentTagSearchSortPayload,
    ) {
        self.scopeMode = scopeMode
        self.scopes = scopes
        self.resultCap = resultCap
        self.includeHidden = includeHidden
        self.sort = sort
    }
}

public nonisolated struct TagSearchRequestPayload: Codable, Equatable, Sendable {
    public let requestedTag: String
    public let scopeMode: RecentTagSearchScopeModePayload
    public let scopes: [String]
    public let resultCap: Int
    public let includeHidden: Bool
    public let sort: RecentTagSearchSortPayload
    public let exactTagVerification: Bool

    public init(
        requestedTag: String,
        scopeMode: RecentTagSearchScopeModePayload,
        scopes: [String],
        resultCap: Int,
        includeHidden: Bool,
        sort: RecentTagSearchSortPayload,
        exactTagVerification: Bool,
    ) {
        self.requestedTag = requestedTag
        self.scopeMode = scopeMode
        self.scopes = scopes
        self.resultCap = resultCap
        self.includeHidden = includeHidden
        self.sort = sort
        self.exactTagVerification = exactTagVerification
    }
}

public nonisolated struct SearchTagPayload: Codable, Equatable, Sendable {
    public let name: String
    public let colorCode: Int

    public init(name: String, colorCode: Int) {
        self.name = name
        self.colorCode = colorCode
    }
}

public nonisolated enum SearchEntrySupplementaryMetadataPayload: Codable, Equatable, Sendable {
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

    public init(from decoder: Decoder) throws {
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

    public func encode(to encoder: Encoder) throws {
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

public nonisolated struct SearchEntryPayload: Codable, Equatable, Sendable {
    public let name: String
    public let fullPath: String
    public let isFolder: Bool
    public let isHidden: Bool
    public let size: Int64
    public let modifiedDate: Date
    public let fileExtension: String
    public let createdDate: Date
    public let addedDate: Date
    public let lastOpenedDate: Date?
    public let kind: String
    public let creatorApplication: String?
    public let tags: [SearchTagPayload]?
    public let supplementaryMetadata: SearchEntrySupplementaryMetadataPayload?

    public init(
        name: String,
        fullPath: String,
        isFolder: Bool,
        isHidden: Bool,
        size: Int64,
        modifiedDate: Date,
        fileExtension: String,
        createdDate: Date,
        addedDate: Date,
        lastOpenedDate: Date?,
        kind: String,
        creatorApplication: String?,
        tags: [SearchTagPayload]?,
        supplementaryMetadata: SearchEntrySupplementaryMetadataPayload?,
    ) {
        self.name = name
        self.fullPath = fullPath
        self.isFolder = isFolder
        self.isHidden = isHidden
        self.size = size
        self.modifiedDate = modifiedDate
        self.fileExtension = fileExtension
        self.createdDate = createdDate
        self.addedDate = addedDate
        self.lastOpenedDate = lastOpenedDate
        self.kind = kind
        self.creatorApplication = creatorApplication
        self.tags = tags
        self.supplementaryMetadata = supplementaryMetadata
    }
}

public nonisolated struct RecentSearchResponsePayload: Codable, Equatable, Sendable {
    public let items: [SearchEntryPayload]

    public init(items: [SearchEntryPayload]) {
        self.items = items
    }
}

public nonisolated struct TagSearchResponsePayload: Codable, Equatable, Sendable {
    public let requestedTag: String
    public let items: [SearchEntryPayload]

    public init(requestedTag: String, items: [SearchEntryPayload]) {
        self.requestedTag = requestedTag
        self.items = items
    }
}

public nonisolated enum JSONValue: Codable, Equatable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case array([JSONValue])
    case object([String: JSONValue])
    case null

    public init(from decoder: Decoder) throws {
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

    public func encode(to encoder: Encoder) throws {
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
