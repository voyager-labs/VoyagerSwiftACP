@preconcurrency import CoreServices
import Foundation
@preconcurrency import GRDB
import Logging
import os

final class IncrementalIndexingEventExecutor {
    private struct ApplyOutcome {
        let upserted: Int
        let deleted: Int
        let error: Error?
    }

    private let manager: DatabaseManager
    private let logger: Logging.Logger
    private let eventLogger: os.Logger
    private let homeURL: URL
    private let homePath: String
    private let cachedVolumeIdentifier: String?
    private var directoryCache: [String: Int64] = [:]

    // DB 반영 실행기 초기화
    init(
        manager: DatabaseManager,
        logger: Logging.Logger,
        eventLogger: os.Logger,
        homeURL: URL,
        cachedVolumeIdentifier: String?,
    ) {
        self.manager = manager
        self.logger = logger
        self.eventLogger = eventLogger
        self.homeURL = homeURL
        homePath = homeURL.standardizedFileURL.path
        self.cachedVolumeIdentifier = cachedVolumeIdentifier
    }

    // 변경 경로 적용 및 마지막 이벤트 저장
    func apply(
        changes: [IncrementalIndexingPlannedChange],
        rescanPaths: [String],
        maxEventId: FSEventStreamEventId,
    ) async throws {
        let startedAt = Date()
        do {
            if !changes.isEmpty {
                try await applyChanges(changes)
            }
            if !rescanPaths.isEmpty {
                try await rescanDirectories(rescanPaths)
            }
            try await persistLastEventId(eventId: maxEventId)
            let durationMs = Int(Date().timeIntervalSince(startedAt) * 1000)
            logIncrementalApplySuccess(
                changes: changes.count,
                rescans: rescanPaths.count,
                durationMs: durationMs,
            )
        } catch {
            let durationMs = Int(Date().timeIntervalSince(startedAt) * 1000)
            logIncrementalApplyFailure(
                changes: changes.count,
                rescans: rescanPaths.count,
                durationMs: durationMs,
                error: error,
            )
            throw error
        }
    }

    // 변경 경로 DB 반영
    private func applyChanges(_ changes: [IncrementalIndexingPlannedChange]) async throws {
        let entryRepo = EntryRepository(manager: manager, logger: logger)
        var insertedOrUpdated = 0
        var deleted = 0
        var lastError: Error?

        for change in changes {
            switch change.action {
            case .delete:
                let outcome = await handleDelete(entryRepo: entryRepo, path: change.path)
                deleted += outcome.deleted
                if let error = outcome.error {
                    lastError = error
                }
            case .upsert:
                let outcome = await handleUpsert(entryRepo: entryRepo, path: change.path)
                insertedOrUpdated += outcome.upserted
                deleted += outcome.deleted
                if let error = outcome.error {
                    lastError = error
                }
            }
        }

        if insertedOrUpdated > 0 || deleted > 0 {
            let messageParts = [
                "Incremental indexing applied: upserted=\(insertedOrUpdated)",
                "deleted=\(deleted)",
            ]
            let message = messageParts.joined(separator: ", ")
            eventLogger.info("\(message, privacy: .public)")
        }

        if let lastError {
            throw lastError
        }
    }

    // 삭제 처리
    private func handleDelete(entryRepo: EntryRepository, path: String) async -> ApplyOutcome {
        do {
            let directoryRepo = DirectoryRepository(manager: manager, logger: logger)
            let deletedDirectories = try await directoryRepo.deleteByPathPrefix(path)
            let deletedEntries = try await entryRepo.deleteByPathPrefix(path)
            return ApplyOutcome(upserted: 0, deleted: deletedDirectories + deletedEntries, error: nil)
        } catch {
            eventLogger.error(
                "Incremental indexing delete failed: \(String(describing: error), privacy: .public)",
            )
            return ApplyOutcome(upserted: 0, deleted: 0, error: error)
        }
    }

