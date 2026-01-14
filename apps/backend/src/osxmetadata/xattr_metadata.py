"""xattr 기반 Finder 메타데이터 읽기 유틸."""

from __future__ import annotations

import os
import plistlib
from typing import Iterable, NamedTuple


class Tag(NamedTuple):
    name: str
    color: int


_kMDItemUserTags = "_kMDItemUserTags"
kMDItemFinderComment = "kMDItemFinderComment"

_XATTR_USER_TAGS = "com.apple.metadata:_kMDItemUserTags"
_XATTR_FINDER_COMMENT = "com.apple.metadata:kMDItemFinderComment"


def _read_xattr(path: str, key: str) -> bytes | None:
    try:
        return os.getxattr(path, key)
    except (OSError, AttributeError):
        return None


def _plist_load(data: bytes) -> object | None:
    try:
        return plistlib.loads(data)
    except Exception:
        return None


def _normalize_tag_values(values: Iterable[object]) -> list[Tag]:
    tags: list[Tag] = []
    for value in values:
        if isinstance(value, bytes):
            text = value.decode("utf-8", errors="ignore")
        else:
            text = str(value)
        parts = text.split("\n", 1)
        name = parts[0].strip()
        color = 0
        if len(parts) > 1:
            try:
                color = int(parts[1])
            except ValueError:
                color = 0
        if name:
            tags.append(Tag(name, color))
    return tags


def get_finder_tags(path: str) -> list[Tag]:
    data = _read_xattr(path, _XATTR_USER_TAGS)
    if not data:
        return []
    values = _plist_load(data)
    if not isinstance(values, list):
        return []
    return _normalize_tag_values(values)


def get_finder_comment(path: str) -> str | None:
    data = _read_xattr(path, _XATTR_FINDER_COMMENT)
    if not data:
        return None
    value = _plist_load(data)
    if value is None:
        return None
    if isinstance(value, bytes):
        return value.decode("utf-8", errors="ignore")
    return str(value)
