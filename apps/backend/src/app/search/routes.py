"""Search API 엔드포인트"""

from fastapi import APIRouter, Depends

from app.search.schemas import (
    QuerySearchRequest,
    SearchResponse,
)
from app.search.services import SearchService, get_search_service

router = APIRouter(prefix="/collection", tags=["collection"])


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
    )
