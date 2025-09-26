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


def get_relative_path_from_home(file_path: Path) -> str | None:
    """HOME 디렉토리 기준 상대 경로를 ~/... 형태로 반환합니다.

    Args:
        file_path: 절대 경로가 아닌 경우 resolve()하여 처리

    Returns:
        HOME 디렉토리 하위에 있으면 ~/... 형태 경로 문자열, 아니면 None

    Examples:
        ~/Documents/project/file.txt
        ~/Desktop/test.py
    """
    home_path = Path.home()
    resolved_path = file_path.resolve()
    try:
        relative_path = resolved_path.relative_to(home_path)
        return f"~/{relative_path}"
    except ValueError:
        # 파일이 HOME 디렉토리 하위에 없는 경우
        return None
