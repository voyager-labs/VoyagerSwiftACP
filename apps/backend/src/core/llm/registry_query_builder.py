"""레지스트리 기반 SQL 쿼리 빌더 (방식 1용)

구조화된 JSON intent를 SQL WHERE절로 변환합니다.
레지스트리를 참조하여 타입 안전성을 보장합니다.
"""

from typing import Any

from core.metadata.mditem_registry import (
    MDITEM_REGISTRY,
    MDItemType,
    get_indexed_attributes,
)


class RegistryQueryBuilder:
    """레지스트리 기반 SQL 쿼리 빌더"""

    def __init__(self):
        self.registry = MDITEM_REGISTRY
        self.indexed = get_indexed_attributes()

    def build_query(self, intent: dict[str, Any]) -> str:
        """구조화 JSON → SQL WHERE절

        Args:
            intent: {
                "conditions": [
                    {"field": "size", "operator": ">", "value": 10485760},
                    {"field": "extension", "operator": "=", "value": "pdf"}
                ],
                "logic": "AND"
            }

        Returns:
            SQL WHERE절 (예: "size > 10485760 AND extension = 'pdf'")
        """
        conditions = intent.get("conditions", [])
        logic = intent.get("logic", "AND").upper()

        if not conditions:
            return "1=1"  # 조건 없음

        sql_parts = []
        for condition in conditions:
            sql_part = self._build_condition(condition)
            if sql_part:
                sql_parts.append(sql_part)

        if not sql_parts:
            return "1=1"

        return f" {logic} ".join(sql_parts)

    def _build_condition(self, condition: dict[str, Any]) -> str:
        """단일 조건 → SQL

        Args:
            condition: {"field": "size", "operator": ">", "value": 10485760}

        Returns:
            SQL 조건 (예: "size > 10485760")
        """
        field = condition.get("field")
        operator = condition.get("operator", "=")
        value = condition.get("value")

        if not field or value is None:
            return ""

        # DB 컬럼 vs JSON 필드 판별
        if self._is_db_column(field):
            return self._build_db_column_condition(field, operator, value)
        else:
            return self._build_json_condition(field, operator, value)

    def _is_db_column(self, field: str) -> bool:
        """DB 컬럼인지 확인"""
        # db_field가 있으면 DB 컬럼
        for attr in self.indexed.values():
            if attr.db_field == field:
                return True
        return False

    def _build_db_column_condition(
        self, field: str, operator: str, value: Any
    ) -> str:
        """DB 컬럼 조건 생성"""
        # 값 타입에 따라 포맷팅
        if isinstance(value, str):
            # 문자열은 작은따옴표
            if operator.upper() == "IN":
                # IN 연산자는 리스트
                values = value if isinstance(value, list) else [value]
                formatted_values = ", ".join(f"'{v}'" for v in values)
                return f"{field} IN ({formatted_values})"
            elif operator.upper() == "LIKE":
                return f"{field} LIKE '{value}'"
            else:
                return f"{field} {operator} '{value}'"
        elif isinstance(value, bool):
            # 불린은 0/1
            bool_val = 1 if value else 0
            return f"{field} {operator} {bool_val}"
        else:
            # 숫자는 그대로
            return f"{field} {operator} {value}"

    def _build_json_condition(self, mditem_key: str, operator: str, value: Any) -> str:
        """JSON 필드 조건 생성

        Args:
            mditem_key: kMDItemPixelHeight 같은 MDItem 키
        """
        if mditem_key not in self.registry:
            # 레지스트리에 없는 속성
            return ""

        attr = self.registry[mditem_key]
        json_path = f"$.{mditem_key}"

        # 타입에 따라 CAST 결정
        if attr.type == MDItemType.NUMBER:
            # NUMBER는 INTEGER 또는 REAL
            if isinstance(value, int):
                cast_type = "INTEGER"
            else:
                cast_type = "REAL"
            return f"CAST(json_extract(original_metadata, '{json_path}') AS {cast_type}) {operator} {value}"

        elif attr.type == MDItemType.STRING:
            # STRING은 CAST 불필요
            if operator.upper() == "LIKE":
                return f"json_extract(original_metadata, '{json_path}') LIKE '{value}'"
            else:
                return f"json_extract(original_metadata, '{json_path}') {operator} '{value}'"

        elif attr.type == MDItemType.BOOLEAN:
            # BOOLEAN은 INTEGER로 CAST
            bool_val = 1 if value else 0
            return f"CAST(json_extract(original_metadata, '{json_path}') AS INTEGER) {operator} {bool_val}"

        elif attr.type == MDItemType.DATE:
            # DATE는 문자열 비교
            return f"json_extract(original_metadata, '{json_path}') {operator} '{value}'"

        elif attr.type == MDItemType.ARRAY:
            # ARRAY는 JSON 함수 사용
            if operator.upper() == "IN":
                # ARRAY 내 값 검색은 복잡하므로 간단히 처리
                return f"json_extract(original_metadata, '{json_path}') LIKE '%{value}%'"
            else:
                return f"json_extract(original_metadata, '{json_path}') {operator} '{value}'"

        return ""

    def get_available_fields(self) -> dict[str, str]:
        """사용 가능한 필드 목록 반환

        Returns:
            {
                "size": "DB 컬럼 (NUMBER)",
                "kMDItemPixelHeight": "JSON 필드 (NUMBER)"
            }
        """
        fields = {}

        # DB 컬럼
        for key, attr in self.indexed.items():
            if attr.db_field:
                fields[attr.db_field] = f"DB 컬럼 ({attr.type.value})"

        # JSON 필드
        for key, attr in self.registry.items():
            if key not in self.indexed or not self.indexed[key].db_field:
                fields[key] = f"JSON 필드 ({attr.type.value})"

        return fields
