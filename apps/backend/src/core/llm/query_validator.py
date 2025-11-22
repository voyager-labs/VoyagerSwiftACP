"""SQL 쿼리 검증 및 자동 수정 (방식 4용)

LLM이 생성한 SQL을 검증하고 오류를 자동으로 수정합니다.
"""

import re
from difflib import get_close_matches
from typing import Any

from core.metadata.mditem_registry import MDITEM_REGISTRY, get_indexed_attributes


class QueryValidator:
    """SQL 쿼리 검증 및 자동 수정"""

    def __init__(self):
        self.registry = MDITEM_REGISTRY
        self.indexed = get_indexed_attributes()

        # 허용된 DB 컬럼 필드명
        self.allowed_db_fields = {
            "size",
            "extension",
            "modification_date",
            "added_date",
            "last_used_date",
            "creation_date",
            "file_kind",
            "is_invisible",
            "uniform_type_identifier",
            "content_creation_date",
            "content_modification_date",
            "parent_dir_name",
            "name_full",
            "name_stem",
            "path",
            "dir_path",
        }

        # 허용된 MDItem 키
        self.allowed_mditem_keys = set(self.registry.keys())

    def validate_and_fix(self, sql: str) -> tuple[str, list[str]]:
        """SQL 검증 및 자동 수정

        Args:
            sql: LLM이 생성한 SQL WHERE절

        Returns:
            (수정된 SQL, 수정 사항 리스트)
        """
        corrections = []

        # 1. 조건 개수 체크
        condition_count = self._count_conditions(sql)
        if condition_count > 3:
            raise ValueError(f"조건이 3개를 초과합니다 ({condition_count}개)")

        # 2. DB 필드명 오타 수정
        sql, field_corrections = self._fix_db_field_typos(sql)
        corrections.extend(field_corrections)

        # 3. MDItem 키 오타 수정
        sql, mditem_corrections = self._fix_mditem_typos(sql)
        corrections.extend(mditem_corrections)

        # 4. CAST 누락 자동 추가
        sql, cast_corrections = self._add_missing_casts(sql)
        corrections.extend(cast_corrections)

        # 5. 확장자 점(.) 제거
        sql, ext_corrections = self._fix_extension_dots(sql)
        corrections.extend(ext_corrections)

        return sql, corrections

    def _count_conditions(self, sql: str) -> int:
        """조건 개수 카운트"""
        # AND와 OR의 개수 세기
        and_count = len(re.findall(r'\bAND\b', sql, re.IGNORECASE))
        or_count = len(re.findall(r'\bOR\b', sql, re.IGNORECASE))

        # 조건 개수 = AND + OR + 1
        return and_count + or_count + 1

    def _fix_db_field_typos(self, sql: str) -> tuple[str, list[str]]:
        """DB 필드명 오타 수정"""
        corrections = []

        # 필드명 패턴: 단어 뒤에 =, <, >, LIKE 등이 오는 경우
        pattern = r'\b([a-z_]+)\s*(=|!=|>|<|>=|<=|LIKE|IN)\s*'
        matches = re.finditer(pattern, sql, re.IGNORECASE)

        for match in matches:
            field = match.group(1)

            # 예약어는 스킵
            if field.lower() in ['and', 'or', 'not', 'in', 'like', 'date']:
                continue

            # 허용된 필드가 아니면 유사한 필드 찾기
            if field not in self.allowed_db_fields:
                similar = get_close_matches(
                    field, self.allowed_db_fields, n=1, cutoff=0.6
                )
                if similar:
                    correct_field = similar[0]
                    sql = sql.replace(
                        f"{field} {match.group(2)}", f"{correct_field} {match.group(2)}"
                    )
                    corrections.append(f"필드명 수정: '{field}' → '{correct_field}'")

        return sql, corrections

    def _fix_mditem_typos(self, sql: str) -> tuple[str, list[str]]:
        """MDItem 키 오타 수정"""
        corrections = []

        # json_extract 패턴에서 MDItem 키 추출
        pattern = r"json_extract\(original_metadata,\s*['\"]?\$\.([a-zA-Z0-9_]+)['\"]?\)"
        matches = re.finditer(pattern, sql)

        for match in matches:
            mditem_key = match.group(1)

            # 허용된 키가 아니면 유사한 키 찾기
            if mditem_key not in self.allowed_mditem_keys:
                similar = get_close_matches(
                    mditem_key, self.allowed_mditem_keys, n=1, cutoff=0.6
                )
                if similar:
                    correct_key = similar[0]
                    sql = sql.replace(f"$.{mditem_key}", f"$.{correct_key}")
                    corrections.append(f"MDItem 키 수정: '{mditem_key}' → '{correct_key}'")

        return sql, corrections

    def _add_missing_casts(self, sql: str) -> tuple[str, list[str]]:
        """CAST 누락 자동 추가"""
        corrections = []

        # json_extract 패턴 찾기
        pattern = r"json_extract\(original_metadata,\s*['\"]?\$\.([a-zA-Z0-9_]+)['\"]?\)"
        matches = list(re.finditer(pattern, sql))

        for match in matches:
            mditem_key = match.group(1)

            # 이미 CAST가 있는지 확인
            # match.start() 이전 50자 확인
            before_text = sql[max(0, match.start() - 50) : match.start()]
            if "CAST" in before_text.upper():
                continue  # 이미 CAST 있음

            # 레지스트리에서 타입 확인
            if mditem_key not in self.registry:
                continue

            attr = self.registry[mditem_key]

            # NUMBER 타입은 CAST 필요
            if attr.type.value == "number":
                # 값을 보고 INTEGER vs REAL 결정
                # 간단히 INTEGER로 처리
                cast_expr = f"CAST({match.group(0)} AS INTEGER)"
                sql = sql.replace(match.group(0), cast_expr)
                corrections.append(f"CAST 추가: {mditem_key} → INTEGER")

            # BOOLEAN 타입도 CAST 필요
            elif attr.type.value == "boolean":
                cast_expr = f"CAST({match.group(0)} AS INTEGER)"
                sql = sql.replace(match.group(0), cast_expr)
                corrections.append(f"CAST 추가: {mditem_key} → INTEGER")

        return sql, corrections

    def _fix_extension_dots(self, sql: str) -> tuple[str, list[str]]:
        """확장자 값에서 점(.) 제거"""
        corrections = []

        # extension = '.pdf' 같은 패턴 찾기
        pattern = r"extension\s*(=|IN)\s*['\"]?(\.[a-z0-9]+)['\"]?"
        matches = re.finditer(pattern, sql, re.IGNORECASE)

        for match in matches:
            ext_with_dot = match.group(2)
            ext_without_dot = ext_with_dot.lstrip('.')

            sql = sql.replace(ext_with_dot, ext_without_dot)
            corrections.append(f"확장자 점 제거: '{ext_with_dot}' → '{ext_without_dot}'")

        return sql, corrections

    def validate_only(self, sql: str) -> dict[str, Any]:
        """검증만 수행 (수정 없이)

        Returns:
            {
                "valid": True/False,
                "issues": ["문제 목록"]
            }
        """
        issues = []

        # 조건 개수
        condition_count = self._count_conditions(sql)
        if condition_count > 3:
            issues.append(f"조건이 3개를 초과합니다 ({condition_count}개)")

        # DB 필드명 체크
        pattern = r'\b([a-z_]+)\s*(=|!=|>|<|>=|<=|LIKE|IN)\s*'
        matches = re.finditer(pattern, sql, re.IGNORECASE)
        for match in matches:
            field = match.group(1)
            if field.lower() not in ['and', 'or', 'not', 'in', 'like', 'date']:
                if field not in self.allowed_db_fields:
                    issues.append(f"알 수 없는 필드: '{field}'")

        # MDItem 키 체크
        pattern = r"json_extract\(original_metadata,\s*['\"]?\$\.([a-zA-Z0-9_]+)['\"]?\)"
        matches = re.finditer(pattern, sql)
        for match in matches:
            mditem_key = match.group(1)
            if mditem_key not in self.allowed_mditem_keys:
                issues.append(f"알 수 없는 MDItem 키: '{mditem_key}'")

        return {"valid": len(issues) == 0, "issues": issues}
