import Foundation
@testable import Voyager
import VoyagerShared

struct LegacyDefinitionOnlyPayload: Codable {
    let schemaVersion: Int
    let id: String
    let name: String
    let createdAt: Date
    let updatedAt: Date
    let query: String
    let scopes: [String]
    let conditions: [CollectionCondition]
    let appVersion: String?
}

struct LegacyNoSchemaPayload: Codable {
    let id: String
    let name: String
    let createdAt: Date
    let updatedAt: Date
    let query: String
    let scopes: [String]
    let conditions: [CollectionCondition]
    let appVersion: String?
}

struct InvalidSnapshotPayload: Codable {
    let schemaVersion: Int
    let id: String
    let name: String
    let createdAt: Date
    let updatedAt: Date
    let query: String
    let scopes: [String]
    let conditions: [CollectionCondition]
    let snapshot: [String: [VoyagerShared.JSONValue]]
    let snapshotMeta: CollectionSnapshotMeta
    let appVersion: String?
}

struct SnapshotOnlyPayload: Codable {
    let schemaVersion: Int
    let id: String
    let name: String
    let createdAt: Date
    let updatedAt: Date
    let query: String
    let scopes: [String]
    let conditions: [CollectionCondition]
    let snapshot: CollectionPersistedSnapshot
    let appVersion: String?
}

struct SnapshotMetaOnlyPayload: Codable {
    let schemaVersion: Int
    let id: String
    let name: String
    let createdAt: Date
    let updatedAt: Date
    let query: String
    let scopes: [String]
    let conditions: [CollectionCondition]
    let snapshotMeta: CollectionSnapshotMeta
    let appVersion: String?
}

struct FutureVersionPayload: Codable {
    let schemaVersion: Int
    let id: String
    let name: String
    let createdAt: Date
    let updatedAt: Date
    let query: String
    let scopes: [String]
    let conditions: [CollectionCondition]
    let snapshot: CollectionPersistedSnapshot?
    let snapshotMeta: CollectionSnapshotMeta?
    let appVersion: String?
}

struct UnrecoverableCorruptionPayload: Codable {
    let schemaVersion: Int
    let id: String
    let name: String
    let createdAt: String
    let updatedAt: String
    let query: String
    let scopes: [String]
    let conditions: [CollectionCondition]
    let appVersion: String?
}
