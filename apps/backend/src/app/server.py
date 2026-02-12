"""Nuitka 빌드를 위한 서버 실행 스크립트"""

from __future__ import annotations

import os

import uvicorn

from app.config import load_env
from app.main import app

os.environ.setdefault("APP_ENV", "prod")

load_env()

if __name__ == "__main__":
    host = os.environ.get("BACKEND_HOST", "127.0.0.1")
    port = int(os.environ.get("BACKEND_PORT", "8000"))
    uvicorn.run(app, host=host, port=port, log_level="info")
