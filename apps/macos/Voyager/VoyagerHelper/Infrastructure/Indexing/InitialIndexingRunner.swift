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
        batchSize: Int? = nil
    ) async throws -> Int {
        let existingCount = try await manager.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM entries") ?? 0
        }
        guard existingCount == 0 else {
            logger.info("Home indexing skipped (entries already exist)")
            return 0
        }

        let homeURL = FileManager.default.homeDirectoryForCurrentUser
        let cachedVolumeIdentifier = InitialIndexingRecordBuilder.volumeIdentifier(from: homeURL)
        let query = try makeQuery(homeURL: homeURL)
        let resultCount = Int(MDQueryGetResultCount(query))
        logger.info("Home indexing started: Spotlight results \(resultCount)")

        let repo = EntryRepository(manager: manager, logger: logger)
        let maxBatchSize = try await manager.read { db in
            try EntryRepository.maxBatchSize(in: db)
        }
        let effectiveBatchSize = batchSize ?? maxBatchSize

        var inserted = 0
        var batch: [EntryRecord] = []
        batch.reserveCapacity(effectiveBatchSize)

        for index in 0..<resultCount {
            guard let item = MDQueryGetResultAtIndex(query, index) else { continue }
            let mdItem = unsafeBitCast(item, to: MDItem.self)
            guard let path = MDItemCopyAttribute(mdItem, kMDItemPath) as? String else {
                continue
            }

            let record = await InitialIndexingRecordBuilder.makeRecord(
                from: path,
                homeURL: homeURL,
                cachedVolumeIdentifier: cachedVolumeIdentifier
            )
            guard let record else { continue }
            batch.append(record)
            if batch.count >= effectiveBatchSize {
                try await repo.insertBatch(batch, batchSize: effectiveBatchSize)
                inserted += batch.count
                batch.removeAll(keepingCapacity: true)
            }
        }

        if !batch.isEmpty {
            try await repo.insertBatch(batch, batchSize: effectiveBatchSize)
            inserted += batch.count
            batch.removeAll(keepingCapacity: false)
        }

        logger.info("Home indexing completed: inserted \(inserted) entries")
        return inserted
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
}
