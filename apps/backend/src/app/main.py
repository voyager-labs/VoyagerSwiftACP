import logging
import platform
import sqlite3
from contextlib import asynccontextmanager

from fastapi import FastAPI

from app.config import load_config
from app.file.routes import router as files_router
from infra.db.bootstrap import initialize_sqlite_db
from infra.db.engine import engine_manager


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Hydra config 로드
    cfg = load_config()
    app.state.config = cfg

    # DB 엔진 초기화 및 Alembic 기반 마이그레이션 적용
    init_summary = initialize_sqlite_db(cfg)

    logger = logging.getLogger("uvicorn.error")
    # api_key_set = bool(cfg.llm.api_key) and str(cfg.llm.api_key).strip() != ""
    py_ver = platform.python_version()
    sqlite_ver = getattr(sqlite3, "sqlite_version", "")
    message = (
        "Environment initialized: "
        f"app={cfg.app.name} env={cfg.app.env} "
        f"python={py_ver} sqlite={sqlite_ver or 'unknown'} "
        # f"api_key_set={api_key_set} "
        f"db_rev={init_summary.current_rev}/{init_summary.head_rev}"
    )
    bar = "=" * max(60, len(message))
    logger.warning(f"\n{bar}\n{message}\n{bar}")

    yield

    # 종료 시 DB 연결 정리
    engine_manager.dispose()


app = FastAPI(
    title="Voyager File Manager API",
    description="macOS 파일 메타데이터 수집 및 검색 API",
    version="0.1.0",
    lifespan=lifespan,
)

# 라우터 등록
app.include_router(files_router, prefix="/api")


@app.get("/")
async def root() -> dict[str, str]:
    return {"message": "Voyager API is running", "docs": "/docs"}
