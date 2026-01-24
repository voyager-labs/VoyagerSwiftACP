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
        let homeURL = FileManager.default.homeDirectoryForCurrentUser
        let cachedVolumeIdentifier = InitialIndexingRecordBuilder.volumeIdentifier(from: homeURL)
        let query = try makeQuery(homeURL: homeURL)
        let resultCount = Int(MDQueryGetResultCount(query))
        logger.info("Home indexing started: Spotlight results \(resultCount)")

        let plan = try await prepareBatchPlan(manager: manager, logger: logger, batchSize: batchSize)
        let repo = plan.repo
        let effectiveBatchSize = plan.effectiveBatchSize

        var inserted = 0
        var batch: [EntryRecord] = []
        batch.reserveCapacity(effectiveBatchSize)

        let pathBatchSize = plan.pathBatchSize
        var index = 0
        while index < resultCount {
            let end = min(index + pathBatchSize, resultCount)
            let items = loadItems(query: query, range: index ..< end)
            let existingPaths = try await fetchExistingPaths(manager: manager, paths: items.map(\.path))

            for item in items where !existingPaths.contains(item.path) {
                let record = await InitialIndexingRecordBuilder.makeRecord(
                    mdItem: item.mdItem,
                    path: item.path,
                    homeURL: homeURL,
                    cachedVolumeIdentifier: cachedVolumeIdentifier,
                )
                guard let record else { continue }
                batch.append(record)
                if batch.count >= effectiveBatchSize {
                    try await repo.insertBatch(batch, batchSize: effectiveBatchSize)
                    inserted += batch.count
                    batch.removeAll(keepingCapacity: true)
                }
            }

            if let heartbeat {
                await heartbeat()
            }
            index = end
        }

        if !batch.isEmpty {
            try await repo.insertBatch(batch, batchSize: effectiveBatchSize)
            inserted += batch.count
            batch.removeAll(keepingCapacity: false)
        }

        if let heartbeat {
            await heartbeat()
        }
        logger.info("Home indexing completed: inserted \(inserted) entries")
        return inserted
    }

    private struct IndexedItem {
        let mdItem: MDItem
        let path: String
    }

    private struct BatchPlan {
        let repo: EntryRepository
        let effectiveBatchSize: Int
        let pathBatchSize: Int
    }

    private static func prepareBatchPlan(
        manager: DatabaseManager,
        logger: Logger,
        batchSize: Int?,
    ) async throws -> BatchPlan {
        let repo = EntryRepository(manager: manager, logger: logger)
        let maxBatchSize = try await manager.read { db in
            try EntryRepository.maxBatchSize(in: db)
        }
        let maxPathBatchSize = try await manager.read { db in
            try Int.fetchOne(db, sql: "PRAGMA max_variable_number") ?? 999
        }
        let effectiveBatchSize = batchSize ?? maxBatchSize
        let pathBatchSize = min(maxPathBatchSize, max(1000, effectiveBatchSize))
        return BatchPlan(
            repo: repo,
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

    private static func fetchExistingPaths(
        manager: DatabaseManager,
        paths: [String],
    ) async throws -> Set<String> {
        guard !paths.isEmpty else { return [] }
        return try await manager.read { db in
            let placeholders = Array(repeating: "?", count: paths.count).joined(separator: ", ")
            let sql = "SELECT path FROM entries WHERE path IN (\(placeholders))"
            let existing = try String.fetchAll(db, sql: sql, arguments: StatementArguments(paths))
            return Set(existing)
        }
    }

    private static func updateLastSyncAt(manager: DatabaseManager) async throws {
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
}
