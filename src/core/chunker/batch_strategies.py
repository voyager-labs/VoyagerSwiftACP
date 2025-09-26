"""
배치 생성 전략 모듈 - 다양한 배치 생성 전략 구현

이 모듈은 문서 청크들을 토큰 제한에 맞춰 배치로 그룹화하는 다양한 전략을 제공합니다.
"""

from langchain_core.documents import Document

from .chunker import get_splitter
from .token_utils import MAX_TOKENS, count_tokens, encoder


def create_sequential_batches(
    document_chunks: list[Document], max_tokens: int = MAX_TOKENS
) -> list[list[Document]]:
    """순차적 방식으로 배치 생성"""
    if not document_chunks:
        return []

    # 작은 문서는 단일 배치로 처리
    total_tokens: int = sum(count_tokens(chunk.page_content) for chunk in document_chunks)
    if total_tokens <= max_tokens:
        return [document_chunks]

    # 순차적 방식으로 배치 생성
    batches: list[list[Document]] = []
    current_batch: list[Document] = []
    current_tokens: int = 0

    for chunk in document_chunks:
        chunk_tokens: int = count_tokens(chunk.page_content)
        if current_tokens + chunk_tokens <= max_tokens:
            current_batch.append(chunk)
            current_tokens += chunk_tokens
        else:
            if current_batch:
                batches.append(current_batch)
            current_batch = [chunk]
            current_tokens = chunk_tokens

    if current_batch:
        batches.append(current_batch)
    return batches


def create_binary_batches(
    document_chunks: list[Document], ext: str, cfg: dict[str, object], max_tokens: int = MAX_TOKENS
) -> list[list[Document]]:
    """이진탐색 기반 정확한 배치 생성"""
    if not document_chunks:
        return []

    batches: list[list[Document]] = []
    current_batch: list[Document] = []
    current_tokens: int = 0

    for chunk in document_chunks:
        chunk_tokens: int = count_tokens(chunk.page_content)

        if current_tokens + chunk_tokens <= max_tokens:
            current_batch.append(chunk)
            current_tokens += chunk_tokens
        else:
            if current_batch:
                remaining_tokens: int = max_tokens - current_tokens
                if remaining_tokens > 0:
                    # 청크를 분할하여 배치 최적화
                    front_chunks, back_chunks = rechunk_for_batch_optimization(
                        chunk, remaining_tokens, ext, cfg
                    )
                    current_batch.extend(front_chunks)
                    batches.append(current_batch)
                    current_batch = back_chunks
                    current_tokens = sum(count_tokens(c.page_content) for c in current_batch)
                else:
                    batches.append(current_batch)
                    current_batch = [chunk]
                    current_tokens = chunk_tokens
            else:
                current_batch = [chunk]
                current_tokens = chunk_tokens

    if current_batch:
        batches.append(current_batch)

    return batches


def rechunk_for_batch_optimization(
    chunk: Document,
    remaining_tokens: int,
    ext: str,
    cfg: dict[str, object],
) -> tuple[list[Document], list[Document]]:
    """이진탐색으로 정확한 분할점 찾기"""
    chunk_text: str = chunk.page_content
    current_tokens: int = count_tokens(chunk_text)

    if current_tokens <= remaining_tokens:
        return [chunk], []

    # splitter를 한 번만 생성
    splitter = get_splitter(ext, cfg)

    # 이진탐색으로 정확한 분할점 찾기
    left: int = 1
    right: int = len(chunk_text)
    best_size: int = 1

    while left <= right:
        mid: int = (left + right) // 2
        test_text: str = chunk_text[:mid]

        # splitter로 테스트
        test_chunks: list[str] = splitter.split_text(test_text)

        if test_chunks:
            # 모든 청크의 총 토큰 수 확인
            total_test_tokens: int = sum(count_tokens(text) for text in test_chunks)
            if total_test_tokens <= remaining_tokens:
                best_size = mid
                left = mid + 1
            else:
                right = mid - 1
        else:
            right = mid - 1

    # front/back 청크 생성
    front_chunks: list[Document] = []
    back_chunks: list[Document] = []

    if best_size > 0:
        front_text: str = chunk_text[:best_size]
        front_texts: list[str] = splitter.split_text(front_text)
        front_metadata = getattr(chunk, "metadata", {}) or {}
        front_chunks = [
            Document(page_content=text, metadata=dict(front_metadata)) for text in front_texts
        ]

    remaining_text: str = chunk_text[best_size:]
    if remaining_text.strip():
        back_metadata = getattr(chunk, "metadata", {}) or {}
        back_chunks = [Document(page_content=remaining_text, metadata=dict(back_metadata))]

    return front_chunks, back_chunks


