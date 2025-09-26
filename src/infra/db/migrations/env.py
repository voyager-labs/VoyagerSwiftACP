from __future__ import annotations

from alembic import context
from sqlalchemy.engine import Connection, Engine
from sqlmodel import SQLModel

from app.config import load_config
from infra.db.engine import engine_manager
from infra.db.migrations.config import AlembicConfigKwargs, build_alembic_config
from infra.db.utils import resolve_db_file_path
from infra.schemas import SCHEMAS

_LOADED_SCHEMAS = SCHEMAS

config = context.config
target_metadata = SQLModel.metadata

ALEMBIC_CONFIG: AlembicConfigKwargs = build_alembic_config(target_metadata=target_metadata)


def run_migrations_offline() -> None:
    cfg = load_config()
    protocol: str = str(cfg.db.protocol)
    db_file_path = resolve_db_file_path(cfg)
    url = f"{protocol}{db_file_path}"

    config.set_main_option("sqlalchemy.url", url)

    context.configure(
        url=url,
        literal_binds=True,
        dialect_opts={"paramstyle": "named"},
        **ALEMBIC_CONFIG,
    )

    with context.begin_transaction():
        context.run_migrations()


def run_migrations_online() -> None:
    """Run migrations in 'online' mode' using the **application's Engine only**.

    This ensures PRAGMA/serializer settings match the runtime exactly.
    """
    provided_conn: Connection | None = config.attributes.get("connection")

    if provided_conn is not None:
        context.configure(
            connection=provided_conn,
            **ALEMBIC_CONFIG,
        )
        with context.begin_transaction():
            context.run_migrations()
        return

    hydra_cfg = load_config()
    engine_manager.initialize(hydra_cfg)
    engine: Engine = engine_manager.engine
    with engine.connect() as connectable:
        context.configure(
            connection=connectable,
            **ALEMBIC_CONFIG,
        )
        with context.begin_transaction():
            context.run_migrations()


if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()
