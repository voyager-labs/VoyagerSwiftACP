import os
from pathlib import Path

from core.file_crawler.models import VoyagerOSXMetaData
from infra.schemas.file_entry_schema import FileEntrySchema
from utils.paths import calculate_depth_from_home, get_relative_path_from_home


def convert_to_file_entry_schema(
    file_path: Path, stat: os.stat_result, metadata: VoyagerOSXMetaData
) -> FileEntrySchema:
    return FileEntrySchema(
        id=None,
        # Identity
        path=str(file_path),
        dir_path=str(file_path.parent),
        name_full=file_path.name,
        name_stem=file_path.stem,
        extension=file_path.suffix.lstrip("."),
        parent_dir_name=file_path.parent.name,
        depth_from_home=calculate_depth_from_home(file_path),
        relative_path_from_home=get_relative_path_from_home(file_path),
        # Properties
        size=stat.st_size,
        dev_id=stat.st_dev,
        inode=stat.st_ino,
        mode=stat.st_mode,
        owner_uid=stat.st_uid,
        owner_gid=stat.st_gid,
        nlink=stat.st_nlink,
        uniform_type_identifier=metadata.get_str("kMDItemContentType"),
        file_kind=metadata.get_str("kMDItemKind"),
        is_invisible=metadata.get_bool("kMDItemFSInvisible"),
        where_from=metadata.get_str("kMDItemWhereFroms"),
        # Timestamps
        creation_date=metadata.get_datetime("kMDItemFSCreationDate", stat.st_ctime),
        modification_date=metadata.get_datetime("kMDItemFSContentChangeDate", stat.st_mtime),
        content_creation_date=metadata.get_datetime("kMDItemContentCreationDate", stat.st_ctime),
        content_modification_date=metadata.get_datetime(
            "kMDItemContentModificationDate", stat.st_mtime
        ),
        added_date=metadata.get_datetime("kMDItemDateAdded", stat.st_ctime),
        last_used_date=metadata.get_datetime_opt("kMDItemLastUsedDate"),
        birthtime=metadata.get_datetime_opt("kMDItemFSCreationDate"),
        # JSON blobs
        finder_tags=metadata.get_tags("_kMDItemUserTags"),
        original_metadata=metadata.asdict(),
    )
