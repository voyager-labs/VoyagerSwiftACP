"""방식 5: Self-Correction LLM (LLM 자기 검증/수정)

1단계 LLM: SQL 생성
2단계 LLM: 자기 검증 및 수정
"""

from typing import Any

from core.llm.llm_provider import LLMProvider
from core.metadata.mditem_registry import get_indexed_attributes, get_json_attributes


class SelfCorrectionQueryConverter:
    """방식 5: LLM 자기 검증"""

    def __init__(self, llm_provider: LLMProvider):
        self.client = llm_provider
        self.generation_prompt = self._build_generation_prompt()
        self.correction_prompt_template = self._build_correction_prompt_template()

    def _build_generation_prompt(self) -> str:
        """1단계: SQL 생성 프롬프트 - 전체 레지스트리 포함"""
        indexed = get_indexed_attributes()
        json_attrs = get_json_attributes()

        # DB 필드
        db_fields = []
        for key, attr in indexed.items():
            if attr.db_field:
                aliases = ", ".join(attr.search_aliases[:2])
                db_fields.append(
                    f"- {attr.db_field} ({attr.type.value}): {attr.description} ({aliases})"
                )

        # JSON 필드
        json_fields = []
        for key, attr in json_attrs.items():
            aliases = ", ".join(attr.search_aliases[:2])

            if attr.type.value == "number":
                cast_type = "INTEGER"
            elif attr.type.value == "string":
                cast_type = "TEXT"
            elif attr.type.value == "boolean":
                cast_type = "INTEGER"
            else:
                cast_type = "TEXT"

            json_fields.append(
                f"- {key} ({attr.type.value}): {attr.description} ({aliases})\n"
                f"  CAST(json_extract(original_metadata, '$.{key}') AS {cast_type})"
            )

        return f"""당신은 SQL 생성 전문가입니다.
자연어를 SQL WHERE절로 변환하세요.

사용 가능한 필드 (총 40개):

DB 컬럼 (10개):
{chr(10).join(db_fields)}

JSON 필드 (30개):
{chr(10).join(json_fields)}

규칙:
1. WHERE 없이 조건만
2. 조건 최대 3개
3. 문자열은 작은따옴표
4. 확장자는 점(.) 없이
5. 날짜: date('now', '-7 days')

크기 변환:
- 1 MB = 1048576
- 10 MB = 10485760
- 1 GB = 1073741824

예시:

입력: "10MB 이상 PDF"
출력: size > 10485760 AND extension = 'pdf'

입력: "최근 7일 1080p 영상"
출력: modification_date > date('now', '-7 days') AND CAST(json_extract(original_metadata, '$.kMDItemPixelHeight') AS INTEGER) >= 1080 AND extension IN ('mp4', 'mov')

입력: "클래식 음악"
출력: CAST(json_extract(original_metadata, '$.kMDItemMusicalGenre') AS TEXT) = 'Classical'"""

    def _build_correction_prompt_template(self) -> str:
        """2단계: 자기 검증 프롬프트 템플릿 - 전체 레지스트리 포함"""
        indexed = get_indexed_attributes()
        json_attrs = get_json_attributes()

        # 모든 DB 필드 목록
        all_db_fields = [attr.db_field for attr in indexed.values() if attr.db_field]

        # 모든 JSON 필드 목록
        all_json_fields = list(json_attrs.keys())

        return f"""당신은 SQL 검증 및 수정 전문가입니다.
다음 SQL을 검증하고 문제가 있으면 수정하세요.

허용된 DB 필드 (10개):
{', '.join(all_db_fields)}

허용된 JSON 필드 (30개):
{', '.join(all_json_fields)}

원본 자연어 쿼리: {{original_query}}
생성된 SQL: {{generated_sql}}

검증 체크리스트:
1. 필드명이 허용 목록에 있는가?
2. 조건이 3개 이하인가?
3. 문자열 값에 작은따옴표가 있는가?
4. 확장자에 점(.)이 없는가?
5. JSON 필드에 CAST가 있는가?
6. SQL 문법이 올바른가?

CAST 타입:
- 숫자 필드: INTEGER
- 문자열 필드: TEXT
- Boolean 필드: INTEGER

문제 발견 시: 수정된 SQL만 출력
문제 없으면: 원본 SQL 그대로 출력
설명 금지, SQL만 출력!

예시:

입력 SQL: szie > 10485760 AND extension = 'pdf'
문제: szie → size (오타)
출력: size > 10485760 AND extension = 'pdf'

입력 SQL: size > 10485760 AND extension = '.pdf'
문제: extension에 점(.)
출력: size > 10485760 AND extension = 'pdf'

입력 SQL: json_extract(original_metadata, '$.kMDItemPixelHeight') >= 1080
문제: CAST 누락
출력: CAST(json_extract(original_metadata, '$.kMDItemPixelHeight') AS INTEGER) >= 1080

입력 SQL: size > 10485760 AND extension = 'pdf'
문제: 없음
출력: size > 10485760 AND extension = 'pdf'"""

    def _clean_sql(self, sql: str) -> str:
        """SQL 출력 정리 (markdown, instruction 텍스트 제거)"""
        import re

        # Markdown 코드 블록 제거
        sql = re.sub(r'```sql\s*', '', sql)
        sql = re.sub(r'```\s*', '', sql)

        # instruction 텍스트 제거
        sql = re.sub(r'^(검증된 SQL|검증 및 수정 결과|입력 SQL|출력|문제):\s*', '', sql, flags=re.MULTILINE)

        # 한글 설명 제거
        lines = sql.split('\n')
        clean_lines = []
        for line in lines:
            line = line.strip()
            # SQL 키워드나 조건으로 시작하는 줄만 유지
            if line and (
                any(line.upper().startswith(kw) for kw in ['SELECT', 'WHERE', 'AND', 'OR', 'CAST', 'SIZE', 'EXTENSION', 'MODIFICATION_DATE', 'PARENT_DIR_NAME', 'UNIFORM_TYPE_IDENTIFIER', 'FILE_KIND', 'IS_INVISIBLE', 'ADDED_DATE'])
                or '=' in line
                or '>' in line
                or '<' in line
                or 'IN' in line
                or 'LIKE' in line
                or 'json_extract' in line.lower()
            ):
                clean_lines.append(line)
                break  # 첫 번째 유효한 SQL 줄만 사용

        return clean_lines[0] if clean_lines else sql.split('\n')[0].strip()

    async def convert(self, query: str) -> str | None:
        """자연어 → SQL (자기 검증 포함)"""
        try:
            # 1단계: SQL 생성
            sql_v1_raw = await self.client.generate(
                prompt=f"입력: {query}\n출력:", system=self.generation_prompt
            )

            # SQL 정리
            sql_v1 = self._clean_sql(sql_v1_raw)

            if not sql_v1 or sql_v1.startswith("ERROR:"):
                print(f"[방식 5] 1단계 실패: {sql_v1}")
                return None

            # 2단계: 자기 검증 및 수정
            correction_prompt = self.correction_prompt_template.format(
                original_query=query, generated_sql=sql_v1
            )

            sql_v2_raw = await self.client.generate(
                prompt="검증 및 수정을 시작하세요.\n출력:", system=correction_prompt
            )

            # SQL 정리
            sql_v2 = self._clean_sql(sql_v2_raw)

            if not sql_v2:
                # 2단계 실패 시 1단계 결과 반환
                print("[방식 5] 2단계 실패, 1단계 결과 사용")
                return sql_v1

            # 수정 여부 확인
            if sql_v2 != sql_v1:
                print(f"[방식 5] 자기 수정됨:\n  원본: {sql_v1}\n  수정: {sql_v2}")

            return sql_v2

        except Exception as e:
            print(f"[방식 5] 변환 실패: {e}")
            return None

    async def convert_with_metadata(self, query: str) -> dict[str, Any]:
        """변환 + 메타데이터 (수정 사항 포함)"""
        try:
            # 1단계: SQL 생성
            sql_v1_raw = await self.client.generate(
                prompt=f"입력: {query}\n출력:", system=self.generation_prompt
            )

            # SQL 정리
            sql_v1 = self._clean_sql(sql_v1_raw)

            if not sql_v1 or sql_v1.startswith("ERROR:"):
                return {
                    "method": "self_correction",
                    "description": "LLM SQL 생성 → LLM 자기 검증/수정",
                    "query": query,
                    "sql": None,
                    "success": False,
                    "steps": ["1. LLM이 SQL 생성 (실패)"],
                    "registry_coverage": "40개 전체 속성 (DB 10개 + JSON 30개)",
                }

            # 2단계: 자기 검증
            correction_prompt = self.correction_prompt_template.format(
                original_query=query, generated_sql=sql_v1
            )

            sql_v2_raw = await self.client.generate(
                prompt="검증 및 수정을 시작하세요.\n출력:", system=correction_prompt
            )

            # SQL 정리
            sql_v2 = self._clean_sql(sql_v2_raw)

            if not sql_v2:
                sql_v2 = sql_v1

            # 수정 여부
            was_corrected = sql_v2 != sql_v1

            return {
                "method": "self_correction",
                "description": "LLM SQL 생성 → LLM 자기 검증/수정",
                "query": query,
                "sql": sql_v2,
                "success": True,
                "original_sql": sql_v1 if was_corrected else None,
                "self_corrected": was_corrected,
                "steps": [
                    "1. LLM이 SQL 생성",
                    "2. LLM이 자기 검증 및 수정",
                ],
                "note": "LLM 2번 호출 (비용 2배)",
                "registry_coverage": "40개 전체 속성 (DB 10개 + JSON 30개)",
            }

        except Exception as e:
            return {
                "method": "self_correction",
                "description": "LLM SQL 생성 → LLM 자기 검증/수정",
                "query": query,
                "sql": None,
                "success": False,
                "error": str(e),
                "steps": [],
                "registry_coverage": "40개 전체 속성 (DB 10개 + JSON 30개)",
            }
