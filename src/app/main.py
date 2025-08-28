import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI

from app.config import load_config


@asynccontextmanager
async def lifespan(app: FastAPI):
    cfg = load_config()
    app.state.config = cfg
    logger = logging.getLogger("uvicorn.error")
    message = f"Environment initialized: app={cfg.app.name} env={cfg.app.env} api_key_set={cfg.llm.api_key is not None}"
    bar = "=" * max(60, len(message))
    logger.warning(f"\n{bar}\n{message}\n{bar}")
    yield


app = FastAPI(lifespan=lifespan)


@app.get("/")
async def root() -> dict[str, str]:
    return {"message": "Hello World!"}
