from __future__ import annotations

from pathlib import Path

from omegaconf import DictConfig


def resolve_db_file_path(cfg: DictConfig) -> Path:
    """Hydra 설정에서 SQLite 파일 경로를 확장합니다."""
    return Path(str(cfg.db.file)).expanduser()


def ensure_parent_dir(path: Path) -> bool:
    """경로 상위 디렉터리가 없으면 생성합니다.

    Returns:
        True if directory created, False if already existed.
    """
    parent = path.expanduser().resolve().parent
    if parent.exists():
        return False
    parent.mkdir(parents=True, exist_ok=True)
    return True


def resolve_migration_lock_path(cfg: DictConfig, db_file: Path) -> Path | None:
    """마이그레이션 락 파일 경로를 계산합니다."""
    lock_cfg = cfg.db.get("lock_file") if hasattr(cfg.db, "get") else None
    if not lock_cfg:
        return None

    lock_name = lock_cfg.get("migration_lock") if hasattr(lock_cfg, "get") else None
    if not lock_name:
        return None

    candidate = Path(str(lock_name)).expanduser()
    if not candidate.is_absolute():
        candidate = db_file.expanduser().resolve().parent / candidate
    return candidate


__all__ = ["resolve_db_file_path", "ensure_parent_dir", "resolve_migration_lock_path"]
