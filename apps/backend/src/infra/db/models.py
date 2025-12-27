from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path


@dataclass
class DbConfig:
    """SQLite 데이터베이스 설정"""

    db_file: Path
    db_url: str
    echo: bool = False
    check_same_thread: bool = False
    migration_lock_name: str | None = None
    protocol: str = "sqlite:///"


@dataclass
class InitSummary:
    """DB 초기화 결과 요약"""

    db_file: Path
    ensured_dir: bool
    had_version_table: bool
    had_existing_tables: bool
    backup_path: Path | None
    stamped: bool
    upgraded: bool
    created_tables: bool
    current_rev: str | None
    head_rev: str | None


__all__ = ["DbConfig", "InitSummary"]
