import Foundation
import VoyagerShared

nonisolated struct SchemaVersion: Codable, Equatable, Comparable, Sendable {
    let major: Int
    let minor: Int

    nonisolated init(major: Int, minor: Int) {
        self.major = major
        self.minor = minor
    }

    nonisolated init(legacyInt: Int) {
        switch legacyInt {
        case 1:
            self.init(major: 1, minor: 0)
        case 2:
            self.init(major: 1, minor: 1)
        default:
            self.init(major: legacyInt, minor: 0)
        }
    }

    nonisolated static func < (lhs: SchemaVersion, rhs: SchemaVersion) -> Bool {
        lhs.major == rhs.major ? lhs.minor < rhs.minor : lhs.major < rhs.major
    }

    private enum CodingKeys: String, CodingKey {
        case major
        case minor
    }

    nonisolated init(from decoder: Decoder) throws {
        if let singleValue = try? decoder.singleValueContainer(),
           let intVersion = try? singleValue.decode(Int.self)
        {
            self.init(legacyInt: intVersion)
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            major: container.decode(Int.self, forKey: .major),
            minor: container.decode(Int.self, forKey: .minor),
        )
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(major, forKey: .major)
        try container.encode(minor, forKey: .minor)
    }
}

struct VoyagerCollectionFile: Codable, Equatable, Sendable {
    let schemaVersion: SchemaVersion
    let id: String
    let name: String
    let createdAt: Date
    let updatedAt: Date
    let query: String
    let scopes: [String]
    let includeSubfolders: Bool
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
        case includeSubfolders
        case conditions
        case snapshot
        case snapshotMeta
        case appVersion
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(SchemaVersion.self, forKey: .schemaVersion)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        query = try container.decode(String.self, forKey: .query)
        scopes = try container.decode([String].self, forKey: .scopes)
        includeSubfolders = try container.decodeIfPresent(Bool.self, forKey: .includeSubfolders) ?? true
        conditions = try container.decode([CollectionCondition].self, forKey: .conditions)
        snapshot = try container.decodeIfPresent(CollectionPersistedSnapshot.self, forKey: .snapshot)
        snapshotMeta = try container.decodeIfPresent(CollectionSnapshotMeta.self, forKey: .snapshotMeta)
        appVersion = try container.decodeIfPresent(String.self, forKey: .appVersion)
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(query, forKey: .query)
        try container.encode(scopes, forKey: .scopes)
        try container.encode(includeSubfolders, forKey: .includeSubfolders)
        try container.encode(conditions, forKey: .conditions)
        try container.encodeIfPresent(snapshot, forKey: .snapshot)
        try container.encodeIfPresent(snapshotMeta, forKey: .snapshotMeta)
        try container.encodeIfPresent(appVersion, forKey: .appVersion)
    }

    nonisolated init(
        schemaVersion: SchemaVersion,
        id: String,
        name: String,
        createdAt: Date,
        updatedAt: Date,
        query: String,
        scopes: [String],
        includeSubfolders: Bool = true,
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
        self.includeSubfolders = includeSubfolders
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
        includeSubfolders: Bool = true,
        conditions: [CollectionCondition],
        snapshot: CollectionPersistedSnapshot?,
        snapshotMeta: CollectionSnapshotMeta?,
        appVersion: String?,
    ) {
        self.init(
            schemaVersion: CollectionFileSchemaVersion.inferred(
                snapshot: snapshot,
                snapshotMeta: snapshotMeta,
            ),
            id: id,
            name: name,
            createdAt: createdAt,
            updatedAt: updatedAt,
            query: query,
            scopes: scopes,
            includeSubfolders: includeSubfolders,
            conditions: conditions,
            snapshot: snapshot,
            snapshotMeta: snapshotMeta,
            appVersion: appVersion,
        )
    }
}

nonisolated struct CollectionPersistedSnapshot: Codable, Equatable, Sendable {
    let items: [VoyagerShared.JSONValue]

    private enum CodingKeys: String, CodingKey {
        case items
    }

    nonisolated init(items: [VoyagerShared.JSONValue]) {
        self.items = items
    }

    nonisolated init(from decoder: Decoder) throws {
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

    nonisolated func encode(to encoder: Encoder) throws {
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

nonisolated struct CollectionSnapshotMeta: Codable, Equatable, Sendable {
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
