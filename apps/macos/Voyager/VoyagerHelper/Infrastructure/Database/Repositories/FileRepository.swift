import Foundation
@preconcurrency import GRDB
import Logging

nonisolated struct FileUpdate: Sendable {
    var path: String?
    var dirPath: String?
    var nameFull: String?
    var nameStem: String?
    var fileExtension: String?
    var size: Int64?
    var uniformTypeIdentifier: String?
    var fileKind: String?
    var isInvisible: Bool?
    var creationDate: Date?
    var modificationDate: Date?
    var contentCreationDate: Date?
    var contentModificationDate: Date?
    var addedDate: Date?
    var lastUsedDate: Date?
    var originalMetadata: String?
    var directoryId: Int64?

    func columnAssignments() -> [ColumnAssignment] {
        var assignments: [ColumnAssignment] = []
        appendPathAssignments(into: &assignments)
        appendAttributeAssignments(into: &assignments)
        appendDateAssignments(into: &assignments)
        appendMetadataAssignments(into: &assignments)
        return assignments
    }

    private func appendPathAssignments(into assignments: inout [ColumnAssignment]) {
        append(&assignments, column: .path, value: path)
        append(&assignments, column: .dirPath, value: dirPath)
        append(&assignments, column: .nameFull, value: nameFull)
        append(&assignments, column: .nameStem, value: nameStem)
        append(&assignments, column: .fileExtension, value: fileExtension)
    }

    private func appendAttributeAssignments(into assignments: inout [ColumnAssignment]) {
        append(&assignments, column: .size, value: size)
        append(&assignments, column: .uniformTypeIdentifier, value: uniformTypeIdentifier)
        append(&assignments, column: .fileKind, value: fileKind)
        append(&assignments, column: .isInvisible, value: isInvisible)
    }

    private func appendDateAssignments(into assignments: inout [ColumnAssignment]) {
        append(&assignments, column: .creationDate, value: creationDate)
        append(&assignments, column: .modificationDate, value: modificationDate)
        append(&assignments, column: .contentCreationDate, value: contentCreationDate)
        append(&assignments, column: .contentModificationDate, value: contentModificationDate)
        append(&assignments, column: .addedDate, value: addedDate)
        append(&assignments, column: .lastUsedDate, value: lastUsedDate)
    }

    private func appendMetadataAssignments(into assignments: inout [ColumnAssignment]) {
        append(&assignments, column: .originalMetadata, value: originalMetadata)
        append(&assignments, column: .directoryId, value: directoryId)
    }

    private func append(
        _ assignments: inout [ColumnAssignment],
        column: FileRecord.Columns,
        value: (some DatabaseValueConvertible)?,
    ) {
        guard let value else { return }
        assignments.append(column.set(to: value))
    }
}

enum FileRepositoryError: Error {
    case missingDirectoryId(path: String)
}

