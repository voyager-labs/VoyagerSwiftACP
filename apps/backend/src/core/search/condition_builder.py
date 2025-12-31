"""SQL 조건 빌더

Search API의 conditions를 SQL WHERE절로 변환합니다.
"""

from typing import Any

from core.metadata.mditem_registry import (
    MDItemType,
    PROPERTY_KEY_REGISTRY,
    PropertyKeyMapping,
)


class ConditionBuilderError(Exception):
    """조건 빌더 에러"""

    pass


class ConditionBuilder:
    """Search conditions를 SQL WHERE절로 변환하는 빌더"""

    # Operator → SQL 매핑
    OPERATOR_MAP: dict[str, str] = {
        "eq": "=",
        "neq": "!=",
        "gt": ">",
        "gte": ">=",
        "lt": "<",
        "lte": "<=",
        "between": "BETWEEN",
        "contains": "LIKE",
        "in": "IN",
    }

    # 타입별 SQL CAST 타입
    TYPE_CAST_MAP: dict[MDItemType, str] = {
        MDItemType.NUMBER: "REAL",
        MDItemType.STRING: "TEXT",
        MDItemType.DATE: "TEXT",
        MDItemType.BOOLEAN: "INTEGER",
        MDItemType.ARRAY: "TEXT",
    }

    def __init__(self, registry: dict[str, PropertyKeyMapping] | None = None):
        """
        Args:
            registry: PropertyKey 레지스트리 (기본: PROPERTY_KEY_REGISTRY)
        """
        self.registry = registry or PROPERTY_KEY_REGISTRY

    def build_clause(
        self, property_key: str, operator: str, value: Any
    ) -> tuple[str, list[Any]]:
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

        if mapping.db_field:
            return self._build_db_clause(mapping, operator, value)
        else:
            return self._build_json_clause(mapping, operator, value)

    def _build_db_clause(
        self, mapping: PropertyKeyMapping, operator: str, value: Any
    ) -> tuple[str, list[Any]]:
        """DB 컬럼 조건 생성"""
        field = mapping.db_field
        return self._build_operator_clause(field, operator, value)

    def _build_json_clause(
        self, mapping: PropertyKeyMapping, operator: str, value: Any
    ) -> tuple[str, list[Any]]:
        """JSON 필드 조건 생성"""
        cast_type = self.TYPE_CAST_MAP.get(mapping.value_type, "TEXT")
        field = f"CAST(json_extract(original_metadata, '{mapping.json_path}') AS {cast_type})"
        return self._build_operator_clause(field, operator, value)

    def _build_operator_clause(
        self, field: str, operator: str, value: Any
    ) -> tuple[str, list[Any]]:
        """연산자별 SQL 절 생성"""
        if operator == "between":
            if not isinstance(value, (list, tuple)) or len(value) != 2:
                raise ConditionBuilderError(
                    f"'between' operator requires [min, max] array, got: {value}"
                )
            return f"{field} BETWEEN ? AND ?", list(value)

        elif operator == "contains":
            return f"{field} LIKE ?", [f"%{value}%"]

        elif operator == "in":
            if not isinstance(value, (list, tuple)):
                raise ConditionBuilderError(
                    f"'in' operator requires array value, got: {type(value).__name__}"
                )
            placeholders = ", ".join(["?"] * len(value))
            return f"{field} IN ({placeholders})", list(value)

        else:
            sql_op = self.OPERATOR_MAP.get(operator, "=")
            return f"{field} {sql_op} ?", [value]

    def build_where(
        self, conditions: list[dict[str, Any]]
    ) -> tuple[str, list[Any]]:
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
