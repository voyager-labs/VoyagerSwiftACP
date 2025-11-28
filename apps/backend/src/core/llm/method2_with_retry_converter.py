"""방식 2 + 재시도 (LLM 전담 + 실행 후 에러 시 재시도)

LLM이 SQL 생성 → DB 실행 테스트 → 에러 발생 시 재시도
"""

from typing import Any

from core.llm.llm_provider import LLMProvider
from core.llm.method2_llm_only_converter import LLMOnlyQueryConverter
from core.llm.sql_postprocessor import SQLPostProcessor


class Method2WithRetryConverter:
    """방식 2 + 실행 후 재시도"""

    def __init__(self, llm_provider: LLMProvider, db_connection=None):
        self.base_converter = LLMOnlyQueryConverter(llm_provider)
        self.llm = llm_provider
        self.db = db_connection
        self.postprocessor = SQLPostProcessor()
        self.fix_prompt = self._build_fix_prompt()

    def _build_fix_prompt(self) -> str:
        """에러 수정용 프롬프트"""
        return """당신은 SQL 디버거입니다.
실패한 SQL과 에러 메시지를 보고 수정된 SQL을 생성하세요.

흔한 에러 패턴:
1. "no such column: kMDItemDownloadedDate"
   → added_date로 변경

2. "no such column: X"
   → 레지스트리에 있는 올바른 컬럼 찾기

3. "near 'date': syntax error"
   → date() 함수 쿼팅 제거

4. "syntax error"
   → SQL 문법 확인

중요:
- 수정된 SQL 조건만 출력하세요
- WHERE 키워드 없이 조건만
- 설명이나 주석 없이!

출력 형식: SQL 조건만!"""

    async def convert(self, query: str) -> str | None:
        """자연어 → SQL (재시도 포함)"""
        # 1차 시도
        sql = await self.base_converter.convert(query)

        if not sql:
            return None

        # 후처리 적용
        sql, corrections = self.postprocessor.process(sql)

        if corrections:
            print(f"[방식 2+재시도] 후처리: {', '.join(corrections)}")

        # DB 실행 테스트 (DB 연결이 있을 때만)
        if self.db:
            is_valid, error = self._test_sql(sql)

            if is_valid:
                print(f"[방식 2+재시도] 1차 성공")
                return sql

            # 실패 - 재시도
            print(f"[방식 2+재시도] 1차 실패: {error}")
            print(f"[방식 2+재시도] 2차 시도 중...")

            fixed_sql = await self._try_fix(query, sql, error)

            if not fixed_sql:
                print(f"[방식 2+재시도] 2차 시도 실패: SQL 생성 불가")
                return None

            # 후처리 재적용
            fixed_sql, corrections2 = self.postprocessor.process(fixed_sql)

            if corrections2:
                print(f"[방식 2+재시도] 2차 후처리: {', '.join(corrections2)}")

            # 재검증
            is_valid2, error2 = self._test_sql(fixed_sql)

            if is_valid2:
                print(f"[방식 2+재시도] 2차 성공")
                return fixed_sql

            print(f"[방식 2+재시도] 2차 실패: {error2}")
            return None

        # DB 연결 없으면 그냥 반환
        return sql

    async def convert_with_metadata(self, query: str) -> dict[str, Any]:
        """변환 + 메타데이터 (재시도 정보 포함)"""
        metadata = {
            "method": "llm_only_with_retry",
            "description": "LLM 전담 + 후처리 + 실행 후 재시도",
            "query": query,
            "attempts": [],
            "final_success": False,
        }

        # 1차 시도
        sql = await self.base_converter.convert(query)
        metadata["attempts"].append(
            {"attempt": 1, "original_sql": sql, "postprocessed_sql": None, "success": None, "error": None}
        )

        if not sql:
            metadata["sql"] = None
            metadata["success"] = False
            metadata["attempts"][0]["success"] = False
            return metadata

        # 후처리
        sql, corrections = self.postprocessor.process(sql)
        metadata["attempts"][0]["postprocessed_sql"] = sql
        metadata["attempts"][0]["corrections"] = corrections

        # DB 테스트
        if self.db:
            is_valid, error = self._test_sql(sql)
            metadata["attempts"][0]["success"] = is_valid
            metadata["attempts"][0]["error"] = error

            if is_valid:
                metadata["sql"] = sql
                metadata["success"] = True
                metadata["final_success"] = True
                metadata["total_attempts"] = 1
                return metadata

            # 2차 시도
            fixed_sql = await self._try_fix(query, sql, error)
            metadata["attempts"].append(
                {
                    "attempt": 2,
                    "original_sql": fixed_sql,
                    "postprocessed_sql": None,
                    "success": None,
                    "error": None,
                }
            )

            if not fixed_sql:
                metadata["sql"] = None
                metadata["success"] = False
                metadata["total_attempts"] = 2
                return metadata

            # 후처리 재적용
            fixed_sql, corrections2 = self.postprocessor.process(fixed_sql)
            metadata["attempts"][1]["postprocessed_sql"] = fixed_sql
            metadata["attempts"][1]["corrections"] = corrections2

            # 재검증
            is_valid2, error2 = self._test_sql(fixed_sql)
            metadata["attempts"][1]["success"] = is_valid2
            metadata["attempts"][1]["error"] = error2

            if is_valid2:
                metadata["sql"] = fixed_sql
                metadata["success"] = True
                metadata["final_success"] = True
                metadata["total_attempts"] = 2
                return metadata

            # 2차도 실패
            metadata["sql"] = None
            metadata["success"] = False
            metadata["total_attempts"] = 2
            return metadata

        # DB 연결 없음
        metadata["sql"] = sql
        metadata["success"] = True
        metadata["total_attempts"] = 1
        metadata["db_test_skipped"] = True
        return metadata

    def _test_sql(self, sql: str) -> tuple[bool, str | None]:
        """SQL을 실제로 실행해서 에러 확인

        LIMIT 0으로 실행하여 문법만 검증하고 데이터는 가져오지 않음
        """
        if not self.db:
            return True, None

        try:
            # EXPLAIN QUERY PLAN으로 문법만 검증 (더 빠름)
            test_query = f"EXPLAIN QUERY PLAN SELECT * FROM file_entries WHERE {sql}"
            cursor = self.db.execute(test_query)
            cursor.fetchall()  # 결과를 읽어야 에러가 발생함
            return True, None
        except Exception as e:
            error_msg = str(e)
            # 에러 메시지 정리
            if "no such column" in error_msg.lower():
                return False, error_msg
            if "syntax error" in error_msg.lower():
                return False, error_msg
            return False, error_msg

    async def _try_fix(self, query: str, failed_sql: str, error: str) -> str | None:
        """에러 정보를 포함해서 수정 요청"""
        fix_request = f"""
원래 쿼리: {query}

생성한 SQL: {failed_sql}

에러 메시지: {error}

위 에러를 수정한 SQL을 생성하세요.
출력:"""

        try:
            response = await self.llm.generate(prompt=fix_request, system=self.fix_prompt)
            return response.strip()
        except Exception as e:
            print(f"[방식 2+재시도] 수정 요청 실패: {e}")
            return None
