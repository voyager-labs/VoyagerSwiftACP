"""방식 3: Two-Stage LLM (LLM 2단계 처리)

1단계 LLM: 자연어 → 구조화 JSON
2단계 LLM: JSON → SQL (레지스트리 참조)
"""

import json
from typing import Any

from langchain_core.output_parsers import JsonOutputParser
from pydantic import BaseModel, Field

from core.llm.llm_provider import LLMProvider
from core.metadata.mditem_registry import get_indexed_attributes, get_json_attributes


class QueryIntent(BaseModel):
    """쿼리 의도 구조"""

    conditions: list[dict[str, Any]] = Field(description="검색 조건 리스트 (최대 3개)")
    logic: str = Field(description="AND 또는 OR")
    error: str | None = Field(default=None, description="에러 메시지 (조건 초과 시)")


class TwoStageQueryConverter:
    """방식 3: Two-Stage LLM"""

    def __init__(self, llm_provider: LLMProvider):
        self.client = llm_provider
        self.parser = JsonOutputParser(pydantic_object=QueryIntent)
        self.stage1_prompt = self._build_stage1_prompt()
        self.stage2_prompt = self._build_stage2_prompt()

    def _build_stage1_prompt(self) -> str:
        """1단계 프롬프트: 자연어 → JSON (전체 레지스트리)"""
        indexed = get_indexed_attributes()
        json_attrs = get_json_attributes()

        # DB 필드 목록
        db_fields = []
        for key, attr in indexed.items():
            if attr.db_field:
                aliases = ", ".join(attr.search_aliases[:2])
                db_fields.append(f"- {attr.db_field}: {attr.description} ({aliases})")

        # JSON 필드 목록
        json_fields = []
        for key, attr in json_attrs.items():
            aliases = ", ".join(attr.search_aliases[:2])
            json_fields.append(f"- {key}: {attr.description} ({aliases})")

        return f"""당신은 자연어를 구조화 JSON으로 변환하는 전문가입니다.

사용 가능한 필드 (총 40개):

DB 컬럼 (10개):
{chr(10).join(db_fields)}

JSON 필드 (30개):
{chr(10).join(json_fields)}

규칙:
1. 반드시 아래 JSON 형식으로만 출력 (설명이나 다른 텍스트 절대 금지!)
2. 조건 최대 3개
3. 3개 초과 시: {{"error": "조건 초과", "conditions": [], "logic": "AND"}}
4. field는 DB 컬럼명 또는 MDItem 키 사용

operator:
- =, !=, >, <, >=, <=, IN, LIKE

value:
- 문자열: 따옴표 없이 (예: "pdf")
- 숫자: 그대로 (예: 10485760)
- 배열: ["jpg", "png"]

크기 변환:
- 1 MB = 1048576
- 10 MB = 10485760
- 100 MB = 104857600
- 1 GB = 1073741824

=== 출력 형식 (이것만 출력!) ===
반드시 이 JSON 형식으로만 응답하세요:
{{
  "conditions": [
    {{"field": "필드명", "operator": "연산자", "value": "값"}}
  ],
  "logic": "AND 또는 OR",
  "error": null
}}

예시:

입력: "10MB 이상 PDF"
출력: {{"conditions": [{{"field": "size", "operator": ">", "value": 10485760}}, {{"field": "extension", "operator": "=", "value": "pdf"}}], "logic": "AND"}}

입력: "클래식 음악 44.1kHz"
출력: {{"conditions": [{{"field": "kMDItemMusicalGenre", "operator": "=", "value": "Classical"}}, {{"field": "kMDItemAudioSampleRate", "operator": "=", "value": 44100}}], "logic": "AND"}}

다시 한번 강조: 반드시 JSON 형식으로만 출력하세요! 설명이나 다른 텍스트를 절대 포함하지 마세요!"""

    def _build_stage2_prompt(self) -> str:
        """2단계 프롬프트: JSON → SQL (전체 레지스트리)"""
        indexed = get_indexed_attributes()
        json_attrs = get_json_attributes()

        # DB 컬럼 목록
        db_fields = []
        for key, attr in indexed.items():
            if attr.db_field:
                db_fields.append(f"- {attr.db_field} ({attr.type.value}): 직접 사용")

        # JSON 필드 목록 (CAST 포함)
        json_fields = []
        for key, attr in json_attrs.items():
            if attr.type.value == "number":
                cast_type = "INTEGER"
            elif attr.type.value == "string":
                cast_type = "TEXT"
            elif attr.type.value == "boolean":
                cast_type = "INTEGER"
            else:
                cast_type = "TEXT"

            json_fields.append(
                f"- {key} ({attr.type.value}): CAST(json_extract(original_metadata, '$.{key}') AS {cast_type})"
            )

        return f"""당신은 JSON을 SQL로 변환하는 전문가입니다.

DB 컬럼 (10개):
{chr(10).join(db_fields)}

JSON 필드 (30개):
{chr(10).join(json_fields)}

변환 규칙:
1. DB 컬럼은 직접 사용
2. JSON 필드는 json_extract + CAST
3. 문자열은 작은따옴표
4. 날짜 함수: date('now', '-7 days') 형식
5. WHERE 키워드 없이 조건만
6. 확장자는 점(.) 없이

크기 변환:
- 1 MB = 1048576
- 10 MB = 10485760
- 100 MB = 104857600
- 1 GB = 1073741824

예시:

입력: {{"conditions": [{{"field": "size", "operator": ">", "value": 10485760}}], "logic": "AND"}}
출력: size > 10485760

입력: {{"conditions": [{{"field": "kMDItemPixelHeight", "operator": ">=", "value": 1080}}], "logic": "AND"}}
출력: CAST(json_extract(original_metadata, '$.kMDItemPixelHeight') AS INTEGER) >= 1080

입력: {{"conditions": [{{"field": "modification_date", "operator": ">", "value": "date('now', '-7 days')"}}, {{"field": "extension", "operator": "=", "value": "pdf"}}], "logic": "AND"}}
출력: modification_date > date('now', '-7 days') AND extension = 'pdf'

SQL만 출력!"""

    def _clean_sql(self, sql: str) -> str:
        """SQL 출력 정리 (markdown, instruction 텍스트 제거)"""
        import re

        # Markdown 코드 블록 제거
        sql = re.sub(r'```sql\s*', '', sql)
        sql = re.sub(r'```\s*', '', sql)

        # instruction 텍스트 제거
        sql = re.sub(r'^(검증된 SQL|입력 SQL|출력|SQL):\s*', '', sql, flags=re.MULTILINE)

        # 첫 번째 유효한 줄만 사용 (설명 제거)
        lines = [line.strip() for line in sql.split('\n') if line.strip()]
        return lines[0] if lines else ''

    async def convert(self, query: str) -> str | None:
        """자연어 → SQL (2단계)"""
        try:
            # Stage 1: 자연어 → JSON (JsonOutputParser 사용)
            stage1_response = await self.client.generate(
                prompt=f"입력: {query}\n출력:", system=self.stage1_prompt
            )

            # JsonOutputParser로 파싱
            try:
                intent = self.parser.parse(stage1_response)
            except Exception as parse_error:
                print(f"[방식 3] JsonOutputParser 파싱 실패: {parse_error}")
                # Fallback: 수동 JSON 추출 시도
                import re

                json_pattern = r'\{[^{}]*(?:\{[^{}]*\}[^{}]*)*\}'
                matches = re.findall(json_pattern, stage1_response, re.DOTALL)

                intent = None
                for match in matches:
                    try:
                        intent = json.loads(match)
                        break
                    except json.JSONDecodeError:
                        continue

                if intent is None:
                    print(f"[방식 3] Fallback JSON 추출 실패: {stage1_response[:200]}")
                    return None

            # 에러 체크
            if isinstance(intent, dict) and intent.get("error"):
                print(f"[방식 3] Stage 1 에러: {intent['error']}")
                return None

            # 조건 개수 체크
            conditions = intent.get("conditions", []) if isinstance(intent, dict) else []
            if len(conditions) == 0:
                return None

            # Stage 2: JSON → SQL
            stage2_response = await self.client.generate(
                prompt=f"JSON: {json.dumps(intent, ensure_ascii=False)}\n출력:",
                system=self.stage2_prompt,
            )

            # SQL 정리 (후처리)
            sql = self._clean_sql(stage2_response)

            if not sql or sql.lower() in ["null", "none"]:
                return None

            return sql

        except Exception as e:
            print(f"[방식 3] 변환 실패: {e}")
            return None

    async def convert_with_metadata(self, query: str) -> dict[str, Any]:
        """변환 + 메타데이터"""
        sql = await self.convert(query)

        return {
            "method": "two_stage",
            "description": "LLM 2단계 (파싱 → SQL 생성)",
            "query": query,
            "sql": sql,
            "success": sql is not None,
            "steps": [
                "1. LLM이 JSON 파싱",
                "2. LLM이 JSON을 SQL로 변환",
            ],
            "note": "LLM 2번 호출 (비용 2배)",
            "registry_coverage": "40개 전체 속성 (DB 10개 + JSON 30개)",
        }
