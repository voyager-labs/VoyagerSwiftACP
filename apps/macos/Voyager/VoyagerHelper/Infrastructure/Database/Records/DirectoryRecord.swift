import Foundation
@preconcurrency import GRDB

nonisolated struct DirectoryRecord: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    var id: Int64?
    var volumeIdentifier: String?
    var fileResourceIdentifier: String?
    var path: String
    var parentId: Int64?
    var nameFull: String?
    var nameStem: String?
    var depthFromHome: Int?
    var relativePathFromHome: String?
    var isInvisible: Bool?
    var creationDate: Date?
    var modificationDate: Date?
    var contentCreationDate: Date?
    var contentModificationDate: Date?
    var addedDate: Date?
    var lastUsedDate: Date?
    var originalMetadata: String?

    static let databaseTableName = "directories"
    static let insertableColumns: [Columns] = [
        .volumeIdentifier,
        .fileResourceIdentifier,
        .path,
        .parentId,
        .nameFull,
        .nameStem,
        .depthFromHome,
        .relativePathFromHome,
        .isInvisible,
        .creationDate,
        .modificationDate,
        .contentCreationDate,
        .contentModificationDate,
        .addedDate,
        .lastUsedDate,
        .originalMetadata,
    ]
    static let insertableColumnCount = insertableColumns.count

    var insertableValues: [DatabaseValueConvertible?] {
        [
            volumeIdentifier,
            fileResourceIdentifier,
            path,
            parentId,
            nameFull,
            nameStem,
            depthFromHome,
            relativePathFromHome,
            isInvisible,
            creationDate,
            modificationDate,
            contentCreationDate,
            contentModificationDate,
            addedDate,
            lastUsedDate,
            originalMetadata,
        ]
    }

    enum Columns: String, ColumnExpression, CaseIterable {
        case id
        case volumeIdentifier = "volume_identifier"
        case fileResourceIdentifier = "file_resource_identifier"
        case path
        case parentId = "parent_id"
        case nameFull = "name_full"
        case nameStem = "name_stem"
        case depthFromHome = "depth_from_home"
        case relativePathFromHome = "relative_path_from_home"
        case isInvisible = "is_invisible"
        case creationDate = "creation_date"
        case modificationDate = "modification_date"
        case contentCreationDate = "content_creation_date"
        case contentModificationDate = "content_modification_date"
        case addedDate = "added_date"
        case lastUsedDate = "last_used_date"
        case originalMetadata = "original_metadata"
    }

    enum CodingKeys: String, CodingKey {
        case id
        case volumeIdentifier = "volume_identifier"
        case fileResourceIdentifier = "file_resource_identifier"
        case path
        case parentId = "parent_id"
        case nameFull = "name_full"
        case nameStem = "name_stem"
        case depthFromHome = "depth_from_home"
        case relativePathFromHome = "relative_path_from_home"
        case isInvisible = "is_invisible"
        case creationDate = "creation_date"
        case modificationDate = "modification_date"
        case contentCreationDate = "content_creation_date"
        case contentModificationDate = "content_modification_date"
        case addedDate = "added_date"
        case lastUsedDate = "last_used_date"
        case originalMetadata = "original_metadata"
    }

    mutating func didInsert(with rowID: Int64, for _: String?) {
        id = rowID
    }
}

// 논리 키는 유니크 제약 기준으로 사용된다.
nonisolated struct DirectoryLogicalKey: Sendable {
    let volumeIdentifier: String
    let fileResourceIdentifier: String
}
