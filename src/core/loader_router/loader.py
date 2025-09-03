import nltk
# nltk.download('averaged_perceptron_tagger')
import traceback
import os
import chardet
import magic
from langchain_docling import DoclingLoader
from langchain_unstructured.document_loaders import UnstructuredLoader
from langchain_pymupdf4llm import PyMuPDF4LLMLoader
from langchain_community.document_loaders.pdf import ZeroxPDFLoader
from langchain_community.document_loaders import (
    DirectoryLoader,
    TextLoader,
    PyMuPDFLoader,
    UnstructuredPowerPointLoader,
    Docx2txtLoader,
    DataFrameLoader,
    CSVLoader,
    UnstructuredCSVLoader,
    PolarsDataFrameLoader,
    UnstructuredExcelLoader,
    UnstructuredTSVLoader,
    UnstructuredWordDocumentLoader,
    PyMuPDFLoader,
    PDFMinerLoader,
    PDFPlumberLoader,
    PyPDFLoader,
    PyPDFDirectoryLoader,
    PyPDFium2Loader,
    UnstructuredPDFLoader,
    UnstructuredTSVLoader,
    UnstructuredOrgModeLoader,
    UnstructuredMarkdownLoader
)

EXT_LOADER_ROUTER = {
    ".txt": TextLoader,
    ".md": TextLoader,
    ".pdf": PyMuPDFLoader,
    ".docx": UnstructuredWordDocumentLoader,
    ".xlsx": DoclingLoader,
    ".csv": TextLoader,
    ".tsv": UnstructuredTSVLoader,
    ".pptx": UnstructuredPowerPointLoader,
    ".ppt": UnstructuredPowerPointLoader,
    ".xls": DoclingLoader,
    ".tsv": UnstructuredTSVLoader,
    ".org": UnstructuredOrgModeLoader
}

def get_loader(path):
    ext = os.path.splitext(path)[1].lower()
    loader_cls = EXT_LOADER_ROUTER.get(ext, UnstructuredLoader)

    if ext == ".txt":
        # TextLoader는 encoding 파라미터 사용
        return loader_cls(path, encoding="utf-8")  # 또는 encoding=None
    elif ext == ".csv":
        # CSVLoader는 autodetect_encoding 파라미터 사용
        return loader_cls(path, autodetect_encoding=True)
    else:
        # 그 외는 인코딩 없이 Loader 인스턴스 생성
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
    # fallback_count = 0
    file_paths = get_file_paths(folder_path)
    for file_path in file_paths:
        ext = os.path.splitext(file_path)[1].lower()
        if extensions is not None and ext not in extensions:
            continue  # 지정한 확장자가 아니면 스킵
        loader = get_loader(file_path)
        try:
            loaded = loader.load()
            docs.extend(loaded)
        except Exception as e:
            print(f"[ERROR] 파일 로드 실패: {file_path} ({type(e).__name__}) - {e}")
            # traceback.print_exc()
            failed_files.append(file_path)
            continue
    return docs, failed_files

