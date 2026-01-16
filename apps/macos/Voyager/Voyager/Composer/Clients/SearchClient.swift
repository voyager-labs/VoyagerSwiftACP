import ComposableArchitecture
import Foundation
import SwiftDotenv

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

struct SearchClient: Sendable {
    var search: @Sendable (_ request: SearchRequestPayload) async throws -> SearchResponsePayload
    var applyFilters: @Sendable (_ request: FiltersOnlyRequestPayload) async throws -> SearchResponsePayload
}

extension SearchClient: DependencyKey {
    static let liveValue: SearchClient = {
        @Sendable
        func post<U: Decodable>(path: String, body: some Encodable) async throws -> U {
            let host = "127.0.0.1"
            let port = "53723"
            guard let baseURL = URL(string: "http://\(host):\(port)") else {
                fatalError("Invalid backend base URL")
            }
            let url = baseURL.appendingPathComponent(path)
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            let encoder = JSONEncoder()
            request.httpBody = try encoder.encode(body)

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, 200 ..< 300 ~= http.statusCode else {
                throw URLError(.badServerResponse)
            }

            let decoder = JSONDecoder()
            return try decoder.decode(U.self, from: data)
        }

        return SearchClient(
            search: { request in
                try await post(path: "api/collection", body: request)
            },
            applyFilters: { request in
                try await post(path: "api/collection/filters", body: request)
            },
        )
    }()

    nonisolated(unsafe) static var testValue: SearchClient = .init(
        search: { _ in .init(itemCount: 0, appliedFilters: nil, items: nil) },
        applyFilters: { _ in .init(itemCount: 0, appliedFilters: nil, items: nil) },
    )
}

extension SearchClient: TestDependencyKey {}

extension DependencyValues {
    nonisolated var searchClient: SearchClient {
        get { self[SearchClient.self] }
        set { self[SearchClient.self] = newValue }
    }
}
