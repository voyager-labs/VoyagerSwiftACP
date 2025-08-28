import os
from pathlib import Path

from dotenv import load_dotenv
from hydra import compose
from hydra.initialize import initialize_config_dir
from omegaconf import DictConfig

from utils.paths import get_source_path

SOURCE_DIR: Path = get_source_path()
CONF_DIR: Path = SOURCE_DIR / "conf"


def load_hydra_config() -> DictConfig:
    app_env = os.getenv("APP_ENV")
    overrides = [f"env={app_env}"] if app_env else []
    try:
        with initialize_config_dir(config_dir=str(CONF_DIR), version_base=None):
            cfg = compose(config_name="config", overrides=overrides)
    except Exception as exc:  # pragma: no cover - defensive
        details = {
            "conf_dir": str(CONF_DIR),
            "app_env": app_env,
            "overrides": overrides,
        }
        raise RuntimeError(f"Failed to compose Hydra config: {details}") from exc
    return cfg


def load_config() -> DictConfig:
    load_dotenv(override=False)
    return load_hydra_config()


__all__ = [
    "SOURCE_DIR",
    "CONF_DIR",
    "ENV_FILE",
    "load_hydra_config",
    "load_config",
]
