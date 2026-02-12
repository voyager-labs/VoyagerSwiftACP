import logging
import platform
import time
from collections.abc import Awaitable, Callable
from contextlib import asynccontextmanager

import setproctitle
from fastapi import FastAPI, Request, Response

from app.config import get_db_config, load_config
from app.search.routes import router as search_router
from infra.db.engine import engine_manager
from infra.db.utils import ensure_parent_dir


@asynccontextmanager
async def lifespan(app: FastAPI):
    # 환경 변수 기반 설정 로드
    cfg = load_config()
    app.state.config = cfg
    setproctitle.setproctitle(f"{cfg.app_name}-server")

    # DB 엔진 초기화
    db_cfg = get_db_config(cfg)
    ensure_parent_dir(db_cfg.db_file)
    engine_manager.initialize(db_cfg)

    logger = logging.getLogger("uvicorn.error")
    py_ver = platform.python_version()
    message = (
        "Environment initialized: \n"
        f"app = {cfg.app_name} env = {cfg.app_env} \n"
        f"python = {py_ver} \n"
        f"gateway_url = {cfg.gateway_url} \n"
        f"sqlite_protocol = {cfg.sqlite_protocol} \n"
        f"sqlite_echo = {cfg.sqlite_echo} \n"
        f"sqlite_check_same_thread = {cfg.sqlite_check_same_thread} \n"
        f"sqlite_file_location = {cfg.sqlite_file_location} \n"
        f"sqlite_file_name = {cfg.sqlite_file_name} \n"
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


# 요청 지연/상태/트레이스 태그를 공통으로 기록
@app.middleware("http")
async def add_request_observability(
    request: Request,
    call_next: Callable[[Request], Awaitable[Response]],
) -> Response:
    start = time.perf_counter()

    response: Response = await call_next(request)
    _ = request.url.path
    _ = request.method
    _ = (time.perf_counter() - start) * 1000
    return response


# 라우터 등록
app.include_router(search_router, prefix="/api")


@app.get("/")
async def root() -> dict[str, str]:
    return {"message": "Voyager API is running", "docs": "/docs"}
