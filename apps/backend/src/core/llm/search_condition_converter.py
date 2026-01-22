"""Search Condition Converter

LLM이 자연어 쿼리를 Search API conditions 배열로 변환합니다.
"""

import os
from importlib import resources
from pathlib import Path
from typing import Any

from pydantic import BaseModel, Field

from core.llm.llm_provider import LLMProvider
from core.metadata.registry_loader import SYSTEM_PROPERTY_REGISTRY, get_all_property_keys


def _read_prompt_template(filename: str) -> str:
    try:
        template = (
            resources.files("core.llm.prompts").joinpath(filename).read_text(encoding="utf-8")
        )
    except Exception as exc:
        raise RuntimeError(
            "프롬프트 템플릿 로드 실패: core.llm.prompts 패키지 리소스를 찾을 수 없습니다. "
            "Nuitka 빌드 시 --include-data-dir로 core/llm/prompts를 포함해야 합니다."
        ) from exc

    missing_placeholders = [
        token for token in ("{home_dir}", "{property_info}") if token not in template
    ]
    if missing_placeholders:
        raise RuntimeError(
            "프롬프트 템플릿 검증 실패: "
            f"{filename}에 필수 placeholder가 없습니다: {', '.join(missing_placeholders)}"
        )

    return template


class SearchCondition(BaseModel):
    """단일 검색 조건"""

    propertyKey: str = Field(description="속성 키 (예: name_full, extension, file_allocated_size)")
    operator: str = Field(description="연산자 (레지스트리 property_types.<type>.operators 기준)")
    value: str | int | float | list[str] | list[int] | list[float] | None = Field(
        description="값 (단일값, 배열, [min, max]) - empty/exists는 생략 가능"
    )


class SearchConditionsOutput(BaseModel):
    """LLM 출력 스키마"""

    conditions: list[SearchCondition] = Field(default_factory=list, description="검색 조건 배열")
    scopes: list[str] | None = Field(None, description="쿼리에서 추출한 폴더 경로 (언급된 경우만)")
    error: str | None = Field(None, description="에러 메시지")


class SearchConditionConverter:
    """LLM 기반 자연어 → Search conditions 변환기"""

    PROMPT_VERSION_DEFAULT = "v2"
    PROMPT_VERSION_ENV = "DSL_PROMPT"
    PROMPT_TEMPLATE_BY_VERSION = {
        "v1": "search_condition_system.md",
        "1": "search_condition_system.md",
        "v2": "search_condition_system.v2.md",
        "2": "search_condition_system.v2.md",
        "v3": "search_condition_system.v3.md",
        "3": "search_condition_system.v3.md",
    }

    def __init__(self, llm_provider: LLMProvider, prompt_version: str | None = None):
        self.client = llm_provider
        self.home_dir = str(Path.home())
        env_version = os.getenv(self.PROMPT_VERSION_ENV)
        selected_version = prompt_version or env_version or self.PROMPT_VERSION_DEFAULT
        template_file = self.PROMPT_TEMPLATE_BY_VERSION.get(selected_version)
        if not template_file:
            raise RuntimeError(
                "알 수 없는 DSL 프롬프트 버전입니다: "
                f"{selected_version}. 지원: {', '.join(sorted(self.PROMPT_TEMPLATE_BY_VERSION))}"
            )
        self.prompt_template_file = template_file
        self.system_prompt = self._build_system_prompt()

    def _build_system_prompt(self) -> str:
        """LLM 시스템 프롬프트 생성"""
        property_info: list[str] = []
        for key, mapping in SYSTEM_PROPERTY_REGISTRY.items():
            operators = ", ".join(mapping.supported_operators)
            type_name = mapping.type.value
            property_info.append(f"  - {key} ({type_name}): operators=[{operators}]")

        template = _read_prompt_template(self.prompt_template_file)
        return template.format(
            home_dir=self.home_dir,
            property_info="\n".join(property_info),
        )

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

    def __init__(
        self,
        llm_provider: LLMProvider,
        cache_size: int = 100,
        prompt_version: str | None = None,
    ):
        super().__init__(llm_provider, prompt_version=prompt_version)
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
