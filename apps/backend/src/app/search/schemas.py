"""Search API 스키마 정의"""

from pydantic import BaseModel, Field


class SearchCondition(BaseModel):
    """단일 검색 조건"""

    propertyKey: str = Field(..., description="속성 키 (예: size, extension)")
    operator: str = Field(..., description="연산자 (eq, gt, gte, lt, lte, between, contains, in)")
    value: str | int | float | list[str] | list[int] | list[float] = Field(
        ..., description="값 (단일값, 배열, [min, max])"
    )


class SearchFilters(BaseModel):
    """검색 필터"""

    scopes: list[str] = Field(default_factory=list, description="검색 경로 범위")
    conditions: list[SearchCondition] = Field(
        default_factory=list, description="검색 조건 목록"
    )


class QuerySearchRequest(BaseModel):
    """POST /api/search 요청"""

    query: str = Field(..., min_length=1, description="자연어 검색 쿼리")
    filters: SearchFilters | None = Field(None, description="선택적 필터")


class FilterSearchRequest(BaseModel):
    """POST /api/search/filters 요청"""

    filters: SearchFilters = Field(..., description="필수 필터")


class SearchItem(BaseModel):
    """검색 결과 아이템"""

    id: int
    path: str
    name: str
    size: int
    extension: str | None = None
    fileKind: str | None = None
    modificationDate: str | None = None


class AppliedFilters(BaseModel):
    """적용된 필터"""

    scopes: list[str] = Field(default_factory=list)
    conditions: list[SearchCondition] = Field(default_factory=list)


class SearchResponse(BaseModel):
    """검색 응답"""

    itemCount: int
    appliedFilters: AppliedFilters
    items: list[SearchItem]
