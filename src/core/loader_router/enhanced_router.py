import re
import subprocess
from contextlib import contextmanager
from pathlib import Path
from tempfile import TemporaryDirectory
from typing import Any, Generator, Union, cast

import pandas as pd
from langchain_community.document_loaders import (
    CSVLoader,
    DataFrameLoader,
    Docx2txtLoader,
    UnstructuredExcelLoader,
    UnstructuredPowerPointLoader,
)
from langchain_core.documents import Document
from langchain_unstructured.document_loaders import UnstructuredLoader
from omegaconf import DictConfig


def is_structured_data(text: str) -> bool:
    """정규식으로 정형 데이터 패턴 감지"""

    # 구분자로 연결된 숫자들 (하이픈, 공백, 슬래시, 콜론, 점, 언더스코어, 해시)
    if re.match(r"^\d+([\s\-/:._#]\d+)+$", text):
        return True

    return False


def is_only_special_characters(text: str) -> bool:
    """특수문자만 있는지 확인"""
    if not re.search(r"[가-힣a-zA-Z0-9]", text):
        return True
    return False


def is_numeric(val: Union[str, int, float, None]) -> bool:
    """값이 숫자인지 확인"""
    if val is None:
        return False

    if isinstance(val, (int, float)):
        return True

    # 문자열이 아닐 수 있으므로 안전하게 문자열로 변환 후 판단
    try:
        str_val = str(val).strip()
    except Exception:
        return False

    if not str_val:
        return False

    # 숫자 패턴 확인
    if re.match(r"^-?\d+\.?\d*$", str_val):
        return True

    # 과학적 표기법 ex) 1e-5, 3.2E+10, 2E8, -4.0e3
    if re.match(r"^-?\d+\.?\d*[eE][+-]?\d+$", str_val):
        return True

    return False


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
        try:
            dst: Path = _convert_with_soffice(path, target_ext, outdir, cfg)
            yield dst
        except Exception:
            # 변환 실패 시 예외를 올리지 않고 원본 경로로 계속 진행
            yield path


def load_document_with_router(path: Path, cfg: DictConfig) -> list[Document]:
    # 기본 라우터 (함수 내부에서만 사용)
    EXT_LOADER_ROUTER = {
        ".docx": Docx2txtLoader,
        ".pptx": UnstructuredPowerPointLoader,
        ".xlsx": DataFrameLoader,  # DataFrameLoader 사용 (.xls도 .xlsx로 변환됨)
        ".csv": DataFrameLoader,
        ".tsv": DataFrameLoader,
    }

    with temporary_ooxml(path, cfg) as proc_path:
        ext = proc_path.suffix.lower()
        loader_cls = EXT_LOADER_ROUTER.get(ext, UnstructuredLoader)

        loader_kwargs: dict[object, dict[str, Any]] = {
            Docx2txtLoader: {"file_path": str(proc_path)},
            UnstructuredPowerPointLoader: {"file_path": str(proc_path), "mode": "paged"},
        }

        if loader_cls is DataFrameLoader:
            # DataFrameLoader는 pandas DataFrame을 받아야 함
            # 파일 형식에 따라 적절한 함수로 DataFrame 생성 (확장자별 폴백 분리)
            if ext in [".xlsx", ".xls"]:
                try:
                    df: pd.DataFrame = pd.read_excel(str(proc_path), dtype=str)  # type: ignore
                except Exception:
                    # 엑셀 전용 폴백 로더
                    loader = UnstructuredExcelLoader(str(proc_path), mode="elements")
                    return loader.load()
            elif ext == ".tsv":
                try:
                    df: pd.DataFrame = pd.read_csv(str(proc_path), dtype=str, sep="\t")  # type: ignore
                except Exception:
                    # TSV 전용 폴백: CSVLoader (구분자 지정)
                    loader = CSVLoader(
                        str(proc_path), autodetect_encoding=True, csv_args={"delimiter": "\t"}
                    )
                    return loader.load()
            elif ext == ".csv":
                try:
                    df: pd.DataFrame = pd.read_csv(str(proc_path), dtype=str)  # type: ignore
                except Exception:
                    # CSV 전용 폴백
                    loader = CSVLoader(str(proc_path), autodetect_encoding=True)
                    return loader.load()
            else:
                raise ValueError(f"지원하지 않는 파일 형식: {ext}")

            def process_row(x: pd.Series) -> str:
                """의미있는 텍스트만 추출 (정형데이터 제외)"""
                meaningful_cells: list[str] = []

                for val in x:
                    # 1단계: 기본 필터링
                    if pd.isna(val) or val is None:
                        continue

                    str_val: str = str(val).strip()
                    if not str_val or str_val.lower() == "nan":
                        continue

                    # 2단계: 숫자 타입 제거
                    if is_numeric(val):
                        continue

                    # 3단계: 정형 데이터 패턴 제거 (전화번호, 코드, ID 등)
                    if is_structured_data(str_val):
                        continue

                    # 4단계: 특수문자만 있는 경우 제외
                    if is_only_special_characters(str_val):
                        continue

                    # 5단계: 너무 긴 텍스트 제거
                    if len(str_val) > 1000:
                        continue

                    meaningful_cells.append(str_val)

                return "|".join(meaningful_cells) if meaningful_cells else ""

            def extract_row_data(x: pd.Series) -> dict[str, Union[str, int, float]]:
                """모든 열을 row_data에 포함"""
                row_data: dict[str, Union[str, int, float]] = {}

                for col_name, val in x.items():
                    # NaN이나 None이 아닌 모든 값 포함
                    if not pd.isna(val) and val is not None:
                        str_val: str = str(val).strip()
                        if str_val and str_val.lower() != "nan":
                            row_data[str(col_name)] = val

                return row_data

            # 1단계: 필터링된 텍스트만 DataFrame에 저장
            df["text"] = df.apply(process_row, axis=1)

            # 2단계: 모든 행 데이터를 별도 컬럼으로 저장
            df["row_data"] = df.apply(extract_row_data, axis=1)

            # 3단계: DataFrameLoader 사용 (text 컬럼만 사용)
            loader = DataFrameLoader(df, page_content_column="text")
            documents: list[Document] = loader.load()

            # 빈 텍스트 문서 제거 (의미 없는 행 제외)
            documents = [document for document in documents if document.page_content.strip()]

            # 4단계: 후처리로 row_data를 메타데이터에 추가
            for index, document in enumerate(documents):
                if document.page_content:  # 의미있는 텍스트가 있는 경우만
                    # 기존 메타데이터 초기화
                    document.metadata = {"source": str(proc_path)}

                    # row_data를 메타데이터에 추가
                    row_data: dict[str, Union[str, int, float]] = cast(
                        dict[str, Union[str, int, float]], df.iloc[index]["row_data"]
                    )
                    # 메타데이터 타입을 명시적으로 지정
                    metadata_dict: dict[
                        str, Union[str, int, float, dict[str, Union[str, int, float]]]
                    ] = {"source": str(proc_path), "row_data": row_data, "row_index": index}
                    document.metadata = metadata_dict

            return documents
        else:
            # 내장 dict 사용하면 타입 체크 더 엄격해서 Any 타입 사용하지 않으면 충돌 발생
            kwargs: dict[str, Any] = loader_kwargs.get(loader_cls, {"file_path": str(proc_path)})
            loader = loader_cls(**kwargs)
        return loader.load()
