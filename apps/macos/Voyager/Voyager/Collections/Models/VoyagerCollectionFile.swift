import Foundation

struct VoyagerCollectionFile: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let id: String
    let name: String
    let createdAt: Date
    let updatedAt: Date
    let query: String
    let scopes: [String]
    let conditions: [CollectionCondition]
    let sortKey: String?
    let sortOrder: String?
    let viewLayout: String?
    let appVersion: String?
}

struct CollectionCondition: Codable, Equatable, Sendable {
    let propertyKey: String
    let operatorCode: String
    let value: JSONValue?

    enum CodingKeys: String, CodingKey {
        case propertyKey
        case operatorCode = "operator"
        case value
    }
}
