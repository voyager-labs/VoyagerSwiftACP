"""macOS 파일 메타데이터 관리 모듈

MDItem 레지스트리 시스템:
- 40+ macOS 메타데이터 속성 정의
- LLM 기반 자연어 검색 지원

사용 예제:
    >>> from core.metadata import MDITEM_REGISTRY
    >>> # 레지스트리에서 속성 조회
    >>> attrs = get_indexed_attributes()
    >>> print(len(attrs))
"""

from .mditem_registry import (
    MDITEM_REGISTRY,
    MDItemAttribute,
    MDItemType,
    get_attributes_by_category,
    get_indexed_attributes,
    get_json_attributes,
)

__all__ = [
    "MDITEM_REGISTRY",
    "MDItemAttribute",
    "MDItemType",
    "get_attributes_by_category",
    "get_indexed_attributes",
    "get_json_attributes",
]
