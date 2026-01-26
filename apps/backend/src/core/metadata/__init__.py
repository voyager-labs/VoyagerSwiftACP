"""macOS 파일 메타데이터 관리 모듈

System property 레지스트리 시스템:
- 40+ macOS 메타데이터 속성 정의
- LLM 기반 자연어 검색 지원

사용 예제:
    >>> from core.metadata import SYSTEM_PROPERTY_REGISTRY
    >>> # 레지스트리에서 속성 조회
    >>> attrs = get_indexed_attributes()
    >>> print(len(attrs))
"""

from .registry_loader import (
    SYSTEM_PROPERTY_REGISTRY,
    SystemPropertyAttribute,
    SystemPropertyType,
    get_indexed_attributes,
    get_json_attributes,
)

__all__ = [
    "SYSTEM_PROPERTY_REGISTRY",
    "SystemPropertyAttribute",
    "SystemPropertyType",
    "get_indexed_attributes",
    "get_json_attributes",
]
