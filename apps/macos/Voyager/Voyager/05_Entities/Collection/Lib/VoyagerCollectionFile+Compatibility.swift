import Foundation

enum CollectionFileContainerFormat: String, Sendable, Equatable {
    case package
    case legacySingleFile
}

enum CollectionFileCompatibilityWarning: String, Sendable, Equatable {
    case droppedMalformedSnapshot
    case droppedIncompleteSnapshotPair
}

enum CollectionFileMigrationStep: String, Sendable, Equatable {
    case legacySingleFileWithoutSchema
    case definitionOnlyV1
    case currentSchemaV2
    case definitionFallbackFromMalformedSnapshot
    case definitionFallbackFromIncompletePair
}

enum CollectionWriteBackEligibility: String, Sendable, Equatable {
    case allowed
    case blockedLegacyVersionUpgrade
    case blockedDefinitionFallback
    case blockedUnsupportedFutureVersion
}

struct CollectionFileCompatibilityMetadata: Sendable, Equatable {
    let sourceSchemaVersion: Int?
    let migrationPath: [CollectionFileMigrationStep]
    let warnings: [CollectionFileCompatibilityWarning]
    let usedDefinitionFallback: Bool
    let writeBackAllowed: Bool
    let writeBackReason: CollectionWriteBackEligibility
}

struct CollectionFileLoadResult: Sendable, Equatable {
    let file: VoyagerCollectionFile
    let containerFormat: CollectionFileContainerFormat
    let compatibility: CollectionFileCompatibilityMetadata
}

enum CollectionFileCompatibilityError: LocalizedError, Equatable {
    case missingSchemaVersion
    case invalidSchemaVersionType
    case unsupportedFutureSchemaVersion(found: Int, current: Int)
    case missingPackagePayload
    case invalidDefinitionPayload
    case unrecoverableDocumentCorruption
    case invalidPropertyListPayload

    var errorDescription: String? {
        switch self {
        case .missingSchemaVersion:
            "Collection file is missing schemaVersion."
        case .invalidSchemaVersionType:
            "Collection file has an invalid schemaVersion type."
        case let .unsupportedFutureSchemaVersion(found, current):
            "Collection file schemaVersion \(found) is newer than supported version \(current)."
        case .missingPackagePayload:
            "Missing collection.plist in .voycoll package."
        case .invalidDefinitionPayload:
            "Collection file definition payload is invalid."
        case .unrecoverableDocumentCorruption:
            "Collection file is corrupted and cannot be recovered."
        case .invalidPropertyListPayload:
            "Collection file payload is not a valid property list dictionary."
        }
    }
}

enum VoyagerCollectionFileCompatibilityOwner {
    private struct SchemaProbe: Sendable, Equatable {
        let sourceSchemaVersion: Int?
        let effectiveSchemaVersion: Int
    }

    private struct SnapshotPairDecision {
        let snapshot: CollectionPersistedSnapshot?
        let snapshotMeta: CollectionSnapshotMeta?
        let warnings: [CollectionFileCompatibilityWarning]
        let usedDefinitionFallback: Bool
    }

    private struct DecodedSnapshotPairDecision {
        let file: VoyagerCollectionFile
        let warning: CollectionFileCompatibilityWarning?
        let usedDefinitionFallback: Bool
    }

    static func decode(
        _ data: Data,
        containerFormat: CollectionFileContainerFormat,
    ) throws -> CollectionFileLoadResult {
        let schemaProbe = try rawSchemaVersion(from: data, containerFormat: containerFormat)

        guard schemaProbe.effectiveSchemaVersion <= VoyagerCollectionFile.currentSchemaVersion else {
            throw CollectionFileCompatibilityError.unsupportedFutureSchemaVersion(
                found: schemaProbe.effectiveSchemaVersion,
                current: VoyagerCollectionFile.currentSchemaVersion,
            )
        }

        if schemaProbe.sourceSchemaVersion == nil {
            return try decodeDroppingSnapshotIfPossible(
                data,
                schemaProbe: schemaProbe,
                containerFormat: containerFormat,
            )
        }

        do {
            let decodedFile = try PropertyListDecoder().decode(VoyagerCollectionFile.self, from: data)
            let snapshotDecision = evaluateDecodedSnapshotPair(decodedFile)
            let file = normalizeForRead(snapshotDecision.file, schemaProbe: schemaProbe)
            return .init(
                file: file,
                containerFormat: containerFormat,
                compatibility: .init(
                    sourceSchemaVersion: schemaProbe.sourceSchemaVersion,
                    migrationPath: migrationPath(
                        schemaProbe: schemaProbe,
                        warning: snapshotDecision.warning,
                    ),
                    warnings: snapshotDecision.warning.map { [$0] } ?? [],
                    usedDefinitionFallback: snapshotDecision.usedDefinitionFallback,
                    writeBackAllowed: snapshotDecision.usedDefinitionFallback == false
                        && schemaProbe.sourceSchemaVersion == VoyagerCollectionFile.currentSchemaVersion,
                    writeBackReason: writeBackReason(
                        schemaVersion: schemaProbe.effectiveSchemaVersion,
                        sourceSchemaVersion: schemaProbe.sourceSchemaVersion,
                        usedDefinitionFallback: snapshotDecision.usedDefinitionFallback,
                    ),
                ),
            )
        } catch {
            let fallback = try decodeDroppingSnapshotIfPossible(
                data,
                schemaProbe: schemaProbe,
                containerFormat: containerFormat,
            )
            return fallback
        }
    }

