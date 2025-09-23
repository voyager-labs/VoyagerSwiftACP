from collections.abc import Generator
from typing import Union, cast

from langchain_core.documents import Document

from .batch_strategies import create_binary_batches
from .token_utils import MAX_TOKENS, count_tokens


def process_document_batches(
    document_chunks: list[Document],
    file_idx: int,
    document_idx: int,
    ext: str,
    cfg: dict[str, object],
    max_tokens: int = MAX_TOKENS,
) -> Generator[
    dict[str, Union[list[Document], dict[str, Union[int, float, list[int]]]]], None, None
]:
    """Document별 배치 처리 (제너레이터 방식)"""
    # 이진탐색 기반 배치 생성
    batches = create_binary_batches(document_chunks, ext, cfg, max_tokens)

    # 배치 메타데이터 생성
    running_idx: int = 0

    for batch_idx, batch in enumerate(batches):
        batch_tokens: int = sum(count_tokens(c.page_content) for c in batch)
        chunk_indices: list[int] = list(range(running_idx, running_idx + len(batch)))
        running_idx += len(batch)

        yield {
            "batch": batch,
            "metadata": {
                "file_idx": file_idx,
                "doc_idx": document_idx,
                "batch_idx": batch_idx,
                "chunk_count": len(batch),
                "chunk_indices": chunk_indices,
                "total_tokens": batch_tokens,
                "utilization_rate": batch_tokens / max_tokens,
            },
        }


def process_all_documents(
    chunked_by_file: list[list[list[Document]]],
    ext: str,
    cfg: dict[str, object],
    max_tokens: int = MAX_TOKENS,
) -> Generator[
    dict[str, Union[list[Document], dict[str, Union[int, float, list[int]]]]], None, None
]:
    """모든 파일과 문서에 대해 배치 처리 (제너레이터 방식)"""
    for file_idx, file_chunks in enumerate(chunked_by_file):
        for document_idx, document_chunks in enumerate(file_chunks):
            yield from process_document_batches(
                document_chunks, file_idx, document_idx, ext, cfg, max_tokens
            )


def analyze_batch_statistics(
    processed_batches: list[
        list[list[dict[str, Union[list[Document], dict[str, Union[int, float, list[int]]]]]]]
    ],
) -> dict[str, Union[int, float]]:
    """배치 통계 분석"""
    total_batches: int = 0
    total_tokens: int = 0
    utilization_rates: list[float] = []

    for file_batches in processed_batches:
        for document_batches in file_batches:
            for batch_info in document_batches:
                total_batches += 1
                metadata = cast(dict[str, Union[int, float, list[int]]], batch_info["metadata"])
                total_tokens += int(cast(int, metadata["total_tokens"]))
                utilization_rates.append(float(cast(float, metadata["utilization_rate"])))

    rate_count: int = len(utilization_rates)
    avg_utilization: float = sum(utilization_rates) / rate_count if rate_count > 0 else 0.0
    min_utilization: float = min(utilization_rates) if utilization_rates else 0.0
    max_utilization: float = max(utilization_rates) if utilization_rates else 0.0

    return {
        "total_batches": total_batches,
        "total_tokens": total_tokens,
        "avg_utilization_rate": avg_utilization,
        "min_utilization_rate": min_utilization,
        "max_utilization_rate": max_utilization,
    }
