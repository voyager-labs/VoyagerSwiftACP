from __future__ import annotations

import sqlite3
from contextlib import contextmanager
from threading import Lock
from typing import Any, Callable, Iterator

import orjson
from sqlalchemy import text
from sqlalchemy.engine import Engine
from sqlalchemy.orm import sessionmaker
from sqlmodel import Session, SQLModel, create_engine

from infra.db.models import DbConfig
from infra.schemas import SCHEMAS

_LOADED_SCHEMAS = SCHEMAS


class EngineManager:
    """SQLite 엔진/세션 관리를 책임지는 객체."""

    def __init__(self) -> None:
        self._engine: Engine | None = None
        self._session_factory: Callable[[], Session] | None = None
        self._max_variables: int | None = None
        self._lock = Lock()

    def initialize(self, cfg: DbConfig) -> None:
        """DbConfig로 엔진/세션팩토리를 초기화합니다.

        - sqlite3 "creator" 콜백으로 새 연결마다 PRAGMA를 적용합니다:
          foreign_keys=ON, journal_mode=WAL(기존이 아니면 전환), WAL일 때 synchronous=NORMAL.

        Args:
            cfg: DB 설정 (primitive 값만 포함)
        """
        if self._engine is not None:
            return

        with self._lock:
            if self._engine is not None:
                return

            db_file_path = cfg.db_file.expanduser().resolve()
            echo = cfg.echo
            check_same_thread = cfg.check_same_thread

            def _creator() -> Any:  # pragma: no cover
                conn = sqlite3.connect(db_file_path, check_same_thread=check_same_thread)
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

            json_serializer: Callable[[Any], str] = lambda obj: orjson.dumps(
                obj, option=orjson.OPT_NAIVE_UTC | orjson.OPT_UTC_Z
            ).decode()

            engine: Engine = create_engine(
                cfg.protocol,
                echo=echo,
                creator=_creator,
                json_serializer=json_serializer,
                json_deserializer=orjson.loads,
            )

            SessionLocal = sessionmaker(bind=engine, class_=Session, expire_on_commit=False)
            self._engine = engine
            self._session_factory = lambda: SessionLocal()

            self._load_max_variables(engine)

    @property
    def engine(self) -> Engine:
        """초기화된 SQLAlchemy 엔진을 반환"""
        if self._engine is None:
            raise RuntimeError("DB is not initialized. Call EngineManager.initialize(cfg) first.")
        return self._engine

    @property
    def max_variables(self) -> int:
        """SQLite 변수 한도(예: 999) 캐시"""
        if self._max_variables is None:
            raise RuntimeError("DB is not initialized. Call EngineManager.initialize(cfg) first.")
        return self._max_variables

    @property
    def is_initialized(self) -> bool:
        return self._engine is not None

    def create_tables(self) -> None:
        """모든 SQLModel 테이블 생성(존재하면 무시됨)"""
        SQLModel.metadata.create_all(self.engine)

    @contextmanager
    def session(self, autocommit: bool = True) -> Iterator[Session]:
        """컨텍스트 매니저: 정상 종료 시 commit, 예외 시 rollback
        - autocommit=True(기본): 블록이 정상 종료되면 commit, 예외 시 rollback.
        - autocommit=False: commit을 수행하지 않음(읽기 전용).

        예시
        ```python
            with engine_manager.session(autocommit=False) as session:  # 읽기 전용
                ...
            with engine_manager.session() as session:  # 쓰기 작업
                ...
        ```
        """
        if self._session_factory is None:
            raise RuntimeError("DB is not initialized. Call EngineManager.initialize(cfg) first.")
        session = self._session_factory()
        try:
            yield session
            if autocommit:
                session.commit()
        except Exception:
            session.rollback()
            raise
        finally:
            session.close()

    def dispose(self) -> None:
        with self._lock:
            if self._engine is not None:
                self._engine.dispose()
            self._engine = None
            self._session_factory = None
            self._max_variables = None

    def _load_max_variables(self, engine: Engine) -> None:
        """SQLite 변수 한도(PRAGMA max_variable_number)를 조회해 캐시합니다."""

        try:
            with engine.connect() as conn:
                val = conn.execute(text("PRAGMA max_variable_number")).scalar()
                self._max_variables = int(val) if isinstance(val, int) and val > 0 else 999
        except Exception:  # pragma: no cover - 환경별 PRAGMA 차이에 대한 방어적 폴백
            self._max_variables = 999


engine_manager = EngineManager()


__all__ = [
    "EngineManager",
    "engine_manager",
]
