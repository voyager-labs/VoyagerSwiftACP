"""방식 1: 완전 분리 (LLM 파싱 → Python SQL 생성)

LLM은 자연어를 구조화 JSON으로 파싱만 하고,
Python 코드(RegistryQueryBuilder)가 SQL을 생성합니다.
"""

import json
from typing import Any

from langchain_core.output_parsers import JsonOutputParser
from langchain_core.prompts import PromptTemplate
from pydantic import BaseModel, Field

from core.llm.llm_provider import LLMProvider
from core.llm.registry_query_builder import RegistryQueryBuilder
from core.metadata.mditem_registry import get_indexed_attributes, get_json_attributes


class QueryIntent(BaseModel):
    """쿼리 의도 구조"""

    conditions: list[dict[str, Any]] = Field(description="검색 조건 리스트 (최대 3개)")
    logic: str = Field(description="AND 또는 OR")
    error: str | None = Field(default=None, description="에러 메시지 (조건 초과 시)")


class SeparatedQueryConverter:
    """방식 1: LLM 파싱 + Python SQL 생성"""

    def __init__(self, llm_provider: LLMProvider):
        self.client = llm_provider
        self.builder = RegistryQueryBuilder()
        self.parser = JsonOutputParser(pydantic_object=QueryIntent)
        self.system_prompt = self._build_system_prompt()

    def _build_system_prompt(self) -> str:
        """LLM 프롬프트 생성 (JSON 파싱만) - 전체 레지스트리 포함"""
        indexed = get_indexed_attributes()
        json_attrs = get_json_attributes()

        # DB 컬럼 정보 (10개 전체)
        db_fields = []
        for key, attr in indexed.items():
            if attr.db_field:
                aliases = ", ".join(attr.search_aliases[:3])
                examples_str = str(attr.examples[0])
                db_fields.append(
                    f"  - {attr.db_field} ({attr.type.value}) - {attr.description}\n"
                    f"    검색어: {aliases} | 예시: {examples_str}"
                )

        # JSON 필드 정보 (30개 전체)
        json_fields = []
        for key, attr in json_attrs.items():
            aliases = ", ".join(attr.search_aliases[:3])
            examples_str = str(attr.examples[0])
            json_fields.append(
                f"  - {key} ({attr.type.value}) - {attr.description}\n"
                f"    검색어: {aliases} | 예시: {examples_str}"
            )

        return f"""당신은 자연어를 구조화 JSON으로 변환하는 파서입니다.

중요 규칙:
1. 반드시 아래 JSON 형식으로만 출력 (설명이나 다른 텍스트 절대 금지!)
2. 조건은 최대 3개까지만
3. 반드시 아래 속성만 사용 (총 40개)

=== 사용 가능한 속성 (40개 전체) ===

【DB 컬럼 - 빠른 검색 (10개)】
{chr(10).join(db_fields)}

【JSON 필드 - 느린 검색 (30개)】
{chr(10).join(json_fields)}

=== field 규칙 ===
- DB 컬럼: db_field 이름 사용 (예: size, extension, modification_date)
- JSON 필드: MDItem 키 사용 (예: kMDItemPixelWidth, kMDItemDurationSeconds)

=== operator 규칙 ===
사용 가능: =, !=, >, <, >=, <=, IN, LIKE
- IN: value를 배열로 ["jpg", "png"]
- LIKE: 패턴 매칭 "%keyword%"

=== value 규칙 ===
- 문자열: 따옴표 없이 (예: "pdf", "mp4")
- 숫자: 그대로 (예: 10485760, 1080)
- 배열: ["jpg", "png", "heic"]
- 날짜 함수: SQLite 함수 (예: "date('now', '-7 days')")

크기 변환:
- 1 KB = 1024
- 1 MB = 1048576
- 10 MB = 10485760
- 100 MB = 104857600
- 1 GB = 1073741824

=== logic 규칙 ===
- AND 또는 OR

=== 출력 형식 (이것만 출력!) ===
반드시 이 JSON 형식으로만 응답하세요:
{{
  "conditions": [
    {{"field": "필드명", "operator": "연산자", "value": "값"}}
  ],
  "logic": "AND 또는 OR",
  "error": null
}}

=== 예시 ===

입력: "10MB 이상 PDF"
출력:
{{
  "conditions": [
    {{"field": "size", "operator": ">", "value": 10485760}},
    {{"field": "extension", "operator": "=", "value": "pdf"}}
  ],
  "logic": "AND"
}}

입력: "최근 7일 1080p 이상 영상"
출력:
{{
  "conditions": [
    {{"field": "modification_date", "operator": ">", "value": "date('now', '-7 days')"}},
    {{"field": "kMDItemPixelHeight", "operator": ">=", "value": 1080}},
    {{"field": "extension", "operator": "IN", "value": ["mp4", "mov", "avi"]}}
  ],
  "logic": "AND"
}}

입력: "클래식 음악 44.1kHz"
출력:
{{
  "conditions": [
    {{"field": "kMDItemMusicalGenre", "operator": "=", "value": "Classical"}},
    {{"field": "kMDItemAudioSampleRate", "operator": "=", "value": 44100}}
  ],
  "logic": "AND"
}}

입력: "4K, 10분, MP4, 최근 7일, 10MB" (5개 조건 - 초과!)
출력:
{{"error": "조건이 3개를 초과합니다", "conditions": [], "logic": "AND"}}

다시 한번 강조: 반드시 JSON 형식으로만 출력하세요! 설명이나 다른 텍스트를 절대 포함하지 마세요!"""

    async def convert(self, query: str) -> str | None:
        """자연어 → SQL WHERE절

        Returns:
            SQL WHERE절 또는 None (실패 시)
        """
        try:
            # 1단계: LLM으로 JSON 파싱 (JsonOutputParser 사용)
            response = await self.client.generate(
                prompt=f"입력: {query}\n출력:", system=self.system_prompt
            )

            # JsonOutputParser로 파싱
            try:
                intent = self.parser.parse(response)
            except Exception as parse_error:
                print(f"[방식 1] JsonOutputParser 파싱 실패: {parse_error}")
                # Fallback: 수동 JSON 추출 시도
                import re

                json_pattern = r'\{[^{}]*(?:\{[^{}]*\}[^{}]*)*\}'
                matches = re.findall(json_pattern, response, re.DOTALL)

                intent = None
                for match in matches:
                    try:
                        intent = json.loads(match)
                        break
                    except json.JSONDecodeError:
                        continue

                if intent is None:
                    print(f"[방식 1] Fallback JSON 추출 실패: {response[:200]}")
                    return None

            # 에러 체크
            if isinstance(intent, dict) and intent.get("error"):
                print(f"[방식 1] 파싱 에러: {intent['error']}")
                return None

            # 조건 개수 체크
            conditions = intent.get("conditions", []) if isinstance(intent, dict) else []
            if len(conditions) > 3:
                print(f"[방식 1] 조건 초과: {len(conditions)}개")
                return None

            if len(conditions) == 0:
                return None

            # 2단계: Python 빌더로 SQL 생성
            sql = self.builder.build_query(intent)

            return sql if sql != "1=1" else None

        except Exception as e:
            print(f"[방식 1] 변환 실패: {e}")
            return None

    async def convert_with_metadata(self, query: str) -> dict[str, Any]:
        """변환 + 메타데이터 반환

        Returns:
            {
                "method": "separated",
                "query": 원본 쿼리,
                "sql": SQL WHERE절,
                "success": 성공 여부,
                "steps": ["LLM 파싱", "Python SQL 생성"]
            }
        """
        sql = await self.convert(query)

        return {
            "method": "separated",
            "description": "LLM 파싱 → Python SQL 생성",
            "query": query,
            "sql": sql,
            "success": sql is not None,
            "steps": ["1. LLM이 JSON 파싱", "2. Python 빌더가 SQL 생성"],
            "registry_coverage": "40개 전체 속성 (DB 10개 + JSON 30개)",
        }
