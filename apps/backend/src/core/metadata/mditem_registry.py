"""macOS MDItem 속성 레지스트리

Apple Developer Documentation 기반:
https://developer.apple.com/documentation/coreservices/file_metadata/mditem/common_metadata_attribute_keys

현재 레지스트리 SSOT는 shared/system_property_registry.json 입니다.
"""

from __future__ import annotations

import json
import os
import sys
from dataclasses import dataclass
from enum import Enum
from pathlib import Path
from typing import Any


class MDItemType(Enum):
    """MDItem 속성 타입"""

    STRING = "string"
    NUMBER = "number"
    DATE = "date"
    BOOLEAN = "boolean"
    ARRAY = "array"


@dataclass
class MDItemAttribute:
    """MDItem 속성 정의

    Attributes:
        key: MDItem 키 (예: kMDItemContentType)
        db_field: 전용 DB 컬럼명 (None이면 JSON 쿼리 사용)
        type: 데이터 타입
        description: 속성 설명
        examples: 예시 값들
        search_aliases: 자연어 검색 시 사용 가능한 별칭들
        category: 속성 카테고리 (파일시스템/콘텐츠/미디어 등)
    """

    key: str
    db_field: str | None
    type: MDItemType
    description: str
    examples: list[Any]
    search_aliases: list[str]
    category: str = "general"


@dataclass
class PropertyKeyMapping:
    """Search API용 propertyKey 매핑

    Attributes:
        property_key: API에서 사용하는 키 (예: "size", "contentType")
        db_field: DB 컬럼명 (None이면 JSON 쿼리)
        json_path: JSON 추출 경로 (예: "$.kMDItemPixelHeight")
        value_type: 값 타입 (검증/변환용)
        supported_operators: 지원하는 연산자 목록
    """

    property_key: str
    db_field: str | None
    json_path: str | None
    value_type: MDItemType
    supported_operators: list[str]


REGISTRY_ENV_VAR = "REGISTRY_PATH"
REGISTRY_FILENAME = "system_property_registry.json"
REGISTRY_SHARED_DIR = "shared"


def _candidate_registry_paths() -> list[Path]:
    candidates: list[Path] = []

    env_path = os.getenv(REGISTRY_ENV_VAR)
    if env_path:
        candidates.append(Path(env_path).expanduser())

    module_path = Path(__file__).resolve()
    for parent in module_path.parents:
        candidates.append(parent / REGISTRY_SHARED_DIR / REGISTRY_FILENAME)

    if sys.argv and sys.argv[0]:
        binary_path = Path(sys.argv[0]).resolve()
        for parent in binary_path.parents:
            candidates.append(parent / REGISTRY_SHARED_DIR / REGISTRY_FILENAME)

    cwd = Path.cwd().resolve()
    for parent in [cwd, *cwd.parents]:
        candidates.append(parent / REGISTRY_SHARED_DIR / REGISTRY_FILENAME)

    unique: list[Path] = []
    seen: set[Path] = set()
    for path in candidates:
        if path in seen:
            continue
        seen.add(path)
        unique.append(path)

    return unique


def _resolve_registry_path() -> Path:
    for path in _candidate_registry_paths():
        if path.exists():
            return path

    tried = "\n".join(f" - {path}" for path in _candidate_registry_paths())
    raise FileNotFoundError(
        f"system_property_registry.json을 찾을 수 없습니다.\n시도한 경로:\n{tried}"
    )


def _load_registry_payload() -> dict[str, Any]:
    path = _resolve_registry_path()
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def _parse_mditem_registry(payload: dict[str, Any]) -> dict[str, MDItemAttribute]:
    raw_registry = payload.get("mditem_registry")
    if raw_registry is None:
        raw_registry = {
            key: value
            for key, value in payload.items()
            if key not in {"property_key_registry", "mditem_registry"}
            and not key.startswith("$")
            and not key.startswith("_")
        }
    registry: dict[str, MDItemAttribute] = {}

    for key, raw in raw_registry.items():
        mditem_key = raw.get("key", key)
        value_type = MDItemType(raw["type"])
        registry[mditem_key] = MDItemAttribute(
            key=mditem_key,
            db_field=raw.get("db_field"),
            type=value_type,
            description=raw.get("description", ""),
            examples=raw.get("examples", []),
            search_aliases=raw.get("search_aliases", []),
            category=raw.get("category", "general"),
        )

    return registry


def _parse_property_key_registry(payload: dict[str, Any]) -> dict[str, PropertyKeyMapping]:
    raw_registry = payload.get("property_key_registry", {})
    registry: dict[str, PropertyKeyMapping] = {}

    for key, raw in raw_registry.items():
        property_key = raw.get("property_key", key)
        value_type = MDItemType(raw["value_type"])
        registry[property_key] = PropertyKeyMapping(
            property_key=property_key,
            db_field=raw.get("db_field"),
            json_path=raw.get("json_path"),
            value_type=value_type,
            supported_operators=raw.get("supported_operators", []),
        )

    return registry


def load_registry() -> tuple[dict[str, MDItemAttribute], dict[str, PropertyKeyMapping]]:
    """JSON 레지스트리를 로딩해 메모리 구조로 변환"""
    payload = _load_registry_payload()
    mditem_registry = _parse_mditem_registry(payload)
    property_key_registry = _parse_property_key_registry(payload)
    return mditem_registry, property_key_registry


MDITEM_REGISTRY, PROPERTY_KEY_REGISTRY = load_registry()


def get_property_key_mapping(property_key: str) -> PropertyKeyMapping | None:
    """propertyKey로 매핑 정보 조회"""
    return PROPERTY_KEY_REGISTRY.get(property_key)


def get_all_property_keys() -> list[str]:
    """모든 지원 propertyKey 목록 반환"""
    return list(PROPERTY_KEY_REGISTRY.keys())


def get_attributes_by_category(category: str) -> dict[str, MDItemAttribute]:
    """카테고리별 속성 필터링"""
    return {k: v for k, v in MDITEM_REGISTRY.items() if v.category == category}


def get_indexed_attributes() -> dict[str, MDItemAttribute]:
    """전용 DB 컬럼이 있는 속성들만 반환"""
    return {k: v for k, v in MDITEM_REGISTRY.items() if v.db_field is not None}


def get_json_attributes() -> dict[str, MDItemAttribute]:
    """JSON 쿼리가 필요한 속성들만 반환"""
    return {k: v for k, v in MDITEM_REGISTRY.items() if v.db_field is None}


__all__ = [
    "MDITEM_REGISTRY",
    "MDItemAttribute",
    "MDItemType",
    "PropertyKeyMapping",
    "PROPERTY_KEY_REGISTRY",
    "get_attributes_by_category",
    "get_indexed_attributes",
    "get_json_attributes",
    "get_property_key_mapping",
    "get_all_property_keys",
]
