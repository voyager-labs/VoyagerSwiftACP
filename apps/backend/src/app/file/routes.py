"""파일 메타데이터 관련 API 라우트"""

import json
import threading
from collections.abc import Generator, Iterable

from fastapi import APIRouter, Query
from fastapi.responses import JSONResponse, StreamingResponse
from pydantic import BaseModel
from sqlmodel import select, text

from app.config import config
from app.file.indexing_service import stream_indexing_events
from app.file.schemas import IndexFilesRequest, NaturalQueryRequest
from core.llm.cached_llm_converter import CachedLLMConverter
from core.llm.langchain_provider import LangChainProvider
from infra.db.engine import engine_manager
from infra.repositories.file_entries import FileEntriesRepository
from infra.schemas.file_entry_schema import FileEntrySchema

router = APIRouter(prefix="/files", tags=["files"])


class NaturalQueryRequest(BaseModel):
    """자연어 검색 요청"""

    query: str


# 캐시 컨버터 싱글톤 (서버 재시작 전까지 캐시 유지)
_cached_converter: CachedLLMConverter | None = None


def get_cached_converter() -> CachedLLMConverter:
    """캐시 컨버터 싱글톤 반환"""
    global _cached_converter
    if _cached_converter is None:
        llm = LangChainProvider(provider="openai", base_url=config.gateway_url)
        _cached_converter = CachedLLMConverter(llm, cache_size=100)
    return _cached_converter


_indexing_lock = threading.Lock()
_indexing_running = False


def _try_start_indexing() -> bool:
    global _indexing_running
    with _indexing_lock:
        if _indexing_running:
            return False
        _indexing_running = True
        return True


def _finish_indexing() -> None:
    global _indexing_running
    with _indexing_lock:
        _indexing_running = False


def _to_ndjson_lines(events: Iterable[dict[str, object]]) -> Generator[bytes, None, None]:
    for event in events:
        payload = {"data": event}
        yield (json.dumps(payload) + "\n").encode("utf-8")


@router.get("/")
async def list_files(
    limit: int = Query(default=100, ge=1, le=1000),
    offset: int = Query(default=0, ge=0),
    extension: str | None = Query(default=None, description="확장자로 필터링 (예: pdf)"),
):
    """파일 목록 조회 (페이지네이션 지원)"""
    with engine_manager.session(autocommit=False) as session:
        stmt = select(FileEntrySchema)

        if extension:
            stmt = stmt.where(FileEntrySchema.extension == extension.lower())

        stmt = stmt.offset(offset).limit(limit).order_by(FileEntrySchema.id.desc())

        results = session.exec(stmt).all()

        return {
            "count": len(results),
            "offset": offset,
            "limit": limit,
            "items": [
                {
                    "id": item.id,
                    "path": item.path,
                    "name": item.name_full,
                    "size": item.size,
                    "extension": item.extension,
                    "file_kind": item.file_kind,
                    "creation_date": item.creation_date.isoformat(),
                    "modification_date": item.modification_date.isoformat(),
                }
                for item in results
            ],
        }


@router.get("/db-size")
async def get_db_size():
    """데이터베이스 파일 크기 및 파일 개수 조회"""
    import os
    from pathlib import Path

    db_path = Path(__file__).parent.parent.parent.parent / "voyager.dev.db"

    if not db_path.exists():
        return {"error": "Database file not found", "path": str(db_path)}

    db_size_bytes = os.path.getsize(db_path)

    # 파일 개수 조회
    with engine_manager.session(autocommit=False) as session:
        file_count = len(session.exec(select(FileEntrySchema)).all())

    return {
        "db_path": str(db_path),
        "db_size_bytes": db_size_bytes,
        "db_size_mb": round(db_size_bytes / (1024 * 1024), 2),
        "db_size_gb": round(db_size_bytes / (1024 * 1024 * 1024), 2),
        "total_files": file_count,
    }


@router.get("/stats")
async def get_stats():
    """파일 통계 정보"""
    with engine_manager.session(autocommit=False) as session:
        # 전체 파일 개수
        total_count = session.exec(select(FileEntrySchema)).all()
        total = len(total_count)

        # 확장자별 개수
        all_files = session.exec(select(FileEntrySchema)).all()
        ext_counts: dict[str, int] = {}
        total_size = 0

        for file in all_files:
            ext = file.extension or "no_extension"
            ext_counts[ext] = ext_counts.get(ext, 0) + 1
            total_size += file.size

        # 상위 10개 확장자
        top_extensions = sorted(ext_counts.items(), key=lambda x: x[1], reverse=True)[:10]

        return {
            "total_files": total,
            "total_size_bytes": total_size,
            "total_size_mb": round(total_size / (1024 * 1024), 2),
            "extension_stats": [
                {"extension": ext, "count": count} for ext, count in top_extensions
            ],
        }


