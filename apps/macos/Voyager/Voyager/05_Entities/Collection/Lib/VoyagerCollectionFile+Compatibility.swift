import Foundation

// swiftlint:disable file_length

enum CollectionFileSchemaVersion {
    nonisolated static let definitionOnlyCurrent = SchemaVersion(major: 1, minor: 0)
    nonisolated static let snapshotBearingCurrent = SchemaVersion(major: 1, minor: 1)
    nonisolated static let current = snapshotBearingCurrent

    nonisolated static func inferred(
        snapshot: CollectionPersistedSnapshot?,
        snapshotMeta: CollectionSnapshotMeta?,
    ) -> SchemaVersion {
        if snapshot != nil, snapshotMeta != nil {
            return snapshotBearingCurrent
        }
        return definitionOnlyCurrent
    }

    nonisolated static func isCurrent(_ version: SchemaVersion) -> Bool {
        version == definitionOnlyCurrent || version == snapshotBearingCurrent
    }
}

enum CollectionFileContainerFormat: String, Sendable, Equatable {
    case package
    case legacySingleFile
}

enum CollectionFileCompatibilityWarning: String, Sendable, Equatable {
    case droppedMalformedSnapshot
    case droppedIncompleteSnapshotPair
    case futureMinorVersionReadOnly
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
    case blockedFutureMinorVersion
    case blockedUnsupportedFutureVersion
}

struct CollectionFileCompatibilityMetadata: Sendable, Equatable {
    let sourceSchemaVersion: SchemaVersion?
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

private struct VoyagerCollectionFileHeader: Decodable {
    let schemaVersion: SchemaVersion?

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(SchemaVersion.self, forKey: .schemaVersion)
    }
}

enum CollectionFileCompatibilityError: LocalizedError, Equatable {
    case missingSchemaVersion
    case invalidSchemaVersionType
    case unsupportedFutureSchemaVersion(found: SchemaVersion, current: SchemaVersion)
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

// swiftlint:disable type_body_length
enum VoyagerCollectionFileCompatibilityOwner {
    private struct SchemaProbe: Sendable, Equatable {
        let sourceSchemaVersion: SchemaVersion?
        let effectiveSchemaVersion: SchemaVersion
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

