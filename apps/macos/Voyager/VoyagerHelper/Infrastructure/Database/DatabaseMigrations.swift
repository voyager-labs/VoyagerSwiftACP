import Foundation
import GRDB

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
        guard let resources = Bundle.main.resourceURL else {
            throw DatabaseError.migrationFailed("Bundle resourceURL not available.")
        }

        let bundledURL = resources.appendingPathComponent("Migrations", isDirectory: true)
        guard isDirectory(bundledURL) else {
            throw DatabaseError.migrationFailed(
                "Bundled migrations directory not found at \(bundledURL.path).",
            )
        }

        return bundledURL
    }

    private static func isDirectory(_ url: URL) -> Bool {
        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return false
        }
        return isDirectory.boolValue
    }
}
