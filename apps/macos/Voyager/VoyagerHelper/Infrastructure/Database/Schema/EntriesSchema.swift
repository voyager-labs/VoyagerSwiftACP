import Foundation

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
        "directory_id",
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
        "directory_id": "디렉터리 참조 (directories.id)",
    ]
}
