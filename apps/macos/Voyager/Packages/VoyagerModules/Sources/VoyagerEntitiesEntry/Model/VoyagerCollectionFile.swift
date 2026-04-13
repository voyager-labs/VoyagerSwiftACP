import Foundation
import VoyagerShared

public struct VoyagerCollectionFile: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let id: String
    public let name: String
    public let createdAt: Date
    public let updatedAt: Date
    public let query: String
    public let scopes: [String]
    public let conditions: [CollectionCondition]
    public let appVersion: String?

    public init(
        schemaVersion: Int,
        id: String,
        name: String,
        createdAt: Date,
        updatedAt: Date,
        query: String,
        scopes: [String],
        conditions: [CollectionCondition],
        appVersion: String?,
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.query = query
        self.scopes = scopes
        self.conditions = conditions
        self.appVersion = appVersion
    }

    public struct CollectionCondition: Codable, Equatable, Sendable {
        public let propertyKey: String
        public let operatorCode: String
        public let value: VoyagerShared.JSONValue?

        public enum CodingKeys: String, CodingKey {
            case propertyKey
            case operatorCode = "operator"
            case value
        }

        public init(
            propertyKey: String,
            operatorCode: String,
            value: VoyagerShared.JSONValue?,
        ) {
            self.propertyKey = propertyKey
            self.operatorCode = operatorCode
            self.value = value
        }
    }
}