def create_precise_batches(
    document_chunks: list[Document], ext: str, cfg: dict[str, object], max_tokens: int = MAX_TOKENS
) -> list[list[Document]]:
    """정확한 토큰 기반 배치 생성"""
    if not document_chunks:
        return []

    batches: list[list[Document]] = []
    current_batch: list[Document] = []
    current_tokens: int = 0

    for chunk in document_chunks:
        chunk_tokens: int = count_tokens(chunk.page_content)

        if current_tokens + chunk_tokens <= max_tokens:
            current_batch.append(chunk)
            current_tokens += chunk_tokens
        else:
            if current_batch:
                remaining_tokens: int = max_tokens - current_tokens

                if remaining_tokens > 0:
                    # 정확한 토큰 수로 분할
                    chunk_text: str = chunk.page_content
                    tokens = encoder.encode(chunk_text)

                    if len(tokens) <= remaining_tokens:
                        current_batch.append(chunk)
                        current_tokens += chunk_tokens
                        continue

                    front_tokens = tokens[:remaining_tokens]
                    back_tokens = tokens[remaining_tokens:]

                    front_text = encoder.decode(front_tokens)
                    back_text = encoder.decode(back_tokens)

                    chunk_metadata = getattr(chunk, "metadata", {}) or {}
                    front_chunk = Document(page_content=front_text, metadata=dict(chunk_metadata))
                    current_batch.append(front_chunk)
                    batches.append(current_batch)

                    if back_text.strip():
                        back_chunk = Document(page_content=back_text, metadata=dict(chunk_metadata))
                        current_batch = [back_chunk]
                        current_tokens = count_tokens(back_text)
                    else:
                        current_batch = []
                        current_tokens = 0
                else:
                    batches.append(current_batch)
                    current_batch = [chunk]
                    current_tokens = chunk_tokens
            else:
                current_batch = [chunk]
                current_tokens = chunk_tokens

    if current_batch:
        batches.append(current_batch)

    return batches


def create_heuristic_batches(
    document_chunks: list[Document], ext: str, cfg: dict[str, object], max_tokens: int = MAX_TOKENS
) -> list[list[Document]]:
    """평균값 기반 휴리스틱으로 배치 생성"""
    if not document_chunks:
        return []

    total_tokens: int = sum(count_tokens(chunk.page_content) for chunk in document_chunks)
    chunk_count: int = len(document_chunks)
    avg_tokens: float = total_tokens / chunk_count if chunk_count > 0 else 0.0
    chunks_per_batch: int = max(1, max_tokens // int(avg_tokens)) if avg_tokens > 0 else 1

    rechunked_chunks: list[Document] = []

    for i, chunk in enumerate(document_chunks):
        if (i + 1) % chunks_per_batch == 0:
            splitter = get_splitter(ext, cfg)

            if hasattr(splitter, "split_text"):
                # MarkdownTextSplitter
                markdown_texts: list[str] = splitter.split_text(chunk.page_content)
                chunk_metadata = getattr(chunk, "metadata", {}) or {}
                rechunked_chunks.extend(
                    [
                        Document(page_content=text, metadata=dict(chunk_metadata))
                        for text in markdown_texts
                    ]
                )
            else:
                # RecursiveCharacterTextSplitter
                recursive_chunks: list[Document] = splitter.split_documents([chunk])
                rechunked_chunks.extend(recursive_chunks)
        else:
            rechunked_chunks.append(chunk)

    # 최종 배치 생성
    batches: list[list[Document]] = []
    current_batch: list[Document] = []
    current_tokens: int = 0

    for chunk in rechunked_chunks:
        chunk_tokens: int = count_tokens(chunk.page_content)

        if current_tokens + chunk_tokens <= max_tokens:
            current_batch.append(chunk)
            current_tokens += chunk_tokens
        else:
            if current_batch:
                batches.append(current_batch)
            current_batch = [chunk]
            current_tokens = chunk_tokens

    if current_batch:
        batches.append(current_batch)

    return batches
