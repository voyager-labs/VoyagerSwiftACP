@preconcurrency import CoreServices
import Foundation
@preconcurrency import GRDB
import Logging

enum InitialIndexingRunner {
    enum IndexingError: Error {
        case queryCreationFailed
        case queryExecutionFailed
    }

    static func indexHomeDirectoryIfNeeded(
        manager: DatabaseManager,
        logger: Logger,
        batchSize: Int? = nil,
        heartbeat: (@Sendable () async -> Void)? = nil,
    ) async throws -> Int {
        let lastSyncAt: String? = try await manager.read { db -> String? in
            guard try db.tableExists("indexing_state") else { return nil }
            return try String.fetchOne(
                db,
                sql: "SELECT value FROM indexing_state WHERE key = ?",
                arguments: ["last_sync_at"],
            )
        }
        if let lastSyncAt, lastSyncAt != "null" {
            logger.info("Home indexing skipped (last_sync_at already set)")
            return 0
        }

        let pragmaSnapshot = try await IndexingDatabasePragmas.apply(manager: manager)

        do {
            let inserted = try await runHomeIndexing(
                manager: manager,
                logger: logger,
                batchSize: batchSize,
                heartbeat: heartbeat,
            )
            try await updateLastSyncAt(manager: manager)
            await IndexingDatabasePragmas.restore(manager: manager, logger: logger, snapshot: pragmaSnapshot)
            return inserted
        } catch {
            await IndexingDatabasePragmas.restore(manager: manager, logger: logger, snapshot: pragmaSnapshot)
            throw error
        }
    }

    private static func makeQuery(homeURL: URL) throws -> MDQuery {
        let queryString = "kMDItemContentTypeTree == \"public.item\""
        guard let query = MDQueryCreate(kCFAllocatorDefault, queryString as CFString, nil, nil) else {
            throw IndexingError.queryCreationFailed
        }
        let scopes = [homeURL as CFURL] as CFArray
        MDQuerySetSearchScope(query, scopes, 0)
        let executed = MDQueryExecute(query, CFOptionFlags(kMDQuerySynchronous.rawValue))
        guard executed else {
            throw IndexingError.queryExecutionFailed
        }
        return query
    }

    private static func runHomeIndexing(
        manager: DatabaseManager,
        logger: Logger,
        batchSize: Int?,
        heartbeat: (@Sendable () async -> Void)?,
    ) async throws -> Int {
        let startedAt = Date()
        let homeURL = FileManager.default.homeDirectoryForCurrentUser
        let cachedVolumeIdentifier = InitialIndexingRecordBuilder.volumeIdentifier(from: homeURL)
        let query = try makeQuery(homeURL: homeURL)
        let resultCount = Int(MDQueryGetResultCount(query))
        logger.info(
            "Home indexing started",
            metadata: ["spotlight_results": "\(resultCount)"],
        )
        VoyagerSentryMetricLogger.logMetric(
            "voyager_initial_index_job",
            value: 1,
            tags: [
                "stage": "home_start",
                "spotlight_results": "\(resultCount)",
            ],
        )

        let plan = try await prepareBatchPlan(manager: manager, logger: logger, batchSize: batchSize)
        let context = ProcessContext(
            manager: manager,
            homeURL: homeURL,
            cachedVolumeIdentifier: cachedVolumeIdentifier,
            plan: plan,
            heartbeat: heartbeat,
        )
        let inserted = try await processQueryResults(query: query, resultCount: resultCount, context: context)
        let durationMs = Int(Date().timeIntervalSince(startedAt) * 1000)
        logger.info(
            "Home indexing completed",
            metadata: [
                "inserted": "\(inserted)",
                "duration_ms": "\(durationMs)",
            ],
        )
        VoyagerSentryMetricLogger.logMetric(
            "voyager_initial_index_job",
            value: 1,
            tags: [
                "stage": "home_completed",
                "inserted": "\(inserted)",
            ],
        )
        VoyagerSentryMetricLogger.logMetric(
            "voyager_initial_index_job_duration_ms",
            value: Double(durationMs),
            tags: [
                "scope": "home",
            ],
        )
        return inserted
    }

    struct IndexedItem {
        let mdItem: MDItem
        let path: String
    }

    private struct BatchPlan {
        let fileRepo: FileRepository
        let directoryRepo: DirectoryRepository
        let effectiveBatchSize: Int
        let pathBatchSize: Int
    }

    private struct ProcessContext {
        let manager: DatabaseManager
        let homeURL: URL
        let cachedVolumeIdentifier: String?
        let plan: BatchPlan
        let heartbeat: (@Sendable () async -> Void)?
    }

    private struct AppendContext {
        let homeURL: URL
        let cachedVolumeIdentifier: String?
        let fileRepo: FileRepository
        let directoryRepo: DirectoryRepository
        let batchSize: Int
    }

