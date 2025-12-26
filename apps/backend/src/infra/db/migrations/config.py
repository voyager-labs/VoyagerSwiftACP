from __future__ import annotations

from pathlib import Path
from typing import Required, TypedDict, Union

from alembic.config import Config
from alembic.script import ScriptDirectory
from alembic.script.revision import ResolutionError, Revision
from sqlalchemy.sql.schema import MetaData


class AlembicConfigKwargs(TypedDict, total=False):
    """공유 Alembic 설정 딕셔너리 형식."""

    target_metadata: Union[MetaData, list[MetaData], None]
    render_as_batch: bool
    compare_type: bool
    compare_server_default: bool
    version_table: Required[str]


ALEMBIC_VERSION_TABLE = "migration_version"


def _find_alembic_ini() -> Path:
    """현재 파일 위치에서 상위 디렉토리를 재귀적으로 탐색하여 alembic.ini를 찾습니다.
    Returns:
        alembic.ini 파일 경로

    Raises:
        FileNotFoundError: alembic.ini를 찾을 수 없을 때
    """
    ALEMBIC_INI_NAME = "alembic.ini"
    MAX_SEARCH_DEPTH = 5

    current = Path(__file__).resolve().parent
    for _ in range(MAX_SEARCH_DEPTH):
        candidate = current / ALEMBIC_INI_NAME
        if candidate.exists():
            return candidate
        if current.parent == current:
            break
        current = current.parent

    raise FileNotFoundError(f"{ALEMBIC_INI_NAME}를 찾을 수 없습니다. 파일 위치를 확인하세요.")


def build_alembic_config(
    *, target_metadata: Union[MetaData, list[MetaData], None]
) -> AlembicConfigKwargs:
    """애플리케이션 표준 Alembic 구성 값을 생성합니다."""

    return {
        "target_metadata": target_metadata,
        "render_as_batch": True,  # SQLite 친화적인 DDL
        "compare_type": True,  # autogenerate: 타입 변경 감지
        "compare_server_default": True,  # autogenerate: 서버 기본값 변경 감지
        "version_table": ALEMBIC_VERSION_TABLE,
    }


def get_alembic_config(*, db_url: str) -> Config:
    """DB URL을 받아 런타임 Alembic Config를 생성합니다.

    Args:
        db_url: SQLAlchemy 형식의 데이터베이스 URL (예: "sqlite:///voyager.db")

    Returns:
        Alembic Config 객체
    """
    alembic_ini = _find_alembic_ini()
    alembic_cfg = Config(str(alembic_ini))
    alembic_cfg.set_main_option("sqlalchemy.url", db_url)
    return alembic_cfg


def is_current_at_or_ancestor_of_head(
    script: ScriptDirectory, current_rev: str | None, head_rev: str | None
) -> bool:
    """현재 리비전이 head 또는 그 조상인지 검사합니다."""

    if not head_rev:
        return True
    if not current_rev:
        return False

    try:
        head = script.get_revision(head_rev)
    except ResolutionError as exc:
        raise RuntimeError(f"Alembic head revision not found: {head_rev}") from exc

    seen: set[str] = set()
    stack: list[Revision] = [head]

    # TODO: 더 나은 revision 검사 로직이 있을지 확인 필요
    while stack:
        rev = stack.pop()
        if rev.revision in seen:
            continue
        if rev.revision == current_rev:
            return True
        seen.add(rev.revision)
        down = rev.down_revision
        if down is None:
            continue
        if isinstance(down, (list, tuple)):
            for d in down:
                try:
                    node = script.get_revision(d)
                except ResolutionError:
                    continue
                stack.append(node)
        else:
            try:
                node = script.get_revision(down)
            except ResolutionError:
                continue
            stack.append(node)
    return False


__all__ = [
    "ALEMBIC_VERSION_TABLE",
    "AlembicConfigKwargs",
    "build_alembic_config",
    "is_current_at_or_ancestor_of_head",
    "get_alembic_config",
]
