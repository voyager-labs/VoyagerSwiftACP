"""SQL 후처리 유틸리티

LLM이 생성한 SQL을 자동으로 수정하여 성공률을 향상시킵니다.
프롬프트는 수정하지 않고, Python 코드로만 패턴을 수정합니다.
"""

import re


class SQLPostProcessor:
    """LLM 출력 SQL 자동 수정"""

    def __init__(self):
        # 패턴 1: 존재하지 않는 컬럼명 매핑
        # LLM이 환각으로 만들어낸 컬럼 → 실제 존재하는 컬럼
        self.column_fixes = {
            # 다운로드 날짜 관련 (가장 흔한 실수)
            "kMDItemDownloadedDate": "added_date",
            "kMDItemDateDownloaded": "added_date",
            "download_date": "added_date",
            "downloaded_date": "added_date",
        }

    def process(self, sql: str) -> tuple[str, list[str]]:
        """SQL 자동 수정 및 수정 내역 반환

        Args:
            sql: LLM이 생성한 원본 SQL

        Returns:
            (수정된 SQL, 수정 내역 리스트)
        """
        if not sql:
            return sql, []

        corrections = []

        # 패턴 1: 존재하지 않는 컬럼 수정
        sql, col_fixes = self._fix_column_names(sql)
        corrections.extend(col_fixes)

        # 패턴 2: date() 함수 쿼팅 제거
        sql, date_fixes = self._fix_date_quoting(sql)
        corrections.extend(date_fixes)

        # 패턴 3: Markdown 코드 블록 제거
        if "```" in sql:
            sql = re.sub(r"```sql\s*", "", sql)
            sql = re.sub(r"```\s*", "", sql)
            corrections.append("Markdown 제거")

        # 패턴 4: 설명 텍스트 제거 (첫 줄만 사용)
        lines = sql.split("\n")
        if len(lines) > 1:
            sql = lines[0].strip()
            corrections.append("설명 제거")

        # 패턴 5: 불필요한 공백 정리
        sql = " ".join(sql.split())

        return sql, corrections

    def _fix_column_names(self, sql: str) -> tuple[str, list[str]]:
        """존재하지 않는 컬럼명을 올바른 컬럼명으로 교체

        예시:
            kMDItemDownloadedDate → added_date
        """
        fixes = []

        for wrong_col, correct_col in self.column_fixes.items():
            if wrong_col in sql:
                sql = sql.replace(wrong_col, correct_col)
                fixes.append(f"컬럼 수정: {wrong_col} → {correct_col}")

        return sql, fixes

    def _fix_date_quoting(self, sql: str) -> tuple[str, list[str]]:
        """date() 함수의 잘못된 쿼팅 제거

        잘못된 예시: 'date('now', '-7 days')'
        올바른 예시: date('now', '-7 days')
        """
        # date() 함수가 따옴표로 감싸져 있는 경우
        pattern = r"'(date\([^)]+\))'"
        matches = re.findall(pattern, sql)

        if matches:
            sql = re.sub(pattern, r"\1", sql)
            return sql, [f"date() 쿼팅 제거: {len(matches)}건"]

        return sql, []

    def add_column_fix(self, wrong_col: str, correct_col: str):
        """새로운 컬럼 매핑 추가

        실패 케이스를 분석해서 동적으로 매핑을 추가할 수 있습니다.

        Args:
            wrong_col: LLM이 사용한 잘못된 컬럼명
            correct_col: 실제로 사용해야 하는 올바른 컬럼명
        """
        self.column_fixes[wrong_col] = correct_col
        print(f"[매핑 추가] {wrong_col} → {correct_col}")
