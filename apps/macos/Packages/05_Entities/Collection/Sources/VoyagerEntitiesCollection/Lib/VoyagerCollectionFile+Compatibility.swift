import Foundation

// swiftlint:disable file_length

public enum CollectionFileSchemaVersion {
    nonisolated public static let definitionOnlyCurrent = SchemaVersion(major: 1, minor: 0)
    nonisolated public static let snapshotBearingCurrent = SchemaVersion(major: 1, minor: 1)
    nonisolated public static let current = snapshotBearingCurrent

    nonisolated public static func inferred(
        snapshot: CollectionPersistedSnapshot?,
        snapshotMeta: CollectionSnapshotMeta?,
    ) -> SchemaVersion {
        if snapshot != nil, snapshotMeta != nil {
            return snapshotBearingCurrent
        }
        return definitionOnlyCurrent
    }

    nonisolated public static func isCurrent(_ version: SchemaVersion) -> Bool {
        version == definitionOnlyCurrent || version == snapshotBearingCurrent
    }
}

public enum CollectionFileContainerFormat: String, Sendable, Equatable {
    case package
    case legacySingleFile
}

public enum CollectionFileCompatibilityWarning: String, Sendable, Equatable {
    case droppedMalformedSnapshot
    case droppedIncompleteSnapshotPair
    case futureMinorVersionReadOnly
}

public enum CollectionFileMigrationStep: String, Sendable, Equatable {
    case legacySingleFileWithoutSchema
    case definitionOnlyV1
    case currentSchemaV2
    case definitionFallbackFromMalformedSnapshot
    case definitionFallbackFromIncompletePair
}

public enum CollectionWriteBackEligibility: String, Sendable, Equatable {
    case allowed
    case blockedLegacyVersionUpgrade
    case blockedDefinitionFallback
    case blockedFutureMinorVersion
    case blockedUnsupportedFutureVersion
}

public struct CollectionFileCompatibilityMetadata: Sendable, Equatable {
    public let sourceSchemaVersion: SchemaVersion?
    public let migrationPath: [CollectionFileMigrationStep]
    public let warnings: [CollectionFileCompatibilityWarning]
    public let usedDefinitionFallback: Bool
    public let writeBackAllowed: Bool
    public let writeBackReason: CollectionWriteBackEligibility

    public init(
        sourceSchemaVersion: SchemaVersion?,
        migrationPath: [CollectionFileMigrationStep],
        warnings: [CollectionFileCompatibilityWarning],
        usedDefinitionFallback: Bool,
        writeBackAllowed: Bool,
        writeBackReason: CollectionWriteBackEligibility,
    ) {
        self.sourceSchemaVersion = sourceSchemaVersion
        self.migrationPath = migrationPath
        self.warnings = warnings
        self.usedDefinitionFallback = usedDefinitionFallback
        self.writeBackAllowed = writeBackAllowed
        self.writeBackReason = writeBackReason
    }
}

public struct CollectionFileLoadResult: Sendable, Equatable {
    public let file: VoyagerCollectionFile
    public let containerFormat: CollectionFileContainerFormat
    public let compatibility: CollectionFileCompatibilityMetadata

    public init(
        file: VoyagerCollectionFile,
        containerFormat: CollectionFileContainerFormat,
        compatibility: CollectionFileCompatibilityMetadata,
    ) {
        self.file = file
        self.containerFormat = containerFormat
        self.compatibility = compatibility
    }
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

public enum CollectionFileCompatibilityError: LocalizedError, Equatable {
    case missingSchemaVersion
    case invalidSchemaVersionType
    case unsupportedFutureSchemaVersion(found: SchemaVersion, current: SchemaVersion)
    case missingPackagePayload
    case invalidDefinitionPayload
    case unrecoverableDocumentCorruption
    case invalidPropertyListPayload

