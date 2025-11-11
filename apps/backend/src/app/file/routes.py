"""파일 메타데이터 관련 API 라우트"""

from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel
from sqlmodel import select, text

from app.config import load_config
from core.llm.ollama_client import OllamaClient
from core.llm.query_converter import QueryConverter
from infra.db.engine import engine_manager
from infra.repositories.file_entries import FileEntriesRepository
from infra.schemas.file_entry_schema import FileEntrySchema

router = APIRouter(prefix="/files", tags=["files"])


class NaturalQueryRequest(BaseModel):
    """자연어 검색 요청"""

    query: str
    limit: int = 50

# 앱 시작 시 DB 초기화 (이미 main.py에서 수행됨)
cfg = load_config()
if not engine_manager.is_initialized:
    engine_manager.initialize(cfg)


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
            "extension_stats": [{"extension": ext, "count": count} for ext, count in top_extensions],
        }


@router.get("/search")
async def search_files(
    q: str = Query(..., min_length=1, description="검색 키워드"),
    limit: int = Query(default=50, ge=1, le=500),
):
    """파일 이름으로 검색"""
    with engine_manager.session(autocommit=False) as session:
        stmt = (
            select(FileEntrySchema)
            .where(FileEntrySchema.name_full.contains(q))
            .limit(limit)
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
async def natural_language_search(request: NaturalQueryRequest):
    """자연어 검색 (LLM 기반)

    사용자의 자연어 쿼리를 LLM이 SQL 조건식으로 변환하여 검색합니다.

    Examples:
        - "어제 다운로드한 PDF 파일"
        - "최근 1주일 이내 수정된 이미지"
        - "Downloads 폴더의 큰 파일"
    """
    # Ollama 클라이언트 초기화
    ollama = OllamaClient(model="qwen2.5:7b")

    # 서버 상태 확인
    if not await ollama.health_check():
        raise HTTPException(
            status_code=503,
            detail="Ollama 서버가 실행 중이지 않습니다. 'ollama serve' 명령으로 시작하세요.",
        )

    try:
        # 쿼리 변환
        converter = QueryConverter(ollama)
        where_clause = await converter.convert(request.query)

        if not where_clause:
            return {
                "query": request.query,
                "where_clause": None,
                "count": 0,
                "items": [],
                "error": "쿼리를 SQL 조건식으로 변환할 수 없습니다.",
            }

        # SQL 실행
        with engine_manager.session(autocommit=False) as session:
            # WHERE 절을 포함한 쿼리 생성
            sql = f"""
                SELECT id, path, name_full, size, extension, file_kind, modification_date
                FROM file_entries
                WHERE {where_clause}
                ORDER BY modification_date DESC
                LIMIT {request.limit}
            """

            stmt = text(sql)
            result = session.exec(stmt)
            rows = result.fetchall()

            # 결과 변환
            items = []
            for row in rows:
                items.append(
                    {
                        "id": row[0],
                        "path": row[1],
                        "name": row[2],
                        "size": row[3],
                        "extension": row[4],
                        "file_kind": row[5],
                        "modification_date": row[6],  # SQLite에서 문자열로 반환됨
                    }
                )

            return {
                "query": request.query,
                "where_clause": where_clause,
                "count": len(items),
                "items": items,
            }

    except Exception as e:
        raise HTTPException(status_code=500, detail=f"검색 실행 오류: {str(e)}")

    finally:
        await ollama.close()
