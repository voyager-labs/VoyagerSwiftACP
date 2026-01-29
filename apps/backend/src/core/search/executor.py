"""Search executor

Scope/condition builder 결과로 SQLModel SELECT를 실행합니다.

- core는 app/infra 스키마에 의존하지 않도록 모델/세션을 주입받습니다.
- TODO: Swift Voyager Helper로 이관 [VOY-152]
- TODO: Swift Voyager Helper 이관 시 SQL 구문을 문자열로 반환하는 대신, Swift의 ORM 쿼리 객체를 반환하도록 변경
"""

from __future__ import annotations

import asyncio
from collections.abc import Callable
from contextlib import AbstractContextManager
from typing import Any, TypeVar

from sqlalchemy import text
from sqlmodel import Session, SQLModel, select

from core.search.condition_builder import ConditionBuilder
from core.search.scope_builder import ScopeBuilder

_TModel = TypeVar("_TModel", bound=SQLModel)
_SessionContext = Callable[[], AbstractContextManager[Session]]


async def execute_search(
    *,
    model: type[_TModel],
    session_context: _SessionContext,
    scopes: list[str],
    conditions: list[dict[str, Any]],
    scope_builder: ScopeBuilder | None = None,
    condition_builder: ConditionBuilder | None = None,
) -> list[_TModel]:
    """검색 조건/스코프로 SELECT를 실행합니다.

    Note:
        - DB 세션은 sync이므로 asyncio.to_thread로 실행합니다.
        - 오류 매핑(SearchError)은 app 계층에서 처리합니다.
    """

    scope_builder = scope_builder or ScopeBuilder()
    condition_builder = condition_builder or ConditionBuilder()

    scope_clause, scope_params = scope_builder.build_scope_clause(scopes)
    condition_clause, condition_params = condition_builder.build_where(conditions)

    where_clause = f"{scope_clause} AND {condition_clause}"
    all_params: dict[str, Any] = {**scope_params, **condition_params}

    def _run_query() -> list[_TModel]:
        where_text = text(where_clause).bindparams(**all_params)
        statement = select(model).where(where_text)
        with session_context() as session:
            result = session.exec(statement)
            return list(result.all())

    return await asyncio.to_thread(_run_query)