    // 업서트 처리
    private func handleUpsert(entryRepo: EntryRepository, path: String) async -> ApplyOutcome {
        if !FileManager.default.fileExists(atPath: path) {
            return await handleDelete(entryRepo: entryRepo, path: path)
        }

        guard let mdItem = MDItemCreate(kCFAllocatorDefault, path as CFString) else {
            return ApplyOutcome(upserted: 0, deleted: 0, error: nil)
        }
        let standardizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
        if InitialIndexingRecordBuilder.isDirectory(mdItem: mdItem, path: standardizedPath) {
            do {
                let directoryRepo = DirectoryRepository(manager: manager, logger: logger)
                _ = await resolveDirectoryId(
                    dirPath: standardizedPath,
                    directoryRepo: directoryRepo,
                )
                return ApplyOutcome(upserted: 0, deleted: 0, error: nil)
            } catch {
                eventLogger.error(
                    "Incremental indexing directory upsert failed: \(String(describing: error), privacy: .public)",
                )
                return ApplyOutcome(upserted: 0, deleted: 0, error: error)
            }
        }
        let cachedIdentifier = path.hasPrefix(homePath) ? cachedVolumeIdentifier : nil
        var entryRecord = await InitialIndexingRecordBuilder.makeRecord(
            mdItem: mdItem,
            path: path,
            homeURL: homeURL,
            cachedVolumeIdentifier: cachedIdentifier,
        )
        guard var entryRecord else {
            return ApplyOutcome(upserted: 0, deleted: 0, error: nil)
        }

        do {
            let directoryRepo = DirectoryRepository(manager: manager, logger: logger)
            guard await assignDirectoryId(
                to: &entryRecord,
                directoryRepo: directoryRepo,
            ) else {
                return ApplyOutcome(upserted: 0, deleted: 0, error: nil)
            }
            _ = try await entryRepo.upsertByPath(entryRecord)
            return ApplyOutcome(upserted: 1, deleted: 0, error: nil)
        } catch {
            eventLogger.error(
                "Incremental indexing upsert failed: \(String(describing: error), privacy: .public)",
            )
            return ApplyOutcome(upserted: 0, deleted: 0, error: error)
        }
    }

    // 마지막 이벤트 ID 저장
    private func persistLastEventId(eventId: FSEventStreamEventId) async throws {
        let value = String(eventId)
        try await manager.write { db in
            let sql = """
            INSERT INTO indexing_state (key, value, updated_at)
            VALUES (?, ?, CURRENT_TIMESTAMP)
            ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at
            """
            try db.execute(sql: sql, arguments: ["last_fsevent_id", value])
        }
    }

    // 부분 재스캔 적용
    private func rescanDirectories(_ paths: [String]) async throws {
        var lastError: Error?
        for path in paths {
            do {
                try await rescanDirectory(path: path)
            } catch {
                lastError = error
                eventLogger.error(
                    "Incremental indexing rescan failed: \(String(describing: error), privacy: .public)",
                )
            }
        }
        if let lastError {
            throw lastError
        }
    }

    // 단일 경로 재스캔
    private func rescanDirectory(path: String) async throws {
        let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
        let entryRepo = EntryRepository(manager: manager, logger: logger)

        guard FileManager.default.fileExists(atPath: standardized) else {
            let outcome = await handleDelete(entryRepo: entryRepo, path: standardized)
            if let error = outcome.error {
                throw error
            }
            return
        }

        let directoryRepo = DirectoryRepository(manager: manager, logger: logger)

        let query = try makeQuery(rootPath: standardized)
        let resultCount = Int(MDQueryGetResultCount(query))
        var scannedPaths: Set<String> = []
        scannedPaths.reserveCapacity(resultCount)

        for index in 0 ..< resultCount {
            guard let item = MDQueryGetResultAtIndex(query, index) else { continue }
            let mdItem = unsafeBitCast(item, to: MDItem.self)
            guard let itemPath = MDItemCopyAttribute(mdItem, kMDItemPath) as? String else { continue }
            let standardizedPath = URL(fileURLWithPath: itemPath).standardizedFileURL.path
            if InitialIndexingRecordBuilder.isDirectory(mdItem: mdItem, path: standardizedPath) {
                _ = await resolveDirectoryId(
                    dirPath: standardizedPath,
                    directoryRepo: directoryRepo,
                )
                continue
            }
            scannedPaths.insert(standardizedPath)
            let cachedIdentifier = itemPath.hasPrefix(homePath) ? cachedVolumeIdentifier : nil
            var entryRecord = await InitialIndexingRecordBuilder.makeRecord(
                mdItem: mdItem,
                path: itemPath,
                homeURL: homeURL,
                cachedVolumeIdentifier: cachedIdentifier,
            )
            guard var entryRecord else { continue }
            guard await assignDirectoryId(
                to: &entryRecord,
                directoryRepo: directoryRepo,
            ) else { continue }
            _ = try await entryRepo.upsertByPath(entryRecord)
        }

        let existingPaths = try await fetchExistingPaths(prefix: standardized)
        for existingPath in existingPaths where !scannedPaths.contains(existingPath) {
            _ = try await entryRepo.deleteByPath(existingPath)
        }
    }

