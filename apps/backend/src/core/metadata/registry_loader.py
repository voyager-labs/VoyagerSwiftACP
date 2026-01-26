from __future__ import annotations

import json
import os
import sys
from dataclasses import dataclass
from enum import Enum
from pathlib import Path
from typing import Any, cast

REGISTRY_SHARED_DIR = "shared"
CONDITION_REGISTRY_FILENAME = "property_condition_registry.json"
SYSTEM_PROPERTY_REGISTRY_FILENAME = "system_property_registry.json"


def _coerce_str_any_dict(value: Any) -> dict[str, Any]:
    if not isinstance(value, dict):
        return {}
    result: dict[str, Any] = {}
    value_dict = cast(dict[str, Any], value)
    for raw_key, raw_value in value_dict.items():
        result[raw_key] = raw_value
    return result


def _coerce_str_list(value: Any) -> list[str]:
    if not isinstance(value, list):
        return []
    result: list[str] = []
    for item in cast(list[str], value):
        result.append(item)
    return result


def _coerce_str_str_dict(value: Any) -> dict[str, str]:
    if not isinstance(value, dict):
        return {}
    result: dict[str, str] = {}
    value_dict = cast(dict[str, str], value)
    for raw_key, raw_value in value_dict.items():
        result[raw_key] = raw_value
    return result


def _candidate_registry_paths(filename: str) -> list[Path]:
    candidates: list[Path] = []

    module_path = Path(__file__).resolve()
    for parent in module_path.parents:
        candidates.append(parent / REGISTRY_SHARED_DIR / filename)

    if sys.argv and sys.argv[0]:
        binary_path = Path(sys.argv[0]).resolve()
        for parent in binary_path.parents:
            candidates.append(parent / REGISTRY_SHARED_DIR / filename)

    cwd = Path.cwd().resolve()
    for parent in [cwd, *cwd.parents]:
        candidates.append(parent / REGISTRY_SHARED_DIR / filename)

    unique: list[Path] = []
    seen: set[Path] = set()
    for path in candidates:
        if path in seen:
            continue
        seen.add(path)
        unique.append(path)

    return unique


def resolve_registry_path(filename: str) -> Path:
    for path in _candidate_registry_paths(filename):
        if path.exists():
            return path

    tried = "\n".join(f" - {path}" for path in _candidate_registry_paths(filename))
    raise FileNotFoundError(f"{filename} not found.\nTried paths:\n{tried}")


def load_registry_payload(filename: str) -> dict[str, Any]:
    path = resolve_registry_path(filename)
    with path.open("r", encoding="utf-8") as f:
        raw = json.load(f)
    payload = _coerce_str_any_dict(raw)
    if not payload:
        raise ValueError(f"{filename} is empty")
    return payload


def _require_registry_kind(payload: dict[str, Any], expected: str, filename: str) -> None:
    kind = payload.get("$kind")
    if kind != expected:
        raise ValueError(f"{filename} $kind is '{expected}' but got '{kind}'")


def _require_payload_mapping(payload: dict[str, Any], key: str, filename: str) -> dict[str, Any]:
    mapping = _coerce_str_any_dict(payload.get(key))
    if not mapping:
        raise ValueError(f"{filename} '{key}' is empty")
    return mapping


@dataclass
class ConditionOperator:
    """조건 연산자 정의"""

    code: str
    sql_operator: str | None
    sql_kind: str | None
    value_shape: str | None
    value_count: int | str | None
    allowed_types: list[str]
    inverse_of: str | None
    aliases: list[str]
    ui_label: str | None
    ui_value_kind: dict[str, str]


@dataclass
class ConditionRegistry:
    """조건 레지스트리"""

    property_types: dict[str, "ConditionTypeDefaults"]
    operators: dict[str, ConditionOperator]


@dataclass
class ConditionTypeDefaults:
    """타입별 기본 설정"""

    operators: list[str]
    sql_cast: str | None


