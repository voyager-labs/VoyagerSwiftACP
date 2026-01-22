"""SQL 조건 빌더

Search API의 conditions를 SQL WHERE절로 변환합니다.
"""

from typing import Any, Sequence, cast

from core.metadata.registry_loader import (
    CONDITION_REGISTRY,
    SYSTEM_PROPERTY_REGISTRY,
    ConditionOperator,
    SystemPropertyAttribute,
    SystemPropertyType,
)


class ConditionBuilderError(Exception):
    """조건 빌더 에러"""

    pass


class ConditionBuilder:
    """Search conditions를 SQL WHERE절로 변환하는 빌더"""

    def __init__(self, registry: dict[str, SystemPropertyAttribute] | None = None):
        """
        Args:
            registry: PropertyKey 레지스트리 (기본: SYSTEM_PROPERTY_REGISTRY)
        """
        self.registry = registry or SYSTEM_PROPERTY_REGISTRY

    def build_clause(self, property_key: str, operator: str, value: Any) -> tuple[str, list[Any]]:
        """단일 조건을 SQL 절로 변환

        Args:
            property_key: 속성 키 (예: "size", "extension")
            operator: 연산자 (예: "eq", "gt", "contains")
            value: 값

        Returns:
            (sql_fragment, parameters) 튜플

        Raises:
            ConditionBuilderError: 알 수 없는 propertyKey 또는 지원하지 않는 operator
        """
        mapping = self.registry.get(property_key)
        if not mapping:
            raise ConditionBuilderError(f"Unknown propertyKey: {property_key}")

        if operator not in mapping.supported_operators:
            raise ConditionBuilderError(
                f"Operator '{operator}' not supported for '{property_key}'. "
                f"Supported: {mapping.supported_operators}"
            )

        operator_meta = CONDITION_REGISTRY.operators.get(operator)
        if not operator_meta:
            raise ConditionBuilderError(f"Unknown operator: {operator}")

        self._validate_operator_meta(operator_meta, operator, property_key)
        self._validate_value(operator_meta.value_count, operator, value, property_key)

        if mapping.db_field:
            return self._build_db_clause(mapping, operator_meta, value)
        return self._build_json_clause(mapping, operator_meta, value)

    def _build_db_clause(
        self, mapping: SystemPropertyAttribute, operator_meta: ConditionOperator, value: Any
    ) -> tuple[str, list[Any]]:
        """DB 컬럼 조건 생성"""
        field = mapping.db_field
        if not field:
            raise ConditionBuilderError(f"Missing db_field for '{mapping.key}'")
        # DATE 타입이면 DATE() 함수로 날짜만 비교
        if mapping.type == SystemPropertyType.DATE:
            field = f"DATE({field})"
        return self._build_kind_clause(
            field=field,
            mapping=mapping,
            operator_meta=operator_meta,
            value=value,
            json_path=None,
        )

    def _build_json_clause(
        self, mapping: SystemPropertyAttribute, operator_meta: ConditionOperator, value: Any
    ) -> tuple[str, list[Any]]:
        """JSON 필드 조건 생성"""
        property_types = CONDITION_REGISTRY.property_types.get(mapping.type.value)
        if not property_types or not property_types.sql_cast:
            raise ConditionBuilderError(f"Missing sql_cast for type '{mapping.type.value}'.")
        cast_type = property_types.sql_cast
        if not mapping.json_path:
            raise ConditionBuilderError(f"Missing JSON path for '{mapping.key}'")
        if mapping.type == SystemPropertyType.STRING_LIST:
            return self._build_string_list_clause(mapping, operator_meta, value)
        field = f"CAST(json_extract(original_metadata, '{mapping.json_path}') AS {cast_type})"
        return self._build_kind_clause(
            field=field,
            mapping=mapping,
            operator_meta=operator_meta,
            value=value,
            json_path=mapping.json_path,
        )

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

        expected_shapes = {
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
        allowed_shapes = expected_shapes.get(sql_kind)
        if allowed_shapes and value_shape not in allowed_shapes:
            raise ConditionBuilderError(
                f"Operator '{operator}' value_shape mismatch: '{value_shape}' for sql_kind '{sql_kind}'."
            )

    def _build_kind_clause(
        self,
        field: str,
        mapping: SystemPropertyAttribute,
        operator_meta: ConditionOperator,
        value: Any,
        json_path: str | None,
    ) -> tuple[str, list[Any]]:
        sql_kind = operator_meta.sql_kind
        sql_operator = operator_meta.sql_operator

        if sql_kind == "exists":
            if json_path:
                return self._build_json_presence_clause(json_path)
            return f"{field} IS NOT NULL", []

        if sql_kind == "empty":
            return self._build_empty_clause(field, mapping, json_path)

        if sql_kind == "range":
            if not isinstance(value, (list, tuple)):
                raise ConditionBuilderError(
                    f"'{operator_meta.code}' operator requires [min, max] array, got: {value}"
                )
            range_values = list(cast(Sequence[Any], value))
            if len(range_values) != 2:
                raise ConditionBuilderError(
                    f"'{operator_meta.code}' operator requires [min, max] array, got: {value}"
                )
            return f"{field} {sql_operator or 'BETWEEN'} ? AND ?", range_values

        if sql_kind == "like_prefix":
            return f"{field} {sql_operator or 'LIKE'} ?", [f"{value}%"]

        if sql_kind == "like_suffix":
            return f"{field} {sql_operator or 'LIKE'} ?", [f"%{value}"]

        if sql_kind == "like_pattern":
            return f"{field} {sql_operator or 'LIKE'} ?", [value]

        if sql_kind == "comparison":
            return f"{field} {sql_operator or '='} ?", [value]

        raise ConditionBuilderError(f"Unsupported sql_kind: {sql_kind}")

    def _build_string_list_clause(
        self, mapping: SystemPropertyAttribute, operator_meta: ConditionOperator, value: Any
    ) -> tuple[str, list[Any]]:
        sql_kind = operator_meta.sql_kind
        json_path = mapping.json_path
        if not json_path:
            raise ConditionBuilderError(f"Missing JSON path for '{mapping.key}'")

        if sql_kind == "exists":
            return self._build_json_presence_clause(json_path)

        if sql_kind == "empty":
            length_clause = "json_array_length(original_metadata, ?)"
            return f"({length_clause} IS NULL OR {length_clause} = 0)", [
                json_path,
                json_path,
            ]

        values: list[Any]
        if isinstance(value, (list, tuple)):
            values = list(cast(Sequence[Any], value))
        else:
            values = []
        if not values:
            raise ConditionBuilderError(
                f"'{operator_meta.code}' operator requires non-empty array value, got: {value}"
            )

        placeholders = ", ".join(["?"] * len(values))
        if sql_kind in {"string_list_any", "string_list_not_any"}:
            clause = (
                "EXISTS (SELECT 1 FROM json_each(original_metadata, ?) "
                f"WHERE value IN ({placeholders}))"
            )
            if sql_kind == "string_list_not_any":
                clause = f"NOT {clause}"
            return clause, [json_path, *values]

        if sql_kind in {"string_list_all", "string_list_not_all"}:
            clause = (
                "(\n"
                "  SELECT COUNT(DISTINCT value)\n"
                "  FROM json_each(original_metadata, ?)\n"
                f"  WHERE value IN ({placeholders})\n"
                ") = ?"
            )
            if sql_kind == "string_list_not_all":
                clause = f"NOT ({clause})"
            return clause, [json_path, *values, len(values)]

        raise ConditionBuilderError(f"Unsupported string_list sql_kind: {sql_kind}")

    def _build_empty_clause(
        self, field: str, mapping: SystemPropertyAttribute, json_path: str | None
    ) -> tuple[str, list[Any]]:
        if mapping.type == SystemPropertyType.STRING_LIST and json_path:
            length_clause = "json_array_length(original_metadata, ?)"
            return f"({length_clause} IS NULL OR {length_clause} = 0)", [
                json_path,
                json_path,
            ]
        return f"({field} IS NULL OR {field} = '')", []

    def _build_json_presence_clause(self, json_path: str) -> tuple[str, list[Any]]:
        return "json_type(original_metadata, ?) IS NOT NULL", [json_path]

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
            if not isinstance(value, (list, tuple)):
                raise ConditionBuilderError(
                    f"Operator '{operator}' requires non-empty array for '{property_key}'."
                )
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

    def build_where(self, conditions: list[dict[str, Any]]) -> tuple[str, list[Any]]:
        """여러 조건을 AND로 결합한 WHERE절 생성

        Args:
            conditions: 조건 목록 [{"propertyKey": ..., "operator": ..., "value": ...}]

        Returns:
            (where_clause, parameters) 튜플
        """
        if not conditions:
            return "1=1", []

        clauses: list[str] = []
        all_params: list[Any] = []

        for condition in conditions:
            property_key = condition.get("propertyKey")
            operator = condition.get("operator")
            value = condition.get("value")

            if not property_key or not operator:
                continue

            clause, params = self.build_clause(property_key, operator, value)
            clauses.append(clause)
            all_params.extend(params)

        if not clauses:
            return "1=1", []

        return " AND ".join(clauses), all_params
