"""
청커 모듈 - 문서 청킹 및 배치 처리
"""

from collections.abc import Mapping
from typing import Generator, TypeAlias, cast

from langchain_core.documents import Document
from langchain_text_splitters import MarkdownTextSplitter, RecursiveCharacterTextSplitter

TextSplitter: TypeAlias = MarkdownTextSplitter | RecursiveCharacterTextSplitter

"""구성 타입(내장 제네릭 사용)"""
ChunkingDefaults: TypeAlias = Mapping[str, int | bool]
PerExtConfig: TypeAlias = Mapping[str, Mapping[str, int | bool]]


def _select_chunk_params(
    ext: str, defaults: ChunkingDefaults, per_ext: PerExtConfig
) -> dict[str, int | bool]:
    """Hydra가 보장하는 defaults/per_ext를 그대로 병합하여 반환."""
    params: dict[str, int | bool] = dict(defaults)
    override = per_ext.get(ext)
    if override is not None:
        params.update(override)
    return params


def get_splitter(ext: str, cfg: dict[str, object]) -> TextSplitter:
    """Hydra 설정을 사용해 스플리터를 생성"""
    chunking = cast(dict[str, object], cfg["chunking"])  # 필수 키 전제
    defaults = cast(ChunkingDefaults, chunking["defaults"])  # 필수 키 전제
    per_ext = cast(PerExtConfig, chunking["per_ext"])  # 필수 키 전제
    params = _select_chunk_params(ext, defaults, per_ext)

    chunk_size: int = int(params["chunk_size"])  # 필수 키 전제
    chunk_overlap: int = int(params["chunk_overlap"])  # 필수 키 전제
    use_markdown_splitter: bool = bool(params.get("use_markdown_splitter", False))

    if use_markdown_splitter:
        return MarkdownTextSplitter(chunk_size=chunk_size, chunk_overlap=chunk_overlap)

    return RecursiveCharacterTextSplitter(chunk_size=chunk_size, chunk_overlap=chunk_overlap)


def chunk_documents(
    docs_by_file: list[list[Document]], ext: str, cfg: dict[str, object]
) -> Generator[Document, None, None]:
    """제너레이터 방식으로 문서 청킹 (메모리 효율적)

    Args:
        docs_by_file: 파일별로 그룹화된 Document 리스트
        ext: 파일 확장자

    Yields:
        Document: 청킹된 문서 청크들 (지연 평가)
    """
    if not docs_by_file:
        return

    splitter: TextSplitter = get_splitter(ext, cfg)

    for file_documents in docs_by_file:
        if not file_documents:
            continue

        for document in file_documents:
            if not document.page_content.strip():
                continue

            if isinstance(splitter, MarkdownTextSplitter):
                markdown_texts: list[str] = splitter.split_text(document.page_content)
                document_metadata = getattr(document, "metadata", {})
                for text in markdown_texts:
                    yield Document(page_content=text, metadata=dict(document_metadata))
            else:
                # RecursiveCharacterTextSplitter는 List[Document]를 반환하므로 yield from 사용
                yield from splitter.split_documents([document])
