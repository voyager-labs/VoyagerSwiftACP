"""
토큰 유틸리티 모듈 - 토큰 계산 및 분석 기능

이 모듈은 텍스트와 문서의 토큰 수를 계산하고 통계를 분석하는 기능을 제공합니다.
"""

from collections.abc import Mapping
from typing import Union, cast

import tiktoken
from langchain_core.documents import Document

from app.config import load_config

# Hydra 설정에서 토큰화 설정 로드
tokenization_cfg = cast(Mapping[str, object], load_config()["tokenization"])  # 필수 키 전제
encoder = tiktoken.get_encoding(cast(str, tokenization_cfg["encoder"]))
MAX_TOKENS: int = cast(int, tokenization_cfg["max_tokens"])  # 모델 최대 토큰 수


def count_tokens(text: str) -> int:
    """텍스트의 토큰 수 계산"""
    return len(encoder.encode(text))


def check_chunk_tokens(chunk: Document) -> int:
    """청크의 토큰 수 확인"""
    return count_tokens(chunk.page_content)


def calculate_document_tokens(document_chunks: list[Document]) -> int:
    """문서 청크들의 총 토큰 수 계산"""
    total_tokens: int = 0
    for chunk in document_chunks:
        total_tokens += count_tokens(chunk.page_content)
    return total_tokens


def analyze_document_tokens(document_chunks: list[Document]) -> dict[str, Union[int, float]]:
    """문서 청크들의 토큰 통계 분석"""
    if not document_chunks:
        return {
            "total_chunks": 0,
            "total_tokens": 0,
            "avg_tokens": 0.0,
            "max_tokens": 0,
            "min_tokens": 0,
        }

    token_counts: list[int] = [check_chunk_tokens(chunk) for chunk in document_chunks]
    total_tokens: int = sum(token_counts)
    chunk_count: int = len(token_counts)

    return {
        "total_chunks": chunk_count,
        "total_tokens": total_tokens,
        "avg_tokens": total_tokens / chunk_count if chunk_count > 0 else 0.0,
        "max_tokens": max(token_counts) if token_counts else 0,
        "min_tokens": min(token_counts) if token_counts else 0,
    }


def analyze_file_tokens(file_chunks: list[list[Document]]) -> dict[str, Union[int, float]]:
    """파일 청크들의 토큰 통계 분석"""
    all_chunks: list[Document] = []
    for document_chunks in file_chunks:
        all_chunks.extend(document_chunks)

    return analyze_document_tokens(all_chunks)