@router.get("/collection")
async def search_files(
    q: str = Query(..., min_length=1, description="검색 키워드"),
):
    """파일 이름으로 검색"""
    with engine_manager.session(autocommit=False) as session:
        stmt = (
            select(FileEntrySchema)
            .where(FileEntrySchema.name_full.contains(q))
            .order_by(FileEntrySchema.modification_date.desc())
        )

        results = session.exec(stmt).all()

        return {
            "query": q,
            "count": len(results),
            "items": [
                {
                    "id": item.id,
                    "path": item.path,
                    "name": item.name_full,
                    "size": item.size,
                    "extension": item.extension,
                    "modification_date": item.modification_date.isoformat(),
                }
                for item in results
            ],
        }


@router.get("/{file_id}")
async def get_file_detail(file_id: int):
    """파일 상세 정보 조회"""
    with engine_manager.session(autocommit=False) as session:
        repo = FileEntriesRepository(session)
        file = repo.get_by_id(file_id)

        if not file:
            return {"error": "File not found"}, 404

        return {
            "id": file.id,
            "path": file.path,
            "dir_path": file.dir_path,
            "name_full": file.name_full,
            "name_stem": file.name_stem,
            "extension": file.extension,
            "parent_dir_name": file.parent_dir_name,
            "depth_from_home": file.depth_from_home,
            "relative_path_from_home": file.relative_path_from_home,
            "size": file.size,
            "uniform_type_identifier": file.uniform_type_identifier,
            "file_kind": file.file_kind,
            "is_invisible": file.is_invisible,
            "creation_date": file.creation_date.isoformat(),
            "modification_date": file.modification_date.isoformat(),
            "content_creation_date": file.content_creation_date.isoformat(),
            "content_modification_date": file.content_modification_date.isoformat(),
            "added_date": file.added_date.isoformat(),
            "last_used_date": file.last_used_date.isoformat() if file.last_used_date else None,
            "owner_uid": file.owner_uid,
            "owner_gid": file.owner_gid,
        }


@router.post("/query")
async def query_files(request: NaturalQueryRequest):
    """자연어 쿼리를 SQL로 변환하여 파일 검색

    동일한 쿼리는 캐시에서 즉시 반환됩니다.
    """
    import time

    start_time = time.time()
    converter = get_cached_converter()

    # 캐시 히트 여부 확인
    cache_hit = request.query in converter._cache

    generated_sql = None
    try:
        generated_sql = await converter.convert(request.query)

        if not generated_sql:
            return {
                "query": request.query,
                "success": False,
                "where_clause": None,
                "count": 0,
                "cache_hit": cache_hit,
                "error": "SQL 변환 실패",
                "execution_time": round(time.time() - start_time, 3),
            }

        # SQL 실행
        with engine_manager.session(autocommit=False) as session:
            sql = f"""
                SELECT id, path, name_full, size, extension, file_kind, modification_date
                FROM file_entries
                WHERE {generated_sql}
                ORDER BY modification_date DESC
            """

            stmt = text(sql)
            result = session.exec(stmt)
            rows = result.fetchall()

            return {
                "query": request.query,
                "success": True,
                "where_clause": generated_sql,
                "count": len(rows),
                "cache_hit": cache_hit,
                "cache_size": len(converter._cache),
                "execution_time": round(time.time() - start_time, 3),
            }

    except Exception as e:
        return {
            "query": request.query,
            "success": False,
            "where_clause": generated_sql,
            "count": 0,
            "cache_hit": cache_hit,
            "error": str(e)[:200],
            "execution_time": round(time.time() - start_time, 3),
        }


# 내부 테스트용 임시 인덱싱 엔드포인트입니다. 정식 API로 승격 전까지 계약이 변경될 수 있습니다.
@router.post("/indexing")
def index_files(request: IndexFilesRequest):
    """내부 테스트용 임시 인덱싱 (NDJSON 스트리밍)"""
    if not _try_start_indexing():
        return JSONResponse(
            status_code=409,
            content={
                "error": {
                    "code": "INDEXING_ALREADY_RUNNING",
                    "details": "이미 인덱싱이 진행 중입니다.",
                }
            },
        )

    events = stream_indexing_events(
        paths=request.paths,
        batch_size=request.batch_size,
        exclude=request.exclude,
    )

    def stream() -> Generator[bytes, None, None]:
        try:
            yield from _to_ndjson_lines(events)
        except Exception as exc:
            error_payload = {
                "error": {
                    "code": "INDEXING_FAILED",
                    "details": exc.__class__.__name__,
                }
            }
            yield (json.dumps(error_payload) + "\n").encode("utf-8")
        finally:
            _finish_indexing()

    return StreamingResponse(
        stream(),
        media_type="application/x-ndjson",
        status_code=202,
    )
