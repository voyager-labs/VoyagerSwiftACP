import Foundation

extension VoyagerCollectionFileCompatibilityOwner {
    private nonisolated static func writeBackReason(
        schemaVersion _: SchemaVersion,
        fileSchemaVersion: SchemaVersion,
        sourceSchemaVersion: SchemaVersion?,
        usedDefinitionFallback: Bool,
    ) -> CollectionWriteBackEligibility {
        if usedDefinitionFallback { return .blockedDefinitionFallback }
        if isFutureMinorVersion(sourceSchemaVersion) { return .blockedFutureMinorVersion }
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
        default:
            path.append(.currentSchemaV2)
        }
        switch warning {
        case .droppedMalformedSnapshot:
            path.append(.definitionFallbackFromMalformedSnapshot)
        case .droppedIncompleteSnapshotPair:
            path.append(.definitionFallbackFromIncompletePair)
        case .futureMinorVersionReadOnly, nil:
            break
        }
        return path
    }

    private static func normalizeForRead(
        _ file: VoyagerCollectionFile,
        schemaProbe: SchemaProbe,
    ) -> VoyagerCollectionFile {
        guard schemaProbe.sourceSchemaVersion == nil else { return file }
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
        return .init(file: normalized, warning: .droppedIncompleteSnapshotPair, usedDefinitionFallback: true)
    }

    private static func decodeSnapshotPair(from payload: CompatibilityPayload) -> SnapshotPairDecision {
        switch (payload.snapshot.value, payload.snapshotMeta.value) {
        case let (.some(snapshot), .some(snapshotMeta)):
            return .init(snapshot: snapshot, snapshotMeta: snapshotMeta, warnings: [], usedDefinitionFallback: false)
        case (.none, .none):
            if payload.snapshot.wasPresent || payload.snapshotMeta.wasPresent {
                return .init(
                    snapshot: nil,
                    snapshotMeta: nil,
                    warnings: [.droppedMalformedSnapshot],
                    usedDefinitionFallback: true,
                )
            }
            return .init(snapshot: nil, snapshotMeta: nil, warnings: [], usedDefinitionFallback: false)
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
