import Foundation
@preconcurrency import GRDB
import Logging

nonisolated struct EntryUpdate: Sendable {
    var path: String?
    var dirPath: String?
    var nameFull: String?
    var nameStem: String?
    var fileExtension: String?
    var parentDirName: String?
    var depthFromHome: Int?
    var relativePathFromHome: String?
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
        append(&assignments, column: .parentDirName, value: parentDirName)
        append(&assignments, column: .depthFromHome, value: depthFromHome)
        append(&assignments, column: .relativePathFromHome, value: relativePathFromHome)
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
    }

    private func append<T: DatabaseValueConvertible>(
        _ assignments: inout [ColumnAssignment],
        column: EntryRecord.Columns,
        value: T?
    ) {
        guard let value else { return }
        assignments.append(column.set(to: value))
    }
}

nonisolated struct EntryRepository: Sendable {
    private let manager: DatabaseManager
    private let logger: Logger

    init(manager: DatabaseManager, logger: Logger = Logger(label: "VoyagerHelper.EntryRepository")) {
        self.manager = manager
        self.logger = logger
    }

    func fetchById(_ id: Int64) async throws -> EntryRecord? {
        try await manager.read { db in
            try EntryRecord.filter(EntryRecord.Columns.id == id).fetchOne(db)
        }
    }

    func fetchByPath(_ path: String) async throws -> EntryRecord? {
        try await manager.read { db in
            try EntryRecord.filter(EntryRecord.Columns.path == path).fetchOne(db)
        }
    }

    func deleteById(_ id: Int64) async throws -> Int {
        try await manager.write { db in
            try EntryRecord.filter(EntryRecord.Columns.id == id).deleteAll(db)
        }
    }

    func deleteByPath(_ path: String) async throws -> Int {
        try await manager.write { db in
            try EntryRecord.filter(EntryRecord.Columns.path == path).deleteAll(db)
        }
    }

    func updateById(_ id: Int64, updates: EntryUpdate) async throws -> EntryRecord? {
        try await manager.write { db in
            let assignments = updates.columnAssignments()
            let request = EntryRecord.filter(EntryRecord.Columns.id == id)
            if assignments.isEmpty {
                return try request.fetchOne(db)
            }

            let updated = try request.updateAll(db, assignments)
            guard updated > 0 else { return nil }
            return try request.fetchOne(db)
        }
    }

    func insertOne(_ record: EntryRecord) async throws {
        try await manager.write { db in
            var record = record
            try record.insert(db)
        }
    }

    func insertBatch(_ records: [EntryRecord]) async throws {
        guard !records.isEmpty else { return }

        let batchSize = try await manager.read { db in
            try Self.maxBatchSize(in: db)
        }
        try await insertBatch(records, batchSize: batchSize)
    }

    func insertBatch(_ records: [EntryRecord], batchSize: Int) async throws {
        guard !records.isEmpty else { return }

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

    func upsertByPath(_ record: EntryRecord) async throws -> EntryRecord {
        try await manager.write { db in
            var record = record
            if let existing = try EntryRecord.filter(EntryRecord.Columns.path == record.path).fetchOne(db) {
                record.id = existing.id
                try record.update(db)
                return record
            }

            record.id = nil
            try record.insert(db)
            return record
        }
    }

    func upsertByLogicalKey(_ key: EntryLogicalKey, record: EntryRecord) async throws -> EntryRecord {
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

    private func fetchByLogicalKey(_ key: EntryLogicalKey, db: Database) throws -> EntryRecord? {
        let request = EntryRecord.filter(
            EntryRecord.Columns.volumeIdentifier == key.volumeIdentifier &&
                EntryRecord.Columns.fileResourceIdentifier == key.fileResourceIdentifier
        )
        return try request.fetchOne(db)
    }

    static func maxBatchSize(in db: Database) throws -> Int {
        let maxVariables = try Int.fetchOne(db, sql: "PRAGMA max_variable_number") ?? 999
        let columnsPerRow = EntryRecord.insertableColumnCount
        guard columnsPerRow > 0 else { return 1 }
        return max(1, maxVariables / columnsPerRow)
    }

    private func insertChunk(_ records: [EntryRecord], db: Database) throws {
        let columns = EntryRecord.insertableColumns
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
        INSERT INTO \(EntryRecord.databaseTableName) (\(columnList))
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

    private func insertChunkIndividually(_ records: [EntryRecord], db: Database) throws {
        var lastError: Error?
        for var record in records {
            do {
                try insertChunk([record], db: db)
            } catch {
                lastError = error
                logger.warning("Entry insert failed: \(error)")
            }
        }
        if let lastError {
            throw lastError
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
