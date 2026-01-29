"""SQL 조건 빌더

Search API의 conditions를 SQL WHERE절로 변환합니다.

- TODO: Swift Voyager Helper로 이관 [VOY-152]
- TODO: Swift Voyager Helper 이관 시 SQL 구문을 문자열로 반환하는 대신, Swift의 ORM 쿼리 객체를 반환하도록 변경
"""

from dataclasses import dataclass
from typing import Any, Sequence, cast

from core.metadata.registry_loader import (
    CONDITION_REGISTRY,
    SYSTEM_PROPERTY_REGISTRY,
    ConditionOperator,
    SystemPropertyAttribute,
    SystemPropertyType,
)

# sql_kind 처리 규칙 모음
SQL_KIND_DEFAULT_OPERATORS: dict[str, str] = {
    "comparison": "=",
    "range": "BETWEEN",
    "like_prefix": "LIKE",
    "like_suffix": "LIKE",
    "like_pattern": "LIKE",
}

SQL_KIND_VALUE_SHAPES: dict[str, set[str]] = {
    "comparison": {"single"},
    "like_prefix": {"single"},
    "like_suffix": {"single"},
    "like_pattern": {"single"},
    "range": {"range"},
    "exists": {"none"},
    "empty": {"none"},
    "string_list_any": {"list"},
    "string_list_all": {"list"},
    "string_list_not_any": {"list"},
    "string_list_not_all": {"list"},
}


class ConditionBuilderError(Exception):
    """조건 빌더 에러"""

    pass


class _ParamBinder:
    def __init__(self, prefix: str = "p") -> None:
        self.prefix = prefix
        self.index = 0
        self.params: dict[str, Any] = {}

    def bind(self, value: Any) -> str:
        name = f"{self.prefix}{self.index}"
        self.index += 1
        self.params[name] = value
        return f":{name}"

    def bind_many(self, values: Sequence[Any]) -> str:
        return ", ".join(self.bind(value) for value in values)


@dataclass(slots=True)
class BuilderClauseParams:
    binder: _ParamBinder
    mapping: SystemPropertyAttribute
    operator_meta: ConditionOperator
    value: Any


@dataclass(slots=True)
class BuilderClauseDetailParams(BuilderClauseParams):
    field: str
    json_path: str | None


