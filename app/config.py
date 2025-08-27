import os
from pathlib import Path

from dotenv import load_dotenv
from hydra import compose
from hydra.initialize import initialize_config_dir
from omegaconf import DictConfig

# TODO: 현재 Path(__file__) 기반 프로젝트 루트와 그 외 경로 탐색을 좀 더 프로그래머블하게 수정하기
PROJECT_ROOT: Path = Path(__file__).resolve().parent.parent
CONF_DIR: Path = PROJECT_ROOT / "conf"
ENV_FILE: Path = PROJECT_ROOT / ".env"


def load_local_env() -> None:
    """.env 파일에서 환경 변수를 로드"""
    load_dotenv(dotenv_path=ENV_FILE, override=False)


def infer_env() -> str:
    """환경 변수 추론

    1) APP_ENV 환경 변수가 있으면 그 값을 사용
    2) .env 파일이 프로젝트 루트에 있으면 dev 환경 사용
    3) 그 외의 경우에는 prod 환경 사용
    """
    app_env = os.getenv("APP_ENV")
    if app_env:
        return app_env
    if ENV_FILE.exists():
        return "dev"
    return "prod"


def load_hydra_config(app_env: str | None = None) -> DictConfig:
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
    load_local_env()
    env_name = infer_env()
    return load_hydra_config(env_name)


__all__ = [
    "PROJECT_ROOT",
    "CONF_DIR",
    "ENV_FILE",
    "load_local_env",
    "infer_env",
    "load_hydra_config",
    "load_config",
]
