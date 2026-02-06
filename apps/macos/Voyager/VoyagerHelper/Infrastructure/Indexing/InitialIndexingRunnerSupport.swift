import Foundation
@preconcurrency import GRDB

extension InitialIndexingRunner {
    static func assignDirectoryId(
        to entryRecord: inout FileRecord,
        homeURL: URL,
        cachedVolumeIdentifier: String?,
        directoryRepo: DirectoryRepository,
        directoryCache: inout [String: Int64],
    ) async -> Bool {
        let directoryPath = parentDirectoryPath(forEntryPath: entryRecord.path)
        entryRecord.dirPath = directoryPath

        let directoryId: Int64? = if let cached = directoryCache[directoryPath] {
            cached
        } else {
            await resolveDirectoryId(
                dirPath: directoryPath,
                homeURL: homeURL,
                cachedVolumeIdentifier: cachedVolumeIdentifier,
                directoryRepo: directoryRepo,
                directoryCache: &directoryCache,
            )
        }

        guard let directoryId else {
            return false
        }

        entryRecord.directoryId = directoryId
        return true
    }

    static func parentDirectoryPath(forEntryPath path: String) -> String {
        URL(fileURLWithPath: path)
            .standardizedFileURL
            .deletingLastPathComponent()
            .path
    }

    static func resolveDirectoryId(
        dirPath: String,
        homeURL: URL,
        cachedVolumeIdentifier: String?,
        directoryRepo: DirectoryRepository,
        directoryCache: inout [String: Int64],
    ) async -> Int64? {
        if let cached = directoryCache[dirPath] {
            return cached
        }

        let parentId = await resolveParentDirectoryId(
            dirPath: dirPath,
            homeURL: homeURL,
            cachedVolumeIdentifier: cachedVolumeIdentifier,
            directoryRepo: directoryRepo,
            directoryCache: &directoryCache,
        )
        let cachedIdentifier = dirPath.hasPrefix(homeURL.path) ? cachedVolumeIdentifier : nil
        guard var directoryRecord = await InitialIndexingRecordBuilder.makeDirectoryRecord(
            path: dirPath,
            homeURL: homeURL,
            cachedVolumeIdentifier: cachedIdentifier,
        ) else {
            return nil
        }
        directoryRecord.parentId = parentId
        return await upsertDirectoryRecord(
            dirPath: dirPath,
            directoryRecord: directoryRecord,
            directoryRepo: directoryRepo,
            directoryCache: &directoryCache,
        )
    }

    static func resolveParentDirectoryId(
        dirPath: String,
        homeURL: URL,
        cachedVolumeIdentifier: String?,
        directoryRepo: DirectoryRepository,
        directoryCache: inout [String: Int64],
    ) async -> Int64? {
        let parentPath = URL(fileURLWithPath: dirPath)
            .standardizedFileURL
            .deletingLastPathComponent()
            .path
        guard parentPath != dirPath else { return nil }
        return await resolveDirectoryId(
            dirPath: parentPath,
            homeURL: homeURL,
            cachedVolumeIdentifier: cachedVolumeIdentifier,
            directoryRepo: directoryRepo,
            directoryCache: &directoryCache,
        )
    }

    static func depthDelta(from oldValue: Int?, to newValue: Int?) -> Int? {
        guard let oldValue, let newValue else { return nil }
        return newValue - oldValue
    }

    static func upsertDirectoryRecord(
        dirPath: String,
        directoryRecord: DirectoryRecord,
        directoryRepo: DirectoryRepository,
        directoryCache: inout [String: Int64],
    ) async -> Int64? {
        do {
            if let volumeIdentifier = directoryRecord.volumeIdentifier,
               let fileResourceIdentifier = directoryRecord.fileResourceIdentifier
            {
                let key = DirectoryLogicalKey(
                    volumeIdentifier: volumeIdentifier,
                    fileResourceIdentifier: fileResourceIdentifier,
                )
                if let existing = try await directoryRepo.fetchByLogicalKey(key),
                   existing.path != directoryRecord.path
                {
                    let request = buildPathUpdateRequest(
                        existing: existing,
                        updated: directoryRecord,
                    )
                    try await directoryRepo.updatePathSubtree(request)
                    directoryCache.removeValue(forKey: existing.path)
                }
                let upserted = try await directoryRepo.upsertByLogicalKey(key, record: directoryRecord)
                if let id = upserted.id {
                    directoryCache[dirPath] = id
                    return id
                }
            } else {
                let upserted = try await directoryRepo.upsertByPath(directoryRecord)
                if let id = upserted.id {
                    directoryCache[dirPath] = id
                    return id
                }
            }
        } catch {
            return nil
        }
        return nil
    }

    static func buildPathUpdateRequest(
        existing: DirectoryRecord,
        updated: DirectoryRecord,
    ) -> DirectoryRepository.PathUpdateRequest {
        let depthDelta = depthDelta(
            from: existing.depthFromHome,
            to: updated.depthFromHome,
        )
        return DirectoryRepository.PathUpdateRequest(
            oldPath: existing.path,
            newPath: updated.path,
            newParentId: updated.parentId,
            newNameFull: updated.nameFull,
            newNameStem: updated.nameStem,
            oldRelativePath: existing.relativePathFromHome,
            newRelativePath: updated.relativePathFromHome,
            depthDelta: depthDelta,
        )
    }

    static func fetchExistingPaths(
        manager: DatabaseManager,
        paths: [String],
    ) async throws -> Set<String> {
        guard !paths.isEmpty else { return [] }
        return try await manager.read { db in
            let placeholders = Array(repeating: "?", count: paths.count).joined(separator: ", ")
            let sql = "SELECT path FROM \(FilesSchema.tableName) WHERE path IN (\(placeholders))"
            let existing = try String.fetchAll(db, sql: sql, arguments: StatementArguments(paths))
            return Set(existing)
        }
    }

    static func updateLastSyncAt(manager: DatabaseManager) async throws {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let value = formatter.string(from: Date())

        try await manager.write { db in
            let sql = """
            INSERT INTO indexing_state (key, value, updated_at)
            VALUES (?, ?, CURRENT_TIMESTAMP)
            ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at
            """
            try db.execute(sql: sql, arguments: ["last_sync_at", value])
        }
    }

    static func emitHeartbeat(_ heartbeat: (@Sendable () async -> Void)?) async {
        guard let heartbeat else { return }
        await heartbeat()
    }

    static func flushBatch(
        _ batch: inout [FileRecord],
        fileRepo: FileRepository,
        inserted: inout Int,
        batchSize: Int,
        keepCapacity: Bool,
    ) async throws {
        guard !batch.isEmpty else { return }
        try await fileRepo.insertBatch(batch, batchSize: batchSize)
        inserted += batch.count
        batch.removeAll(keepingCapacity: keepCapacity)
    }
}
