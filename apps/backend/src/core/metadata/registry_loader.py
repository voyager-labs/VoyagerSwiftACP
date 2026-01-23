from __future__ import annotations

import json
import os
import sys
from dataclasses import dataclass
from enum import Enum
from pathlib import Path
from typing import Any

REGISTRY_ENV_VAR = "REGISTRY_PATH"
REGISTRY_SHARED_DIR = "shared"
CONDITION_REGISTRY_FILENAME = "property_condition_registry.json"
SYSTEM_PROPERTY_REGISTRY_FILENAME = "system_property_registry.json"


def _candidate_registry_paths(filename: str) -> list[Path]:
    candidates: list[Path] = []

    env_path = os.getenv(REGISTRY_ENV_VAR)
    if env_path:
        env_candidate = Path(env_path).expanduser()
        if env_candidate.is_dir():
            candidates.append(env_candidate / filename)
        elif env_candidate.suffix == ".json":
            if env_candidate.name == filename:
                candidates.append(env_candidate)
            else:
                candidates.append(env_candidate.parent / filename)
        else:
            candidates.append(env_candidate / filename)

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
    raise FileNotFoundError(f"{filename}을 찾을 수 없습니다.\n시도한 경로:\n{tried}")


def load_registry_payload(filename: str) -> dict[str, Any]:
    path = resolve_registry_path(filename)
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def _require_registry_kind(payload: dict[str, Any], expected: str, filename: str) -> None:
    kind = payload.get("$kind")
    if kind != expected:
        raise ValueError(f"{filename} $kind이 '{expected}'여야 합니다. (현재: {kind})")


def _require_payload_mapping(payload: dict[str, Any], key: str, filename: str) -> dict[str, Any]:
    value = payload.get(key)
    if not isinstance(value, dict) or not value:
        raise ValueError(f"{filename} '{key}'는 비어있지 않은 객체여야 합니다.")
    return value


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
    property_types = _require_payload_mapping(payload, "property_types", filename)
    operators_payload = _require_payload_mapping(payload, "operators", filename)

    operators: dict[str, ConditionOperator] = {}
    for code, raw in operators_payload.items():
        operators[code] = ConditionOperator(
            code=code,
            sql_operator=raw.get("sql_operator"),
            sql_kind=raw.get("sql_kind"),
            value_shape=raw.get("value_shape"),
            value_count=raw.get("value_count"),
            allowed_types=list(raw.get("allowed_types", [])),
            inverse_of=raw.get("inverse_of"),
            aliases=list(raw.get("aliases", [])),
            ui_label=raw.get("ui_label"),
            ui_value_kind=dict(raw.get("ui_value_kind", {})),
        )

    parsed_property_types: dict[str, ConditionTypeDefaults] = {}
    for type_key, raw in property_types.items():
        if not isinstance(raw, dict):
            raise ValueError(f"property_types.{type_key}는 객체여야 합니다.")
        parsed_property_types[type_key] = ConditionTypeDefaults(
            operators=list(raw.get("operators", [])),
            sql_cast=raw.get("sql_cast"),
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
    db_field: str | None
    db_indexed: bool
    type: SystemPropertyType
    label: str
    description: str
    search_aliases: list[str]
    category: str
    system_keys: list[str]
    json_path: str | None
    supported_operators: list[str]
    availability: str | None = None
    value_format: str | None = None
    ui_pinned: bool | None = None


def _parse_value_type(raw_type: str) -> SystemPropertyType:
    return SystemPropertyType(raw_type.lower())


def _json_path_for(system_keys: list[str]) -> str | None:
    if not system_keys:
        return None

    for system_key in system_keys:
        if system_key.startswith("mditem:"):
            return f"$.{system_key.split(':', 1)[1]}"

    first = system_keys[0]
    return f"$.{first.split(':', 1)[1]}" if ":" in first else f"$.{first}"


def _operators_for_type(registry: ConditionRegistry, value_type: SystemPropertyType) -> list[str]:
    type_key = value_type.value
    property_types = registry.property_types.get(type_key)
    operator_codes = property_types.operators if property_types else []
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
    payload: dict[str, Any], condition_registry: ConditionRegistry
) -> dict[str, SystemPropertyAttribute]:
    categories = payload.get("categories")
    if not isinstance(categories, dict) or not categories:
        raise ValueError("system_property_registry의 categories는 비어있지 않은 객체여야 합니다.")
    registry: dict[str, SystemPropertyAttribute] = {}

    for category, entries in categories.items():
        if not isinstance(entries, dict):
            continue
        for key, raw in entries.items():
            value_type = _parse_value_type(raw["type"])
            system_keys = raw.get("system_keys", [])
            registry[key] = SystemPropertyAttribute(
                key=key,
                db_field=key if raw.get("db_indexed") else None,
                db_indexed=bool(raw.get("db_indexed", False)),
                type=value_type,
                label=raw.get("label", key),
                description=raw.get("description", ""),
                search_aliases=raw.get("search_aliases", []),
                category=category,
                system_keys=system_keys,
                json_path=_json_path_for(system_keys),
                supported_operators=_operators_for_type(condition_registry, value_type),
                availability=raw.get("availability"),
                value_format=raw.get("value_format"),
                ui_pinned=raw.get("ui_pinned"),
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


def get_attributes_by_category(category: str) -> dict[str, SystemPropertyAttribute]:
    """카테고리별 속성 필터링"""
    return {k: v for k, v in SYSTEM_PROPERTY_REGISTRY.items() if v.category == category}


def get_indexed_attributes() -> dict[str, SystemPropertyAttribute]:
    """전용 DB 컬럼이 있는 속성들만 반환"""
    return {k: v for k, v in SYSTEM_PROPERTY_REGISTRY.items() if v.db_field is not None}


def get_json_attributes() -> dict[str, SystemPropertyAttribute]:
    """JSON 쿼리가 필요한 속성들만 반환"""
    return {k: v for k, v in SYSTEM_PROPERTY_REGISTRY.items() if v.db_field is None}


__all__ = [
    "CONDITION_REGISTRY",
    "SYSTEM_PROPERTY_REGISTRY",
    "ConditionOperator",
    "ConditionRegistry",
    "SystemPropertyAttribute",
    "SystemPropertyType",
    "get_all_property_keys",
    "get_attributes_by_category",
    "get_indexed_attributes",
    "get_json_attributes",
    "get_property_key_mapping",
    "load_condition_registry",
    "load_registry_payload",
    "load_system_property_registry",
    "resolve_registry_path",
]
