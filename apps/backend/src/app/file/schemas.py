from __future__ import annotations

from pydantic import BaseModel, Field

from app.file.indexing_service import DEFAULT_BATCH_SIZE, DEFAULT_EXCLUDES


class NaturalQueryRequest(BaseModel):
    """자연어 검색 요청"""

    query: str


class IndexFilesRequest(BaseModel):
    """내부 테스트용 임시 인덱싱 요청 스키마."""

    paths: list[str] = Field(min_length=1, description="인덱싱할 경로 목록")
    batch_size: int = Field(default=DEFAULT_BATCH_SIZE, ge=1, description="배치 저장 크기")
    exclude: list[str] = Field(
        default_factory=lambda: list(DEFAULT_EXCLUDES),
        description="제외할 디렉토리 목록",
    )
