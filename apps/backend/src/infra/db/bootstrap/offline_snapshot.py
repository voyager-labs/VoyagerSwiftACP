from __future__ import annotations

import sqlite3
from dataclasses import dataclass
from pathlib import Path
from typing import Sequence

from infra.db.migrations.config import ALEMBIC_VERSION_TABLE


@dataclass
class OfflineSnapshot:
    """엔진을 만들지 않고 SQLite 파일을 읽기 전용으로 조사한 스냅샷."""

    db_file: Path
    had_version_table: bool
    had_existing_tables: bool
    current_revision: str | None

    @classmethod
    def collect(cls, db_file: Path) -> OfflineSnapshot:
        had_version_table = cls._has_table(db_file, ALEMBIC_VERSION_TABLE)
        had_existing_tables = len(cls._list_user_tables(db_file)) > 0
        current_rev = cls._get_current_revision(db_file)
        return cls(
            db_file=db_file,
            had_version_table=had_version_table,
            had_existing_tables=had_existing_tables,
            current_revision=current_rev,
        )

    @staticmethod
    def _has_table(db_file: Path, name: str) -> bool:
        if not db_file.exists():
            return False
        try:
            uri = f"file:{db_file}?mode=ro"
            with sqlite3.connect(uri, uri=True) as conn:
                row = conn.execute(
                    "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
                    (name,),
                ).fetchone()
                return row is not None
        except Exception:
            return False

    @staticmethod
    def _list_user_tables(db_file: Path) -> Sequence[str]:
        if not db_file.exists():
            return []
        try:
            uri = f"file:{db_file}?mode=ro"
            with sqlite3.connect(uri, uri=True) as conn:
                rows = conn.execute(
                    f"SELECT name FROM sqlite_master WHERE type='table' AND name NOT IN ('sqlite_sequence', '{ALEMBIC_VERSION_TABLE}')"
                ).fetchall()
                return [str(r[0]) for r in rows]
        except Exception:
            return []

    @classmethod
    def _get_current_revision(cls, db_file: Path) -> str | None:
        if not cls._has_table(db_file, ALEMBIC_VERSION_TABLE):
            return None
        try:
            uri = f"file:{db_file}?mode=ro"
            with sqlite3.connect(uri, uri=True) as conn:
                row = conn.execute(
                    f"SELECT version_num FROM {ALEMBIC_VERSION_TABLE} ORDER BY rowid DESC LIMIT 1"
                ).fetchone()
                return str(row[0]) if row and row[0] is not None else None
        except Exception:
            return None


__all__ = ["OfflineSnapshot"]
