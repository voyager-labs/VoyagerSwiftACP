from __future__ import annotations

import sqlite3
from contextlib import contextmanager
from typing import Any, Callable, Iterator

from omegaconf import DictConfig
from sqlalchemy.engine import Engine
from sqlalchemy.orm import sessionmaker
from sqlmodel import Session, SQLModel, create_engine

_engine: Engine | None = None
_session_factory: Callable[[], Session] | None = None


def init_engine(cfg: DictConfig) -> None:
    """Hydra 설정으로 엔진/세션팩토리를 초기화

    - 여러 번 호출되어도 최초 한 번만 초기화(idempotent).
    - sqlite3 "creator" 콜백으로 새 연결마다 PRAGMA를 적용합니다: foreign_keys=ON, journal_mode=WAL(기존이 아니면 전환), WAL일 때 synchronous=NORMAL.
    - 생성된 sessionmaker는 get_db_session()에서 사용됩니다.
    """
    global _engine, _session_factory
    if _engine is not None:
        return

    file_name: str = str(cfg.db.file)
    echo: bool = bool(cfg.db.echo)
    check_same_thread: bool = bool(cfg.db.check_same_thread)

    def _creator() -> Any:  # pragma: no cover
        conn = sqlite3.connect(file_name, check_same_thread=check_same_thread)
        try:
            cur = conn.cursor()
            cur.execute("PRAGMA foreign_keys=ON;")
            row = cur.execute("PRAGMA journal_mode;").fetchone()
            mode = (row[0] if row else "").lower()
            if mode != "wal":
                mode = cur.execute("PRAGMA journal_mode=WAL;").fetchone()[0].lower()
            if mode == "wal":
                cur.execute("PRAGMA synchronous=NORMAL;")
            cur.close()
        except Exception:
            pass
        return conn

    engine: Engine = create_engine(str(cfg.db.url), echo=echo, creator=_creator)

    SessionLocal = sessionmaker(bind=engine, class_=Session, expire_on_commit=False)
    _engine = engine
    _session_factory = lambda: SessionLocal()


def create_tables() -> None:
    """모든 SQLModel 테이블 생성(존재하면 무시됨)"""
    if _engine is None:
        raise RuntimeError("DB is not initialized. Call init_engine(cfg) first.")

    SQLModel.metadata.create_all(_engine)


@contextmanager
def get_db_session(autocommit: bool = True) -> Iterator[Session]:
    """컨텍스트 매니저로 DB 세션 제공

    - autocommit=True(기본): 블록이 정상 종료되면 commit, 예외 시 rollback.
    - autocommit=False: commit을 수행하지 않음(읽기 전용).

    예시
        with get_db_session(autocommit=False) as session:  # 읽기 전용
            ...
        with get_db_session() as session:  # 쓰기 작업
            ...
    """
    if _session_factory is None:
        raise RuntimeError("DB is not initialized. Call init_engine(cfg) first.")
    session = _session_factory()
    try:
        yield session
        if autocommit:
            session.commit()
    except Exception:
        session.rollback()
        raise
    finally:
        session.close()


__all__ = [
    "init_engine",
    "create_tables",
    "get_db_session",
]
