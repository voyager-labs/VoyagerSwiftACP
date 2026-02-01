from __future__ import annotations

from collections.abc import Iterator
from contextlib import contextmanager

import pytest
from sqlmodel import Field, SQLModel, Session, create_engine

from core.search import ConditionBuilder, ScopeBuilder, execute_search
from core.search.condition_builder import ConditionBuilderError


class EntryRow(SQLModel, table=True):
    __tablename__ = "test_entries"

    id: int | None = Field(default=None, primary_key=True)
    dir_path: str
    name_full: str
    name_stem: str


@contextmanager
def _session_context() -> Iterator[Session]:
    engine = create_engine("sqlite://", echo=False)
    SQLModel.metadata.create_all(engine)
    with Session(engine) as session:
        session.add_all(
            [
                EntryRow(
                    dir_path="/Users/foo/Downloads",
                    name_full="report.pdf",
                    name_stem="report",
                ),
                EntryRow(
                    dir_path="/Users/foo/Documents",
                    name_full="notes.txt",
                    name_stem="notes",
                ),
            ]
        )
        session.commit()
        yield session


@pytest.mark.anyio
async def test_execute_search_filters_by_scope_and_condition() -> None:
    results = await execute_search(
        model=EntryRow,
        session_context=_session_context,
        scopes=["/Users/foo/Downloads"],
        conditions=[{"propertyKey": "name_stem", "operator": "cn", "value": "report"}],
        scope_builder=ScopeBuilder(),
        condition_builder=ConditionBuilder(),
    )

    assert len(results) == 1
    assert results[0].name_full == "report.pdf"


@pytest.mark.anyio
async def test_execute_search_raises_on_invalid_condition() -> None:
    with pytest.raises(ConditionBuilderError):
        await execute_search(
        model=EntryRow,
            session_context=_session_context,
            scopes=[],
            conditions=[{"propertyKey": "name_stem", "operator": "unknown", "value": "x"}],
            scope_builder=ScopeBuilder(),
            condition_builder=ConditionBuilder(),
        )


@pytest.fixture
def anyio_backend() -> str:
    return "asyncio"