        if schemaProbe.effectiveSchemaVersion.major > CollectionFileSchemaVersion.current.major {
            throw CollectionFileCompatibilityError.unsupportedFutureSchemaVersion(
                found: schemaProbe.effectiveSchemaVersion,
                current: CollectionFileSchemaVersion.current,
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
            return makeLoadResult(
                file: file,
                containerFormat: containerFormat,
                sourceSchemaVersion: schemaProbe.sourceSchemaVersion,
                warning: snapshotDecision.warning,
                usedDefinitionFallback: snapshotDecision.usedDefinitionFallback,
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
        let canonicalVersion = CollectionFileSchemaVersion.inferred(
            snapshot: file.snapshot,
            snapshotMeta: file.snapshotMeta,
        )

        if file.schemaVersion == canonicalVersion {
            return file
        }

        return VoyagerCollectionFile(
            schemaVersion: canonicalVersion,
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

    static func compatibilityForCurrentFile(_ file: VoyagerCollectionFile) -> CollectionFileCompatibilityMetadata {
        let snapshotDecision = evaluateDecodedSnapshotPair(file)
        let normalized = snapshotDecision.file
        return makeLoadResult(
            file: normalized,
            containerFormat: .package,
            sourceSchemaVersion: normalized.schemaVersion,
            warning: snapshotDecision.warning,
            usedDefinitionFallback: snapshotDecision.usedDefinitionFallback,
        ).compatibility
    }

    nonisolated static func makeLoadResult(
        file: VoyagerCollectionFile,
        containerFormat: CollectionFileContainerFormat,
        sourceSchemaVersion: SchemaVersion?,
        warning: CollectionFileCompatibilityWarning?,
        usedDefinitionFallback: Bool,
    ) -> CollectionFileLoadResult {
        let effectiveSchemaVersion = sourceSchemaVersion ?? SchemaVersion(major: 1, minor: 0)
        let schemaProbe = SchemaProbe(
            sourceSchemaVersion: sourceSchemaVersion,
            effectiveSchemaVersion: effectiveSchemaVersion,
        )
        let warnings = warning.map { [$0] } ?? []
        let futureMinorWarning = isFutureMinorVersion(sourceSchemaVersion)
            ? CollectionFileCompatibilityWarning.futureMinorVersionReadOnly
            : nil
        let combinedWarnings = warnings + (futureMinorWarning.map { [$0] } ?? [])

        return .init(
            file: file,
            containerFormat: containerFormat,
            compatibility: .init(
                sourceSchemaVersion: sourceSchemaVersion,
                migrationPath: migrationPath(
                    schemaProbe: schemaProbe,
                    warning: warning,
                ),
                warnings: combinedWarnings,
                usedDefinitionFallback: usedDefinitionFallback,
                writeBackAllowed: usedDefinitionFallback == false
                    && sourceSchemaVersion == file.schemaVersion
                    && !isFutureMinorVersion(sourceSchemaVersion),
                writeBackReason: writeBackReason(
                    schemaVersion: effectiveSchemaVersion,
                    fileSchemaVersion: file.schemaVersion,
                    sourceSchemaVersion: sourceSchemaVersion,
                    usedDefinitionFallback: usedDefinitionFallback,
                ),
            ),
        )
    }

    private static func rawSchemaVersion(
        from data: Data,
        containerFormat: CollectionFileContainerFormat,
    ) throws -> SchemaProbe {
        let header: VoyagerCollectionFileHeader
        do {
            header = try PropertyListDecoder().decode(VoyagerCollectionFileHeader.self, from: data)
        } catch let DecodingError.typeMismatch(_, context)
            where context.codingPath.last?.stringValue == "schemaVersion"
        {
            throw CollectionFileCompatibilityError.invalidSchemaVersionType
        } catch let DecodingError.dataCorrupted(context)
            where context.codingPath.isEmpty
        {
            throw CollectionFileCompatibilityError.invalidPropertyListPayload
        } catch let DecodingError.typeMismatch(_, context) where context.codingPath.isEmpty {
            throw CollectionFileCompatibilityError.invalidPropertyListPayload
        } catch {
            throw CollectionFileCompatibilityError.invalidPropertyListPayload
        }

        guard let schemaVersion = header.schemaVersion else {
            if containerFormat == .legacySingleFile {
                return .init(sourceSchemaVersion: nil, effectiveSchemaVersion: SchemaVersion(major: 1, minor: 0))
            }
            throw CollectionFileCompatibilityError.missingSchemaVersion
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

        return makeLoadResult(
            file: file,
            containerFormat: containerFormat,
            sourceSchemaVersion: schemaProbe.sourceSchemaVersion,
            warning: snapshotPair.warnings.first,
            usedDefinitionFallback: snapshotPair.usedDefinitionFallback,
        )
    }

    private nonisolated static func writeBackReason(
        schemaVersion _: SchemaVersion,
        fileSchemaVersion: SchemaVersion,
        sourceSchemaVersion: SchemaVersion?,
        usedDefinitionFallback: Bool,
    ) -> CollectionWriteBackEligibility {
        if usedDefinitionFallback {
            return .blockedDefinitionFallback
        }

        if isFutureMinorVersion(sourceSchemaVersion) {
            return .blockedFutureMinorVersion
        }

        if sourceSchemaVersion == nil || sourceSchemaVersion != fileSchemaVersion {
            return .blockedLegacyVersionUpgrade
        }

        return .allowed
    }

    private nonisolated static func migrationPath(
        schemaProbe: SchemaProbe,
        warning: CollectionFileCompatibilityWarning?,
    ) -> [CollectionFileMigrationStep] {
        var path: [CollectionFileMigrationStep] = []

        if schemaProbe.sourceSchemaVersion == nil {
            path.append(.legacySingleFileWithoutSchema)
        }

        switch schemaProbe.effectiveSchemaVersion {
        case SchemaVersion(major: 1, minor: 0):
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
        case .futureMinorVersionReadOnly:
            break
        case nil:
            break
        }

        return path
    }

    private static func normalizeForRead(
        _ file: VoyagerCollectionFile,
        schemaProbe: SchemaProbe,
    ) -> VoyagerCollectionFile {
        guard schemaProbe.sourceSchemaVersion == nil else {
            return file
        }

        return normalizeForSave(file)
    }

    private nonisolated static func isFutureMinorVersion(_ sourceSchemaVersion: SchemaVersion?) -> Bool {
        guard let sourceSchemaVersion else { return false }
        return sourceSchemaVersion.major == CollectionFileSchemaVersion.current.major
            && sourceSchemaVersion.minor > CollectionFileSchemaVersion.current.minor
    }

    private static func evaluateDecodedSnapshotPair(_ file: VoyagerCollectionFile) -> DecodedSnapshotPairDecision {
        let hasSnapshot = file.snapshot != nil
        let hasSnapshotMeta = file.snapshotMeta != nil

        guard hasSnapshot != hasSnapshotMeta else {
            return .init(file: file, warning: nil, usedDefinitionFallback: false)
        }

        if hasSnapshot == false,
           let snapshotMeta = file.snapshotMeta,
           snapshotMeta.itemCount == 0
        {
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

// swiftlint:enable type_body_length

private nonisolated struct CompatibilityPayload: Decodable {
    let schemaVersion: SchemaVersion?
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

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(SchemaVersion.self, forKey: .schemaVersion)
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

private nonisolated struct LossyOptionalField<Value: Decodable>: Decodable {
    let value: Value?
    let wasPresent: Bool

    nonisolated static var missing: Self {
        .init(value: nil, wasPresent: false)
    }

    nonisolated init(value: Value?, wasPresent: Bool) {
        self.value = value
        self.wasPresent = wasPresent
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        value = try? container.decode(Value.self)
        wasPresent = true
    }
}

// swiftlint:enable file_length
