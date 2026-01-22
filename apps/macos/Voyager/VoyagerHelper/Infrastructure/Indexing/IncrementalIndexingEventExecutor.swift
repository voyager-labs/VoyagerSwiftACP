@preconcurrency import CoreServices
import Foundation
@preconcurrency import GRDB
import Logging
import os

final class IncrementalIndexingEventExecutor {
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
        changes: [(String, FSEventStreamEventFlags)],
        maxEventId: FSEventStreamEventId
    ) async throws {
        if !changes.isEmpty {
            try await applyChanges(changes)
        }
        try await persistLastEventId(eventId: maxEventId)
    }

    // 변경 경로 DB 반영
    private func applyChanges(_ changes: [(String, FSEventStreamEventFlags)]) async throws {
        let repo = EntryRepository(manager: manager, logger: logger)
        var insertedOrUpdated = 0
        var deleted = 0
        var lastError: Error?

        for (path, flags) in changes {
            let removed = flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemRemoved) != 0
            let exists = FileManager.default.fileExists(atPath: path)
            if removed || !exists {
                do {
                    deleted += try await repo.deleteByPath(path)
                } catch {
                    lastError = error
                    eventLogger.error(
                        "Incremental indexing delete failed: \(String(describing: error), privacy: .public)"
                    )
                }
                continue
            }

            guard let mdItem = MDItemCreate(kCFAllocatorDefault, path as CFString) else {
                continue
            }
            let cachedIdentifier = path.hasPrefix(homePath) ? cachedVolumeIdentifier : nil
            let record = await InitialIndexingRecordBuilder.makeRecord(
                mdItem: mdItem,
                path: path,
                homeURL: homeURL,
                cachedVolumeIdentifier: cachedIdentifier
            )
            guard let record else { continue }

            do {
                _ = try await repo.upsertByPath(record)
                insertedOrUpdated += 1
            } catch {
                lastError = error
                eventLogger.error(
                    "Incremental indexing upsert failed: \(String(describing: error), privacy: .public)"
                )
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
