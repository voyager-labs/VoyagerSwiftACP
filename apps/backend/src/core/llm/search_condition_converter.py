"""Search Condition Converter

LLM이 자연어 쿼리를 Search API conditions 배열로 변환합니다.
"""

from pathlib import Path
from typing import Any

from pydantic import BaseModel, Field

from core.llm.llm_provider import LLMProvider
from core.metadata.mditem_registry import PROPERTY_KEY_REGISTRY, get_all_property_keys


class SearchCondition(BaseModel):
    """단일 검색 조건"""

    propertyKey: str = Field(description="속성 키 (예: size, extension, modifiedAt)")
    operator: str = Field(description="연산자 (eq, gt, gte, lt, lte, between, contains, in)")
    value: str | int | float | list[str] | list[int] | list[float] = Field(
        description="값 (단일값, 배열, [min, max])"
    )


class SearchConditionsOutput(BaseModel):
    """LLM 출력 스키마"""

    conditions: list[SearchCondition] = Field(
        default_factory=list, description="검색 조건 배열"
    )
    scopes: list[str] | None = Field(
        None, description="쿼리에서 추출한 폴더 경로 (언급된 경우만)"
    )
    error: str | None = Field(None, description="에러 메시지")


class SearchConditionConverter:
    """LLM 기반 자연어 → Search conditions 변환기"""

    def __init__(self, llm_provider: LLMProvider):
        self.client = llm_provider
        self.home_dir = str(Path.home())
        self.system_prompt = self._build_system_prompt()

    def _build_system_prompt(self) -> str:
        """LLM 시스템 프롬프트 생성 """
        # PropertyKey 정보 생성
        property_info: list[str] = []
        for key, mapping in PROPERTY_KEY_REGISTRY.items():
            operators = ", ".join(mapping.supported_operators)
            type_name = mapping.value_type.value
            property_info.append(f"  - {key} ({type_name}): operators=[{operators}]")

        return f"""당신은 파일 검색을 위한 조건 생성 전문가입니다.
자연어를 구조화된 검색 조건 배열로 변환하세요.

🚨 절대 규칙 (반드시 지켜야 함):
1. 반드시 아래에 있는 propertyKey만 사용
2. ⚠️ 없는 propertyKey는 절대 사용하지 마세요!
3. ⚠️ 설명, 주석, 부가 설명을 절대 추가하지 마세요! 조건만 출력!

=== 기존 조건/스코프 조합 규칙 ===
사용자가 기존 조건/스코프를 함께 보내면:
- 쿼리 의도와 기존 조건을 분석하여 최적의 조건 배열 생성
- 중복 조건: 쿼리 의도에 맞게 수정 또는 유지
- 충돌 조건: 쿼리 의도 우선, 기존 조건 수정/삭제 가능
- 보완 조건: 쿼리에서 언급하지 않은 기존 조건은 유지
- 스코프(폴더): 쿼리에서 다른 폴더를 언급하면 쿼리 우선, 아니면 기존 스코프 유지

=== 출력 형식 ===
조건 객체 배열과 스코프를 반환합니다:
- conditions: 조건 배열
- scopes: 쿼리에서 폴더를 언급한 경우만 설정 (언급 없으면 null)

각 조건:
- propertyKey: 속성 키 (아래 목록에서만 선택)
- operator: 연산자 (eq, gt, gte, lt, lte, between, contains, in)
- value: 값 (숫자, 문자열, 배열, [min, max])

=== 스코프(폴더) 추출 규칙 ===
쿼리에서 폴더/경로를 언급하면 scopes에 절대 경로로 추출:
- "다운로드 폴더" → ["{self.home_dir}/Downloads"]
- "데스크탑에서" → ["{self.home_dir}/Desktop"]
- "문서 폴더" → ["{self.home_dir}/Documents"]
- "홈 폴더" → ["{self.home_dir}"]
- ⚠️ 폴더 언급이 없으면 scopes는 null (기존 스코프 유지)

=== 지원 속성 (propertyKey) ===
{chr(10).join(property_info)}

=== 추가 속성 (중요!) ===

  - name (STRING) - 파일 이름 (확장자 포함)
    검색어: 파일명, 이름
    사용: operator="contains", value="검색어"
    ⚠️ 파일명 검색은 반드시 'name' 사용!

  - extension (STRING) - 파일 확장자 (점 없이)
    예시: operator="eq", value="pdf"
    예시: operator="in", value=["jpg", "jpeg", "png"]

=== 연산자 규칙 ===
- eq: 정확히 일치 (value: 단일값)
- gt: 초과 (>)
- gte: 이상 (>=)
- lt: 미만 (<)
- lte: 이하 (<=)
- between: 범위 (value: [min, max] 배열)
- contains: 문자열 포함 (value: 문자열)
- in: 목록 중 하나 (value: 배열)

=== 변환 규칙 ===

1. 크기 변환:
   - 1 KB = 1024
   - 1 MB = 1048576
   - 10 MB = 10485760
   - 100 MB = 104857600
   - 1 GB = 1073741824

2. 파일 타입 매핑:
   - PDF → extension: "pdf"
   - 이미지 → extension: ["jpg", "jpeg", "png", "gif", "heic"]
   - 영상/비디오 → extension: ["mp4", "mov", "avi", "mkv"]
   - 문서 → extension: ["pdf", "doc", "docx", "ppt", "pptx", "xls", "xlsx"]
   - 압축파일 → extension: ["zip", "rar", "7z", "tar", "gz"]

3. 날짜 (⚠️ ISO 8601 형식):
   - 오늘: 현재 날짜의 시작 (예: "2025-12-25T00:00:00")
   - 어제: 현재-1일
   - 최근 7일: 현재-7일
   - 최근 30일: 현재-30일
   - ⚠️ 날짜 값은 반드시 ISO 8601 문자열!

4. "다운로드" 관련 (⚠️ 중요):
   - "다운로드한 파일" → addedAt 사용
   - "어제 다운로드" → addedAt, operator="gt", value=(어제 날짜)

5. 시간/길이 변환:
   - 1분 = 60초
   - 10분 = 600초
   - 1시간 = 3600초

=== 올바른 예시 ===

입력: "10MB 이상 PDF 파일"
출력: [
  {{"propertyKey": "size", "operator": "gt", "value": 10485760}},
  {{"propertyKey": "extension", "operator": "eq", "value": "pdf"}}
]

입력: "어제 다운로드한 파일"
출력: [
  {{"propertyKey": "addedAt", "operator": "gt", "value": "2025-12-24T00:00:00"}}
]

입력: "최근 7일 1080p 이상 영상"
출력: [
  {{"propertyKey": "modifiedAt", "operator": "gt", "value": "2025-12-18T00:00:00"}},
  {{"propertyKey": "pixelHeight", "operator": "gte", "value": 1080}},
  {{"propertyKey": "extension", "operator": "in", "value": ["mp4", "mov", "avi"]}}
]

입력: "이미지 파일"
출력: [
  {{"propertyKey": "extension", "operator": "in", "value": ["jpg", "jpeg", "png", "gif", "heic"]}}
]

입력: "파일명에 report가 포함된 PDF"
출력: [
  {{"propertyKey": "name", "operator": "contains", "value": "report"}},
  {{"propertyKey": "extension", "operator": "eq", "value": "pdf"}}
]

입력: "1MB ~ 100MB 사이 영상"
출력: [
  {{"propertyKey": "size", "operator": "between", "value": [1048576, 104857600]}},
  {{"propertyKey": "extension", "operator": "in", "value": ["mp4", "mov", "avi", "mkv"]}}
]

입력: "10분 이상 영상"
출력: [
  {{"propertyKey": "duration", "operator": "gt", "value": 600}},
  {{"propertyKey": "extension", "operator": "in", "value": ["mp4", "mov", "avi", "mkv"]}}
]

입력: "암호화된 PDF"
출력: [
  {{"propertyKey": "extension", "operator": "eq", "value": "pdf"}}
]

입력: "4K, 10분, MP4, 최근 7일, 10MB" (5개 조건 → 4개만 선택)
출력: [
  {{\"propertyKey\": \"pixelHeight\", \"operator\": \"gte\", \"value\": 2160}},
  {{\"propertyKey\": \"duration\", \"operator\": \"gte\", \"value\": 600}},
  {{\"propertyKey\": \"extension\", \"operator\": \"eq\", \"value\": \"mp4\"}},
  {{\"propertyKey\": \"modifiedAt\", \"operator\": \"gt\", \"value\": \"2025-12-18T00:00:00\"}}
]

=== 잘못된 예시 (이렇게 하지 마세요!) ===

❌ 틀림: propertyKey="filename"
   이유: 'filename'은 존재하지 않음
   ✅ 올바름: propertyKey="name"

❌ 틀림: propertyKey="downloadedAt"
   이유: 'downloadedAt'은 존재하지 않음
   ✅ 올바름: propertyKey="addedAt"

❌ 틀림: value=".pdf"
   이유: 확장자에 점(.) 포함하면 안 됨
   ✅ 올바름: value="pdf"

출력 형식: 조건 배열만! 설명 없이!"""

    async def convert(
        self,
        query: str,
        existing_conditions: list[dict[str, Any]] | None = None,
        existing_scopes: list[str] | None = None,
    ) -> dict[str, Any]:
        """자연어 → 조건 배열 + 스코프 변환

        Args:
            query: 자연어 검색 쿼리
            existing_conditions: 사용자가 미리 설정한 조건들 (선택적)
            existing_scopes: 사용자가 미리 설정한 스코프들 (선택적)

        Returns:
            {"conditions": [...], "scopes": [...] | None}
        """
        try:
            import json

            # 프롬프트 구성
            prompt_parts = [f"사용자 쿼리: {query}"]

            if existing_conditions:
                conditions_json = json.dumps(existing_conditions, ensure_ascii=False)
                prompt_parts.append(f"기존 조건: {conditions_json}")

            if existing_scopes:
                scopes_json = json.dumps(existing_scopes, ensure_ascii=False)
                prompt_parts.append(f"기존 스코프: {scopes_json}")

            if existing_conditions or existing_scopes:
                prompt_parts.append(
                    "위 쿼리와 기존 조건/스코프를 분석하여 최적의 결과를 생성하세요. "
                    "쿼리에서 폴더를 언급하면 스코프를 변경하고, 아니면 기존 스코프를 유지(scopes=null)하세요."
                )

            prompt_parts.append("출력:")
            prompt = "\n".join(prompt_parts)

            result = await self.client.generate_structured(
                prompt=prompt,
                schema=SearchConditionsOutput,
                system=self.system_prompt,
            )

            if result.error:
                print(f"[SearchConditionConverter] {result.error}")
                return {"conditions": [], "scopes": None}

            return {
                "conditions": [c.model_dump() for c in result.conditions],
                "scopes": result.scopes,
            }

        except Exception as e:
            print(f"[SearchConditionConverter] 변환 실패: {e}")
            return {"conditions": [], "scopes": None}

    async def convert_with_metadata(self, query: str) -> dict[str, Any]:
        """변환 + 메타데이터 반환"""
        result = await self.convert(query)

        return {
            "method": "llm_structured",
            "description": "LLM 기반 구조화된 조건 생성",
            "query": query,
            "conditions": result["conditions"],
            "scopes": result["scopes"],
            "success": len(result["conditions"]) > 0,
            "supported_properties": get_all_property_keys(),
        }


