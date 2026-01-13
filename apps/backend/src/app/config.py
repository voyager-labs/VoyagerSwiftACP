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

    # Backend 설정
    backend_host: str  # PUBLIC_BACKEND_HOST
    backend_port: str  # PUBLIC_BACKEND_PORT (0이면 동적 할당)
    backend_process_name: str  # PUBLIC_BACKEND_PROCESS_NAME

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
    2. .env.{BACKEND_MODE} (존재 시)
    3. .env.{APP_ENV} (존재 시)
    """
    app_env = os.getenv("APP_ENV", "dev")
    backend_mode = os.getenv("BACKEND_MODE", "source")

    backend_env_file = find_dotenv(filename=f".env.{backend_mode}")
    app_env_file = find_dotenv(filename=f".env.{app_env}")

    load_dotenv(dotenv_path=backend_env_file, override=False)
    load_dotenv(dotenv_path=app_env_file, override=False)


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

    _config = VoyagerConfig(
        # App 기본 설정
        app_name=os.getenv("PUBLIC_APP_NAME") or "",
        app_env=os.getenv("APP_ENV") or "dev",  # type: ignore[arg-type]
        log_level=os.getenv("PUBLIC_LOG_LEVEL") or "",
        # Gateway/Web 설정
        gateway_url=os.getenv("PUBLIC_GATEWAY_URL") or "",
        web_base_url=os.getenv("PUBLIC_WEB_BASE_URL") or "",
        # Backend 설정
        backend_host=os.getenv("PUBLIC_BACKEND_HOST") or "",
        backend_port=os.getenv("PUBLIC_BACKEND_PORT") or "",
        backend_process_name=os.getenv("PUBLIC_BACKEND_PROCESS_NAME") or "",
        # SQLite 설정
        sqlite_protocol=os.getenv("PUBLIC_SQLITE_PROTOCOL") or "",
        sqlite_echo=(os.getenv("PUBLIC_SQLITE_ECHO") or "").lower() == "true",
        sqlite_check_same_thread=(os.getenv("PUBLIC_SQLITE_CHECK_SAME_THREAD") or "").lower()
        == "true",
        sqlite_file_location=os.getenv("PUBLIC_SQLITE_FILE_LOCATION") or "",
        sqlite_file_name=os.getenv("PUBLIC_SQLITE_FILE_NAME") or "",
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


config = load_config()

__all__ = ["load_config", "get_db_config", "VoyagerConfig", "config"]
