from __future__ import annotations

import os
import shutil
from contextlib import contextmanager, nullcontext
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Iterator

from alembic import command
from alembic.config import Config
from alembic.script import ScriptDirectory
from omegaconf import DictConfig
from sqlalchemy.engine import Engine

from infra.db.bootstrap.offline_snapshot import OfflineSnapshot
from infra.db.engine import EngineManager
from infra.db.engine import engine_manager as _engine_manager
from infra.db.migrations.config import (
    get_alembic_config_from_hydra,
    is_current_at_or_ancestor_of_head,
)
from infra.db.utils import ensure_parent_dir, resolve_db_file_path, resolve_migration_lock_path


@dataclass
class InitSummary:
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


@contextmanager
def _migration_lock(lock_path: Path) -> Iterator[None]:
    locked = False
    ensure_parent_dir(lock_path)
    try:
        with lock_path.open("x", encoding="utf-8") as fh:
            fh.write(
                f"pid={os.getpid()} timestamp={datetime.now().isoformat()}\n"
                "This lock ensures a single migration/initialization runs at a time.\n"
            )
        locked = True
        yield
    except FileExistsError as exc:  # pragma: no cover - 동시 실행 방지용 가드
        raise RuntimeError(
            f"Migration lock file already exists: {lock_path}. "
            "Another initialization may be running."
        ) from exc
    finally:
        if locked:
            lock_path.unlink()
            # TODO: logger 세팅


def _backup_db_file(db_file: Path) -> Path:
    # TODO: 프로덕션 백업 파일 경로 재확인
    timestamp = datetime.now().strftime("%Y%m%d%H%M%S")
    backup = db_file.with_suffix(db_file.suffix + f".bak.{timestamp}")
    shutil.copy2(db_file, backup)
    return backup


def _bootstrap_unversioned_db(
    *,
    db_file: Path,
    snapshot: OfflineSnapshot,
    db_manager: EngineManager,
    engine: Engine,
    alembic_cfg: Config,
) -> tuple[bool, bool, Path | None]:
    backup_path: Path | None = None
    created_tables = False

    if snapshot.had_existing_tables and db_file.exists():
        backup_path = _backup_db_file(db_file)
        # TODO: logger 세팅

    if not snapshot.had_existing_tables:
        db_manager.create_tables()
        created_tables = True

    with engine.connect() as conn:
        alembic_cfg.attributes["connection"] = conn
        command.stamp(alembic_cfg, "head")

    return True, created_tables, backup_path


def _upgrade_to_head_if_needed(
    *,
    snapshot: OfflineSnapshot,
    alembic_cfg: Config,
    script_dir: ScriptDirectory,
    engine: Engine,
    head_rev: str | None,
) -> bool:
    needs_upgrade = not is_current_at_or_ancestor_of_head(
        script_dir, snapshot.current_revision, head_rev
    )
    if not needs_upgrade:
        return False

    with engine.connect() as conn:
        alembic_cfg.attributes["connection"] = conn
        command.upgrade(alembic_cfg, "head")

    return True


def initialize_sqlite_db(cfg: DictConfig, manager: EngineManager | None = None) -> InitSummary:
    """SQLite 데이터베이스를 사용 가능한 상태로 맞춥니다(idempotent).

    - TODO: 시나리오별 테스트 추가 필요
    """

    db_file = resolve_db_file_path(cfg)
    lock_path = resolve_migration_lock_path(cfg, db_file)
    lock_ctx = _migration_lock(lock_path) if lock_path is not None else nullcontext()

    with lock_ctx:
        initial_snapshot = OfflineSnapshot.collect(db_file)

        backup_path: Path | None = None
        stamped = False
        upgraded = False
        created_tables = False

        alembic_cfg = get_alembic_config_from_hydra(cfg)
        script_dir = ScriptDirectory.from_config(alembic_cfg)
        head_rev = script_dir.get_current_head()

        ensured_dir = ensure_parent_dir(db_file)
        db_manager = manager or _engine_manager
        if not db_manager.is_initialized:
            db_manager.initialize(cfg)
        engine = db_manager.engine

        if not initial_snapshot.had_version_table:
            stamped, created_tables, backup_path = _bootstrap_unversioned_db(
                db_file=db_file,
                snapshot=initial_snapshot,
                db_manager=db_manager,
                engine=engine,
                alembic_cfg=alembic_cfg,
            )
        else:
            upgraded = _upgrade_to_head_if_needed(
                snapshot=initial_snapshot,
                alembic_cfg=alembic_cfg,
                script_dir=script_dir,
                engine=engine,
                head_rev=head_rev,
            )

        final_snapshot = OfflineSnapshot.collect(db_file)

        # TODO: logger 세팅

        return InitSummary(
            db_file=db_file,
            ensured_dir=ensured_dir,
            had_version_table=final_snapshot.had_version_table,
            had_existing_tables=final_snapshot.had_existing_tables,
            backup_path=backup_path,
            stamped=stamped,
            upgraded=upgraded,
            created_tables=created_tables,
            current_rev=final_snapshot.current_revision,
            head_rev=head_rev,
        )


__all__ = ["initialize_sqlite_db", "InitSummary"]