def load_condition_registry(
    filename: str = CONDITION_REGISTRY_FILENAME,
) -> ConditionRegistry:
    payload = load_registry_payload(filename)
    _require_registry_kind(payload, "property_condition_registry", filename)

    property_types_payload = _require_payload_mapping(payload, "property_types", filename)
    operators_payload = _require_payload_mapping(payload, "operators", filename)

    operators: dict[str, ConditionOperator] = {}
    for code, raw in operators_payload.items():
        raw_dict = _coerce_str_any_dict(raw)
        if not raw_dict:
            continue
        operators[code] = ConditionOperator(
            code=code,
            sql_operator=cast(str | None, raw_dict.get("sql_operator")),
            sql_kind=cast(str | None, raw_dict.get("sql_kind")),
            value_shape=cast(str | None, raw_dict.get("value_shape")),
            value_count=cast(int | str | None, raw_dict.get("value_count")),
            allowed_types=_coerce_str_list(raw_dict.get("allowed_types")),
            inverse_of=cast(str | None, raw_dict.get("inverse_of")),
            aliases=_coerce_str_list(raw_dict.get("aliases")),
            ui_label=cast(str | None, raw_dict.get("ui_label")),
            ui_value_kind=_coerce_str_str_dict(raw_dict.get("ui_value_kind")),
        )

    parsed_property_types: dict[str, ConditionTypeDefaults] = {}
    for type_key, raw in property_types_payload.items():
        raw_dict = _coerce_str_any_dict(raw)
        if not raw_dict:
            continue
        parsed_property_types[type_key] = ConditionTypeDefaults(
            operators=_coerce_str_list(raw_dict.get("operators")),
            sql_cast=cast(str | None, raw_dict.get("sql_cast")),
        )

    return ConditionRegistry(property_types=parsed_property_types, operators=operators)


class SystemPropertyType(Enum):
    """System property 타입"""

    STRING = "string"
    NUMBER = "number"
    DATE = "date"
    BOOLEAN = "boolean"
    STRING_LIST = "string_list"


@dataclass
class SystemPropertyAttribute:
    """System property 정의"""

    key: str
    db_indexed: bool
    type: SystemPropertyType
    ui_label: str
    legacy_keys: list[str]
    description: str
    search_aliases: list[str]
    category: str
    system_keys: list[str]
    json_path: str | None
    supported_operators: list[str]
    availability: str | None = None
    value_format: str | None = None
    ui_pinned: bool | None = None
    ui_hidden: bool = False


def _parse_value_type(raw_type: str) -> SystemPropertyType:
    return SystemPropertyType(raw_type.lower())


def _json_path_for(system_keys: list[str]) -> str | None:
    """system_keys에서 original_metadata JSON path를 유도합니다."""

    if not system_keys:
        return None

    # original_metadata는 kMDItem* 키(또는 기타 provider key) 기반으로 저장됩니다.
    for system_key in system_keys:
        if system_key.startswith("mditem:"):
            return f"$.{system_key.split(':', 1)[1]}"

    first = system_keys[0]
    if ":" in first:
        return f"$.{first.split(':', 1)[1]}"
    return f"$.{first}"


def _operators_for_type(registry: ConditionRegistry, value_type: SystemPropertyType) -> list[str]:
    type_key = value_type.value
    defaults = registry.property_types.get(type_key)
    operator_codes = defaults.operators if defaults else []
    supported: list[str] = []
    for code in operator_codes:
        operator = registry.operators.get(code)
        if not operator:
            continue
        if operator.allowed_types and type_key not in operator.allowed_types:
            continue
        supported.append(code)
    return supported