nonisolated struct FileRepository: Sendable {
    private let manager: DatabaseManager
    private let logger: Logger

    init(manager: DatabaseManager, logger: Logger = Logger(label: "VoyagerHelper.FileRepository")) {
        self.manager = manager
        self.logger = logger
    }

    func fetchById(_ id: Int64) async throws -> FileRecord? {
        try await manager.read { db in
            try FileRecord.filter(FileRecord.Columns.id == id).fetchOne(db)
        }
    }

    func fetchByPath(_ path: String) async throws -> FileRecord? {
        try await manager.read { db in
            try FileRecord.filter(FileRecord.Columns.path == path).fetchOne(db)
        }
    }

    func deleteById(_ id: Int64) async throws -> Int {
        try await manager.write { db in
            try FileRecord.filter(FileRecord.Columns.id == id).deleteAll(db)
        }
    }

    func deleteByPath(_ path: String) async throws -> Int {
        try await manager.write { db in
            try FileRecord.filter(FileRecord.Columns.path == path).deleteAll(db)
        }
    }

    func deleteByPathPrefix(_ path: String) async throws -> Int {
        let likePrefix = path.hasSuffix("/") ? "\(path)%" : "\(path)/%"
        let tableName = FileRecord.databaseTableName
        return try await manager.write { db in
            try db.execute(
                sql: "DELETE FROM \(tableName) WHERE path = ? OR path LIKE ?",
                arguments: [path, likePrefix],
            )
            return db.changesCount
        }
    }

    func updateById(_ id: Int64, updates: FileUpdate) async throws -> FileRecord? {
        try await manager.write { db in
            let assignments = updates.columnAssignments()
            let request = FileRecord.filter(FileRecord.Columns.id == id)
            if assignments.isEmpty {
                return try request.fetchOne(db)
            }

            let updated = try request.updateAll(db, assignments)
            guard updated > 0 else { return nil }
            return try request.fetchOne(db)
        }
    }

    func insertOne(_ record: FileRecord) async throws {
        try Self.ensureDirectoryId(record)
        try await manager.write { db in
            var record = record
            try record.insert(db)
        }
    }

    func insertBatch(_ records: [FileRecord]) async throws {
        guard !records.isEmpty else { return }

        let batchSize = try await manager.read { db in
            try Self.maxBatchSize(in: db)
        }
        try await insertBatch(records, batchSize: batchSize)
    }

    func insertBatch(_ records: [FileRecord], batchSize: Int) async throws {
        guard !records.isEmpty else { return }
        try Self.ensureDirectoryIds(records)

        let logger = logger

        for chunk in records.chunked(into: batchSize) {
            do {
                try await manager.write { db in
                    try insertChunk(chunk, db: db)
                }
            } catch {
                logger.warning("Batch insert failed, retrying per-row: \(error)")
                try await manager.write { db in
                    try insertChunkIndividually(chunk, db: db)
                }
            }
        }
    }

    func upsertByPath(_ record: FileRecord) async throws -> FileRecord {
        try Self.ensureDirectoryId(record)
        return try await manager.write { db in
            var record = record
            if let existing = try FileRecord.filter(FileRecord.Columns.path == record.path).fetchOne(db) {
                record.id = existing.id
                try record.update(db)
                return record
            }

            record.id = nil
            try record.insert(db)
            return record
        }
    }

    func upsertByLogicalKey(_ key: FileLogicalKey, record: FileRecord) async throws -> FileRecord {
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

    private func fetchByLogicalKey(_ key: FileLogicalKey, db: Database) throws -> FileRecord? {
        let request = FileRecord.filter(
            FileRecord.Columns.volumeIdentifier == key.volumeIdentifier &&
                FileRecord.Columns.fileResourceIdentifier == key.fileResourceIdentifier,
        )
        return try request.fetchOne(db)
    }

    static func maxBatchSize(in db: Database) throws -> Int {
        let maxVariables = try Int.fetchOne(db, sql: "PRAGMA max_variable_number") ?? 999
        let columnsPerRow = FileRecord.insertableColumnCount
        guard columnsPerRow > 0 else { return 1 }
        return max(1, maxVariables / columnsPerRow)
    }

    private func insertChunk(_ records: [FileRecord], db: Database) throws {
        let columns = FileRecord.insertableColumns
        guard !columns.isEmpty else { return }

        let updatableColumns = columns.filter {
            $0 != .volumeIdentifier && $0 != .fileResourceIdentifier
        }
        let updateAssignments = updatableColumns
            .map { "\($0.rawValue) = excluded.\($0.rawValue)" }
            .joined(separator: ", ")

        let columnList = columns.map(\.rawValue).joined(separator: ", ")
        let placeholder = "(" + Array(repeating: "?", count: columns.count).joined(separator: ", ") + ")"
        let placeholders = Array(repeating: placeholder, count: records.count).joined(separator: ", ")
        let sql = """
        INSERT INTO \(FileRecord.databaseTableName) (\(columnList))
        VALUES \(placeholders)
        ON CONFLICT(volume_identifier, file_resource_identifier)
        DO UPDATE SET \(updateAssignments)
        """

        var arguments: [DatabaseValueConvertible?] = []
        arguments.reserveCapacity(records.count * columns.count)
        for record in records {
            arguments.append(contentsOf: record.insertableValues)
        }

        let statement = try db.cachedStatement(sql: sql)
        try statement.execute(arguments: StatementArguments(arguments))
    }

    private func insertChunkIndividually(_ records: [FileRecord], db: Database) throws {
        var lastError: Error?
        for record in records {
            do {
                try insertChunk([record], db: db)
            } catch {
                lastError = error
                logger.warning("File insert failed: \(error)")
            }
        }
        if let lastError {
            throw lastError
        }
    }

    private static func ensureDirectoryIds(_ records: [FileRecord]) throws {
        for record in records {
            try ensureDirectoryId(record)
        }
    }

    private static func ensureDirectoryId(_ record: FileRecord) throws {
        guard record.directoryId != nil else {
            throw FileRepositoryError.missingDirectoryId(path: record.path)
        }
    }
}

private nonisolated extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        var chunks: [[Element]] = []
        chunks.reserveCapacity((count / size) + 1)
        var index = 0
        while index < count {
            let end = Swift.min(index + size, count)
            chunks.append(Array(self[index ..< end]))
            index = end
        }
        return chunks
    }
}
