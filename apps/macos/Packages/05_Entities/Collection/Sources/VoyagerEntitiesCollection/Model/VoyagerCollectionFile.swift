import Foundation
import VoyagerShared

public nonisolated struct SchemaVersion: Codable, Equatable, Comparable, Sendable {
    public let major: Int
    public let minor: Int

    public nonisolated init(major: Int, minor: Int) {
        self.major = major
        self.minor = minor
    }

    public nonisolated init(legacyInt: Int) {
        switch legacyInt {
        case 1:
            self.init(major: 1, minor: 0)
        case 2:
            self.init(major: 1, minor: 1)
        default:
            self.init(major: legacyInt, minor: 0)
        }
    }

    public nonisolated static func < (lhs: SchemaVersion, rhs: SchemaVersion) -> Bool {
        lhs.major == rhs.major ? lhs.minor < rhs.minor : lhs.major < rhs.major
    }

    private enum CodingKeys: String, CodingKey {
        case major
        case minor
    }

    public nonisolated init(from decoder: Decoder) throws {
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

    public nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(major, forKey: .major)
        try container.encode(minor, forKey: .minor)
    }
}

public struct VoyagerCollectionFile: Codable, Equatable, Sendable {
    public let schemaVersion: SchemaVersion
    public let id: String
    public let name: String
    public let createdAt: Date
    public let updatedAt: Date
    public let query: String
    public let scopes: [String]
    public let conditions: [CollectionCondition]
    public let snapshot: CollectionPersistedSnapshot?
    public let snapshotMeta: CollectionSnapshotMeta?
    public let appVersion: String?

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

    public nonisolated init(
        schemaVersion: SchemaVersion,
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

    public nonisolated init(
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
            conditions: conditions,
            snapshot: snapshot,
            snapshotMeta: snapshotMeta,
            appVersion: appVersion,
        )
    }
}

public nonisolated struct CollectionPersistedSnapshot: Codable, Equatable, Sendable {
    public let items: [VoyagerShared.JSONValue]

    private enum CodingKeys: String, CodingKey {
        case items
    }

    public nonisolated init(items: [VoyagerShared.JSONValue]) {
        self.items = items
    }

    public nonisolated init(from decoder: Decoder) throws {
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

    public nonisolated func encode(to encoder: Encoder) throws {
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

public nonisolated struct CollectionSnapshotMeta: Codable, Equatable, Sendable {
    public let definitionFingerprint: String
    public let capturedAt: Date
    public let itemCount: Int
    public let relevanceRoots: [String]

    public nonisolated init(
        definitionFingerprint: String,
        capturedAt: Date,
        itemCount: Int,
        relevanceRoots: [String],
    ) {
        self.definitionFingerprint = definitionFingerprint
        self.capturedAt = capturedAt
        self.itemCount = itemCount
        self.relevanceRoots = relevanceRoots
    }
}

public struct CollectionCondition: Codable, Equatable, Sendable {
    public let propertyKey: String
    public let operatorCode: String
    public let value: VoyagerShared.JSONValue?

    public init(propertyKey: String, operatorCode: String, value: VoyagerShared.JSONValue? = nil) {
        self.propertyKey = propertyKey
        self.operatorCode = operatorCode
        self.value = value
    }

    public enum CodingKeys: String, CodingKey {
        case propertyKey
        case operatorCode = "operator"
        case value
    }
}