def _parse_system_property_registry(
    payload: dict[str, Any],
    condition_registry: ConditionRegistry,
) -> dict[str, SystemPropertyAttribute]:
    categories = payload.get("categories")
    categories_dict = _coerce_str_any_dict(categories)
    if not categories_dict:
        raise ValueError("system_property_registry의 categories는 비어있지 않은 객체여야 합니다.")

    registry: dict[str, SystemPropertyAttribute] = {}
    for category, entries in categories_dict.items():
        entries_dict = _coerce_str_any_dict(entries)
        if not entries_dict:
            continue

        for key, raw in entries_dict.items():
            raw_dict = _coerce_str_any_dict(raw)
            if not raw_dict:
                continue

            raw_type = raw_dict.get("type")
            if not isinstance(raw_type, str):
                continue
            value_type = _parse_value_type(raw_type)

            system_keys = _coerce_str_list(raw_dict.get("system_keys"))
            legacy_keys = _coerce_str_list(raw_dict.get("legacy_keys"))
            search_aliases = _coerce_str_list(raw_dict.get("search_aliases"))

            ui_label_value = raw_dict.get("ui_label")
            ui_label = ui_label_value if isinstance(ui_label_value, str) else key

            description_value = raw_dict.get("description")
            description = description_value if isinstance(description_value, str) else ""

            availability_value = raw_dict.get("availability")
            availability = availability_value if isinstance(availability_value, str) else None

            value_format_value = raw_dict.get("value_format")
            value_format = value_format_value if isinstance(value_format_value, str) else None

            ui_pinned_value = raw_dict.get("ui_pinned")
            ui_pinned = ui_pinned_value if isinstance(ui_pinned_value, bool) else None

            registry[key] = SystemPropertyAttribute(
                key=key,
                db_indexed=bool(raw_dict.get("db_indexed", False)),
                type=value_type,
                ui_label=ui_label,
                legacy_keys=legacy_keys,
                description=description,
                search_aliases=search_aliases,
                category=category,
                system_keys=system_keys,
                json_path=_json_path_for(system_keys),
                supported_operators=_operators_for_type(condition_registry, value_type),
                availability=availability,
                value_format=value_format,
                ui_pinned=ui_pinned,
                ui_hidden=bool(raw_dict.get("ui_hidden", False)),
            )

    return registry


def load_system_property_registry(
    condition_registry: ConditionRegistry | None = None,
    filename: str = SYSTEM_PROPERTY_REGISTRY_FILENAME,
) -> dict[str, SystemPropertyAttribute]:
    if condition_registry is None:
        condition_registry = load_condition_registry()
    payload = load_registry_payload(filename)
    _require_registry_kind(payload, "system_property_registry", filename)
    return _parse_system_property_registry(payload, condition_registry)


CONDITION_REGISTRY = load_condition_registry()
SYSTEM_PROPERTY_REGISTRY = load_system_property_registry(CONDITION_REGISTRY)


def get_property_key_mapping(property_key: str) -> SystemPropertyAttribute | None:
    """propertyKey로 매핑 정보 조회"""

    return SYSTEM_PROPERTY_REGISTRY.get(property_key)


def get_all_property_keys() -> list[str]:
    """모든 지원 propertyKey 목록 반환"""

    return list(SYSTEM_PROPERTY_REGISTRY.keys())


def get_visible_property_keys() -> list[str]:
    """UI에 노출 가능한 propertyKey 목록 반환"""

    return [k for k, v in SYSTEM_PROPERTY_REGISTRY.items() if not v.ui_hidden]


def get_attributes_by_category(category: str) -> dict[str, SystemPropertyAttribute]:
    """카테고리별 속성 필터링"""

    return {k: v for k, v in SYSTEM_PROPERTY_REGISTRY.items() if v.category == category}


def get_indexed_attributes() -> dict[str, SystemPropertyAttribute]:
    """전용 DB 컬럼이 있는 속성들만 반환"""

    return {k: v for k, v in SYSTEM_PROPERTY_REGISTRY.items() if v.db_indexed}


def get_json_attributes() -> dict[str, SystemPropertyAttribute]:
    """JSON 쿼리가 필요한 속성들만 반환"""

    return {k: v for k, v in SYSTEM_PROPERTY_REGISTRY.items() if not v.db_indexed}


__all__ = [
    "CONDITION_REGISTRY",
    "SYSTEM_PROPERTY_REGISTRY",
    "ConditionOperator",
    "ConditionRegistry",
    "ConditionTypeDefaults",
    "SystemPropertyAttribute",
    "SystemPropertyType",
    "get_all_property_keys",
    "get_visible_property_keys",
    "get_attributes_by_category",
    "get_indexed_attributes",
    "get_json_attributes",
    "get_property_key_mapping",
    "load_condition_registry",
    "load_registry_payload",
    "load_system_property_registry",
    "resolve_registry_path",
]
