import Foundation
import VoyagerShared

struct VoyagerCollectionFile: Codable, Equatable, Sendable {
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

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case id
        case name
        case createdAt
        case updatedAt
        case query
        case scopes
        case conditions
        case snapshot
        case snapshotMeta
        case appVersion
    }

    nonisolated init(
        schemaVersion: Int,
        id: String,
        name: String,
        createdAt: Date,
        updatedAt: Date,
        query: String,
        scopes: [String],
        conditions: [CollectionCondition],
        snapshot: CollectionPersistedSnapshot?,
        snapshotMeta: CollectionSnapshotMeta?,
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
        self.snapshot = snapshot
        self.snapshotMeta = snapshotMeta
        self.appVersion = appVersion
    }

    nonisolated init(
        id: String,
        name: String,
        createdAt: Date,
        updatedAt: Date,
        query: String,
        scopes: [String],
        conditions: [CollectionCondition],
        snapshot: CollectionPersistedSnapshot?,
        snapshotMeta: CollectionSnapshotMeta?,
        appVersion: String?,
    ) {
        self.init(
            schemaVersion: CollectionFileSchemaVersion.current,
            id: id,
            name: name,
            createdAt: createdAt,
            updatedAt: updatedAt,
            query: query,
            scopes: scopes,
            conditions: conditions,
            snapshot: snapshot,
            snapshotMeta: snapshotMeta,
            appVersion: appVersion,
        )
    }
}

struct CollectionPersistedSnapshot: Codable, Equatable, Sendable {
    let items: [VoyagerShared.JSONValue]

    private enum CodingKeys: String, CodingKey {
        case items
    }

    init(items: [VoyagerShared.JSONValue]) {
        self.items = items
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let items = try container.decode([VoyagerShared.JSONValue].self, forKey: .items)
        guard items.allSatisfy({
            if case .string = $0 { return true }
            return false
        }) else {
            throw DecodingError.dataCorruptedError(
                forKey: .items,
                in: container,
                debugDescription: "Collection snapshot items must be path strings only",
            )
        }
        self.items = items
    }

    func encode(to encoder: Encoder) throws {
        guard items.allSatisfy({
            if case .string = $0 { return true }
            return false
        }) else {
            throw EncodingError.invalidValue(
                items,
                .init(
                    codingPath: [CodingKeys.items],
                    debugDescription: "Collection snapshot items must be path strings only",
                ),
            )
        }
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(items, forKey: .items)
    }
}

struct CollectionSnapshotMeta: Codable, Equatable, Sendable {
    let definitionFingerprint: String
    let capturedAt: Date
    let itemCount: Int
    let relevanceRoots: [String]
}

struct CollectionCondition: Codable, Equatable, Sendable {
    let propertyKey: String
    let operatorCode: String
    let value: VoyagerShared.JSONValue?

    enum CodingKeys: String, CodingKey {
        case propertyKey
        case operatorCode = "operator"
        case value
    }
}
