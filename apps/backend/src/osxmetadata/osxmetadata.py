"""ctypes 기반 osxmetadata (읽기 전용)."""

from __future__ import annotations

import base64
import datetime
import json
import pathlib
import typing as t

from ._version import __version__
from .attribute_data import (
    MDIMPORTER_ATTRIBUTE_DATA,
    MDITEM_ATTRIBUTE_DATA,
    MDITEM_ATTRIBUTE_SHORT_NAMES,
)
from .mditem import MDItemValueType, create_mditem, get_mditem_metadata, release_mditem
from .xattr_metadata import (
    Tag,
    _kMDItemUserTags,
    get_finder_comment,
    get_finder_tags,
    kMDItemFinderComment,
)

ASDICT_ATTRIBUTES = {
    *list(MDITEM_ATTRIBUTE_DATA.keys()),
    *list(MDIMPORTER_ATTRIBUTE_DATA.keys()),
    _kMDItemUserTags,
    kMDItemFinderComment,
}


class OSXMetaDataAttributeError(Exception):
    """지원하지 않는 메타데이터 접근 시 발생"""


class OSXMetaData:
    """macOS 메타데이터 읽기 전용 클래스"""

    def __init__(self, fname: str):
        self._fname = pathlib.Path(fname)
        if not self._fname.exists():
            raise FileNotFoundError(f"file does not exist: {fname}")
        self._posix_path = self._fname.resolve().as_posix()
        self._mditem = create_mditem(self._posix_path)
        self.__init = True

    def __del__(self) -> None:
        if hasattr(self, "_mditem"):
            release_mditem(self._mditem)

    def get(self, attribute: str) -> MDItemValueType:
        return self.__getattr__(attribute)

    def set(self, attribute: str, value: MDItemValueType) -> None:
        raise OSXMetaDataAttributeError("ctypes 버전은 쓰기를 지원하지 않습니다")

    def asdict(self, attributes: t.Set[str] = ASDICT_ATTRIBUTES) -> dict[str, t.Any]:
        return {key: getattr(self, key) for key in attributes}

    def to_json(self, attributes: t.Set[str] = ASDICT_ATTRIBUTES, indent: int = 4) -> str:
        dict_data = self.asdict(attributes)
        dict_data.update(
            {
                "_version": __version__,
                "_filepath": self._posix_path,
                "_filename": self._fname.name,
            }
        )

        for key, value in dict_data.items():
            if isinstance(value, datetime.datetime):
                dict_data[key] = value.isoformat()
            elif isinstance(value, (list, tuple)):
                if value and isinstance(value[0], datetime.datetime):
                    dict_data[key] = [v.isoformat() for v in value]
            elif isinstance(value, bytes):
                dict_data[key] = base64.b64encode(value).decode("ascii")

        return json.dumps(dict_data, indent=indent)

    def get_mditem_attribute_value(self, attribute: str) -> MDItemValueType:
        return get_mditem_metadata(self._mditem, attribute)

    @property
    def path(self) -> str:
        return self._posix_path

    def __getattr__(self, attribute: str) -> MDItemValueType:
        if attribute in ["tags", _kMDItemUserTags]:
            return get_finder_tags(self._posix_path)
        if attribute in ["findercomment", kMDItemFinderComment]:
            value = get_mditem_metadata(self._mditem, kMDItemFinderComment)
            return value if value is not None else get_finder_comment(self._posix_path)
        if attribute in MDITEM_ATTRIBUTE_SHORT_NAMES:
            attribute = MDITEM_ATTRIBUTE_SHORT_NAMES[attribute]
        if attribute not in MDITEM_ATTRIBUTE_DATA and attribute not in MDIMPORTER_ATTRIBUTE_DATA:
            raise OSXMetaDataAttributeError(f"지원하지 않는 attribute: {attribute}")
        return get_mditem_metadata(self._mditem, attribute)
