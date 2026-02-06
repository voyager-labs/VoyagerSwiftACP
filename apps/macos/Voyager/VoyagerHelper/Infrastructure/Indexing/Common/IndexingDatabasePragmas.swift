import Foundation
@preconcurrency import GRDB
import Logging

enum IndexingDatabasePragmas {
    struct Snapshot {
        let journalMode: String
        let synchronous: Int
        let tempStore: Int
        let cacheSize: Int
        let mmapSize: Int64
    }

    private struct Config {
        let journalMode: String
        let synchronous: String
        let tempStore: String
        let cacheSize: Int
        let mmapSize: Int64
    }

    private nonisolated static let config = Config(
        journalMode: "WAL",
        synchronous: "NORMAL",
        tempStore: "MEMORY",
        cacheSize: -16384,
        mmapSize: 134_217_728,
    )

    static func apply(manager: DatabaseManager) async throws -> Snapshot {
        try await manager.writeWithoutTransaction { db in
            let snapshot = try Snapshot(
                journalMode: (String.fetchOne(db, sql: "PRAGMA journal_mode")) ?? "delete",
                synchronous: (Int.fetchOne(db, sql: "PRAGMA synchronous")) ?? 1,
                tempStore: (Int.fetchOne(db, sql: "PRAGMA temp_store")) ?? 0,
                cacheSize: (Int.fetchOne(db, sql: "PRAGMA cache_size")) ?? 0,
                mmapSize: (Int64.fetchOne(db, sql: "PRAGMA mmap_size")) ?? 0,
            )

            let config = Self.config
            try db.execute(sql: "PRAGMA journal_mode = \(config.journalMode)")
            try db.execute(sql: "PRAGMA synchronous = \(config.synchronous)")
            try db.execute(sql: "PRAGMA temp_store = \(config.tempStore)")
            try db.execute(sql: "PRAGMA cache_size = \(config.cacheSize)")
            try db.execute(sql: "PRAGMA mmap_size = \(config.mmapSize)")

            return snapshot
        }
    }

    static func restore(
        manager: DatabaseManager,
        logger: Logger,
        snapshot: Snapshot,
    ) async {
        do {
            try await manager.writeWithoutTransaction { db in
                try db.execute(sql: "PRAGMA journal_mode = \(snapshot.journalMode)")
                try db.execute(sql: "PRAGMA synchronous = \(snapshot.synchronous)")
                try db.execute(sql: "PRAGMA temp_store = \(snapshot.tempStore)")
                try db.execute(sql: "PRAGMA cache_size = \(snapshot.cacheSize)")
                try db.execute(sql: "PRAGMA mmap_size = \(snapshot.mmapSize)")
            }
        } catch {
            logger.warning("Failed to restore indexing PRAGMA values: \(error)")
        }
    }
}
