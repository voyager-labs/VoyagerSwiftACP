import subprocess
from contextlib import contextmanager
from pathlib import Path
from tempfile import TemporaryDirectory
from typing import Any, Dict, Generator, List

import pandas as pd
from langchain_community.document_loaders import (
    DataFrameLoader,
    Docx2txtLoader,
    UnstructuredExcelLoader,
    UnstructuredPowerPointLoader,
)
from langchain_core.documents import Document
from langchain_unstructured.document_loaders import UnstructuredLoader
from omegaconf import DictConfig


def _get_soffice_path(cfg: DictConfig) -> str:
    """LibreOffice 경로를 하이드라 설정에서 가져옴"""
    return cfg.libreoffice.soffice_path


def _convert_with_soffice(src: Path, target_ext: str, outdir: Path, cfg: DictConfig) -> Path:
    """soffice --convert-to로 변환"""
    cmd = [
        _get_soffice_path(cfg),
        "--headless",
        "--convert-to",
        target_ext,
        "--outdir",
        str(outdir),
        str(src),
    ]

    try:
        subprocess.run(cmd, capture_output=True, text=True, timeout=30, check=True)
        dst_file: Path = outdir / (src.stem + "." + target_ext)
        if not dst_file.exists():
            raise RuntimeError(f"변환된 파일이 존재하지 않음: {dst_file}")
        return dst_file
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as e:
        raise RuntimeError(f"LibreOffice 변환 실패: {e}")


@contextmanager
def temporary_ooxml(path: Path, cfg: DictConfig) -> Generator[Path, None, None]:
    """
    .doc/.ppt는 임시 디렉토리에 .docx/.pptx로 변환해 사용하고 종료 시 삭제.
    원본/확장자는 변경하지 않음. .docx/.pptx는 그대로 반환.
    """
    ext = path.suffix.lower()
    if ext not in {".doc", ".ppt", ".xls"}:
        yield path
        return

    # 변환
    target_ext = {".doc": "docx", ".ppt": "pptx", ".xls": "xlsx"}[ext]

    with TemporaryDirectory(prefix="voy-ooxml-") as td:
        outdir = Path(td)
        dst: Path = _convert_with_soffice(path, target_ext, outdir, cfg)
        yield dst


def load_document_with_router(path: Path, cfg: DictConfig) -> List[Document]:
    # 기본 라우터 (함수 내부에서만 사용)
    EXT_LOADER_ROUTER = {
        ".docx": Docx2txtLoader,
        ".pptx": UnstructuredPowerPointLoader,
        ".xlsx": DataFrameLoader,  # DataFrameLoader 사용 (.xls도 .xlsx로 변환됨)
    }

    with temporary_ooxml(path, cfg) as proc_path:
        ext = proc_path.suffix.lower()
        loader_cls = EXT_LOADER_ROUTER.get(ext, UnstructuredLoader)

        loader_kwargs: Dict[type, Dict[str, Any]] = {
            Docx2txtLoader: {"path": str(proc_path)},
            UnstructuredPowerPointLoader: {"path": str(proc_path), "mode": "paged"},
        }

        if loader_cls is DataFrameLoader:
            # DataFrameLoader는 pandas DataFrame을 받아야 함
            try:
                df: pd.DataFrame = pd.read_excel(str(proc_path))  # type: ignore
                df["text"] = df.astype(str).apply(lambda x: " | ".join(x.dropna()), axis=1)  # type: ignore
                loader = DataFrameLoader(df, page_content_column="text")
            except Exception:
                # DataFrameLoader 실패 시 UnstructuredExcelLoader로 fallback
                loader = UnstructuredExcelLoader(str(proc_path), mode="elements")
        else:
            kwargs: Dict[str, Any] = loader_kwargs.get(loader_cls, {"path": str(proc_path)})
            loader = loader_cls(**kwargs)
        return loader.load()
