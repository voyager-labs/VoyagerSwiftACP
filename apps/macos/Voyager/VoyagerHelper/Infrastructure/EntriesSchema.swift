import Foundation
import GRDB

nonisolated enum EntriesSchema {
    static let tableName = "entries"

    static let requiredColumns = [
        "id",
        "volume_identifier",
        "file_resource_identifier",
        "path",
        "dir_path",
        "name_full",
        "name_stem",
        "extension",
        "parent_dir_name",
        "depth_from_home",
        "relative_path_from_home",
        "size",
        "uniform_type_identifier",
        "file_kind",
        "is_invisible",
        "creation_date",
        "modification_date",
        "content_creation_date",
        "content_modification_date",
        "added_date",
        "last_used_date",
        "original_metadata",
    ]

    static let columnDescriptions: [String: String] = [
        "id": "기본키",
        "volume_identifier": "볼륨 식별자 (URLResourceKey.volumeIdentifierKey)",
        "file_resource_identifier": "파일 리소스 식별자 (URLResourceKey.fileResourceIdentifierKey)",
        "path": "파일 절대 경로 (Path)",
        "dir_path": "파일이 속한 디렉토리 절대 경로 (Path.parent)",
        "name_full": "파일 이름(확장자 포함) (Path.name)",
        "name_stem": "파일 이름(확장자 제외) (Path.stem)",
        "extension": "파일 확장자 (Path.suffix)",
        "parent_dir_name": "파일이 속한 부모 디렉토리 이름 (Path.parent.name)",
        "depth_from_home": "$HOME 기준 파일 경로 깊이",
        "relative_path_from_home": "$HOME 기준 상대 경로",
        "size": "파일 크기 (kMDItemFSSize)",
        "uniform_type_identifier": "유니폼 타입 식별자 (kMDItemContentType)",
        "file_kind": "파일 종류 (kMDItemKind)",
        "is_invisible": "숨김 파일 여부 (kMDItemFSInvisible)",
        "creation_date": "파일 생성 시간 (kMDItemFSCreationDate)",
        "modification_date": "파일 수정 시간 (kMDItemFSContentChangeDate)",
        "content_creation_date": "콘텐츠 생성 시간 (kMDItemContentCreationDate)",
        "content_modification_date": "콘텐츠 수정 시간 (kMDItemContentModificationDate)",
        "added_date": "파일 추가 시간 (kMDItemDateAdded)",
        "last_used_date": "파일 마지막 실행 시간 (kMDItemLastUsedDate)",
        "original_metadata": "원본 메타데이터 (OSXMetaData)",
    ]

    static func createTable(_ db: Database) throws {
        try db.create(table: tableName) { table in
            table.autoIncrementedPrimaryKey("id")
            table.column("volume_identifier", .text).notNull()
            table.column("file_resource_identifier", .text).notNull()
            table.uniqueKey(["volume_identifier", "file_resource_identifier"])
            table.column("path", .text).notNull()
            table.column("dir_path", .text).notNull()
            table.column("name_full", .text).notNull()
            table.column("name_stem", .text).notNull()
            table.column("extension", .text).notNull()
            table.column("parent_dir_name", .text).notNull()
            table.column("depth_from_home", .integer).notNull()
            table.column("relative_path_from_home", .text)
            table.column("size", .integer).notNull()
            table.column("uniform_type_identifier", .text)
            table.column("file_kind", .text)
            table.column("is_invisible", .boolean).notNull().defaults(to: false)
            table.column("creation_date", .datetime).notNull()
            table.column("modification_date", .datetime).notNull()
            table.column("content_creation_date", .datetime).notNull()
            table.column("content_modification_date", .datetime).notNull()
            table.column("added_date", .datetime).notNull()
            table.column("last_used_date", .datetime)
            table.column("original_metadata", .text).notNull()
        }
    }
}
