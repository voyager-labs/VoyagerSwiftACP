import os
from langchain_unstructured.document_loaders import UnstructuredLoader
from langchain_teddynote.document_loaders import HWPLoader
from langchain_community.document_loaders import (
    TextLoader,
    PyMuPDFLoader,
    Docx2txtLoader,
    CSVLoader,
)
from .enhanced_router import load_with_router

class EnhancedRouterLoader:
    def __init__(self, path, mode="paged", strategy="fast", hi_res_model_disabled=True):
        self.path = path
        self.mode = mode
        # strategy, hi_res_model_disabled는 현재 load_with_router에서 사용하지 않음

    def load(self):
        return load_with_router(self.path, mode=self.mode)

EXT_LOADER_ROUTER = {
    ".txt": TextLoader,
    ".md": TextLoader,
    ".org": TextLoader,
    ".docx": Docx2txtLoader,
    ".doc": EnhancedRouterLoader,
    ".pdf": PyMuPDFLoader,
    ".xlsx": EnhancedRouterLoader,
    ".xls": EnhancedRouterLoader,
    ".csv": CSVLoader,
    ".tsv": CSVLoader,
    ".pptx": EnhancedRouterLoader,
    ".ppt": EnhancedRouterLoader,
    ".hwp": HWPLoader,
    ".rtf": TextLoader
}

def get_loader(path):
    ext = os.path.splitext(path)[1].lower()
    # fallback 로더로 사용
    loader_cls = EXT_LOADER_ROUTER.get(ext, UnstructuredLoader)

    if ext == ".txt":
        return loader_cls(path, encoding="utf-8")
    elif ext == ".csv":
        return loader_cls(path, autodetect_encoding=True)
    else:
        return loader_cls(path)


# 폴더 내 모든 파일 경로 수집
def get_file_paths(folder_path):
    file_paths = []
    for file in os.listdir(folder_path):
        full_path = os.path.join(folder_path, file)
        if os.path.isfile(full_path):
            file_paths.append(full_path)
    return file_paths


def connect_loader(folder_path, extensions=None):
    docs = []
    failed_files = []
    file_paths = get_file_paths(folder_path)
    for file_path in file_paths:
        ext = os.path.splitext(file_path)[1].lower()
        if extensions is not None and ext not in extensions:
            continue  # 지정한 확장자가 아니면 스킵
        loader = get_loader(file_path)
        try:
            loaded = loader.load()
            docs.append(loaded)
        except Exception as e:
            print(f"[ERROR] 파일 로드 실패: {file_path} ({type(e).__name__}) - {e}")
            failed_files.append(file_path)
            continue
    return docs, failed_files

