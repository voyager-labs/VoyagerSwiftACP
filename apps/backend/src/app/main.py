import logging
import os
import platform
from contextlib import asynccontextmanager

import setproctitle
from fastapi import FastAPI

from app.config import get_db_config, load_config
from app.search.routes import router as search_router
from infra.db.engine import engine_manager
from infra.db.utils import ensure_parent_dir


@asynccontextmanager
async def lifespan(app: FastAPI):
    # 환경 변수 기반 설정 로드
    cfg = load_config()
    app.state.config = cfg

    process_title = os.environ["PUBLIC_BACKEND_PROCESS_NAME"]
    setproctitle.setproctitle(process_title)

    # DB 엔진 초기화
    db_cfg = get_db_config(cfg)
    ensure_parent_dir(db_cfg.db_file)
    engine_manager.initialize(db_cfg)

    logger = logging.getLogger("uvicorn.error")
    py_ver = platform.python_version()
    message = (
        "Environment initialized: "
        f"app={cfg.app_name} env={cfg.app_env} "
        f"python={py_ver} "
        f"gateway_url={cfg.gateway_url}"
        f"backend_host={cfg.backend_host}"
        f"backend_port={cfg.backend_port}"
        f"backend_process_name={cfg.backend_process_name}"
        f"sqlite_protocol={cfg.sqlite_protocol}"
        f"sqlite_echo={cfg.sqlite_echo}"
        f"sqlite_check_same_thread={cfg.sqlite_check_same_thread}"
        f"sqlite_file_location={cfg.sqlite_file_location}"
        f"sqlite_file_name={cfg.sqlite_file_name}"
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
app.include_router(search_router, prefix="/api")


@app.get("/")
async def root() -> dict[str, str]:
    return {"message": "Voyager API is running", "docs": "/docs"}
