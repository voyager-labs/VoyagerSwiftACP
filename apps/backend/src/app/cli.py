from __future__ import annotations

import os
import sys
from pathlib import Path

import setproctitle
from fastapi.cli import main as fastapi_main

from app.config import load_env

MAIN_FILE = Path(__file__).parent / "main.py"


def _with_env(default_env: str) -> dict[str, str]:
    os.environ.setdefault("APP_ENV", default_env)
    os.environ.setdefault("BACKEND_MODE", "source")
    load_env()
    return os.environ.copy()


def _set_supervisor_title(env: dict[str, str]) -> None:
    process_title = env.get("PUBLIC_BACKEND_PROCESS_NAME")
    if process_title:
        setproctitle.setproctitle(f"{process_title} (Supervisor)")


def dev() -> None:
    """개발 모드 실행: fastapi dev (자동 리로드)"""
    env = _with_env("dev")
    # 환경변수 설정
    for key, value in env.items():
        os.environ[key] = value

    _set_supervisor_title(env)

    host = env["PUBLIC_BACKEND_HOST"]
    port = env["PUBLIC_BACKEND_PORT"]

    # sys.argv 조작하여 FastAPI CLI 호출
    original_argv = sys.argv.copy()
    try:
        sys.argv = ["fastapi", "dev", str(MAIN_FILE), "--host", host, "--port", port]
        fastapi_main()
    finally:
        sys.argv = original_argv


def prod() -> None:
    """프로덕션 모드 실행: fastapi run (자동 리로드 없음)"""
    env = _with_env("prod")
    # 환경변수 설정
    for key, value in env.items():
        os.environ[key] = value

    _set_supervisor_title(env)

    host = env["PUBLIC_BACKEND_HOST"]
    port = env["PUBLIC_BACKEND_PORT"]

    # sys.argv 조작하여 FastAPI CLI 호출
    original_argv = sys.argv.copy()
    try:
        sys.argv = ["fastapi", "run", str(MAIN_FILE), "--host", host, "--port", port]
        fastapi_main()
    finally:
        sys.argv = original_argv
