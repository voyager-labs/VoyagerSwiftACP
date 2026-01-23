import Foundation
import GRDB
import SwiftDotenv

nonisolated enum DatabaseMigrations {
    static func registerAll(into migrator: inout DatabaseMigrator) throws {
        for migration in try loadSQLMigrations() {
            migrator.registerMigration(migration.id) { db in
                try db.execute(sql: migration.sql)
            }
        }
    }

    static func validateMigrationHistory(_ db: Database) throws {
        guard try db.tableExists("grdb_migrations") else { return }

        let applied = try String.fetchAll(
            db,
            sql: "SELECT identifier FROM grdb_migrations ORDER BY rowid",
        )
        let migrationIdentifiers = try loadSQLMigrations().map(\.id)
        let known = Set(migrationIdentifiers)
        let unknown = applied.filter { !known.contains($0) }
        if !unknown.isEmpty {
            throw DatabaseError.migrationFailed(
                "Unknown migrations detected: \(unknown.joined(separator: ", "))",
            )
        }

        let expectedPrefix = Array(migrationIdentifiers.prefix(applied.count))
        if applied != expectedPrefix {
            throw DatabaseError.migrationFailed(
                "Migration history mismatch: expected \(expectedPrefix.joined(separator: ", "))",
            )
        }
    }

    private typealias DatabaseError = DatabaseManager.DatabaseError

    private struct SQLMigration {
        let id: String
        let sql: String
    }

    private static func loadSQLMigrations() throws -> [SQLMigration] {
        let directoryURL = try migrationDirectoryURL()
        let fileURLs = try FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
        )
        let sqlFiles = fileURLs
            .filter { $0.pathExtension.lowercased() == "sql" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        guard !sqlFiles.isEmpty else {
            throw DatabaseError.migrationFailed(
                "No migration SQL files found in \(directoryURL.path)",
            )
        }

        return try sqlFiles.map { url in
            let id = url.deletingPathExtension().lastPathComponent
            let sql = try String(contentsOf: url, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !sql.isEmpty else {
                throw DatabaseError.migrationFailed("Empty migration SQL: \(id)")
            }
            return SQLMigration(id: id, sql: sql)
        }
    }

    private static func migrationDirectoryURL() throws -> URL {
        guard let location = envValue(for: "PUBLIC_SQLITE_MIGRATIONS_FILE_LOCATION") else {
            throw DatabaseError.migrationFailed(
                "Migration directory not configured. Set PUBLIC_SQLITE_MIGRATIONS_FILE_LOCATION.",
            )
        }

        let expandedLocation = (location as NSString).expandingTildeInPath
        let directoryURL: URL
        if expandedLocation.hasPrefix("/") {
            directoryURL = URL(fileURLWithPath: expandedLocation, isDirectory: true)
        } else if let projectRoot = ProcessInfo.processInfo.environment["VOYAGER_PROJECT_ROOT"],
                  !projectRoot.isEmpty
        {
            directoryURL = URL(fileURLWithPath: projectRoot, isDirectory: true)
                .appendingPathComponent(expandedLocation, isDirectory: true)
        } else if let resources = Bundle.main.resourceURL {
            let bundledURL = resources.appendingPathComponent(expandedLocation, isDirectory: true)
            var isDirectory = ObjCBool(false)
            if FileManager.default.fileExists(atPath: bundledURL.path, isDirectory: &isDirectory),
               isDirectory.boolValue
            {
                directoryURL = bundledURL
            } else if let projectRoot = ProcessInfo.processInfo.environment["VOYAGER_PROJECT_ROOT"],
                      !projectRoot.isEmpty
            {
                directoryURL = URL(fileURLWithPath: projectRoot, isDirectory: true)
                    .appendingPathComponent(expandedLocation, isDirectory: true)
            } else {
                throw DatabaseError.migrationFailed(
                    "VOYAGER_PROJECT_ROOT required for relative migration path: \(expandedLocation)",
                )
            }
        } else {
            throw DatabaseError.migrationFailed(
                "VOYAGER_PROJECT_ROOT required for relative migration path: \(expandedLocation)",
            )
        }

        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: directoryURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            throw DatabaseError.migrationFailed(
                "Migration directory not found at \(directoryURL.path)",
            )
        }
        return directoryURL
    }

    private static func envValue(for key: String) -> String? {
        if let value = Dotenv[key]?.stringValue, !value.isEmpty {
            return value
        }
        if let value = ProcessInfo.processInfo.environment[key], !value.isEmpty {
            return value
        }
        return nil
    }

    private static func validateExistingEntriesTable(_ db: Database) throws {
        let existingColumns = try Set(db.columns(in: EntriesSchema.tableName).map(\.name))
        let missing = EntriesSchema.requiredColumns.filter { !existingColumns.contains($0) }
        if !missing.isEmpty {
            throw DatabaseError.migrationFailed(
                "Legacy entries table missing columns: \(missing.joined(separator: ", "))",
            )
        }
    }

    private static func validateExistingIndexingStateTable(_ db: Database) throws {
        let existingColumns = try Set(db.columns(in: IndexingStateSchema.tableName).map(\.name))
        let missing = IndexingStateSchema.requiredColumns.filter { !existingColumns.contains($0) }
        if !missing.isEmpty {
            throw DatabaseError.migrationFailed(
                "Legacy indexing_state table missing columns: \(missing.joined(separator: ", "))",
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
        now: Date,
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
