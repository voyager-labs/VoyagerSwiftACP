import Foundation
@preconcurrency import GRDB
import Logging

nonisolated struct DirectoryRepository: Sendable {
    private let manager: DatabaseManager
    private let logger: Logger

    init(manager: DatabaseManager, logger: Logger = Logger(label: "VoyagerHelper.DirectoryRepository")) {
        self.manager = manager
        self.logger = logger
    }

    func fetchById(_ id: Int64) async throws -> DirectoryRecord? {
        try await manager.read { db in
            try DirectoryRecord.filter(DirectoryRecord.Columns.id == id).fetchOne(db)
        }
    }

    func fetchByPath(_ path: String) async throws -> DirectoryRecord? {
        try await manager.read { db in
            try DirectoryRecord.filter(DirectoryRecord.Columns.path == path).fetchOne(db)
        }
    }

    func insertOne(_ record: DirectoryRecord) async throws {
        try await manager.write { db in
            var record = record
            try record.insert(db)
        }
    }

    func upsertByPath(_ record: DirectoryRecord) async throws -> DirectoryRecord {
        try await manager.write { db in
            var record = record
            if let existing = try DirectoryRecord.filter(DirectoryRecord.Columns.path == record.path).fetchOne(db) {
                record.id = existing.id
                try record.update(db)
                return record
            }

            record.id = nil
            try record.insert(db)
            return record
        }
    }
}
