#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
from pathlib import Path


ROOT_DIR = Path(__file__).resolve().parents[2]


def fail(message: str) -> None:
    print(message, file=sys.stderr)
    raise SystemExit(1)


def main() -> None:
    project_path = os.environ.get(
        "PROJECT_PATH", "apps/macos/Voyager/Voyager.xcodeproj"
    )
    scheme = os.environ.get("SCHEME", "Voyager-Dev")
    build_dir = Path(os.environ.get("BUILD_DIR", str(ROOT_DIR / "build/dev")))
    derived_data_path = Path(
        os.environ.get("DERIVED_DATA_PATH", str(build_dir / "DerivedData"))
    )

    if shutil.which("xcode-build-server") is None:
        fail("xcode-build-server is not installed. Run: mise run lsp-install")

    derived_data_path.mkdir(parents=True, exist_ok=True)

    subprocess.run(
        ["xcode-build-server", "config", "-project", project_path, "-scheme", scheme],
        cwd=ROOT_DIR,
        check=True,
    )

    config_path = ROOT_DIR / "buildServer.json"
    config = json.loads(config_path.read_text())
    config["build_root"] = str(derived_data_path)
    config_path.write_text(json.dumps(config, indent=2) + "\n")

    print(f"Generated buildServer.json for {scheme}")
    print(f"build_root: {derived_data_path}")


if __name__ == "__main__":
    main()
