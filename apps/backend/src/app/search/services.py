"""Search 서비스 레이어"""

from typing import Any

from sqlalchemy import text

from app.config import load_config
from app.search.schemas import (
    AppliedFilters,
    SearchCondition,
    SearchFilters,
    SearchItem,
    SearchResponse,
)
from core.llm.langchain_provider import LangChainProvider
from core.llm.search_condition_converter import CachedSearchConditionConverter
from core.search.condition_builder import ConditionBuilder, ConditionBuilderError
from core.search.scope_builder import ScopeBuilder
from infra.db.engine import engine_manager


def _create_llm_provider() -> LangChainProvider:
    """VoyagerConfig 설정으로 LLM Provider 생성"""
    cfg = load_config()

    # LLM provider 설정 (openai만 지원)
    provider_kwargs = {}
    if cfg.llm_provider == "openai" and cfg.openai_api_key:
        provider_kwargs["api_key"] = cfg.openai_api_key

    return LangChainProvider(
        provider=cfg.llm_provider,
        model=cfg.llm_model,
        temperature=cfg.llm_temperature,
        **provider_kwargs,
    )


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
            llm_provider = _create_llm_provider()
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

        # 2. LLM으로 query + 기존 조건/스코프 → 최적 결과 생성
        llm_result = await self.converter.convert(
            query, existing_conditions, existing_scopes
        )

        # 3. 결과 조건 생성
        applied_conditions = [
            SearchCondition(**c) for c in llm_result["conditions"]
        ]

        # 4. Scopes 설정: LLM이 새 스코프를 반환하면 사용, 아니면 기존 스코프 유지
        applied_scopes = (
            llm_result["scopes"]
            if llm_result["scopes"] is not None
            else (existing_scopes or [])
        )

        # 5. SQL 생성 및 실행
        items = await self._execute_search(
            scopes=applied_scopes,
            conditions=[c.model_dump() for c in applied_conditions],
        )

        return SearchResponse(
            itemCount=len(items),
            appliedFilters=AppliedFilters(
                scopes=applied_scopes,
                conditions=applied_conditions,
            ),
            items=items,
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
        items = await self._execute_search(
            scopes=filters.scopes,
            conditions=[c.model_dump() for c in filters.conditions],
        )

        return SearchResponse(
            itemCount=len(items),
            appliedFilters=AppliedFilters(
                scopes=filters.scopes,
                conditions=list(filters.conditions),
            ),
            items=items,
        )

    async def _execute_search(
        self,
        scopes: list[str],
        conditions: list[dict[str, Any]],
    ) -> list[SearchItem]:
        """SQL 실행 및 결과 반환"""
        try:
            # Scope 조건 생성
            scope_clause, scope_params = self.scope_builder.build_scope_clause(scopes)

            # Condition 조건 생성
            condition_clause, condition_params = self.condition_builder.build_where(
                conditions
            )

            # WHERE절 결합
            where_clause = f"{scope_clause} AND {condition_clause}"
            all_params = scope_params + condition_params

            # SQL 실행
            sql = f"""
                SELECT
                    id, path, name_full, size, extension,
                    file_kind, modification_date
                FROM file_entries
                WHERE {where_clause}
                ORDER BY modification_date DESC
            """

            # 파라미터를 positional에서 named로 변환
            param_dict: dict[str, Any] = {}
            for i, param in enumerate(all_params):
                param_name = f"p{i}"
                sql = sql.replace("?", f":{param_name}", 1)
                param_dict[param_name] = param

            with engine_manager.session(autocommit=False) as session:
                result = session.execute(text(sql), param_dict)
                rows = result.fetchall()

            return [
                SearchItem(
                    id=row[0],
                    path=row[1],
                    name=row[2],
                    size=row[3],
                    extension=row[4],
                    fileKind=row[5],
                    modificationDate=str(row[6]) if row[6] else None,
                )
                for row in rows
            ]

        except ConditionBuilderError as e:
            print(f"[SearchService] Condition error: {e}")
            return []
        except Exception as e:
            print(f"[SearchService] Search error: {e}")
            return []


# 싱글톤 인스턴스
_search_service: SearchService | None = None


def get_search_service() -> SearchService:
    """SearchService 싱글톤 반환"""
    global _search_service
    if _search_service is None:
        _search_service = SearchService()
    return _search_service
