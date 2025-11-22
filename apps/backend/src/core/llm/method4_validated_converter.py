"""방식 4: LLM + Validation (LLM SQL 생성 → Python 검증/수정)

LLM이 SQL을 생성하고,
Python이 검증 및 자동 수정을 수행합니다.
"""

from typing import Any

from core.llm.llm_provider import LLMProvider
from core.llm.query_validator import QueryValidator
from core.metadata.mditem_registry import get_indexed_attributes, get_json_attributes


class ValidatedQueryConverter:
    """방식 4: LLM + Python 검증"""

    def __init__(self, llm_provider: LLMProvider):
        self.client = llm_provider
        self.validator = QueryValidator()
        self.system_prompt = self._build_system_prompt()

    def _clean_sql(self, sql: str) -> str:
        """SQL 출력 정리 (markdown, instruction 텍스트 제거)"""
        import re

        # Markdown 코드 블록 제거
        sql = re.sub(r'```sql\s*', '', sql)
        sql = re.sub(r'```\s*', '', sql)

        # instruction 텍스트 제거
        sql = re.sub(r'^(검증된 SQL|입력 SQL|출력|SQL):\s*', '', sql, flags=re.MULTILINE)

        # 한글 설명 제거 (예: "이 조건은...")
        lines = sql.split('\n')
        clean_lines = []
        for line in lines:
            line = line.strip()
            # SQL 키워드나 컬럼명으로 시작하는 줄만 유지
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

        return clean_lines[0] if clean_lines else sql.split('\n')[0].strip()

    def _build_system_prompt(self) -> str:
        """LLM 프롬프트 (SQL 생성) - 전체 레지스트리 포함"""
        indexed = get_indexed_attributes()
        json_attrs = get_json_attributes()

        # DB 필드 목록
        db_fields = []
        for key, attr in indexed.items():
            if attr.db_field:
                aliases = ", ".join(attr.search_aliases[:2])
                db_fields.append(
                    f"- {attr.db_field} ({attr.type.value}): {attr.description} ({aliases})"
                )

        # JSON 필드 목록
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
                f"  사용: CAST(json_extract(original_metadata, '$.{key}') AS {cast_type})"
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
3. 3개 초과 시: "ERROR: 조건 초과"

SQL 생성 규칙:
- DB 컬럼: 직접 사용 (예: size > 10485760)
- JSON 필드: json_extract + CAST
- 문자열: 작은따옴표
- 확장자: 점(.) 없이
- 날짜: date('now', '-7 days')

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
출력: CAST(json_extract(original_metadata, '$.kMDItemMusicalGenre') AS TEXT) = 'Classical'

입력: "10분 이상 비디오"
출력: CAST(json_extract(original_metadata, '$.kMDItemDurationSeconds') AS INTEGER) >= 600 AND extension IN ('mp4', 'mov', 'avi')

참고:
- 오타나 실수가 있어도 괜찮습니다
- Python이 자동으로 수정합니다
- 최선을 다해 SQL을 생성하세요"""

    async def convert(self, query: str) -> str | None:
        """자연어 → SQL (검증 포함)"""
        try:
            # 1단계: LLM으로 SQL 생성
            response = await self.client.generate(
                prompt=f"입력: {query}\n출력:", system=self.system_prompt
            )

            sql = response.strip()

            if sql.startswith("ERROR:"):
                print(f"[방식 4] {sql}")
                return None

            if not sql:
                return None

            # 2단계: Python으로 검증 및 수정
            try:
                validated_sql, corrections = self.validator.validate_and_fix(sql)

                if corrections:
                    print(f"[방식 4] 자동 수정: {corrections}")

                return validated_sql

            except ValueError as e:
                # 조건 초과 등의 에러
                print(f"[방식 4] 검증 실패: {e}")
                return None

        except Exception as e:
            print(f"[방식 4] 변환 실패: {e}")
            return None

    async def convert_with_metadata(self, query: str) -> dict[str, Any]:
        """변환 + 메타데이터 (수정 사항 포함)"""
        corrections = []

        try:
            # LLM 생성
            response = await self.client.generate(
                prompt=f"입력: {query}\n출력:", system=self.system_prompt
            )

            # SQL 정리 (markdown, instruction 텍스트 제거)
            sql = self._clean_sql(response)

            if sql.startswith("ERROR:") or not sql:
                return {
                    "method": "validated",
                    "description": "LLM SQL 생성 → Python 검증/수정",
                    "query": query,
                    "sql": None,
                    "success": False,
                    "steps": ["1. LLM이 SQL 생성 (실패)"],
                    "registry_coverage": "40개 전체 속성 (DB 10개 + JSON 30개)",
                }

            # 검증 및 수정
            validated_sql, corrections = self.validator.validate_and_fix(sql)

            return {
                "method": "validated",
                "description": "LLM SQL 생성 → Python 검증/수정",
                "query": query,
                "sql": validated_sql,
                "success": True,
                "original_sql": sql if corrections else None,
                "corrections": corrections if corrections else None,
                "steps": [
                    "1. LLM이 SQL 생성",
                    "2. Python이 검증 및 자동 수정",
                ],
                "registry_coverage": "40개 전체 속성 (DB 10개 + JSON 30개)",
            }

        except ValueError as e:
            return {
                "method": "validated",
                "description": "LLM SQL 생성 → Python 검증/수정",
                "query": query,
                "sql": None,
                "success": False,
                "error": str(e),
                "steps": ["1. LLM이 SQL 생성", "2. Python 검증 실패"],
                "registry_coverage": "40개 전체 속성 (DB 10개 + JSON 30개)",
            }
        except Exception as e:
            return {
                "method": "validated",
                "description": "LLM SQL 생성 → Python 검증/수정",
                "query": query,
                "sql": None,
                "success": False,
                "error": str(e),
                "steps": [],
                "registry_coverage": "40개 전체 속성 (DB 10개 + JSON 30개)",
            }
