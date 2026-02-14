import Foundation

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

struct SearchRequestPayload: Codable, Equatable, Sendable {
    let query: String
    let filters: SearchFiltersPayload
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
