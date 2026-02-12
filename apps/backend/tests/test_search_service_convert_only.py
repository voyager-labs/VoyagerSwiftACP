from __future__ import annotations

from typing import Any

import pytest

from app.search.schemas import SearchCondition, SearchFilters
from app.search.services import SearchService
from core.llm.search_condition_converter import (
    CachedSearchConditionConverter,
    SearchConditionPayload,
    SearchConversionResult,
)


class _FakeCachedConverter(CachedSearchConditionConverter):
    def __init__(self, result: SearchConversionResult):
        self._result = result
        self.calls: list[tuple[str, list[dict[str, Any]] | None, list[str] | None]] = []

    async def convert(
        self,
        query: str,
        existing_conditions: list[dict[str, Any]] | None = None,
        existing_scopes: list[str] | None = None,
    ) -> SearchConversionResult:
        self.calls.append((query, existing_conditions, existing_scopes))
        return self._result


class _TestSearchService(SearchService):
    def __init__(self, fake_converter: CachedSearchConditionConverter):
        super().__init__()
        self.fake_converter = fake_converter

    @property
    def converter(self) -> CachedSearchConditionConverter:
        return self.fake_converter


@pytest.mark.anyio
async def test_query_search_returns_convert_only_response() -> None:
    fake_converter = _FakeCachedConverter(
        result=SearchConversionResult(
            conditions=[
                SearchConditionPayload(propertyKey="name_stem", operator="cn", value="report"),
            ],
            scopes=["/Users/foo/Downloads"],
            error=None,
        )
    )
    service = _TestSearchService(fake_converter)

    response = await service.query_search(
        query="report 파일",
        filters=SearchFilters(
            scopes=["/Users/foo"],
            conditions=[SearchCondition(propertyKey="extension", operator="eq", value="pdf")],
        ),
    )

    assert response.itemCount == 0
    assert response.items == []
    assert response.error is None
    assert response.appliedFilters.scopes == ["/Users/foo/Downloads"]
    assert len(response.appliedFilters.conditions) == 1
    assert response.appliedFilters.conditions[0].propertyKey == "name_stem"
    assert fake_converter.calls == [
        (
            "report 파일",
            [{"propertyKey": "extension", "operator": "eq", "value": "pdf"}],
            ["/Users/foo"],
        )
    ]


@pytest.mark.anyio
async def test_query_search_returns_llm_error_with_existing_filters() -> None:
    fake_converter = _FakeCachedConverter(
        result=SearchConversionResult(
            conditions=[],
            scopes=None,
            error="gateway timeout",
        )
    )
    service = _TestSearchService(fake_converter)

    response = await service.query_search(
        query="timeout case",
        filters=SearchFilters(
            scopes=["/Users/foo/Desktop"],
            conditions=[SearchCondition(propertyKey="name_stem", operator="cn", value="draft")],
        ),
    )

    assert response.itemCount == 0
    assert response.items == []
    assert response.error is not None
    assert response.error.code == "LLM_CONVERSION_FAILED"
    assert response.error.details == "gateway timeout"
    assert response.appliedFilters.scopes == ["/Users/foo/Desktop"]
    assert len(response.appliedFilters.conditions) == 1
    assert response.appliedFilters.conditions[0].propertyKey == "name_stem"


@pytest.fixture
def anyio_backend() -> str:
    return "asyncio"
