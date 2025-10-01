from __future__ import annotations

import os
import subprocess
import sys

from utils.paths import get_source_path

MAIN_FILE = get_source_path() / "app" / "main.py"


def _run_fastapi(*args: str, env: dict[str, str] | None = None) -> int:
    cmd = [sys.executable, "-m", "fastapi", *args]
    proc = subprocess.Popen(cmd, env=env)
    try:
        return proc.wait()
    except KeyboardInterrupt:
        try:
            proc.wait(timeout=1)
        except Exception:
            pass
        return 130


def _with_env(default_env: str) -> dict[str, str]:
    merged = os.environ.copy()
    merged.setdefault("APP_ENV", default_env)
    return merged


def dev() -> None:
    exit_code = _run_fastapi("dev", str(MAIN_FILE), env=_with_env("dev"))
    raise SystemExit(exit_code)


def prod() -> None:
    exit_code = _run_fastapi("run", str(MAIN_FILE), env=_with_env("prod"))
    raise SystemExit(exit_code)
