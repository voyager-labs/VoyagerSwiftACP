from pathlib import Path


def get_root_path() -> Path:
    current = Path(__file__).resolve()
    for parent in [current, *current.parents]:
        if (parent / "pyproject.toml").exists():
            return parent
    raise RuntimeError("Project root not found (missing pyproject.toml)")


def get_source_path() -> Path:
    return get_root_path() / "src"


def calculate_depth_from_home(file_path: Path) -> int:
    """HOME 디렉토리로부터의 깊이를 계산합니다."""
    home_path = Path.home()
    try:
        relative_path = file_path.relative_to(home_path)
        return len(relative_path.parts) - 1  # 파일 자체는 제외하고 디렉토리 깊이만 계산
    except ValueError:
        # 파일이 HOME 디렉토리 하위에 없는 경우
        return -1