    // 재스캔 쿼리 생성
    private func makeQuery(rootPath: String) throws -> MDQuery {
        let queryString = "kMDItemContentTypeTree == \"public.item\""
        guard let query = MDQueryCreate(kCFAllocatorDefault, queryString as CFString, nil, nil) else {
            throw InitialIndexingRunner.IndexingError.queryCreationFailed
        }
        let scopeURL = URL(fileURLWithPath: rootPath) as CFURL
        let scopes = [scopeURL] as CFArray
        MDQuerySetSearchScope(query, scopes, 0)
        let executed = MDQueryExecute(query, CFOptionFlags(kMDQuerySynchronous.rawValue))
        guard executed else {
            throw InitialIndexingRunner.IndexingError.queryExecutionFailed
        }
        return query
    }

    // 재스캔 경로 목록 로드
    private func fetchExistingPaths(prefix: String) async throws -> [String] {
        let likePrefix = prefix.hasSuffix("/") ? "\(prefix)%" : "\(prefix)/%"
        let tableName = EntriesSchema.tableName
        return try await manager.read { db in
            try String.fetchAll(
                db,
                sql: "SELECT path FROM \(tableName) WHERE path = ? OR path LIKE ?",
                arguments: [prefix, likePrefix],
            )
        }
    }
}

private extension IncrementalIndexingEventExecutor {
    func assignDirectoryId(
        to entryRecord: inout EntryRecord,
        directoryRepo: DirectoryRepository,
    ) async -> Bool {
        guard let directoryId = await resolveDirectoryId(
            dirPath: entryRecord.dirPath,
            directoryRepo: directoryRepo,
        ) else {
            let entryPath = entryRecord.path
            eventLogger.error(
                "Incremental indexing skipped entry without directory_id: \(entryPath, privacy: .public)",
            )
            return false
        }
        entryRecord.directoryId = directoryId
        return true
    }

    func resolveDirectoryId(
        dirPath: String,
        directoryRepo: DirectoryRepository,
    ) async -> Int64? {
        if let cached = directoryCache[dirPath] {
            return cached
        }

        let parentId = await resolveParentDirectoryId(
            dirPath: dirPath,
            directoryRepo: directoryRepo,
        )
        let cachedIdentifier = dirPath.hasPrefix(homePath) ? cachedVolumeIdentifier : nil
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
        )
    }

    func depthDelta(from oldValue: Int?, to newValue: Int?) -> Int? {
        guard let oldValue, let newValue else { return nil }
        return newValue - oldValue
    }

    func upsertDirectoryRecord(
        dirPath: String,
        directoryRecord: DirectoryRecord,
        directoryRepo: DirectoryRepository,
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

    func buildPathUpdateRequest(
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

    func resolveParentDirectoryId(
        dirPath: String,
        directoryRepo: DirectoryRepository,
    ) async -> Int64? {
        let parentPath = URL(fileURLWithPath: dirPath)
            .standardizedFileURL
            .deletingLastPathComponent()
            .path
        guard parentPath != dirPath else { return nil }
        return await resolveDirectoryId(
            dirPath: parentPath,
            directoryRepo: directoryRepo,
        )
    }
}

private extension IncrementalIndexingEventExecutor {
    func logIncrementalApplySuccess(
        changes: Int,
        rescans: Int,
        durationMs: Int,
    ) {
        logger.info(
            "Incremental indexing applied",
            metadata: [
                "changes": "\(changes)",
                "rescans": "\(rescans)",
                "duration_ms": "\(durationMs)",
            ],
        )
    }

    func logIncrementalApplyFailure(
        changes: Int,
        rescans: Int,
        durationMs: Int,
        error: Error,
    ) {
        logger.error(
            "Incremental indexing failed",
            metadata: [
                "changes": "\(changes)",
                "rescans": "\(rescans)",
                "duration_ms": "\(durationMs)",
                "error": "\(String(describing: error))",
            ],
        )
    }
}
