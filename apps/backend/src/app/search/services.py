"""Search 서비스 레이어"""

import asyncio
import logging
import time
from typing import Any, cast

from sqlalchemy import text
from sqlmodel import select

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
from core.search.condition_builder import ConditionBuilder, ConditionBuilderError
from core.search.scope_builder import ScopeBuilder
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
        llm_start = time.perf_counter()
        llm_result = await self.converter.convert(query, existing_conditions, existing_scopes)
        llm_error = llm_result.get("error")

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

        applied_conditions = [SearchCondition(**c) for c in llm_result["conditions"]]

        # 4. Scopes 설정: LLM이 새 스코프를 반환하면 사용, 아니면 기존 스코프 유지
        applied_scopes = (
            llm_result["scopes"] if llm_result["scopes"] is not None else (existing_scopes or [])
        )

        # 5. SQL 생성 및 실행
        items, error = await self._execute_search(
            scopes=applied_scopes,
            conditions=[c.model_dump() for c in applied_conditions],
        )
        _tag_search_result(
            items,
            error,
            conditions_count=len(applied_conditions),
            scopes_count=len(applied_scopes),
        )
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
        start = time.perf_counter()
        items, error = await self._execute_search(
            scopes=filters.scopes,
            conditions=[c.model_dump() for c in filters.conditions],
        )
        _tag_search_result(
            items,
            error,
            conditions_count=len(filters.conditions),
            scopes_count=len(filters.scopes),
        )
        return SearchResponse(
            itemCount=len(items),
            appliedFilters=AppliedFilters(
                scopes=filters.scopes,
                conditions=list(filters.conditions),
            ),
            items=items,
            error=error,
        )

    async def _execute_search(
        self,
        scopes: list[str],
        conditions: list[dict[str, Any]],
    ) -> tuple[list[SearchItem], SearchError | None]:
        """SQL 실행 및 결과 반환"""
        try:
            # Scope 조건 생성
            scope_clause, scope_params = self.scope_builder.build_scope_clause(scopes)

            # Condition 조건 생성
            condition_clause, condition_params = self.condition_builder.build_where(conditions)

            # WHERE절 결합
            where_clause = f"{scope_clause} AND {condition_clause}"
            all_params: dict[str, Any] = {**scope_params, **condition_params}

            def _run_query() -> list[EntrySchema]:
                where_text = text(where_clause).bindparams(**all_params)
                statement = select(EntrySchema).where(where_text)
                with engine_manager.session(autocommit=False) as session:
                    result = session.exec(statement)
                    return list(result.all())

            sql_start = time.perf_counter()
            entries: list[EntrySchema] = await asyncio.to_thread(_run_query)
            items: list[SearchItem] = []
            for entry in entries:
                entry_id = cast(int, entry.id)
                items.append(
                    SearchItem(
                        id=entry_id,
                        path=entry.path,
                        name=entry.name_full,
                        size=entry.size,
                        extension=entry.extension,
                        fileKind=entry.file_kind,
                        modificationDate=str(entry.modification_date)
                        if entry.modification_date
                        else None,
                    )
                )

            return items, None

        except ConditionBuilderError as e:
            logger.error("[SearchService] Condition error: %s", e)
            return [], SearchError(code="CONDITION_BUILD_FAILED", details=str(e))
        except Exception as e:
            logger.exception("[SearchService] Search error: %s", e)
            return [], SearchError(code="SEARCH_EXECUTION_FAILED", details=str(e))


# 싱글톤 인스턴스
_search_service: SearchService | None = None


def get_search_service() -> SearchService:
    """SearchService 싱글톤 반환"""
    global _search_service
    if _search_service is None:
        _search_service = SearchService()
    return _search_service


logger = logging.getLogger("uvicorn.error")


def _tag_search_result(
    items: list[SearchItem],
    error: SearchError | None,
    conditions_count: int,
    scopes_count: int,
) -> None:
    if error:
        return


def _bucket_for_count(value: int) -> str:
    if value <= 0:
        return "0"
    if value <= 1:
        return "1"
    if value <= 10:
        return "2-10"
    if value <= 50:
        return "11-50"
    return "51+"
