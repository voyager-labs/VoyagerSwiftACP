"""Search API 스키마 정의"""

from __future__ import annotations

from pydantic import BaseModel, Field, field_validator


def _empty_conditions() -> list[SearchCondition]:
    return []


class SearchCondition(BaseModel):
    """단일 검색 조건"""

    propertyKey: str = Field(
        ..., description="속성 키 (예: name_full, content_type_tree, file_allocated_size)"
    )
    operator: str = Field(
        ...,
        description=(
            "연산자 (eq, neq, gt, gte, lt, lte, btw, nbtw, sw, ew, rx, cn, nc, "
            "any, all, none, miss, empty, exists)"
        ),
    )
    value: str | int | float | list[str] | list[int] | list[float] | None = Field(
        None, description="값 (단일값, 배열, [min, max]) - empty/exists는 생략 가능"
    )


class SearchFilters(BaseModel):
    """검색 필터"""

    scopes: list[str] = Field(default_factory=list, description="검색 경로 범위")
    conditions: list[SearchCondition] = Field(
        default_factory=_empty_conditions,
        description="검색 조건 목록",
    )


class QuerySearchRequest(BaseModel):
    """POST /api/collection 요청"""

    query: str = Field(..., min_length=1, description="자연어 검색 쿼리")
    filters: SearchFilters | None = Field(None, description="선택적 필터")

    @field_validator("query")
    @classmethod
    def validate_query(cls, value: str) -> str:
        trimmed = value.strip()
        if not trimmed:
            raise ValueError("query는 공백만 포함할 수 없습니다.")
        return trimmed


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
    conditions: list[SearchCondition] = Field(default_factory=_empty_conditions)


class SearchError(BaseModel):
    """검색 오류 메타"""

    code: str = Field(..., description="오류 코드")
    details: str | None = Field(None, description="오류 상세")


class SearchResponse(BaseModel):
    """검색 응답"""

    itemCount: int
    appliedFilters: AppliedFilters
    items: list[SearchItem]
    error: SearchError | None = None
