"""Search API 엔드포인트"""

from fastapi import APIRouter, Depends

from app.search.schemas import (
    FilterSearchRequest,
    QuerySearchRequest,
    SearchResponse,
)
from app.search.services import SearchService, get_search_service

router = APIRouter(prefix="/search", tags=["search"])


@router.post("", response_model=SearchResponse)
async def query_search(
    request: QuerySearchRequest,
    service: SearchService = Depends(get_search_service),
) -> SearchResponse:
    """쿼리 기반 검색

    자연어 쿼리를 LLM이 해석하여 검색 조건으로 변환합니다.
    선택적으로 filters를 제공하면 scopes(경로 범위)가 적용됩니다.

    - **query**: 자연어 검색 쿼리 (필수)
    - **filters**: 선택적 필터 (scopes, conditions)
    """
    return await service.query_search(
        query=request.query,
        filters=request.filters,
        limit=50,
    )


@router.post("/filters", response_model=SearchResponse)
async def filter_search(
    request: FilterSearchRequest,
    service: SearchService = Depends(get_search_service),
) -> SearchResponse:
    """필터 기반 검색

    LLM 없이 제공된 필터를 직접 적용합니다.

    - **filters**: 검색 필터 (필수)
        - **scopes**: 검색 경로 범위
        - **conditions**: 검색 조건 목록
    """
    return await service.filter_search(
        filters=request.filters,
        limit=50,
    )
