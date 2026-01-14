"""Voyager용 osxmetadata 포크 (ctypes 기반 읽기 전용)."""

# TODO: osxmetadata 실제 리포지토리 기반 포크 진행
from ._version import __version__
from .osxmetadata import OSXMetaData, OSXMetaDataAttributeError

__all__ = ["OSXMetaData", "OSXMetaDataAttributeError", "__version__"]
