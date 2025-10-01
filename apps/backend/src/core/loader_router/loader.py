import os
from pathlib import Path
from typing import Any, Mapping, Union, cast

from langchain_community.document_loaders import (
    CSVLoader,
    Docx2txtLoader,
    PyMuPDFLoader,
    TextLoader,
)
from langchain_core.documents import Document
from langchain_teddynote.document_loaders import HWPLoader
from langchain_unstructured.document_loaders import UnstructuredLoader
from omegaconf import DictConfig

from .enhanced_router import load_document_with_router


class EnhancedRouterLoader:
    def __init__(self, path: str, cfg: DictConfig, mode: str = "paged"):
        self.path = path
        self.cfg = cfg
        self.mode = mode

    def load(self) -> list[Document]:
        return load_document_with_router(Path(self.path), self.cfg)


LoaderType = Union[
    TextLoader,
    PyMuPDFLoader,
    Docx2txtLoader,
    CSVLoader,
    HWPLoader,
    EnhancedRouterLoader,
    UnstructuredLoader,
]

EXT_LOADER_ROUTER: Mapping[str, type[LoaderType]] = {
    "txt": TextLoader,
    "md": TextLoader,
    "org": TextLoader,
    "docx": Docx2txtLoader,
    "doc": EnhancedRouterLoader,
    "pdf": PyMuPDFLoader,
    "xlsx": EnhancedRouterLoader,
    "xls": EnhancedRouterLoader,
    "csv": EnhancedRouterLoader,
    "tsv": EnhancedRouterLoader,
    "pptx": EnhancedRouterLoader,
    "ppt": EnhancedRouterLoader,
    "hwp": HWPLoader,
    "rtf": TextLoader,
}


def get_loader(path: str, cfg: DictConfig) -> LoaderType:
    ext = os.path.splitext(path)[1].lower()[1:]
    # fallback 로더로 사용
    loader_cls = EXT_LOADER_ROUTER.get(ext, UnstructuredLoader)

    loader_kwargs: dict[object, dict[str, str | bool]] = {
        TextLoader: {"encoding": "utf-8"},
        CSVLoader: {"autodetect_encoding": True},
    }

    kwargs: dict[str, Any] = loader_kwargs.get(loader_cls, {})

    # EnhancedRouterLoader는 cfg가 필요함
    if loader_cls == EnhancedRouterLoader:
        return cast(LoaderType, EnhancedRouterLoader(path, cfg, **kwargs))
    else:
        # 모든 로더는 위치 인자로 path 전달 (Any 캐스팅으로 타입 체커 우회)
        return loader_cls(path, **kwargs)


# 폴더 내 모든 파일 경로 수집
def get_file_paths(folder_path: str) -> list[str]:
    file_paths: list[str] = []
    for file in os.listdir(folder_path):
        full_path = os.path.join(folder_path, file)
        if os.path.isfile(full_path):
            file_paths.append(full_path)
    return file_paths


def connect_loader(
    folder_path: str, cfg: DictConfig, extensions: list[str] = []
) -> tuple[list[list[Document]], list[str]]:
    documents: list[list[Document]] = []
    failed_files: list[str] = []
    file_paths = get_file_paths(folder_path)
    for file_path in file_paths:
        ext = os.path.splitext(file_path)[1].lower()
        if ext not in extensions:
            continue  # 지정한 확장자가 아니면 스킵
        loader = get_loader(file_path, cfg)
        try:
            loaded = loader.load()
            documents.append(loaded)
        except Exception as e:
            print(f"[ERROR] 파일 로드 실패: {file_path} ({type(e).__name__}) - {e}")
            # 런타임 폴백: UnstructuredLoader로 한 번 더 시도
            try:
                if not isinstance(loader, UnstructuredLoader):
                    fallback_loader = UnstructuredLoader(file_path)
                    loaded_fallback = fallback_loader.load()
                    documents.append(loaded_fallback)
                    print(f"[FALLBACK] UnstructuredLoader 성공: {file_path}")
                    continue
            except Exception as fe:
                print(f"[ERROR] 폴백 실패: {file_path} ({type(fe).__name__}) - {fe}")
            failed_files.append(file_path)
            continue
    return documents, failed_files
