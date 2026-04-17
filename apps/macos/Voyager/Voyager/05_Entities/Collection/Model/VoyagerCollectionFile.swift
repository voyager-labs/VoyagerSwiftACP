import Foundation
import VoyagerShared

struct VoyagerCollectionFile: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 2

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

    init(
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
        schemaVersion = Self.currentSchemaVersion
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
}

extension VoyagerCollectionFile {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let snapshot: CollectionPersistedSnapshot?
        let snapshotMeta: CollectionSnapshotMeta?
        do {
            let decodedSnapshot = try container.decodeIfPresent(CollectionPersistedSnapshot.self, forKey: .snapshot)
            let decodedSnapshotMeta = try container.decodeIfPresent(CollectionSnapshotMeta.self, forKey: .snapshotMeta)
            if decodedSnapshot != nil, decodedSnapshotMeta != nil {
                snapshot = decodedSnapshot
                snapshotMeta = decodedSnapshotMeta
            } else {
                snapshot = nil
                snapshotMeta = nil
            }
        } catch {
            snapshot = nil
            snapshotMeta = nil
        }

        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        query = try container.decode(String.self, forKey: .query)
        scopes = try container.decode([String].self, forKey: .scopes)
        conditions = try container.decode([CollectionCondition].self, forKey: .conditions)
        self.snapshot = snapshot
        self.snapshotMeta = snapshotMeta
        appVersion = try container.decodeIfPresent(String.self, forKey: .appVersion)
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