class CachedSearchConditionConverter(SearchConditionConverter):
    """캐싱 기능이 있는 SearchConditionConverter"""

    def __init__(self, llm_provider: LLMProvider, cache_size: int = 100):
        super().__init__(llm_provider)
        self._cache: dict[str, dict[str, Any]] = {}
        self._cache_size = cache_size

    async def convert(
        self,
        query: str,
        existing_conditions: list[dict[str, Any]] | None = None,
        existing_scopes: list[str] | None = None,
    ) -> dict[str, Any]:
        """캐시된 변환 결과 반환

        Note: existing_conditions나 existing_scopes가 있으면 캐시를 사용하지 않음
        """
        # 기존 조건/스코프가 있으면 캐시 미사용 (동적 조합 필요)
        if existing_conditions or existing_scopes:
            return await super().convert(query, existing_conditions, existing_scopes)

        # 캐시 히트
        if query in self._cache:
            return self._cache[query]

        # 변환 실행
        result = await super().convert(query)

        # 캐시 저장 (크기 제한)
        if len(self._cache) >= self._cache_size:
            # 가장 오래된 항목 제거 (간단한 FIFO)
            oldest_key = next(iter(self._cache))
            del self._cache[oldest_key]

        self._cache[query] = result
        return result

    def clear_cache(self) -> None:
        """캐시 초기화"""
        self._cache.clear()
