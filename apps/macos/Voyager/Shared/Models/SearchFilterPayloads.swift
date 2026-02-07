struct SearchRequestPayload: Codable, Equatable, Sendable {
    let query: String
    let filters: SearchFiltersPayload
}

struct QuerySearchXPCRequestPayload: Codable, Equatable, Sendable {
    let query: String
    let filters: SearchFiltersPayload
    let backendURL: String?

    var searchRequest: SearchRequestPayload {
        SearchRequestPayload(query: query, filters: filters)
    }
}

struct SearchFiltersPayload: Codable, Equatable, Sendable {
    let scopes: [String]
    let conditions: [SearchConditionPayload]
}

struct SearchConditionPayload: Codable, Equatable, Sendable {
    let propertyKey: String
    let `operator`: String
    let value: JSONValue?

    enum CodingKeys: String, CodingKey {
        case propertyKey
        case `operator`
        case value
    }
}

struct FiltersOnlyRequestPayload: Codable, Equatable, Sendable {
    let filters: SearchFiltersPayload
}

struct SearchResponsePayload: Codable, Equatable, Sendable {
    let itemCount: Int
    let appliedFilters: AppliedFiltersPayload?
    let items: [JSONValue]?
}

struct AppliedFiltersPayload: Codable, Equatable, Sendable {
    let scopes: [String]?
    let conditions: [SearchConditionPayload]?
}

enum JSONValue: Codable, Equatable, Sendable {
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
        } else if let boolValue = try? container.decode(Bool.self) {
            self = .bool(boolValue)
        } else if let numberValue = try? container.decode(Double.self) {
            self = .number(numberValue)
        } else if let stringValue = try? container.decode(String.self) {
            self = .string(stringValue)
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
