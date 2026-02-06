import Foundation
@preconcurrency import GRDB
import Logging

nonisolated struct DirectoryRepository: Sendable {
    struct PathUpdateRequest: Sendable {
        let oldPath: String
        let newPath: String
        let newParentId: Int64?
        let newNameFull: String?
        let newNameStem: String?
        let oldRelativePath: String?
        let newRelativePath: String?
        let depthDelta: Int?
    }

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

    func upsertByLogicalKey(_ key: DirectoryLogicalKey, record: DirectoryRecord) async throws -> DirectoryRecord {
        try await manager.write { db in
            var record = record
            record.volumeIdentifier = key.volumeIdentifier
            record.fileResourceIdentifier = key.fileResourceIdentifier

            if let existing = try fetchByLogicalKey(key, db: db) {
                record.id = existing.id
                try record.update(db)
                return record
            }

            record.id = nil
            try record.insert(db)
            return record
        }
    }

    func fetchByLogicalKey(_ key: DirectoryLogicalKey) async throws -> DirectoryRecord? {
        try await manager.read { db in
            try fetchByLogicalKey(key, db: db)
        }
    }

    func updatePathSubtree(_ request: PathUpdateRequest) async throws {
        try await manager.write { db in
            try performPathSubtreeUpdate(
                db: db,
                request: request,
            )
        }
    }

    func deleteByPathPrefix(_ path: String) async throws -> Int {
        let likePrefix = path.hasSuffix("/") ? "\(path)%" : "\(path)/%"
        return try await manager.write { db in
            try db.execute(
                sql: "DELETE FROM directories WHERE path = ? OR path LIKE ?",
                arguments: [path, likePrefix],
            )
            return db.changesCount
        }
    }

    private func performPathSubtreeUpdate(
        db: Database,
        request: PathUpdateRequest,
    ) throws {
        try updateRootDirectory(
            db: db,
            request: request,
        )
        try updateChildDirectories(
            db: db,
            request: request,
        )
        try syncEntriesDirPathByDirectoryId(
            db: db,
            newPath: request.newPath,
        )
        try updateEntriesDirPathFallback(
            db: db,
            oldPath: request.oldPath,
            newPath: request.newPath,
        )
    }

    private func updateRootDirectory(
        db: Database,
        request: PathUpdateRequest,
    ) throws {
        let updateRootSql = """
        UPDATE directories
        SET path = ?,
            parent_id = ?,
            name_full = ?,
            name_stem = ?,
            depth_from_home = CASE
                WHEN ? IS NULL THEN depth_from_home
                WHEN depth_from_home IS NULL THEN NULL
                ELSE depth_from_home + ?
            END,
            relative_path_from_home = ?
        WHERE path = ?
        """
        try db.execute(
            sql: updateRootSql,
            arguments: [
                request.newPath,
                request.newParentId,
                request.newNameFull,
                request.newNameStem,
                request.depthDelta,
                request.depthDelta,
                request.newRelativePath,
                request.oldPath,
            ],
        )
    }

    private func updateChildDirectories(
        db: Database,
        request: PathUpdateRequest,
    ) throws {
        if let oldRelativePath = request.oldRelativePath,
           let newRelativePath = request.newRelativePath
        {
            try updateChildDirectoriesWithRelativePath(
                db: db,
                oldPath: request.oldPath,
                newPath: request.newPath,
                oldRelativePath: oldRelativePath,
                newRelativePath: newRelativePath,
                depthDelta: request.depthDelta,
            )
            return
        }
        try updateChildDirectoriesWithoutRelativePath(
            db: db,
            oldPath: request.oldPath,
            newPath: request.newPath,
            depthDelta: request.depthDelta,
        )
    }

    private func updateChildDirectoriesWithRelativePath(
        db: Database,
        oldPath: String,
        newPath: String,
        oldRelativePath: String,
        newRelativePath: String,
        depthDelta: Int?,
    ) throws {
        let updateChildrenSql = """
        UPDATE directories
        SET path = ? || substr(path, length(?) + 1),
            depth_from_home = CASE
                WHEN ? IS NULL THEN depth_from_home
                WHEN depth_from_home IS NULL THEN NULL
                ELSE depth_from_home + ?
            END,
            relative_path_from_home = CASE
                WHEN relative_path_from_home = ?
                    THEN ?
                WHEN relative_path_from_home LIKE ? || '/%'
                    THEN ? || substr(relative_path_from_home, length(?) + 1)
                ELSE relative_path_from_home
            END
        WHERE path LIKE ? || '/%'
        """
        let updateChildrenArgs: [DatabaseValueConvertible?] = [
            newPath,
            oldPath,
            depthDelta,
            depthDelta,
            oldRelativePath,
            newRelativePath,
            oldRelativePath,
            newRelativePath,
            oldRelativePath,
            oldPath,
        ]
        try db.execute(sql: updateChildrenSql, arguments: StatementArguments(updateChildrenArgs))
    }

    private func updateChildDirectoriesWithoutRelativePath(
        db: Database,
        oldPath: String,
        newPath: String,
        depthDelta: Int?,
    ) throws {
        let updateChildrenSql = """
        UPDATE directories
        SET path = ? || substr(path, length(?) + 1),
            depth_from_home = CASE
                WHEN ? IS NULL THEN depth_from_home
                WHEN depth_from_home IS NULL THEN NULL
                ELSE depth_from_home + ?
            END
        WHERE path LIKE ? || '/%'
        """
        let updateChildrenArgs: [DatabaseValueConvertible?] = [
            newPath,
            oldPath,
            depthDelta,
            depthDelta,
            oldPath,
        ]
        try db.execute(sql: updateChildrenSql, arguments: StatementArguments(updateChildrenArgs))
    }

    private func syncEntriesDirPathByDirectoryId(
        db: Database,
        newPath: String,
    ) throws {
        let entriesTable = EntriesSchema.tableName
        let syncEntriesSql = """
        UPDATE \(entriesTable)
        SET dir_path = (
            SELECT d.path
            FROM directories d
            WHERE d.id = \(entriesTable).directory_id
        )
        WHERE directory_id IN (
            SELECT id
            FROM directories
            WHERE path = ? OR path LIKE ? || '/%'
        )
        """
        try db.execute(
            sql: syncEntriesSql,
            arguments: [newPath, newPath],
        )
    }

    private func updateEntriesDirPathFallback(
        db: Database,
        oldPath: String,
        newPath: String,
    ) throws {
        let entriesTable = EntriesSchema.tableName
        let updateEntriesSql = """
        UPDATE \(entriesTable)
        SET dir_path = CASE
            WHEN dir_path = ?
                THEN ?
            WHEN dir_path LIKE ? || '/%'
                THEN ? || substr(dir_path, length(?) + 1)
            ELSE dir_path
        END
        WHERE directory_id IS NULL
          AND (dir_path = ? OR dir_path LIKE ? || '/%')
        """
        try db.execute(
            sql: updateEntriesSql,
            arguments: [
                oldPath,
                newPath,
                oldPath,
                newPath,
                oldPath,
                oldPath,
                oldPath,
            ],
        )
    }

    private func fetchByLogicalKey(_ key: DirectoryLogicalKey, db: Database) throws -> DirectoryRecord? {
        let request = DirectoryRecord.filter(
            DirectoryRecord.Columns.volumeIdentifier == key.volumeIdentifier &&
                DirectoryRecord.Columns.fileResourceIdentifier == key.fileResourceIdentifier,
        )
        return try request.fetchOne(db)
    }
}
