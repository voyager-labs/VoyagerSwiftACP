import logging
import os
import platform
import time
from collections.abc import Awaitable, Callable
from contextlib import asynccontextmanager

import sentry_sdk
import setproctitle
from fastapi import FastAPI, Request, Response
from sentry_sdk.integrations.fastapi import FastApiIntegration

from app.config import get_db_config, load_config, load_env
from app.search.routes import router as search_router
from infra.db.engine import engine_manager
from infra.db.utils import ensure_parent_dir
from utils.telemetry import log_metric


def _parse_sample_rate(value: str | None, default: float) -> float:
    if not value:
        return default
    try:
        parsed = float(value)
    except ValueError:
        return default
    if parsed < 0:
        return 0.0
    if parsed > 1:
        return 1.0
    return parsed


def init_sentry() -> None:
    load_env()
    dsn = os.getenv("PUBLIC_SENTRY_DSN")
    if not dsn:
        return
    traces_sample_rate_value = os.getenv("PUBLIC_SENTRY_TRACES_SAMPLE_RATE")
    traces_sample_rate = _parse_sample_rate(traces_sample_rate_value, 0.0) if traces_sample_rate_value else None
    environment = os.getenv("APP_ENV")
    init_kwargs: dict[str, object] = {
        "dsn": dsn,
        "integrations": [FastApiIntegration()],
        "send_default_pii": False,
    }
    if traces_sample_rate is not None:
        init_kwargs["traces_sample_rate"] = traces_sample_rate
    if environment:
        init_kwargs["environment"] = environment
    sentry_sdk.init(
        **init_kwargs,
    )


init_sentry()


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


# 요청 지연/상태/트레이스 태그를 공통으로 기록
@app.middleware("http")
async def add_request_observability(
    request: Request,
    call_next: Callable[[Request], Awaitable[Response]],
) -> Response:
    start = time.perf_counter()
    trace_id = request.headers.get("X-Trace-Id")
    session_id = request.headers.get("X-Session-Id")
    device_id = request.headers.get("X-Voyager-Device-Id")
    app_version = request.headers.get("X-Voyager-App-Version")
    os_version = request.headers.get("X-Voyager-OS-Version")
    route = request.url.path
    method = request.method

    with sentry_sdk.push_scope() as scope:
        scope.set_tag("route", route)
        scope.set_tag("method", method)
        if trace_id:
            scope.set_tag("trace_id", trace_id)
        if session_id:
            scope.set_tag("session_id", session_id)
        if device_id:
            scope.set_user({"id": device_id})
        if app_version:
            scope.set_tag("app_version", app_version)
        if os_version:
            scope.set_tag("os_version", os_version)

        response: Response = await call_next(request)
        duration_ms = (time.perf_counter() - start) * 1000
        scope.set_tag("status", response.status_code)
        scope.set_extra("duration_ms", round(duration_ms, 2))
        tags: dict[str, str] = {
            "route": route,
            "method": method,
            "status": str(response.status_code),
        }
        log_metric("voyager_http_request_duration_ms", round(duration_ms, 2), tags)
        log_metric("voyager_http_requests_total", 1, tags)
        if response.status_code >= 500:
            log_metric(
                "voyager_http_errors_total",
                1,
                {"route": route, "error_code": "HTTP_5XX"},
            )
        return response


# 라우터 등록
app.include_router(search_router, prefix="/api")


@app.get("/")
async def root() -> dict[str, str]:
    return {"message": "Voyager API is running", "docs": "/docs"}
