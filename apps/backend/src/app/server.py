"""Nuitka 빌드를 위한 서버 실행 스크립트"""

from __future__ import annotations

import os

import uvicorn

os.environ.setdefault("APP_ENV", "prod")

if __name__ == "__main__":
    host = os.getenv("PUBLIC_BACKEND_HOST")
    port = int(os.getenv("PUBLIC_BACKEND_PORT"))
    uvicorn.run("app.main:app", host=host, port=port, log_level="info")
