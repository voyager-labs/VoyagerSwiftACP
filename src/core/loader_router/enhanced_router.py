import os
import subprocess
from contextlib import contextmanager
from tempfile import TemporaryDirectory
from pathlib import Path
from typing import Optional, Union

from langchain_community.document_loaders import (
    UnstructuredFileLoader,
    Docx2txtLoader,
    UnstructuredPowerPointLoader,
    UnstructuredExcelLoader,
    DataFrameLoader
)

def _get_soffice_path():
    """LibreOffice 경로를 Hydra config에서 가져옴"""
    try:
        import sys
        sys.path.append(str(Path(__file__).parent.parent.parent / "src"))
        from app.config import load_config
        config = load_config()
        return config.libreoffice.soffice_path
    except (ImportError, AttributeError):
        # 설정 로드 실패 시 환경변수로 fallback
        soffice = os.environ.get("SOFFICE") or os.environ.get("LIBREOFFICE_PATH")
        if not soffice:
            raise ValueError("SOFFICE 또는 LIBREOFFICE_PATH 환경변수가 설정되어야 합니다")
        return soffice

# 기본 라우터(필요시 외부에서 주입 가능)
EXT_LOADER_ROUTER = {
    ".docx": Docx2txtLoader,
    ".pptx": UnstructuredPowerPointLoader,
    ".xlsx": DataFrameLoader,  # DataFrameLoader 사용 (.xls도 .xlsx로 변환됨)
}

def _convert_with_soffice(src: Path, target_ext: str, outdir: Path) -> Path:
    """soffice --convert-to로 변환"""
    cmd = [
        _get_soffice_path(),
        "--headless",
        "--convert-to",
        target_ext,
        "--outdir",
        str(outdir),
        str(src),
    ]
    
    try:
        subprocess.run(cmd, capture_output=True, text=True, timeout=30, check=True)
        dst_file = outdir / (src.stem + "." + target_ext)
        return dst_file if dst_file.exists() else None
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired):
        return None

@contextmanager
def temporary_ooxml(path: Union[str, Path]):
    """
    .doc/.ppt는 임시 디렉토리에 .docx/.pptx로 변환해 사용하고 종료 시 삭제.
    원본/확장자는 변경하지 않음. .docx/.pptx는 그대로 반환.
    """
    p = Path(path)
    ext = p.suffix.lower()
    if ext not in {".doc", ".ppt", ".xls"}:  
        yield p
        return

    # 변환
    target_ext = {".doc": "docx", ".ppt": "pptx", ".xls": "xlsx"}[ext]
    
    with TemporaryDirectory(prefix="voy-ooxml-") as td:
        outdir = Path(td)
        dst = _convert_with_soffice(p, target_ext, outdir)
        if not dst:
            raise RuntimeError(f"변환 실패: {p} → *.{target_ext}")
        yield dst

def load_with_router(path: Union[str, Path],
                    router: Optional[dict[str, type]] = None,
                    mode: str = None):  # 기본값 제거
    r = router or EXT_LOADER_ROUTER
    
    with temporary_ooxml(path) as proc_path:
        ext = proc_path.suffix.lower()
        loader_cls = r.get(ext, UnstructuredFileLoader)

        if loader_cls is Docx2txtLoader:
            loader = loader_cls(str(proc_path))
        elif loader_cls is UnstructuredPowerPointLoader:
            loader = loader_cls(str(proc_path), mode="paged")
        elif loader_cls is DataFrameLoader:
            # DataFrameLoader는 pandas DataFrame을 받아야 함
            try:
                import pandas as pd
                df = pd.read_excel(str(proc_path))
                df['text'] = df.astype(str).apply(lambda x: ' | '.join(x.dropna()), axis=1)
                loader = loader_cls(df, page_content_column='text')
            except Exception:
                # DataFrameLoader 실패 시 UnstructuredExcelLoader로 fallback
                loader = UnstructuredExcelLoader(str(proc_path), mode="elements")
        else:
            loader = loader_cls(str(proc_path))
        return loader.load()