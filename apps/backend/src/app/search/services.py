"""Search 서비스 레이어"""

import logging
from typing import Any

from app.config import load_config
from app.search.schemas import (
    AppliedFilters,
    SearchCondition,
    SearchError,
    SearchFilters,
    SearchResponse,
)
from core.llm.langchain_provider import LangChainProvider
from core.llm.search_condition_converter import CachedSearchConditionConverter


class SearchService:
    """검색 서비스"""

    def __init__(self):
        self._converter: CachedSearchConditionConverter | None = None

    @property
    def converter(self) -> CachedSearchConditionConverter:
        """Lazy initialization of converter"""
        if self._converter is None:
            config = load_config()
            llm_provider = LangChainProvider(
                provider="openai",
                base_url=config.gateway_url,
            )
            self._converter = CachedSearchConditionConverter(llm_provider)
        return self._converter

    async def query_search(
        self,
        query: str,
        filters: SearchFilters | None = None,
    ) -> SearchResponse:
        """쿼리 기반 검색 (LLM 해석)

        Args:
            query: 자연어 검색 쿼리
            filters: 선택적 필터 (scopes, conditions)

        Returns:
            SearchResponse
        """
        # 1. 사용자가 보낸 기존 조건/스코프 추출
        existing_conditions: list[dict[str, Any]] | None = None
        existing_scopes: list[str] | None = None
        if filters:
            if filters.conditions:
                existing_conditions = [
                    {
                        "propertyKey": c.propertyKey,
                        "operator": c.operator,
                        "value": c.value,
                    }
                    for c in filters.conditions
                ]
            if filters.scopes:
                existing_scopes = filters.scopes

        # 2. query + 기존 조건/스코프 → 최적 결과 생성
        llm_result = await self.converter.convert(query, existing_conditions, existing_scopes)
        llm_error = llm_result.error

        # 3. 결과 조건 생성
        if llm_error:
            logger.error("[SearchService] LLM convert error: %s", llm_error)
            applied_conditions = [SearchCondition(**c) for c in (existing_conditions or [])]
            applied_scopes = existing_scopes or []
            return SearchResponse(
                itemCount=0,
                appliedFilters=AppliedFilters(
                    scopes=applied_scopes,
                    conditions=applied_conditions,
                ),
                items=[],
                error=SearchError(code="LLM_CONVERSION_FAILED", details=llm_error),
            )

        applied_conditions = [
            SearchCondition(
                propertyKey=c.propertyKey,
                operator=c.operator,
                value=c.value,
            )
            for c in llm_result.conditions
        ]

        # 4. Scopes 설정: LLM이 새 스코프를 반환하면 사용, 아니면 기존 스코프 유지
        applied_scopes = (
            llm_result.scopes if llm_result.scopes is not None else (existing_scopes or [])
        )

        return SearchResponse(
            itemCount=0,
            appliedFilters=AppliedFilters(
                scopes=applied_scopes,
                conditions=applied_conditions,
            ),
            items=[],
            error=None,
        )


# 싱글톤 인스턴스
_search_service: SearchService | None = None


def get_search_service() -> SearchService:
    """SearchService 싱글톤 반환"""
    global _search_service
    if _search_service is None:
        _search_service = SearchService()
    return _search_service


logger = logging.getLogger("uvicorn.error")
