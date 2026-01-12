from __future__ import annotations

from alembic import context
from sqlalchemy import create_engine
from sqlalchemy.engine import Engine
from sqlmodel import SQLModel

from infra.db.migrations.config import AlembicConfigKwargs, build_alembic_config
from infra.schemas import SCHEMAS

_LOADED_SCHEMAS = SCHEMAS

config = context.config
target_metadata = SQLModel.metadata

ALEMBIC_CONFIG: AlembicConfigKwargs = build_alembic_config(target_metadata=target_metadata)


def run_migrations_offline(url: str) -> None:
    """Offline 모드: 실제 DB 연결 없이 SQL만 생성"""

    context.configure(
        url=url,
        literal_binds=True,
        dialect_opts={"paramstyle": "named"},
        **ALEMBIC_CONFIG,
    )

    with context.begin_transaction():
        context.run_migrations()


def run_migrations_online(url: str) -> None:
    """Online 모드: 실제 DB에 연결하여 마이그레이션 실행"""

    engine: Engine = create_engine(url, echo=False)
    with engine.connect() as conn:
        context.configure(connection=conn, **ALEMBIC_CONFIG)
        with context.begin_transaction():
            context.run_migrations()


# Alembic 진입점
provided_conn = config.attributes.get("connection")

if provided_conn:
    # Bootstrap 경로: 환경 변수 기반 설정에서 connection 주입됨
    context.configure(connection=provided_conn, **ALEMBIC_CONFIG)
    with context.begin_transaction():
        context.run_migrations()
else:
    # CLI 경로: alembic.ini의 URL 사용 (dev 전용)
    url = config.get_main_option("sqlalchemy.url")
    if not url:
        raise RuntimeError("alembic.ini에 sqlalchemy.url이 설정되지 않았습니다.")
    if context.is_offline_mode():
        run_migrations_offline(url)
    else:
        run_migrations_online(url)
