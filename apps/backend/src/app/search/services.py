"""Search 서비스 레이어"""

import logging
from typing import cast

from app.config import load_config
from app.search.schemas import (
    AppliedFilters,
    SearchCondition,
    SearchError,
    SearchFilters,
    SearchItem,
    SearchResponse,
)
from core.llm.langchain_provider import LangChainProvider
from core.llm.search_condition_converter import CachedSearchConditionConverter
from core.search import ConditionBuilder, ScopeBuilder, execute_search
from core.search.condition_builder import ConditionBuilderError
from infra.db.engine import engine_manager
from infra.schemas.entry_schema import EntrySchema


# TODO: Collection으로 변경 모듈 이름 변경
class SearchService:
    """검색 서비스"""

    def __init__(self):
        self.condition_builder = ConditionBuilder()
        self.scope_builder = ScopeBuilder()
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
        existing_conditions = None
        existing_scopes = None
        if filters:
            if filters.conditions:
                existing_conditions = [c.model_dump() for c in filters.conditions]
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

        applied_conditions = [SearchCondition(**c.model_dump()) for c in llm_result.conditions]

        # 4. Scopes 설정: LLM이 새 스코프를 반환하면 사용, 아니면 기존 스코프 유지
        applied_scopes = (
            llm_result.scopes if llm_result.scopes is not None else (existing_scopes or [])
        )

        # 5. SQL 생성 및 실행
        condition_dicts = [c.model_dump() for c in applied_conditions]
        try:
            entries = await execute_search(
                model=EntrySchema,
                session_context=lambda: engine_manager.session(autocommit=False),
                scopes=applied_scopes,
                conditions=condition_dicts,
                scope_builder=self.scope_builder,
                condition_builder=self.condition_builder,
            )
            items = [
                SearchItem(
                    id=cast(int, entry.id),
                    path=entry.path,
                    name=entry.name_full,
                    size=entry.size,
                    extension=entry.extension,
                    fileKind=entry.file_kind,
                    modificationDate=str(entry.modification_date)
                    if entry.modification_date
                    else None,
                )
                for entry in entries
            ]
            error: SearchError | None = None
        except ConditionBuilderError as e:
            logger.error("[SearchService] Condition error: %s", e)
            items = []
            error = SearchError(code="CONDITION_BUILD_FAILED", details=str(e))
        except Exception as e:
            logger.exception("[SearchService] Search error: %s", e)
            items = []
            error = SearchError(code="SEARCH_EXECUTION_FAILED", details=str(e))

        return SearchResponse(
            itemCount=len(items),
            appliedFilters=AppliedFilters(
                scopes=applied_scopes,
                conditions=applied_conditions,
            ),
            items=items,
            error=error,
        )

    async def filter_search(
        self,
        filters: SearchFilters,
    ) -> SearchResponse:
        """필터 기반 검색 (LLM 없음)

        Args:
            filters: 필수 필터 (scopes, conditions)

        Returns:
            SearchResponse
        """
        # 직접 필터 적용
        condition_dicts = [c.model_dump() for c in filters.conditions]
        try:
            entries = await execute_search(
                model=EntrySchema,
                session_context=lambda: engine_manager.session(autocommit=False),
                scopes=filters.scopes,
                conditions=condition_dicts,
                scope_builder=self.scope_builder,
                condition_builder=self.condition_builder,
            )
            items = [
                SearchItem(
                    id=cast(int, entry.id),
                    path=entry.path,
                    name=entry.name_full,
                    size=entry.size,
                    extension=entry.extension,
                    fileKind=entry.file_kind,
                    modificationDate=str(entry.modification_date)
                    if entry.modification_date
                    else None,
                )
                for entry in entries
            ]
            error: SearchError | None = None
        except ConditionBuilderError as e:
            logger.error("[SearchService] Condition error: %s", e)
            items = []
            error = SearchError(code="CONDITION_BUILD_FAILED", details=str(e))
        except Exception as e:
            logger.exception("[SearchService] Search error: %s", e)
            items = []
            error = SearchError(code="SEARCH_EXECUTION_FAILED", details=str(e))

        return SearchResponse(
            itemCount=len(items),
            appliedFilters=AppliedFilters(
                scopes=filters.scopes,
                conditions=list(filters.conditions),
            ),
            items=items,
            error=error,
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