    public var errorDescription: String? {
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
public enum VoyagerCollectionFileCompatibilityOwner {
    private struct SchemaProbe: Equatable {
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

    private enum CurrentSemanticMeaning {
        case definitionOnlyCurrent
        case snapshotBearingCurrent
    }

    public static func decode(
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
            return try decodeDroppingSnapshotIfPossible(
                data,
                schemaProbe: schemaProbe,
                containerFormat: containerFormat,
            )
        }
    }

    public static func normalizeForSave(_ file: VoyagerCollectionFile) -> VoyagerCollectionFile {
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
            excludedScopes: file.excludedScopes,
            includeSubfolders: file.includeSubfolders,
            conditions: file.conditions,
            snapshot: file.snapshot,
            snapshotMeta: file.snapshotMeta,
            appVersion: file.appVersion,
        )
    }

    public static func encodeCurrent(_ file: VoyagerCollectionFile) throws -> Data {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        return try encoder.encode(normalizeForSave(file))
    }

    nonisolated public static func makeLoadResult(
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

        let semanticMeaning = currentSemanticMeaning(for: schemaProbe)
        let writeBackAllowed: Bool = switch semanticMeaning {
        case .definitionOnlyCurrent:
            false
        case .snapshotBearingCurrent:
            usedDefinitionFallback == false
                && sourceSchemaVersion == file.schemaVersion
                && !isFutureMinorVersion(sourceSchemaVersion)
        }

        return .init(
            file: file,
            containerFormat: containerFormat,
            compatibility: .init(
                sourceSchemaVersion: sourceSchemaVersion,
                migrationPath: migrationPath(
                    schemaProbe: schemaProbe,
                    warning: warning,
                    currentSemanticMeaning: semanticMeaning,
                ),
                warnings: combinedWarnings,
                usedDefinitionFallback: usedDefinitionFallback,
                writeBackAllowed: writeBackAllowed,
                writeBackReason: writeBackReason(
                    schemaVersion: effectiveSchemaVersion,
                    fileSchemaVersion: file.schemaVersion,
                    sourceSchemaVersion: sourceSchemaVersion,
                    usedDefinitionFallback: usedDefinitionFallback,
                ),
            ),
        )
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
            excludedScopes: payload.excludedScopes,
            includeSubfolders: payload.includeSubfolders,
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

    nonisolated private static func writeBackReason(
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

    nonisolated private static func migrationPath(
        schemaProbe: SchemaProbe,
        warning: CollectionFileCompatibilityWarning?,
        currentSemanticMeaning: CurrentSemanticMeaning,
    ) -> [CollectionFileMigrationStep] {
        var path: [CollectionFileMigrationStep] = []

        if schemaProbe.sourceSchemaVersion == nil {
            path.append(.legacySingleFileWithoutSchema)
        }

        switch currentSemanticMeaning {
        case .definitionOnlyCurrent:
            path.append(.definitionOnlyV1)
        case .snapshotBearingCurrent:
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

    /// Policy reads semantic meaning first (definition-only current vs snapshot-bearing current),
    /// rather than branching directly on ad-hoc numeric cases at each call site.
    nonisolated private static func currentSemanticMeaning(
        for schemaProbe: SchemaProbe,
    ) -> CurrentSemanticMeaning {
        if schemaProbe.effectiveSchemaVersion == CollectionFileSchemaVersion.definitionOnlyCurrent {
            return .definitionOnlyCurrent
        }
        return .snapshotBearingCurrent
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

    nonisolated private static func isFutureMinorVersion(_ sourceSchemaVersion: SchemaVersion?) -> Bool {
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
            excludedScopes: file.excludedScopes,
            includeSubfolders: file.includeSubfolders,
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

nonisolated private struct CompatibilityPayload: Decodable {
    let schemaVersion: SchemaVersion?
    let id: String
    let name: String
    let createdAt: Date
    let updatedAt: Date
    let query: String
    let scopes: [String]
    let excludedScopes: [String]
    let includeSubfolders: Bool
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
        case excludedScopes
        case includeSubfolders
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
        excludedScopes = try container.decodeIfPresent([String].self, forKey: .excludedScopes) ?? []
        includeSubfolders = try container.decodeIfPresent(Bool.self, forKey: .includeSubfolders) ?? true
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

nonisolated private struct LossyOptionalField<Value: Decodable>: Decodable {
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
