import Foundation
@preconcurrency import GRDB
import Logging

@MainActor
final class IndexingRequestListener {
    enum InitialIndexingStatus: String {
        case pending
        case running
        case completed
    }

    enum StateKey {
        static let initialIndexingStatus = "initial_indexing_status"
        static let initialIndexingRequestedAt = "initial_indexing_requested_at"
        static let initialIndexingStartedAt = "initial_indexing_started_at"
        static let initialIndexingCompletedAt = "initial_indexing_completed_at"
        static let initialIndexingLastHeartbeat = "initial_indexing_last_heartbeat"
        static let initialIndexingRetryCount = "initial_indexing_retry_count"
        static let initialIndexingLastRetryAt = "initial_indexing_last_retry_at"
        static let initialIndexingResetReason = "initial_indexing_reset_reason"
    }

    enum StartTrigger: String {
        case request
        case recovery
    }

    enum RunningStatusContext {
        case prepare
        case request
    }

    private let manager: DatabaseManager
    let logger: Logger
    private nonisolated(unsafe) var observer: NSObjectProtocol?
    var lastHeartbeatAt: Date?

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
                if status == .running {
                    _ = await handleRunningStatus(context: .prepare)
                    return
                }
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
            forName: .voyagerIndexingRequest,
            object: nil,
            queue: .main,
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                await self.handleIndexingRequest()
            }
        }
        observer = token
        logger.info("Indexing request listener started")
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
                    _ = await handleRunningStatus(context: .request)
                    return
                }
                if status == .completed {
                    logger.info("Initial indexing already completed; request ignored")
                    return
                }
            }

            try await startInitialIndexing(trigger: .request)
        } catch {
            logger.error("Initial indexing request failed: \(error)")
            do {
                try await setStatus(.pending)
            } catch {
                logger.error("Initial indexing status reset failed: \(error)")
            }
        }
    }

    private func handleRunningStatus(context: RunningStatusContext) async -> Bool {
        if await recoverIfStuckIfNeeded(context: context) {
            return true
        }
        switch context {
        case .prepare:
            logger.info("Initial indexing status: \(InitialIndexingStatus.running.rawValue)")
        case .request:
            logger.info("Initial indexing already running; request ignored")
        }
        return true
    }

    private func fetchStatus() async throws -> InitialIndexingStatus? {
        guard let raw = try await fetchStateValue(StateKey.initialIndexingStatus) else {
            return nil
        }
        return InitialIndexingStatus(rawValue: raw)
    }

    func setStatus(
        _ status: InitialIndexingStatus,
        requestedAt: String? = nil,
        startedAt: String? = nil,
        completedAt: String? = nil,
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

    // 초기 인덱싱 실행
    func startInitialIndexing(trigger: StartTrigger) async throws {
        let now = iso8601Now()
        try await setStatus(.running, requestedAt: now, startedAt: now)
        try await upsertStateValue(StateKey.initialIndexingLastHeartbeat, value: now)
        lastHeartbeatAt = Date()

        logger.info("Initial indexing start (\(trigger.rawValue))")

        let heartbeat: @Sendable () async -> Void = { [weak self] in
            await self?.recordHeartbeatIfNeeded()
        }

        _ = try await InitialIndexingRunner.indexHomeDirectoryIfNeeded(
            manager: manager,
            logger: logger,
            heartbeat: heartbeat,
        )

        try await setStatus(.completed, completedAt: iso8601Now())
        await IncrementalIndexingValidator.startIfReady(manager: manager, logger: logger)
        logger.info("Initial indexing completed (\(trigger.rawValue))")
    }

    func fetchStateValue(_ key: String) async throws -> String? {
        try await manager.read { db in
            guard try db.tableExists("indexing_state") else { return nil }
            return try String.fetchOne(
                db,
                sql: "SELECT value FROM indexing_state WHERE key = ?",
                arguments: [key],
            )
        }
    }

    func upsertStateValue(_ key: String, value: String) async throws {
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
}
