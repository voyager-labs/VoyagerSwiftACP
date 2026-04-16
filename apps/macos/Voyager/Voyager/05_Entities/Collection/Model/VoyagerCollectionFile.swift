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

        try self.init(
            schemaVersion: container.decode(Int.self, forKey: .schemaVersion),
            id: container.decode(String.self, forKey: .id),
            name: container.decode(String.self, forKey: .name),
            createdAt: container.decode(Date.self, forKey: .createdAt),
            updatedAt: container.decode(Date.self, forKey: .updatedAt),
            query: container.decode(String.self, forKey: .query),
            scopes: container.decode([String].self, forKey: .scopes),
            conditions: container.decode([CollectionCondition].self, forKey: .conditions),
            snapshot: snapshot,
            snapshotMeta: snapshotMeta,
            appVersion: container.decodeIfPresent(String.self, forKey: .appVersion),
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
