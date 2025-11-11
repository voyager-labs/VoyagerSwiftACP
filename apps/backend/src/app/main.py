from contextlib import asynccontextmanager

from fastapi import FastAPI

from app.config import load_config
from app.file.routes import router as files_router
from infra.db.engine import engine_manager


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Hydra config 로드
    cfg = load_config()
    app.state.config = cfg

    # DB 엔진 초기화 및 테이블 생성
    engine_manager.initialize(cfg)
    engine_manager.create_tables()

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
