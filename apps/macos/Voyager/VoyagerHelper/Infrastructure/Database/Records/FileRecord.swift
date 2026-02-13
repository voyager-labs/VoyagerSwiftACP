import Foundation
@preconcurrency import GRDB

nonisolated struct FileRecord: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    var id: Int64?
    var volumeIdentifier: String
    var fileResourceIdentifier: String
    var path: String
    var dirPath: String
    var nameFull: String
    var nameStem: String
    var fileExtension: String
    var size: Int64
    var uniformTypeIdentifier: String?
    var fileKind: String?
    var isInvisible: Bool
    var creationDate: Date
    var modificationDate: Date
    var contentCreationDate: Date
    var contentModificationDate: Date
    var addedDate: Date
    var lastUsedDate: Date?
    var originalMetadata: String
    var directoryId: Int64?

    static let databaseTableName = FilesSchema.tableName
    static let insertableColumns: [Columns] = [
        .volumeIdentifier,
        .fileResourceIdentifier,
        .path,
        .dirPath,
        .nameFull,
        .nameStem,
        .fileExtension,
        .size,
        .uniformTypeIdentifier,
        .fileKind,
        .isInvisible,
        .creationDate,
        .modificationDate,
        .contentCreationDate,
        .contentModificationDate,
        .addedDate,
        .lastUsedDate,
        .originalMetadata,
        .directoryId,
    ]
    static let insertableColumnCount = insertableColumns.count

    var insertableValues: [DatabaseValueConvertible?] {
        [
            volumeIdentifier,
            fileResourceIdentifier,
            path,
            dirPath,
            nameFull,
            nameStem,
            fileExtension,
            size,
            uniformTypeIdentifier,
            fileKind,
            isInvisible,
            creationDate,
            modificationDate,
            contentCreationDate,
            contentModificationDate,
            addedDate,
            lastUsedDate,
            originalMetadata,
            directoryId,
        ]
    }

    enum Columns: String, ColumnExpression, CaseIterable {
        case id
        case volumeIdentifier = "volume_identifier"
        case fileResourceIdentifier = "file_resource_identifier"
        case path
        case dirPath = "dir_path"
        case nameFull = "name_full"
        case nameStem = "name_stem"
        case fileExtension = "extension"
        case size
        case uniformTypeIdentifier = "uniform_type_identifier"
        case fileKind = "file_kind"
        case isInvisible = "is_invisible"
        case creationDate = "creation_date"
        case modificationDate = "modification_date"
        case contentCreationDate = "content_creation_date"
        case contentModificationDate = "content_modification_date"
        case addedDate = "added_date"
        case lastUsedDate = "last_used_date"
        case originalMetadata = "original_metadata"
        case directoryId = "directory_id"
    }

    enum CodingKeys: String, CodingKey {
        case id
        case volumeIdentifier = "volume_identifier"
        case fileResourceIdentifier = "file_resource_identifier"
        case path
        case dirPath = "dir_path"
        case nameFull = "name_full"
        case nameStem = "name_stem"
        case fileExtension = "extension"
        case size
        case uniformTypeIdentifier = "uniform_type_identifier"
        case fileKind = "file_kind"
        case isInvisible = "is_invisible"
        case creationDate = "creation_date"
        case modificationDate = "modification_date"
        case contentCreationDate = "content_creation_date"
        case contentModificationDate = "content_modification_date"
        case addedDate = "added_date"
        case lastUsedDate = "last_used_date"
        case originalMetadata = "original_metadata"
        case directoryId = "directory_id"
    }

    mutating func didInsert(with rowID: Int64, for _: String?) {
        id = rowID
    }
}

// 논리 키는 유니크 제약 기준으로 사용된다.
nonisolated struct FileLogicalKey: Sendable {
    let volumeIdentifier: String
    let fileResourceIdentifier: String
}
