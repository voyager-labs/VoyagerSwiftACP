from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path
from typing import Literal

from dotenv import find_dotenv, load_dotenv

from infra.db.models import DbConfig


@dataclass
class VoyagerConfig:
    """환경 변수 기반 설정 (.env 파일 구조 그대로 반영)"""

    # App 기본 설정
    app_name: str  # PUBLIC_APP_NAME
    app_env: Literal["dev", "prod"]  # APP_ENV
    log_level: str  # PUBLIC_LOG_LEVEL

    # Gateway/Web 설정
    gateway_url: str  # PUBLIC_GATEWAY_URL
    web_base_url: str  # PUBLIC_WEB_BASE_URL

    # SQLite 설정
    sqlite_protocol: str  # PUBLIC_SQLITE_PROTOCOL
    sqlite_echo: bool  # PUBLIC_SQLITE_ECHO
    sqlite_check_same_thread: bool  # PUBLIC_SQLITE_CHECK_SAME_THREAD
    sqlite_file_location: str  # PUBLIC_SQLITE_FILE_LOCATION
    sqlite_file_name: str  # PUBLIC_SQLITE_FILE_NAME

    def get_db_config(self) -> DbConfig:
        """DbConfig 인스턴스 생성"""
        location = Path(self.sqlite_file_location).expanduser()
        db_file = location / self.sqlite_file_name

        return DbConfig(
            db_file=db_file,
            db_url=f"{self.sqlite_protocol}{db_file}",
            echo=self.sqlite_echo,
            check_same_thread=self.sqlite_check_same_thread,
            protocol=self.sqlite_protocol,
        )


def load_env() -> None:
    """환경 변수 로드 (.env 파일)

    로딩 순서 (override=False이므로 먼저 로드된 값 우선):
    1. 프로세스 환경 변수 (이미 설정됨, 최우선)
    2. .env.{APP_ENV} (존재 시)
    """
    app_env = os.getenv("APP_ENV", "dev")
    app_env_file = find_dotenv(filename=f".env.{app_env}")

    load_dotenv(dotenv_path=app_env_file, override=False)


def _require_env(key: str) -> str:
    try:
        value = os.environ[key]
    except KeyError as exc:
        raise RuntimeError(f"필수 환경 변수 누락: {key}") from exc

    if value == "":
        raise RuntimeError(f"필수 환경 변수 값이 비어 있습니다: {key}")

    return value


def _require_bool(key: str) -> bool:
    value = _require_env(key)
    normalized = value.lower()
    if normalized in {"true", "false"}:
        return normalized == "true"

    raise RuntimeError(f"환경 변수 {key}는 true/false여야 합니다: {value}")


# 싱글톤 VoyagerConfig 인스턴스
_config: VoyagerConfig | None = None


def load_config() -> VoyagerConfig:
    """환경 변수에서 VoyagerConfig 인스턴스 생성 (싱글톤)

    첫 호출 시 VoyagerConfig 인스턴스를 생성하고 캐시합니다.
    이후 호출 시 동일한 인스턴스를 반환합니다.

    Returns:
        VoyagerConfig: .env 구조를 그대로 반영한 설정 객체
    """
    global _config

    if _config is not None:
        return _config

    load_env()

    app_env = _require_env("APP_ENV")
    if app_env == "dev":
        app_env_literal: Literal["dev", "prod"] = "dev"
    elif app_env == "prod":
        app_env_literal = "prod"
    else:
        raise RuntimeError(f"APP_ENV는 dev/prod만 허용됩니다: {app_env}")

    _config = VoyagerConfig(
        # App 기본 설정
        app_name=_require_env("PUBLIC_APP_NAME"),
        app_env=app_env_literal,
        log_level=_require_env("PUBLIC_LOG_LEVEL"),
        # Gateway/Web 설정
        gateway_url=_require_env("PUBLIC_GATEWAY_URL"),
        web_base_url=_require_env("PUBLIC_WEB_BASE_URL"),
        # SQLite 설정
        sqlite_protocol=_require_env("PUBLIC_SQLITE_PROTOCOL"),
        sqlite_echo=_require_bool("PUBLIC_SQLITE_ECHO"),
        sqlite_check_same_thread=_require_bool("PUBLIC_SQLITE_CHECK_SAME_THREAD"),
        sqlite_file_location=_require_env("PUBLIC_SQLITE_FILE_LOCATION"),
        sqlite_file_name=_require_env("PUBLIC_SQLITE_FILE_NAME"),
    )

    return _config


def get_db_config(cfg: VoyagerConfig) -> DbConfig:
    """VoyagerConfig에서 DbConfig 추출 (기존 호환성 유지)

    Args:
        cfg: VoyagerConfig 인스턴스

    Returns:
        DbConfig: infra.db.models의 DbConfig 인스턴스
    """
    return cfg.get_db_config()


__all__ = ["load_config", "get_db_config", "VoyagerConfig"]