    private static func processQueryResults(
        query: MDQuery,
        resultCount: Int,
        context: ProcessContext,
    ) async throws -> Int {
        let fileRepo = context.plan.fileRepo
        let directoryRepo = context.plan.directoryRepo
        let effectiveBatchSize = context.plan.effectiveBatchSize
        var inserted = 0
        var batch: [FileRecord] = []
        batch.reserveCapacity(effectiveBatchSize)
        var directoryCache: [String: Int64] = [:]

        let pathBatchSize = context.plan.pathBatchSize
        let appendContext = AppendContext(
            homeURL: context.homeURL,
            cachedVolumeIdentifier: context.cachedVolumeIdentifier,
            fileRepo: fileRepo,
            directoryRepo: directoryRepo,
            batchSize: effectiveBatchSize,
        )
        var index = 0
        while index < resultCount {
            let end = min(index + pathBatchSize, resultCount)
            let items = loadItems(query: query, range: index ..< end)
            let existingPaths = try await fetchExistingPaths(manager: context.manager, paths: items.map(\.path))

            try await appendRecords(
                items: items,
                existingPaths: existingPaths,
                context: appendContext,
                batch: &batch,
                inserted: &inserted,
                directoryCache: &directoryCache,
            )

            await emitHeartbeat(context.heartbeat)
            index = end
        }

        try await flushBatch(
            &batch,
            fileRepo: fileRepo,
            inserted: &inserted,
            batchSize: effectiveBatchSize,
            keepCapacity: false,
        )
        await emitHeartbeat(context.heartbeat)
        return inserted
    }

    private static func prepareBatchPlan(
        manager: DatabaseManager,
        logger: Logger,
        batchSize: Int?,
    ) async throws -> BatchPlan {
        let fileRepo = FileRepository(manager: manager, logger: logger)
        let directoryRepo = DirectoryRepository(manager: manager, logger: logger)
        let maxBatchSize = try await manager.read { db in
            try FileRepository.maxBatchSize(in: db)
        }
        let maxPathBatchSize = try await manager.read { db in
            try Int.fetchOne(db, sql: "PRAGMA max_variable_number") ?? 999
        }
        let effectiveBatchSize = batchSize ?? maxBatchSize
        let pathBatchSize = min(maxPathBatchSize, max(1000, effectiveBatchSize))
        return BatchPlan(
            fileRepo: fileRepo,
            directoryRepo: directoryRepo,
            effectiveBatchSize: effectiveBatchSize,
            pathBatchSize: pathBatchSize,
        )
    }

    private static func loadItems(query: MDQuery, range: Range<Int>) -> [IndexedItem] {
        var items: [IndexedItem] = []
        items.reserveCapacity(range.count)

        for index in range {
            guard let item = MDQueryGetResultAtIndex(query, index) else { continue }
            let mdItem = unsafeBitCast(item, to: MDItem.self)
            guard let path = MDItemCopyAttribute(mdItem, kMDItemPath) as? String else {
                continue
            }
            items.append(IndexedItem(mdItem: mdItem, path: path))
        }

        return items
    }

    private static func appendRecords(
        items: [IndexedItem],
        existingPaths: Set<String>,
        context: AppendContext,
        batch: inout [FileRecord],
        inserted: inout Int,
        directoryCache: inout [String: Int64],
    ) async throws {
        let directoryPaths = collectDirectoryPaths(items: items)
        await resolveDirectoryPaths(
            directoryPaths,
            homeURL: context.homeURL,
            cachedVolumeIdentifier: context.cachedVolumeIdentifier,
            directoryRepo: context.directoryRepo,
            directoryCache: &directoryCache,
        )
        for item in items where !existingPaths.contains(item.path) {
            let standardizedPath = URL(fileURLWithPath: item.path).standardizedFileURL.path
            if InitialIndexingRecordBuilder.isDirectory(mdItem: item.mdItem, path: standardizedPath) {
                continue
            }
            let fileRecord = await InitialIndexingRecordBuilder.makeRecord(
                mdItem: item.mdItem,
                path: item.path,
                homeURL: context.homeURL,
                cachedVolumeIdentifier: context.cachedVolumeIdentifier,
            )
            guard var fileRecord else { continue }
            let assigned = await assignDirectoryId(
                to: &fileRecord,
                homeURL: context.homeURL,
                cachedVolumeIdentifier: context.cachedVolumeIdentifier,
                directoryRepo: context.directoryRepo,
                directoryCache: &directoryCache,
            )
            guard assigned else {
                continue
            }
            batch.append(fileRecord)
            if batch.count >= context.batchSize {
                try await flushBatch(
                    &batch,
                    fileRepo: context.fileRepo,
                    inserted: &inserted,
                    batchSize: context.batchSize,
                    keepCapacity: true,
                )
            }
        }
    }
}
