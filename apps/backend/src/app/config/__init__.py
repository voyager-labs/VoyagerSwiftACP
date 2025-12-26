from __future__ import annotations

import os
from pathlib import Path

from dotenv import find_dotenv, load_dotenv
from hydra import compose
from hydra.initialize import initialize_config_dir
from omegaconf import DictConfig

from infra.db.models import DbConfig


def load_hydra_config(app_env: str) -> DictConfig:
    overrides = [f"env={app_env}"] if app_env else []
    config_dir = Path(__file__).resolve().parent

    try:
        with initialize_config_dir(config_dir=str(config_dir), version_base=None):
            cfg = compose(config_name="config", overrides=overrides)
    except Exception as exc:  # pragma: no cover - defensive
        details = {
            "config_dir": str(config_dir),
            "app_env": app_env,
            "overrides": overrides,
        }
        raise RuntimeError(f"Failed to compose Hydra config: {details}") from exc
    return cfg


def load_config() -> DictConfig:
    app_env = os.getenv("APP_ENV", "dev")
    env_file = find_dotenv(filename=f".env.{app_env}")
    load_dotenv(dotenv_path=env_file, override=False)
    return load_hydra_config(app_env)


def get_db_config(cfg: DictConfig) -> DbConfig:
    """Hydra 설정에서 DB 초기화용 설정을 추출합니다.

    DB 경로는 Hydra의 db/sqlite.yaml에서 관리됩니다 (SSOT).

    Args:
        cfg: Hydra DictConfig

    Returns:
        DbConfig: infra 레이어에서 사용할 primitive 기반 설정
    """
    # DB 파일 경로 해석
    db_file = Path(str(cfg.db.file)).expanduser()

    # DB URL: Hydra 설정에서 구성 (SSOT)
    db_url = f"{cfg.db.protocol}{db_file}"

    # Lock 파일 설정 추출
    lock_cfg = cfg.db.get("lock_file") if hasattr(cfg.db, "get") else None
    migration_lock_name: str | None = None
    if lock_cfg:
        migration_lock_name = lock_cfg.get("migration_lock") if hasattr(lock_cfg, "get") else None

    return DbConfig(
        db_file=db_file,
        db_url=db_url,
        echo=bool(cfg.db.echo),
        check_same_thread=bool(cfg.db.check_same_thread),
        migration_lock_name=migration_lock_name,
        protocol=str(cfg.db.protocol),
    )


__all__ = [
    "load_config",
    "get_db_config",
]
