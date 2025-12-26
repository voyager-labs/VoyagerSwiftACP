"""Nuitka 빌드를 위한 서버 실행 스크립트"""

from __future__ import annotations

import os

import uvicorn

from app.main import app

os.environ.setdefault("APP_ENV", "prod")

if __name__ == "__main__":
    backend_host = os.getenv("PUBLIC_BACKEND_HOST", "127.0.0.1")
    backend_port = int(os.getenv("PUBLIC_VOYAGER_PORT", "8000"))

    uvicorn.run(
        app,
        host=backend_host,
        port=backend_port,
        log_level="info",
    )
