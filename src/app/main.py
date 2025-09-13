import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI

from app.config import load_config
from infra.db.engine import create_tables, init_engine


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Hydra config 로드
    cfg = load_config()
    app.state.config = cfg

    # DB 엔진/세션 초기화 및 테이블 보장
    init_engine(cfg)
    create_tables()

    logger = logging.getLogger("uvicorn.error")
    api_key_set = bool(cfg.llm.api_key) and str(cfg.llm.api_key).strip() != ""
    message = (
        f"Environment initialized: app={cfg.app.name} env={cfg.app.env} api_key_set={api_key_set}"
    )
    bar = "=" * max(60, len(message))
    logger.warning(f"\n{bar}\n{message}\n{bar}")
    yield


app = FastAPI(lifespan=lifespan)


@app.get("/")
async def root() -> dict[str, str]:
    return {"message": "Hello World!"}
