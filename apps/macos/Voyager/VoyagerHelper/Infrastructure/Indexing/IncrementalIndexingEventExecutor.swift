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
        let repo = EntryRepository(manager: manager, logger: logger)
        var insertedOrUpdated = 0
        var deleted = 0
        var lastError: Error?

        for change in changes {
            switch change.action {
            case .delete:
                let outcome = await handleDelete(repo: repo, path: change.path)
                deleted += outcome.deleted
                if let error = outcome.error {
                    lastError = error
                }
            case .upsert:
                let outcome = await handleUpsert(repo: repo, path: change.path)
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
            logIncrementalChangesSummary(upserted: insertedOrUpdated, deleted: deleted)
        }

        if let lastError {
            logIncrementalChangeFailure(context: "incremental_changes", error: lastError)
            throw lastError
        }
    }

    // 삭제 처리
    private func handleDelete(repo: EntryRepository, path: String) async -> ApplyOutcome {
        do {
            let deleted = try await repo.deleteByPath(path)
            return ApplyOutcome(upserted: 0, deleted: deleted, error: nil)
        } catch {
            eventLogger.error(
                "Incremental indexing delete failed: \(String(describing: error), privacy: .public)",
            )
            logIncrementalChangeFailure(context: "delete", error: error)
            return ApplyOutcome(upserted: 0, deleted: 0, error: error)
        }
    }

    // 업서트 처리
    private func handleUpsert(repo: EntryRepository, path: String) async -> ApplyOutcome {
        if !FileManager.default.fileExists(atPath: path) {
            return await handleDelete(repo: repo, path: path)
        }

        guard let mdItem = MDItemCreate(kCFAllocatorDefault, path as CFString) else {
            return ApplyOutcome(upserted: 0, deleted: 0, error: nil)
        }
        let cachedIdentifier = path.hasPrefix(homePath) ? cachedVolumeIdentifier : nil
        let record = await InitialIndexingRecordBuilder.makeRecord(
            mdItem: mdItem,
            path: path,
            homeURL: homeURL,
            cachedVolumeIdentifier: cachedIdentifier,
        )
        guard let record else {
            return ApplyOutcome(upserted: 0, deleted: 0, error: nil)
        }

        do {
            _ = try await repo.upsertByPath(record)
            return ApplyOutcome(upserted: 1, deleted: 0, error: nil)
        } catch {
            eventLogger.error(
                "Incremental indexing upsert failed: \(String(describing: error), privacy: .public)",
            )
            logIncrementalChangeFailure(context: "upsert", error: error)
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
                logIncrementalChangeFailure(context: "rescan", error: error)
            }
        }
        if let lastError {
            throw lastError
        }
    }

    // 단일 경로 재스캔
    private func rescanDirectory(path: String) async throws {
        let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
        let repo = EntryRepository(manager: manager, logger: logger)

        guard FileManager.default.fileExists(atPath: standardized) else {
            _ = try await repo.deleteByPath(standardized)
            return
        }

        let query = try makeQuery(rootPath: standardized)
        let resultCount = Int(MDQueryGetResultCount(query))
        var scannedPaths: Set<String> = []
        scannedPaths.reserveCapacity(resultCount)

        for index in 0 ..< resultCount {
            guard let item = MDQueryGetResultAtIndex(query, index) else { continue }
            let mdItem = unsafeBitCast(item, to: MDItem.self)
            guard let itemPath = MDItemCopyAttribute(mdItem, kMDItemPath) as? String else { continue }
            scannedPaths.insert(itemPath)
            let cachedIdentifier = itemPath.hasPrefix(homePath) ? cachedVolumeIdentifier : nil
            let record = await InitialIndexingRecordBuilder.makeRecord(
                mdItem: mdItem,
                path: itemPath,
                homeURL: homeURL,
                cachedVolumeIdentifier: cachedIdentifier,
            )
            guard let record else { continue }
            _ = try await repo.upsertByPath(record)
        }

        let existingPaths = try await fetchExistingPaths(prefix: standardized)
        for existingPath in existingPaths where !scannedPaths.contains(existingPath) {
            _ = try await repo.deleteByPath(existingPath)
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
        return try await manager.read { db in
            try String.fetchAll(
                db,
                sql: "SELECT path FROM entries WHERE path = ? OR path LIKE ?",
                arguments: [prefix, likePrefix],
            )
        }
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
        VoyagerSentryMetricLogger.logMetric(
            "voyager_incremental_index_job",
            value: 1,
            tags: [
                "stage": "incremental_apply",
                "changes": "\(changes)",
                "rescans": "\(rescans)",
            ],
        )
        VoyagerSentryMetricLogger.logMetric(
            "voyager_incremental_index_job_duration_ms",
            value: Double(durationMs),
            tags: [
                "scope": "incremental",
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
        VoyagerSentryMetricLogger.logMetric(
            "voyager_incremental_index_job",
            value: 1,
            tags: [
                "stage": "failed",
                "context": "incremental_apply",
                "error_type": String(describing: error),
            ],
            level: .error,
        )
        VoyagerSentryMetricLogger.logMetric(
            "voyager_incremental_index_job_duration_ms",
            value: Double(durationMs),
            tags: [
                "scope": "incremental",
                "status": "failed",
            ],
            level: .error,
        )
    }

    func logIncrementalChangesSummary(upserted: Int, deleted: Int) {
        VoyagerSentryMetricLogger.logMetric(
            "voyager_incremental_index_job",
            value: 1,
            tags: [
                "stage": "incremental_changes",
                "upserted": "\(upserted)",
                "deleted": "\(deleted)",
            ],
        )
    }

    func logIncrementalChangeFailure(context: String, error: Error) {
        VoyagerSentryMetricLogger.logMetric(
            "voyager_incremental_index_job",
            value: 1,
            tags: [
                "stage": "failed",
                "context": context,
                "error_type": String(describing: error),
            ],
            level: .error,
        )
    }
}
