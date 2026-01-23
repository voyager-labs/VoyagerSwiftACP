import Foundation
@preconcurrency import GRDB
import Logging

@MainActor
final class HelperIndexingRequestListener {
    private enum InitialIndexingStatus: String {
        case pending
        case running
        case completed
    }

    private enum StateKey {
        static let initialIndexingStatus = "initial_indexing_status"
        static let initialIndexingRequestedAt = "initial_indexing_requested_at"
        static let initialIndexingStartedAt = "initial_indexing_started_at"
        static let initialIndexingCompletedAt = "initial_indexing_completed_at"
    }

    private let manager: DatabaseManager
    private let logger: Logger
    private nonisolated(unsafe) var observer: NSObjectProtocol?

    init(manager: DatabaseManager, logger: Logger) {
        self.manager = manager
        self.logger = logger
    }

    deinit {
        guard let observer else { return }
        Task { @MainActor in
            DistributedNotificationCenter.default().removeObserver(observer)
        }
    }

    // 초기 상태 준비 및 pending/completed 확정
    func prepare() async {
        do {
            guard try await isIndexingStateReady() else { return }
            if let status = try await fetchStatus() {
                logger.info("Initial indexing status: \(status.rawValue)")
                return
            }

            try await setStatus(.pending)
        } catch {
            logger.error("Initial indexing status prepare failed: \(error)")
        }
    }

    // Helper 인덱싱 요청 알림 구독
    func startObservingRequests() {
        guard observer == nil else { return }
        let token = DistributedNotificationCenter.default().addObserver(
            forName: .voyagerHelperIndexingRequest,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                await self.handleIndexingRequest()
            }
        }
        observer = token
    }

    // 초기 인덱싱 완료 여부 판단
    func hasCompletedInitialIndexing() async -> Bool {
        do {
            if let status = try await fetchStatus() {
                return status == .completed
            }
            return false
        } catch {
            logger.error("Initial indexing status check failed: \(error)")
            return false
        }
    }

    private func handleIndexingRequest() async {
        do {
            guard try await isIndexingStateReady() else { return }

            if let status = try await fetchStatus() {
                if status == .running {
                    logger.info("Initial indexing already running; request ignored")
                    return
                }
                if status == .completed {
                    logger.info("Initial indexing already completed; request ignored")
                    return
                }
            }

            let now = iso8601Now()
            try await setStatus(.running, requestedAt: now, startedAt: now)
            logger.info("Initial indexing request accepted")

            _ = try await InitialIndexingRunner.indexHomeDirectoryIfNeeded(
                manager: manager,
                logger: logger
            )

            try await setStatus(.completed, completedAt: iso8601Now())
            await IncrementalIndexingValidator.startIfReady(manager: manager, logger: logger)
        } catch {
            logger.error("Initial indexing request failed: \(error)")
            do {
                try await setStatus(.pending)
            } catch {
                logger.error("Initial indexing status reset failed: \(error)")
            }
        }
    }

    private func fetchStatus() async throws -> InitialIndexingStatus? {
        guard let raw = try await fetchStateValue(StateKey.initialIndexingStatus) else {
            return nil
        }
        return InitialIndexingStatus(rawValue: raw)
    }

    private func setStatus(
        _ status: InitialIndexingStatus,
        requestedAt: String? = nil,
        startedAt: String? = nil,
        completedAt: String? = nil
    ) async throws {
        try await upsertStateValue(StateKey.initialIndexingStatus, value: status.rawValue)
        if let requestedAt {
            try await upsertStateValue(StateKey.initialIndexingRequestedAt, value: requestedAt)
        }
        if let startedAt {
            try await upsertStateValue(StateKey.initialIndexingStartedAt, value: startedAt)
        }
        if let completedAt {
            try await upsertStateValue(StateKey.initialIndexingCompletedAt, value: completedAt)
        }
    }

    private func fetchStateValue(_ key: String) async throws -> String? {
        try await manager.read { db in
            guard try db.tableExists("indexing_state") else { return nil }
            return try String.fetchOne(
                db,
                sql: "SELECT value FROM indexing_state WHERE key = ?",
                arguments: [key]
            )
        }
    }

    private func upsertStateValue(_ key: String, value: String) async throws {
        try await manager.write { db in
            let sql = """
            INSERT INTO indexing_state (key, value, updated_at)
            VALUES (?, ?, CURRENT_TIMESTAMP)
            ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at
            """
            try db.execute(sql: sql, arguments: [key, value])
        }
    }

    private func isIndexingStateReady() async throws -> Bool {
        try await manager.read { db in
            try db.tableExists("indexing_state")
        }
    }

    private func iso8601Now() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }
}
