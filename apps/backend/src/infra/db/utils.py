from __future__ import annotations

from pathlib import Path


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


def resolve_migration_lock_path(lock_name: str | None, db_file: Path) -> Path | None:
    """마이그레이션 락 파일 경로를 계산합니다.

    Args:
        lock_name: 락 파일 이름 (예: ".migration.lock") 또는 None
        db_file: 데이터베이스 파일 경로,

    Returns:
        락 파일의 절대 경로 또는 None
    """
    if not lock_name:
        return None

    candidate = Path(lock_name).expanduser()
    if not candidate.is_absolute():
        candidate = db_file.expanduser().resolve().parent / candidate
    return candidate


__all__ = ["ensure_parent_dir", "resolve_migration_lock_path"]
