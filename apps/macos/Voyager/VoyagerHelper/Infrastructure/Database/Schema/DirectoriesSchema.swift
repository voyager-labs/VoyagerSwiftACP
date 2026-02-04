import Foundation

nonisolated enum DirectoriesSchema {
    static let tableName = "directories"

    static let requiredColumns = [
        "id",
        "volume_identifier",
        "file_resource_identifier",
        "path",
        "parent_id",
        "name_full",
        "name_stem",
        "depth_from_home",
        "relative_path_from_home",
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
        "path": "디렉터리 절대 경로 (Path)",
        "parent_id": "상위 디렉터리 참조 (directories.id)",
        "name_full": "디렉터리 이름 (Path.name)",
        "name_stem": "디렉터리 이름(확장자 제외) (Path.stem)",
        "depth_from_home": "$HOME 기준 경로 깊이",
        "relative_path_from_home": "$HOME 기준 상대 경로",
        "is_invisible": "숨김 여부 (kMDItemFSInvisible)",
        "creation_date": "생성 시간 (kMDItemFSCreationDate)",
        "modification_date": "수정 시간 (kMDItemFSContentChangeDate)",
        "content_creation_date": "콘텐츠 생성 시간 (kMDItemContentCreationDate)",
        "content_modification_date": "콘텐츠 수정 시간 (kMDItemContentModificationDate)",
        "added_date": "추가 시간 (kMDItemDateAdded)",
        "last_used_date": "마지막 실행 시간 (kMDItemLastUsedDate)",
        "original_metadata": "원본 메타데이터 (OSXMetaData)",
    ]
}
