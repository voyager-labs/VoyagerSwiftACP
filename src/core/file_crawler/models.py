from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Any, Optional

from osxmetadata import OSXMetaData

from utils.paths import calculate_depth_from_home


class VoyagerOSXMetaData(OSXMetaData):
    def get_str(self, key: str) -> Optional[str]:
        v_obj: object | None = self.get(key)
        if type(v_obj) is str:
            return v_obj
        if type(v_obj) is list:
            return v_obj[0] if v_obj else None
        return None

    def get_datetime(self, key: str, fallback_ts: float) -> datetime:
        v = self.get(key)
        if isinstance(v, datetime):
            return v
        return datetime.fromtimestamp(fallback_ts)

    def get_datetime_opt(self, key: str) -> Optional[datetime]:
        v = self.get(key)
        return v if isinstance(v, datetime) else None

    def get_tags(self, key: str) -> list[str]:
        v = self.get(key)
        if type(v) is list:
            try:
                return [str(x) for x in v]
            except Exception:
                return []
        return []

    def get_bool(self, key: str, default: bool = False) -> bool:
        v = self.get(key)
        return v if type(v) is bool else default


@dataclass(frozen=True, slots=True)
class VoyagerFileMeta:
    name_full: str
    name_stem: str
    extension: str
    size: int
    uniform_type_identifier: Optional[str]
    file_kind: Optional[str]
    path: Path
    dir_path: Path
    parent_dir_name: str
    depth: int
    creation_date: datetime
    modification_date: datetime
    content_creation_date: datetime
    content_modification_date: datetime
    added_date: datetime
    last_used_date: Optional[datetime]
    finder_tags: list[str]
    is_invisible: bool
    where_from: Optional[str]
    # sha256: str # TODO: 추후 추가 고려
    original_metadata: dict[str, Any]

    @classmethod
    def from_file_path(cls, file_path: Path) -> "VoyagerFileMeta":
        stat = file_path.stat()
        metadata = VoyagerOSXMetaData(str(file_path))

        return cls(
            name_full=file_path.name,
            name_stem=file_path.stem,
            extension=file_path.suffix,
            size=stat.st_size,
            uniform_type_identifier=metadata.get_str("kMDItemContentType"),
            file_kind=metadata.get_str("kMDItemKind"),
            path=file_path,
            dir_path=file_path.parent,
            parent_dir_name=file_path.parent.name,
            depth=calculate_depth_from_home(file_path),
            creation_date=metadata.get_datetime("kMDItemFSCreationDate", stat.st_ctime),
            modification_date=metadata.get_datetime("kMDItemFSContentChangeDate", stat.st_mtime),
            content_creation_date=metadata.get_datetime(
                "kMDItemContentCreationDate", stat.st_ctime
            ),
            content_modification_date=metadata.get_datetime(
                "kMDItemContentModificationDate", stat.st_mtime
            ),
            added_date=metadata.get_datetime("kMDItemDateAdded", stat.st_ctime),
            last_used_date=metadata.get_datetime_opt("kMDItemLastUsedDate"),
            finder_tags=metadata.get_tags("_kMDItemUserTags"),
            is_invisible=metadata.get_bool("kMDItemFSInvisible", False),
            where_from=metadata.get_str("kMDItemWhereFroms"),
            original_metadata=metadata.asdict(),
        )
