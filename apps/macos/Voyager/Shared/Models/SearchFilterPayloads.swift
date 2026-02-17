nonisolated struct SearchRequestPayload: Codable, Equatable, Sendable {
    let query: String
    let filters: SearchFiltersPayload
}

nonisolated struct SearchFiltersPayload: Codable, Equatable, Sendable {
    let scopes: [String]
    let conditions: [SearchConditionPayload]
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
    let conditions: [SearchConditionPayload]?
}

nonisolated struct SearchErrorPayload: Codable, Equatable, Sendable {
    let code: String
    let details: String?
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
