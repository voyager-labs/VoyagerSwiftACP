import Foundation
@preconcurrency import GRDB
import Logging

enum IncrementalIndexingValidator {
    struct StateSnapshot {
        let watchedPaths: String?
        let lastSyncAt: String?
        let spotlightSeed: String?
    }

    static func startIfReady(
        manager: DatabaseManager,
        logger: Logger
    ) async {
        do {
            let snapshot = try await loadStateSnapshot(manager: manager)
            guard isReady(snapshot: snapshot) else {
                logger.info("Incremental indexing skipped (state not ready)")
                return
            }
            logger.info("Incremental indexing ready (pipeline pending)")
        } catch {
            logger.error("Incremental indexing gate failed: \(error)")
        }
    }

    private static func loadStateSnapshot(manager: DatabaseManager) async throws -> StateSnapshot {
        try await manager.read { db in
            guard try db.tableExists("indexing_state") else {
                throw DatabaseManager.DatabaseError.migrationFailed("indexing_state table missing")
            }
            let watchedPaths = try String.fetchOne(
                db,
                sql: "SELECT value FROM indexing_state WHERE key = ?",
                arguments: ["watched_paths"]
            )
            let lastSyncAt = try String.fetchOne(
                db,
                sql: "SELECT value FROM indexing_state WHERE key = ?",
                arguments: ["last_sync_at"]
            )
            let spotlightSeed = try String.fetchOne(
                db,
                sql: "SELECT value FROM indexing_state WHERE key = ?",
                arguments: ["spotlight_seed"]
            )
            return StateSnapshot(
                watchedPaths: watchedPaths,
                lastSyncAt: lastSyncAt,
                spotlightSeed: spotlightSeed
            )
        }
    }

    private static func isReady(snapshot: StateSnapshot) -> Bool {
        guard snapshot.watchedPaths != nil, snapshot.spotlightSeed != nil else {
            return false
        }
        guard let lastSyncAt = snapshot.lastSyncAt, lastSyncAt != "null" else {
            return false
        }
        return true
    }
}
