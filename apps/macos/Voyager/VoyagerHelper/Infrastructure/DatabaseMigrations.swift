import Foundation
import GRDB

nonisolated enum DatabaseMigrations {
    static func registerAll(into migrator: inout DatabaseMigrator) {
        registerInitialMigration(into: &migrator)
    }

    static func validateMigrationHistory(_ db: Database) throws {
        guard try db.tableExists("grdb_migrations") else { return }

        let applied = try String.fetchAll(
            db,
            sql: "SELECT identifier FROM grdb_migrations ORDER BY rowid"
        )
        let known = Set(migrationIdentifiers)
        let unknown = applied.filter { !known.contains($0) }
        if !unknown.isEmpty {
            throw DatabaseError.migrationFailed(
                "Unknown migrations detected: \(unknown.joined(separator: ", "))"
            )
        }

        let expectedPrefix = Array(migrationIdentifiers.prefix(applied.count))
        if applied != expectedPrefix {
            throw DatabaseError.migrationFailed(
                "Migration history mismatch: expected \(expectedPrefix.joined(separator: ", "))"
            )
        }
    }

    private typealias DatabaseError = DatabaseManager.DatabaseError

    private static let migrationIdentifiers = [
        "v1_create_entries",
    ]

    private static func registerInitialMigration(into migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v1_create_entries") { db in
            if try db.tableExists(EntriesSchema.tableName) {
                try validateExistingEntriesTable(db)
            } else {
                try EntriesSchema.createTable(db)
            }

            try ensureIndexingStateTable(db)
            try dropNonUniqueIndexes(on: EntriesSchema.tableName, db: db)
            try dropNonUniqueIndexes(on: IndexingStateSchema.tableName, db: db)
            let now = Date()
            try insertIndexingStateDefault(db, key: "watched_paths", value: "[]", now: now)
            try insertIndexingStateDefault(db, key: "spotlight_seed", value: "null", now: now)
            try insertIndexingStateDefault(db, key: "last_sync_at", value: "null", now: now)
        }
    }

    private static func validateExistingEntriesTable(_ db: Database) throws {
        let existingColumns = Set(try db.columns(in: EntriesSchema.tableName).map(\.name))
        let missing = EntriesSchema.requiredColumns.filter { !existingColumns.contains($0) }
        if !missing.isEmpty {
            throw DatabaseError.migrationFailed(
                "Legacy entries table missing columns: \(missing.joined(separator: ", "))"
            )
        }
    }

    private static func validateExistingIndexingStateTable(_ db: Database) throws {
        let existingColumns = Set(try db.columns(in: IndexingStateSchema.tableName).map(\.name))
        let missing = IndexingStateSchema.requiredColumns.filter { !existingColumns.contains($0) }
        if !missing.isEmpty {
            throw DatabaseError.migrationFailed(
                "Legacy indexing_state table missing columns: \(missing.joined(separator: ", "))"
            )
        }
    }

    private static func ensureIndexingStateTable(_ db: Database) throws {
        if try db.tableExists(IndexingStateSchema.tableName) {
            try validateExistingIndexingStateTable(db)
        } else {
            try IndexingStateSchema.createTable(db)
        }
    }

    private static func dropNonUniqueIndexes(on table: String, db: Database) throws {
        let indexes = try db.indexes(on: table)
        for index in indexes where !index.isUnique {
            let safeName = index.name.replacingOccurrences(of: "\"", with: "\"\"")
            try db.execute(sql: "DROP INDEX IF EXISTS \"\(safeName)\"")
        }
    }

    private static func insertIndexingStateDefault(
        _ db: Database,
        key: String,
        value: String,
        now: Date
    ) throws {
        let sql = """
        INSERT INTO indexing_state (key, value, updated_at)
        SELECT ?, ?, ?
        WHERE NOT EXISTS (
            SELECT 1 FROM indexing_state WHERE key = ?
        )
        """
        try db.execute(sql: sql, arguments: [key, value, now, key])
    }
}
