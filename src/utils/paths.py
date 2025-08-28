from pathlib import Path


def get_root_path() -> Path:
    current = Path(__file__).resolve()
    for parent in [current, *current.parents]:
        if (parent / "pyproject.toml").exists():
            return parent
    raise RuntimeError("Project root not found (missing pyproject.toml)")


def get_source_path() -> Path:
    return get_root_path() / "src"
