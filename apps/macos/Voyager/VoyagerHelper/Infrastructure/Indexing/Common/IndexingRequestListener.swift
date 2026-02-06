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
            VoyagerSentryMetricLogger.logMetric(
                "voyager_initial_index_job",
                value: 1,
                tags: [
                    "stage": "failed",
                    "context": "prepare",
                    "error_type": String(describing: error),
                ],
                level: .error,
            )
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
            VoyagerSentryMetricLogger.logMetric(
                "voyager_initial_index_job",
                value: 1,
                tags: [
                    "stage": "failed",
                    "context": "status_check",
                    "error_type": String(describing: error),
                ],
                level: .error,
            )
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
                    if await needsReindex() {
                        logger.warning("Initial indexing state invalid; resetting to pending")
                        try await resetInitialIndexingState(reason: "validation_failed")
                    } else {
                        logger.info("Initial indexing already completed; request ignored")
                        return
                    }
                }
            }

            try await startInitialIndexing(trigger: .request)
        } catch {
            logger.error("Initial indexing request failed: \(error)")
            VoyagerSentryMetricLogger.logMetric(
                "voyager_initial_index_job",
                value: 1,
                tags: [
                    "stage": "failed",
                    "context": "request",
                    "error_type": String(describing: error),
                ],
                level: .error,
            )
            do {
                try await setStatus(.pending)
            } catch {
                logger.error("Initial indexing status reset failed: \(error)")
                VoyagerSentryMetricLogger.logMetric(
                    "voyager_initial_index_job",
                    value: 1,
                    tags: [
                        "stage": "failed",
                        "context": "status_reset",
                        "error_type": String(describing: error),
                    ],
                    level: .error,
                )
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
        let startedAt = Date()
        let now = iso8601Now()
        try await setStatus(.running, requestedAt: now, startedAt: now)
        try await upsertStateValue(StateKey.initialIndexingLastHeartbeat, value: now)
        lastHeartbeatAt = Date()

        logInitialIndexingStart(trigger: trigger)

        let heartbeat: @Sendable () async -> Void = { [weak self] in
            await self?.recordHeartbeatIfNeeded()
        }

        do {
            let inserted = try await InitialIndexingRunner.indexHomeDirectoryIfNeeded(
                manager: manager,
                logger: logger,
                heartbeat: heartbeat,
            )

            try await setStatus(.completed, completedAt: iso8601Now())
            await IncrementalIndexingValidator.startIfReady(manager: manager, logger: logger)
            let durationMs = Int(Date().timeIntervalSince(startedAt) * 1000)
            logInitialIndexingCompleted(
                trigger: trigger,
                inserted: inserted,
                durationMs: durationMs,
            )
        } catch {
            let durationMs = Int(Date().timeIntervalSince(startedAt) * 1000)
            logInitialIndexingFailed(
                trigger: trigger,
                durationMs: durationMs,
                error: error,
            )
            throw error
        }
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

private extension IndexingRequestListener {
    struct IndexingValidationSnapshot {
        let indexingStateExists: Bool
        let filesExists: Bool
        let completedAt: String?
        let lastSyncAt: String?
        let filesCount: Int
    }

    func needsReindex() async -> Bool {
        do {
            let snapshot = try await fetchValidationSnapshot()
            var reasons: [String] = []

            if !snapshot.indexingStateExists {
                reasons.append("missing_indexing_state")
            }
            if !snapshot.filesExists {
                reasons.append("missing_files_table")
            }
            if snapshot.completedAt == nil || snapshot.completedAt == "null" {
                reasons.append("missing_completed_at")
            }
            if snapshot.lastSyncAt == nil || snapshot.lastSyncAt == "null" {
                reasons.append("missing_last_sync_at")
            }
            if snapshot.filesCount == 0 {
                reasons.append("files_empty")
            }

            if reasons.isEmpty {
                logger.info(
                    "Initial indexing validation passed",
                    metadata: [
                        "files_count": .string("\(snapshot.filesCount)"),
                        "completed_at": .string(snapshot.completedAt ?? "nil"),
                        "last_sync_at": .string(snapshot.lastSyncAt ?? "nil"),
                    ],
                )
                return false
            }

            logger.warning(
                "Initial indexing validation failed",
                metadata: [
                    "reasons": .string(reasons.joined(separator: ",")),
                    "files_count": .string("\(snapshot.filesCount)"),
                    "completed_at": .string(snapshot.completedAt ?? "nil"),
                    "last_sync_at": .string(snapshot.lastSyncAt ?? "nil"),
                ],
            )
            return true
        } catch {
            logger.error("Initial indexing validation failed: \(error)")
            return true
        }
    }

    func resetInitialIndexingState(reason: String) async throws {
        try await setStatus(.pending)
        try await upsertStateValue(StateKey.initialIndexingResetReason, value: reason)
        try await upsertStateValue(StateKey.initialIndexingCompletedAt, value: "null")
        try await upsertStateValue("last_sync_at", value: "null")
        logger.warning("Initial indexing state reset", metadata: ["reason": .string(reason)])
    }

    func fetchValidationSnapshot() async throws -> IndexingValidationSnapshot {
        let completedAtKey = StateKey.initialIndexingCompletedAt
        let lastSyncKey = "last_sync_at"
        let filesTable = FilesSchema.tableName
        return try await manager.read { db in
            let indexingStateExists = try db.tableExists("indexing_state")
            let filesExists = try db.tableExists(filesTable)
            var completedAt: String?
            var lastSyncAt: String?
            if indexingStateExists {
                completedAt = try String.fetchOne(
                    db,
                    sql: "SELECT value FROM indexing_state WHERE key = ?",
                    arguments: [completedAtKey],
                )
                lastSyncAt = try String.fetchOne(
                    db,
                    sql: "SELECT value FROM indexing_state WHERE key = ?",
                    arguments: [lastSyncKey],
                )
            }
            let filesCount = try filesExists
                ? (Int.fetchOne(db, sql: "SELECT COUNT(1) FROM \(filesTable)") ?? 0)
                : 0
            return IndexingValidationSnapshot(
                indexingStateExists: indexingStateExists,
                filesExists: filesExists,
                completedAt: completedAt,
                lastSyncAt: lastSyncAt,
                filesCount: filesCount,
            )
        }
    }
}

private extension IndexingRequestListener {
    func logInitialIndexingStart(trigger: StartTrigger) {
        logger.info(
            "Initial indexing start",
            metadata: ["trigger": "\(trigger.rawValue)"],
        )
        VoyagerSentryMetricLogger.logMetric(
            "voyager_initial_index_job",
            value: 1,
            tags: [
                "stage": "start",
                "trigger": trigger.rawValue,
            ],
        )
    }

    func logInitialIndexingCompleted(
        trigger: StartTrigger,
        inserted: Int,
        durationMs: Int,
    ) {
        logger.info(
            "Initial indexing completed",
            metadata: [
                "trigger": "\(trigger.rawValue)",
                "inserted": "\(inserted)",
                "duration_ms": "\(durationMs)",
            ],
        )
        VoyagerSentryMetricLogger.logMetric(
            "voyager_initial_index_job",
            value: 1,
            tags: [
                "stage": "completed",
                "trigger": trigger.rawValue,
                "inserted": "\(inserted)",
            ],
        )
        VoyagerSentryMetricLogger.logMetric(
            "voyager_initial_index_job_duration_ms",
            value: Double(durationMs),
            tags: [
                "trigger": trigger.rawValue,
            ],
        )
    }

    func logInitialIndexingFailed(
        trigger: StartTrigger,
        durationMs: Int,
        error: Error,
    ) {
        logger.error(
            "Initial indexing failed",
            metadata: [
                "trigger": "\(trigger.rawValue)",
                "duration_ms": "\(durationMs)",
                "error": "\(String(describing: error))",
            ],
        )
        VoyagerSentryMetricLogger.logMetric(
            "voyager_initial_index_job",
            value: 1,
            tags: [
                "stage": "failed",
                "trigger": trigger.rawValue,
                "error_type": String(describing: error),
            ],
            level: .error,
        )
        VoyagerSentryMetricLogger.logMetric(
            "voyager_initial_index_job_duration_ms",
            value: Double(durationMs),
            tags: [
                "trigger": trigger.rawValue,
                "status": "failed",
            ],
            level: .error,
        )
    }
}
