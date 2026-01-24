from __future__ import annotations

from datetime import datetime
from typing import ClassVar

from sqlalchemy import UniqueConstraint
from sqlmodel import Field, SQLModel


class EntrySchema(SQLModel, table=True):
    __tablename__: ClassVar[str] = "entries"
    __table_args__ = (
        UniqueConstraint(
            "volume_identifier",
            "file_resource_identifier",
            name="uix_entries_volume_resource",
        ),
    )

    id: int | None = Field(default=None, primary_key=True)

    # Identity
    volume_identifier: str = Field(index=True, description="볼륨 식별자 (URLResourceKey.volumeIdentifierKey)")
    file_resource_identifier: str = Field(
        index=True, description="파일 리소스 식별자 (URLResourceKey.fileResourceIdentifierKey)"
    )
    path: str = Field(index=True, description="파일 절대 경로 (Path)")
    dir_path: str = Field(index=True, description="파일이 속한 디렉토리 절대 경로 (Path.parent)")
    name_full: str = Field(index=True, description="파일 이름(확장자 포함) (Path.name)")
    name_stem: str = Field(index=True, description="파일 이름(확장자 제외) (Path.stem)")
    extension: str = Field(index=True, description="파일 확장자 (Path.suffix)")
    parent_dir_name: str = Field(
        index=True, description="파일이 속한 부모 디렉토리 이름 (Path.parent.name)"
    )
    depth_from_home: int = Field(description="$HOME 기준 파일 경로 깊이")
    relative_path_from_home: str | None = Field(default=None, description="$HOME 기준 상대 경로")

    # Properties
    size: int = Field(index=True, description="파일 크기 (kMDItemFSSize)")
    uniform_type_identifier: str | None = Field(
        default=None, index=True, description="유니폼 타입 식별자 (kMDItemContentType)"
    )
    file_kind: str | None = Field(default=None, index=True, description="파일 종류 (kMDItemKind)")
    is_invisible: bool = Field(
        default=False, index=True, description="숨김 파일 여부 (kMDItemFSInvisible)"
    )

    # Timestamps
    creation_date: datetime = Field(description="파일 생성 시간 (kMDItemFSCreationDate)")
    modification_date: datetime = Field(description="파일 수정 시간 (kMDItemFSContentChangeDate)")
    content_creation_date: datetime = Field(
        description="콘텐츠 생성 시간 (kMDItemContentCreationDate)"
    )
    content_modification_date: datetime = Field(
        description="콘텐츠 수정 시간 (kMDItemContentModificationDate)"
    )
    added_date: datetime = Field(description="파일 추가 시간 (kMDItemDateAdded)")
    last_used_date: datetime | None = Field(
        default=None, description="파일 마지막 실행 시간 (kMDItemLastUsedDate)"
    )
    # JSON blobs
    original_metadata: str = Field(description="원본 메타데이터 (OSXMetaData)")

    # TODO: 추후 추가 고려 키: VOY-25 이슈 설명 확인


__all__ = ["EntrySchema"]