    static func normalizeForSave(_ file: VoyagerCollectionFile) -> VoyagerCollectionFile {
        if file.schemaVersion == VoyagerCollectionFile.currentSchemaVersion {
            return file
        }

        return VoyagerCollectionFile(
            id: file.id,
            name: file.name,
            createdAt: file.createdAt,
            updatedAt: file.updatedAt,
            query: file.query,
            scopes: file.scopes,
            conditions: file.conditions,
            snapshot: file.snapshot,
            snapshotMeta: file.snapshotMeta,
            appVersion: file.appVersion,
        )
    }

    static func encodeCurrent(_ file: VoyagerCollectionFile) throws -> Data {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        return try encoder.encode(normalizeForSave(file))
    }

    private static func rawSchemaVersion(
        from data: Data,
        containerFormat: CollectionFileContainerFormat,
    ) throws -> SchemaProbe {
        let propertyList = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        guard let dictionary = propertyList as? [String: Any] else {
            throw CollectionFileCompatibilityError.invalidPropertyListPayload
        }

        guard let rawValue = dictionary["schemaVersion"] else {
            if containerFormat == .legacySingleFile {
                return .init(sourceSchemaVersion: nil, effectiveSchemaVersion: 1)
            }
            throw CollectionFileCompatibilityError.missingSchemaVersion
        }

        guard let schemaVersion = rawValue as? Int else {
            throw CollectionFileCompatibilityError.invalidSchemaVersionType
        }

        return .init(sourceSchemaVersion: schemaVersion, effectiveSchemaVersion: schemaVersion)
    }

    private static func decodeDroppingSnapshotIfPossible(
        _ data: Data,
        schemaProbe: SchemaProbe,
        containerFormat: CollectionFileContainerFormat,
    ) throws -> CollectionFileLoadResult {
        let payload: CompatibilityPayload
        do {
            payload = try PropertyListDecoder().decode(CompatibilityPayload.self, from: data)
        } catch {
            throw CollectionFileCompatibilityError.unrecoverableDocumentCorruption
        }
        guard payload.id.isEmpty == false else {
            throw CollectionFileCompatibilityError.invalidDefinitionPayload
        }

        let snapshotPair = decodeSnapshotPair(from: payload)
        let file = normalizeForRead(VoyagerCollectionFile(
            schemaVersion: schemaProbe.effectiveSchemaVersion,
            id: payload.id,
            name: payload.name,
            createdAt: payload.createdAt,
            updatedAt: payload.updatedAt,
            query: payload.query,
            scopes: payload.scopes,
            conditions: payload.conditions,
            snapshot: snapshotPair.snapshot,
            snapshotMeta: snapshotPair.snapshotMeta,
            appVersion: payload.appVersion,
        ), schemaProbe: schemaProbe)

        return .init(
            file: file,
            containerFormat: containerFormat,
            compatibility: .init(
                sourceSchemaVersion: schemaProbe.sourceSchemaVersion,
                migrationPath: migrationPath(
                    schemaProbe: schemaProbe,
                    warning: snapshotPair.warnings.first,
                ),
                warnings: snapshotPair.warnings,
                usedDefinitionFallback: snapshotPair.usedDefinitionFallback,
                writeBackAllowed: snapshotPair.usedDefinitionFallback == false
                    && schemaProbe.effectiveSchemaVersion == VoyagerCollectionFile.currentSchemaVersion,
                writeBackReason: writeBackReason(
                    schemaVersion: schemaProbe.effectiveSchemaVersion,
                    sourceSchemaVersion: schemaProbe.sourceSchemaVersion,
                    usedDefinitionFallback: snapshotPair.usedDefinitionFallback,
                ),
            ),
        )
    }

    private static func writeBackReason(
        schemaVersion: Int,
        sourceSchemaVersion: Int?,
        usedDefinitionFallback: Bool,
    ) -> CollectionWriteBackEligibility {
        if usedDefinitionFallback {
            return .blockedDefinitionFallback
        }

        if sourceSchemaVersion == nil || schemaVersion < VoyagerCollectionFile.currentSchemaVersion {
            return .blockedLegacyVersionUpgrade
        }

        return .allowed
    }

