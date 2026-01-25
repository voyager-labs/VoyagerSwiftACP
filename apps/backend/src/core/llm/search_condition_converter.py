"""Search Condition Converter

LLM이 자연어 쿼리를 Search API conditions 배열로 변환합니다.
"""

from __future__ import annotations

import json
import logging
import re
from importlib import resources
from pathlib import Path
from typing import Any, TypeVar, cast

from langchain_core.messages import BaseMessage, HumanMessage, SystemMessage
from langchain_core.runnables import Runnable
from pydantic import BaseModel, Field

from core.metadata.registry_loader import (
    SYSTEM_PROPERTY_REGISTRY,
    get_visible_property_keys,
    load_condition_registry,
)

logger = logging.getLogger("uvicorn.error")

TStructured = TypeVar("TStructured", bound=BaseModel)


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

    PROMPT_TEMPLATE_FILE = "compose_filter_system.md"
    CORE_KEYS = {
        "name_full",
        "extension",
        "content_type_tree",
        "file_allocated_size",
        "size",
        "downloaded_date",
        "modification_date",
        "creation_date",
        "dir_path",
        "path",
    }
    SCOPE_PATTERNS = (
        (r"\bdownloads?\b", "Downloads"),
        (r"\bdocuments?\b", "Documents"),
        (r"\bdesktop\b", "Desktop"),
        (r"\bhome folder\b|\bhome directory\b", ""),
    )

    def __init__(self, llm_provider: Any):
        self.client = llm_provider
        self.home_dir = str(Path.home())
        self.prompt_template_file = self.PROMPT_TEMPLATE_FILE
        self.system_prompt = self._build_system_prompt()

    def _build_system_prompt(self) -> str:
        """LLM 시스템 프롬프트 생성"""
        property_info = self._build_property_info()
        template = _read_prompt_template(self.prompt_template_file)
        return template.format(
            home_dir=self.home_dir,
            property_info=property_info,
        )

    def _build_property_info(self) -> str:
        return "keys from user prompt"

    def _extract_candidate_keys(
        self,
        query: str,
        existing_conditions: list[dict[str, Any]] | None = None,
    ) -> set[str]:
        candidates = set(self.CORE_KEYS)

        for raw in existing_conditions or []:
            key = raw.get("propertyKey")
            if isinstance(key, str):
                candidates.add(key)

        lower = query.lower()
        for key, mapping in SYSTEM_PROPERTY_REGISTRY.items():
            if mapping.ui_hidden:
                continue
            for alias in mapping.search_aliases:
                if alias and alias.lower() in lower:
                    candidates.add(key)
                    break
            if key.lower() in lower:
                candidates.add(key)

        return {key for key in candidates if self._is_visible_key(key)}

    @staticmethod
    def _is_visible_key(key: str) -> bool:
        mapping = SYSTEM_PROPERTY_REGISTRY.get(key)
        return bool(mapping) and not mapping.ui_hidden

    def _build_key_groups(
        self,
        query: str,
        existing_conditions: list[dict[str, Any]] | None = None,
    ) -> dict[str, list[str]]:
        candidates = self._extract_candidate_keys(query, existing_conditions)
        grouped: dict[str, list[str]] = {}
        for key in sorted(candidates):
            mapping = SYSTEM_PROPERTY_REGISTRY.get(key)
            if not mapping or mapping.ui_hidden:
                continue
            grouped.setdefault(mapping.type.value, []).append(key)
        return grouped

    def _build_keys_payload(
        self,
        query: str,
        existing_conditions: list[dict[str, Any]] | None = None,
    ) -> str:
        grouped = self._build_key_groups(query, existing_conditions)
        segments: list[str] = []
        for type_name in sorted(grouped.keys()):
            keys = ",".join(sorted(grouped[type_name]))
            segments.append(f"{type_name}:{keys}")
        return "|".join(segments)

    def _build_ops_payload(self, type_names: list[str]) -> str:
        registry = load_condition_registry()
        parts: list[str] = []
        for type_name in sorted(set(type_names)):
            defaults = registry.property_types.get(type_name)
            if not defaults:
                continue
            operators = defaults.operators
            filtered: list[str] = []
            for operator_code in operators:
                operator = registry.operators.get(operator_code)
                if not operator:
                    continue
                if operator.allowed_types and type_name not in operator.allowed_types:
                    continue
                filtered.append(operator_code)
            parts.append(f"{type_name}={','.join(filtered)}")
        return "|".join(parts)

    def _infer_scopes_from_query(self, query: str) -> list[str] | None:
        lower = query.lower()
        scopes: list[str] = []
        for pattern, suffix in self.SCOPE_PATTERNS:
            if not re.search(pattern, lower):
                continue
            path = self.home_dir if suffix == "" else str(Path(self.home_dir) / suffix)
            if path not in scopes:
                scopes.append(path)
        return scopes or None

    def _build_user_prompt(
        self,
        query: str,
        existing_conditions: list[dict[str, Any]] | None = None,
        existing_scopes: list[str] | None = None,
    ) -> str:
        prompt_parts = [f"q={query}"]
        grouped = self._build_key_groups(query, existing_conditions)
        keys_payload = "|".join(
            f"{type_name}:{','.join(sorted(grouped[type_name]))}"
            for type_name in sorted(grouped.keys())
        )
        if keys_payload:
            prompt_parts.append(f"keys={keys_payload}")

        ops_payload = self._build_ops_payload(list(grouped.keys()))
        if ops_payload:
            prompt_parts.append(f"ops={ops_payload}")

        if existing_conditions:
            conditions_json = json.dumps(existing_conditions, ensure_ascii=False)
            prompt_parts.append(f"conditions={conditions_json}")

        if existing_scopes:
            scopes_json = json.dumps(existing_scopes, ensure_ascii=False)
            prompt_parts.append(f"scopes={scopes_json}")
        else:
            inferred_scopes = self._infer_scopes_from_query(query)
            if inferred_scopes:
                scopes_json = json.dumps(inferred_scopes, ensure_ascii=False)
                prompt_parts.append(f"scopes={scopes_json}")

        return "\n".join(prompt_parts)

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
            visible_conditions = None
            if existing_conditions:
                visible_conditions = [
                    condition
                    for condition in existing_conditions
                    if self._is_visible_key(str(condition.get("propertyKey", "")))
                ]

            prompt = self._build_user_prompt(query, visible_conditions, existing_scopes)

            result = await self._request_structured(
                prompt=prompt,
                schema=SearchConditionsOutput,
                system=self.system_prompt,
            )

            if result.error:
                logger.error("[SearchConditionConverter] %s", result.error)
                return {"conditions": [], "scopes": None, "error": result.error}

            normalized_conditions = [
                self._normalize_condition(c.model_dump()) for c in result.conditions
            ]
            filtered_conditions = [
                c
                for c in normalized_conditions
                if c is not None and self._is_visible_key(str(c.get("propertyKey", "")))
            ]
            return {
                "conditions": filtered_conditions,
                "scopes": result.scopes,
                "error": None,
            }

        except Exception as e:
            logger.exception("[SearchConditionConverter] 변환 실패: %s", e)
            return {"conditions": [], "scopes": None, "error": str(e)}

    def _normalize_condition(self, condition: dict[str, Any]) -> dict[str, Any] | None:
        operator = condition.get("operator")
        value = condition.get("value")
        if operator == "eq" and value is None:
            return None
        if operator == "matches" and isinstance(value, str):
            condition["value"] = self._normalize_matches_value(value)
        return condition

    async def _request_structured(
        self,
        prompt: str,
        schema: type[TStructured],
        system: str | None = None,
    ) -> TStructured:
        messages = self._build_messages(prompt=prompt, system=system)
        structured_llm = cast(
            Runnable[list[BaseMessage], TStructured],
            self.client.llm.with_structured_output(schema),
        )
        return await structured_llm.ainvoke(messages)

    @staticmethod
    def _build_messages(prompt: str, system: str | None = None) -> list[BaseMessage]:
        messages: list[BaseMessage] = [HumanMessage(content=prompt)]
        if system:
            messages.insert(0, SystemMessage(content=system))
        return messages

    @staticmethod
    def _normalize_matches_value(value: str) -> str:
        if "%" in value:
            return value
        if ".*" in value:
            return value.replace(".*", "%")
        return value

    async def convert_with_metadata(self, query: str) -> dict[str, Any]:
        """변환 + 메타데이터 반환"""
        result = await self.convert(query)

        return {
            "method": "llm_structured",
            "description": "LLM 기반 구조화된 조건 생성",
            "query": query,
            "conditions": result["conditions"],
            "scopes": result["scopes"],
            "success": not result.get("error") and len(result["conditions"]) > 0,
            "supported_properties": get_visible_property_keys(),
            "error": result.get("error"),
        }


class CachedSearchConditionConverter(SearchConditionConverter):
    """캐싱 기능이 있는 SearchConditionConverter"""

    def __init__(
        self,
        llm_provider: Any,
        cache_size: int = 100,
    ):
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
