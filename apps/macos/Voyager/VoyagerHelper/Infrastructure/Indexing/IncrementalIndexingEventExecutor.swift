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
        cachedVolumeIdentifier: String?
    ) {
        self.manager = manager
        self.logger = logger
        self.eventLogger = eventLogger
        self.homeURL = homeURL
        self.homePath = homeURL.standardizedFileURL.path
        self.cachedVolumeIdentifier = cachedVolumeIdentifier
    }

    // 변경 경로 적용 및 마지막 이벤트 저장
    func apply(
        changes: [IncrementalIndexingPlannedChange],
        maxEventId: FSEventStreamEventId
    ) async throws {
        if !changes.isEmpty {
            try await applyChanges(changes)
        }
        try await persistLastEventId(eventId: maxEventId)
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
                "deleted=\(deleted)"
            ]
            let message = messageParts.joined(separator: ", ")
            eventLogger.info("\(message, privacy: .public)")
        }

        if let lastError {
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
                "Incremental indexing delete failed: \(String(describing: error), privacy: .public)"
            )
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
            cachedVolumeIdentifier: cachedIdentifier
        )
        guard let record else {
            return ApplyOutcome(upserted: 0, deleted: 0, error: nil)
        }

        do {
            _ = try await repo.upsertByPath(record)
            return ApplyOutcome(upserted: 1, deleted: 0, error: nil)
        } catch {
            eventLogger.error(
                "Incremental indexing upsert failed: \(String(describing: error), privacy: .public)"
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
}