class ConditionBuilder:
    """Search conditions를 SQL WHERE절로 변환하는 빌더"""

    def __init__(self, registry: dict[str, SystemPropertyAttribute] | None = None):
        """
        Args:
            registry: PropertyKey 레지스트리 (기본: SYSTEM_PROPERTY_REGISTRY)
        """
        self.registry = registry or SYSTEM_PROPERTY_REGISTRY
        self._json_path_cache: dict[str, str | None] = {}
        self._operator_cache: dict[str, ConditionOperator] = {}

    def build_clause(
        self, property_key: str, operator: str, value: Any
    ) -> tuple[str, dict[str, Any]]:
        """단일 조건을 SQL 절로 변환

        Args:
            property_key: 속성 키 (예: "size", "extension")
            operator: 연산자 (예: "eq", "gt", "cn")
            value: 값

        Returns:
            (sql_fragment, parameters) 튜플

        Raises:
            ConditionBuilderError: 알 수 없는 propertyKey 또는 지원하지 않는 operator
        """
        binder = _ParamBinder()
        clause = self._build_clause_with_binder(binder, property_key, operator, value)
        return clause, binder.params

    def _build_clause_with_binder(
        self, binder: _ParamBinder, property_key: str, operator: str, value: Any
    ) -> str:
        mapping = self.registry.get(property_key)
        if not mapping:
            raise ConditionBuilderError(f"Unknown propertyKey: {property_key}")

        if mapping.ui_hidden:
            raise ConditionBuilderError(f"Hidden propertyKey: {property_key}")

        if operator not in mapping.supported_operators:
            raise ConditionBuilderError(
                f"Operator '{operator}' not supported for '{property_key}'. "
                f"Supported: {mapping.supported_operators}"
            )

        operator_meta = self._operator_cache.get(operator)
        if not operator_meta:
            operator_meta = CONDITION_REGISTRY.operators.get(operator)
            if operator_meta:
                self._operator_cache[operator] = operator_meta
        if not operator_meta:
            raise ConditionBuilderError(f"Unknown operator: {operator}")

        self._validate_operator_meta(operator_meta, operator, property_key)
        self._validate_value(operator_meta.value_count, operator, value, property_key)

        if mapping.db_indexed:
            return self._build_db_clause(
                BuilderClauseParams(
                    binder=binder,
                    mapping=mapping,
                    operator_meta=operator_meta,
                    value=value,
                )
            )
        return self._build_json_clause(
            BuilderClauseParams(
                binder=binder,
                mapping=mapping,
                operator_meta=operator_meta,
                value=value,
            )
        )

    def _build_db_clause(self, params: BuilderClauseParams) -> str:
        """DB 컬럼 조건 생성"""
        field = params.mapping.key
        params = BuilderClauseDetailParams(
            binder=params.binder,
            field=field,
            mapping=params.mapping,
            operator_meta=params.operator_meta,
            value=params.value,
            json_path=None,
        )
        if params.mapping.type == SystemPropertyType.STRING_LIST:
            return self._build_db_string_list_clause(params)
        # DATE 타입이면 DATE() 함수로 날짜만 비교
        if params.mapping.type == SystemPropertyType.DATE:
            params.field = f"DATE({field})"
        return self._build_kind_clause(params)

    def _build_json_clause(self, params: BuilderClauseParams) -> str:
        """JSON 필드 조건 생성"""
        property_types = CONDITION_REGISTRY.property_types.get(params.mapping.type.value)
        if not property_types or not property_types.sql_cast:
            raise ConditionBuilderError(f"Missing sql_cast for type '{params.mapping.type.value}'.")
        cast_type = property_types.sql_cast
        json_path = self._json_path_cache.get(params.mapping.key)
        if json_path is None:
            json_path = self._json_path_for_system_keys(params.mapping.system_keys)
            self._json_path_cache[params.mapping.key] = json_path
        if not json_path:
            raise ConditionBuilderError(f"Missing JSON path for '{params.mapping.key}'")
        field = f"CAST(json_extract(original_metadata, '{json_path}') AS {cast_type})"
        if params.mapping.type == SystemPropertyType.DATE:
            field = f"DATE({field})"
        params = BuilderClauseDetailParams(
            binder=params.binder,
            field=field,
            mapping=params.mapping,
            operator_meta=params.operator_meta,
            value=params.value,
            json_path=json_path,
        )
        return self._build_kind_clause(params)

    def _validate_operator_meta(
        self, operator_meta: ConditionOperator, operator: str, property_key: str
    ) -> None:
        sql_kind = operator_meta.sql_kind
        if not sql_kind:
            raise ConditionBuilderError(
                f"Missing sql_kind for operator '{operator}' (propertyKey: {property_key})."
            )

        value_shape = operator_meta.value_shape
        if not value_shape:
            return

        allowed_shapes = SQL_KIND_VALUE_SHAPES.get(sql_kind)
        if allowed_shapes and value_shape not in allowed_shapes:
            raise ConditionBuilderError(
                f"Operator '{operator}' value_shape mismatch: '{value_shape}' for sql_kind '{sql_kind}'."
            )

    def _build_kind_clause(self, params: BuilderClauseDetailParams) -> str:
        sql_kind = params.operator_meta.sql_kind
        if not sql_kind:
            raise ConditionBuilderError(
                f"Missing sql_kind for operator '{params.operator_meta.code}' (propertyKey: {params.mapping.key})."
            )
        match sql_kind:
            case "exists":
                return self._build_exists_clause(params)
            case "empty":
                return self._build_empty_clause(params)
            case "range":
                return self._build_range_clause(params)
            case "like_prefix":
                return self._build_like_prefix_clause(params)
            case "like_suffix":
                return self._build_like_suffix_clause(params)
            case "like_pattern":
                return self._build_like_pattern_clause(params)
            case "comparison":
                return self._build_comparison_clause(params)
            case "string_list_any":
                return self._build_string_list_any_clause(params)
            case "string_list_not_any":
                return self._build_string_list_not_any_clause(params)
            case "string_list_all":
                return self._build_string_list_all_clause(params)
            case "string_list_not_all":
                return self._build_string_list_not_all_clause(params)
            case _:
                raise ConditionBuilderError(f"Unsupported sql_kind: {sql_kind}")

    def _build_exists_clause(self, params: BuilderClauseDetailParams) -> str:
        if params.json_path:
            return self._build_json_presence_clause(params.binder, params.json_path)
        return f"{params.field} IS NOT NULL"

    def _build_empty_clause(self, params: BuilderClauseDetailParams) -> str:
        if params.mapping.type == SystemPropertyType.STRING_LIST and params.json_path:
            length_clause = "json_array_length(original_metadata, {})"
            first = params.binder.bind(params.json_path)
            second = params.binder.bind(params.json_path)
            return f"({length_clause.format(first)} IS NULL OR {length_clause.format(second)} = 0)"
        return f"({params.field} IS NULL OR {params.field} = '')"

    def _build_db_string_list_clause(self, params: BuilderClauseDetailParams) -> str:
        sql_kind = params.operator_meta.sql_kind

        if sql_kind == "exists":
            return f"{params.field} IS NOT NULL"

        if sql_kind == "empty":
            return f"({params.field} IS NULL OR {params.field} = '')"

        values: list[Any]
        raw_value = params.value
        if isinstance(raw_value, (list, tuple)):
            values = list(cast(Sequence[Any], raw_value))
        else:
            values = []
        if not values:
            raise ConditionBuilderError(
                f"'{params.operator_meta.code}' operator requires non-empty array value, got: {raw_value}"
            )

        if sql_kind == "string_list_any":
            placeholders = params.binder.bind_many(values)
            return f"{params.field} IN ({placeholders})"

        if sql_kind == "string_list_not_any":
            placeholders = params.binder.bind_many(values)
            return f"{params.field} NOT IN ({placeholders})"

        if sql_kind in {"string_list_all", "string_list_not_all"}:
            raise ConditionBuilderError(
                f"Operator '{params.operator_meta.code}' is not supported for DB string_list fields."
            )

        raise ConditionBuilderError(f"Unsupported string_list sql_kind: {sql_kind}")

    def _build_range_clause(self, params: BuilderClauseDetailParams) -> str:
        raw_value: Any = params.value
        if not isinstance(raw_value, (list, tuple)):
            raise ConditionBuilderError(
                f"'{params.operator_meta.code}' operator requires [min, max] array, got: {raw_value}"
            )
        range_values = list(cast(Sequence[Any], raw_value))
        if len(range_values) != 2:
            raise ConditionBuilderError(
                f"'{params.operator_meta.code}' operator requires [min, max] array, got: {raw_value}"
            )
        start = params.binder.bind(range_values[0])
        end = params.binder.bind(range_values[1])
        sql_operator = self._resolve_sql_operator(params.operator_meta)
        return f"{params.field} {sql_operator} {start} AND {end}"

    def _build_like_prefix_clause(self, params: BuilderClauseDetailParams) -> str:
        placeholder = params.binder.bind(f"{params.value}%")
        sql_operator = self._resolve_sql_operator(params.operator_meta)
        return f"{params.field} {sql_operator} {placeholder}"

    def _build_like_suffix_clause(self, params: BuilderClauseDetailParams) -> str:
        placeholder = params.binder.bind(f"%{params.value}")
        sql_operator = self._resolve_sql_operator(params.operator_meta)
        return f"{params.field} {sql_operator} {placeholder}"

    def _build_like_pattern_clause(self, params: BuilderClauseDetailParams) -> str:
        normalized = self._normalize_like_pattern_value(params.operator_meta, params.value)
        placeholder = params.binder.bind(normalized)
        sql_operator = self._resolve_sql_operator(params.operator_meta)
        return f"{params.field} {sql_operator} {placeholder}"

    def _build_comparison_clause(self, params: BuilderClauseDetailParams) -> str:
        placeholder = params.binder.bind(params.value)
        sql_operator = self._resolve_sql_operator(params.operator_meta)
        return f"{params.field} {sql_operator} {placeholder}"

    def _build_string_list_any_clause(self, params: BuilderClauseDetailParams) -> str:
        values = self._normalize_string_list_values(params.operator_meta, params.value)
        # db_indexed 컬럼 또는 categorical 스칼라 값은 JSON array membership가 아니라 IN(...)로 처리합니다.
        if not params.json_path or params.mapping.type == SystemPropertyType.CATEGORICAL:
            if len(values) == 1:
                placeholder = params.binder.bind(values[0])
                return f"{params.field} = {placeholder}"
            placeholders = params.binder.bind_many(values)
            return f"{params.field} IN ({placeholders})"

        placeholders = params.binder.bind_many(values)
        json_placeholder = params.binder.bind(params.json_path)
        return (
            f"EXISTS (SELECT 1 FROM json_each(original_metadata, {json_placeholder}) "
            f"WHERE value IN ({placeholders}))"
        )

    def _build_string_list_not_any_clause(self, params: BuilderClauseDetailParams) -> str:
        values = self._normalize_string_list_values(params.operator_meta, params.value)
        if not params.json_path or params.mapping.type == SystemPropertyType.CATEGORICAL:
            if len(values) == 1:
                placeholder = params.binder.bind(values[0])
                return f"{params.field} != {placeholder}"
            placeholders = params.binder.bind_many(values)
            return f"{params.field} NOT IN ({placeholders})"

        clause = self._build_string_list_any_clause(params)
        return f"NOT {clause}"

    def _build_string_list_all_clause(self, params: BuilderClauseDetailParams) -> str:
        values = self._normalize_string_list_values(params.operator_meta, params.value)
        if not params.json_path:
            # 스칼라 컬럼에서 "all"은 값이 모두 동일할 때만 만족 가능
            if len(values) == 1:
                placeholder = params.binder.bind(values[0])
                return f"{params.field} = {placeholder}"
            return "1=0"

        placeholders = params.binder.bind_many(values)
        json_placeholder = params.binder.bind(params.json_path)
        count_placeholder = params.binder.bind(len(values))
        return (
            "(\n"
            "  SELECT COUNT(DISTINCT value)\n"
            f"  FROM json_each(original_metadata, {json_placeholder})\n"
            f"  WHERE value IN ({placeholders})\n"
            f") = {count_placeholder}"
        )

    def _build_string_list_not_all_clause(self, params: BuilderClauseDetailParams) -> str:
        values = self._normalize_string_list_values(params.operator_meta, params.value)
        if not params.json_path:
            if len(values) == 1:
                placeholder = params.binder.bind(values[0])
                return f"{params.field} != {placeholder}"
            return "1=1"

        clause = self._build_string_list_all_clause(params)
        return f"NOT ({clause})"

    def _json_path_for_system_keys(self, system_keys: list[str]) -> str | None:
        if not system_keys:
            return None
        preferred: str | None = None
        for system_key in system_keys:
            if system_key.startswith("mditem:"):
                preferred = system_key
                break
        if not preferred:
            for system_key in system_keys:
                if not system_key.startswith("nsurl:"):
                    preferred = system_key
                    break
        if not preferred:
            preferred = system_keys[0]
        return f"$.{preferred.split(':', 1)[1]}" if ":" in preferred else f"$.{preferred}"

    def _require_json_path(self, mapping: SystemPropertyAttribute) -> str:
        json_path = self._json_path_for_system_keys(mapping.system_keys)
        if not json_path:
            raise ConditionBuilderError(f"Missing JSON path for '{mapping.key}'")
        return json_path

    def _normalize_string_list_values(
        self,
        operator_meta: ConditionOperator,
        value: Any,
    ) -> list[Any]:
        values: list[Any]
        if isinstance(value, (list, tuple)):
            values = list(cast(Sequence[Any], value))
        elif value is None:
            values = []
        else:
            values = [value]

        if not values:
            raise ConditionBuilderError(
                f"'{operator_meta.code}' operator requires non-empty value, got: {value}"
            )
        return list(dict.fromkeys(values))

    def _normalize_like_pattern_value(
        self,
        operator_meta: ConditionOperator,
        value: Any,
    ) -> Any:
        if not isinstance(value, str):
            return value
        if operator_meta.code in {"cn", "nc"} and "%" not in value:
            return f"%{value}%"
        return value

    def _resolve_sql_operator(self, operator_meta: ConditionOperator) -> str:
        sql_kind = operator_meta.sql_kind
        if operator_meta.sql_operator:
            return operator_meta.sql_operator
        if not sql_kind:
            return ""
        return SQL_KIND_DEFAULT_OPERATORS.get(sql_kind, "")

    def _build_json_presence_clause(self, binder: _ParamBinder, json_path: str) -> str:
        placeholder = binder.bind(json_path)
        return f"json_type(original_metadata, {placeholder}) IS NOT NULL"

    def _validate_value(
        self, value_count: int | str | None, operator: str, value: Any, property_key: str
    ) -> None:
        if value_count == 0:
            if value is not None:
                raise ConditionBuilderError(
                    f"Operator '{operator}' does not accept a value for '{property_key}'."
                )
            return
        if value_count == "n":
            if value is None:
                raise ConditionBuilderError(
                    f"Operator '{operator}' requires non-empty value for '{property_key}'."
                )
            if isinstance(value, (list, tuple)):
                values = list(cast(Sequence[Any], value))
                if len(values) == 0:
                    raise ConditionBuilderError(
                        f"Operator '{operator}' requires non-empty array for '{property_key}'."
                    )
            return
        if value_count == 2:
            if not isinstance(value, (list, tuple)):
                raise ConditionBuilderError(
                    f"Operator '{operator}' requires [min, max] array for '{property_key}'."
                )
            values = list(cast(Sequence[Any], value))
            if len(values) != 2:
                raise ConditionBuilderError(
                    f"Operator '{operator}' requires [min, max] array for '{property_key}'."
                )
            return
        if value_count == 1 and value is None:
            raise ConditionBuilderError(
                f"Operator '{operator}' requires a value for '{property_key}'."
            )

    def build_where(self, conditions: list[dict[str, Any]]) -> tuple[str, dict[str, Any]]:
        """여러 조건을 AND로 결합한 WHERE절 생성

        Args:
            conditions: 조건 목록 [{"propertyKey": ..., "operator": ..., "value": ...}]

        Returns:
            (where_clause, parameters) 튜플 (parameters는 dict[str, Any])
        """
        if not conditions:
            return "1=1", {}

        clauses: list[str] = []
        binder = _ParamBinder()

        for condition in conditions:
            property_key = condition.get("propertyKey")
            operator = condition.get("operator")
            value = condition.get("value")

            if not property_key or not operator:
                raise ConditionBuilderError(
                    f"Missing propertyKey/operator in condition: {condition}"
                )

            clause = self._build_clause_with_binder(binder, property_key, operator, value)
            clauses.append(clause)

        if not clauses:
            return "1=1", {}

        return " AND ".join(clauses), binder.params