    private static func migrationPath(
        schemaProbe: SchemaProbe,
        warning: CollectionFileCompatibilityWarning?,
    ) -> [CollectionFileMigrationStep] {
        var path: [CollectionFileMigrationStep] = []

        if schemaProbe.sourceSchemaVersion == nil {
            path.append(.legacySingleFileWithoutSchema)
        }

        switch schemaProbe.effectiveSchemaVersion {
        case 1:
            path.append(.definitionOnlyV1)
            path.append(.currentSchemaV2)
        default:
            path.append(.currentSchemaV2)
        }

        switch warning {
        case .droppedMalformedSnapshot:
            path.append(.definitionFallbackFromMalformedSnapshot)
        case .droppedIncompleteSnapshotPair:
            path.append(.definitionFallbackFromIncompletePair)
        case nil:
            break
        }

        return path
    }

    private static func normalizeForRead(
        _ file: VoyagerCollectionFile,
        schemaProbe: SchemaProbe,
    ) -> VoyagerCollectionFile {
        guard schemaProbe.sourceSchemaVersion == nil || schemaProbe.effectiveSchemaVersion < VoyagerCollectionFile
            .currentSchemaVersion
        else {
            return file
        }

        return normalizeForSave(file)
    }

    private static func evaluateDecodedSnapshotPair(_ file: VoyagerCollectionFile) -> DecodedSnapshotPairDecision {
        let hasSnapshot = file.snapshot != nil
        let hasSnapshotMeta = file.snapshotMeta != nil

        guard hasSnapshot != hasSnapshotMeta else {
            return .init(file: file, warning: nil, usedDefinitionFallback: false)
        }

        let normalized = VoyagerCollectionFile(
            schemaVersion: file.schemaVersion,
            id: file.id,
            name: file.name,
            createdAt: file.createdAt,
            updatedAt: file.updatedAt,
            query: file.query,
            scopes: file.scopes,
            conditions: file.conditions,
            snapshot: nil,
            snapshotMeta: nil,
            appVersion: file.appVersion,
        )
        return .init(
            file: normalized,
            warning: .droppedIncompleteSnapshotPair,
            usedDefinitionFallback: true,
        )
    }

    private static func decodeSnapshotPair(from payload: CompatibilityPayload) -> SnapshotPairDecision {
        switch (payload.snapshot.value, payload.snapshotMeta.value) {
        case let (.some(snapshot), .some(snapshotMeta)):
            return .init(
                snapshot: snapshot,
                snapshotMeta: snapshotMeta,
                warnings: [],
                usedDefinitionFallback: false,
            )
        case (.none, .none):
            if payload.snapshot.wasPresent || payload.snapshotMeta.wasPresent {
                return .init(
                    snapshot: nil,
                    snapshotMeta: nil,
                    warnings: [.droppedMalformedSnapshot],
                    usedDefinitionFallback: true,
                )
            }
            return .init(
                snapshot: nil,
                snapshotMeta: nil,
                warnings: [],
                usedDefinitionFallback: false,
            )
        default:
            return .init(
                snapshot: nil,
                snapshotMeta: nil,
                warnings: [.droppedIncompleteSnapshotPair],
                usedDefinitionFallback: true,
            )
        }
    }
}

private struct CompatibilityPayload: Decodable {
    let schemaVersion: Int?
    let id: String
    let name: String
    let createdAt: Date
    let updatedAt: Date
    let query: String
    let scopes: [String]
    let conditions: [CollectionCondition]
    let snapshot: LossyOptionalField<CollectionPersistedSnapshot>
    let snapshotMeta: LossyOptionalField<CollectionSnapshotMeta>
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

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        query = try container.decode(String.self, forKey: .query)
        scopes = try container.decode([String].self, forKey: .scopes)
        conditions = try container.decode([CollectionCondition].self, forKey: .conditions)
        snapshot = try container.decodeIfPresent(
            LossyOptionalField<CollectionPersistedSnapshot>.self,
            forKey: .snapshot,
        )
            ?? .missing
        snapshotMeta = try container.decodeIfPresent(
            LossyOptionalField<CollectionSnapshotMeta>.self,
            forKey: .snapshotMeta,
        )
            ?? .missing
        appVersion = try container.decodeIfPresent(String.self, forKey: .appVersion)
    }
}

private struct LossyOptionalField<Value: Decodable>: Decodable {
    let value: Value?
    let wasPresent: Bool

    static var missing: Self {
        .init(value: nil, wasPresent: false)
    }

    init(value: Value?, wasPresent: Bool) {
        self.value = value
        self.wasPresent = wasPresent
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        value = try? container.decode(Value.self)
        wasPresent = true
    }
}
