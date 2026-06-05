#!/usr/bin/env python3
from __future__ import annotations

import shutil
import subprocess
import sys
from pathlib import Path


ROOT_DIR = Path(__file__).resolve().parents[2]


def run(args: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        args,
        cwd=ROOT_DIR,
        check=False,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )


def fail(message: str) -> None:
    print(message, file=sys.stderr)
    raise SystemExit(1)


def main() -> None:
    expected_version = (ROOT_DIR / ".swift-toolchain-version").read_text().strip()
    if not expected_version:
        fail(".swift-toolchain-version is empty")

    swift = run(["xcrun", "swift", "--version"])
    if swift.returncode != 0:
        fail(swift.stderr.strip() or "Failed to run xcrun swift --version")

    expected_marker = f"Apple Swift version {expected_version}"
    if expected_marker not in swift.stdout:
        print("Swift version mismatch.", file=sys.stderr)
        print(f"Expected: {expected_marker}", file=sys.stderr)
        print("Actual:", file=sys.stderr)
        print(swift.stdout.strip(), file=sys.stderr)
        print("Run: mise run xcode", file=sys.stderr)
        raise SystemExit(1)

    print(swift.stdout, end="")

    if shutil.which("swiftly") is None:
        return

    swiftly = run(["swiftly", "use"])
    swiftly_output = "\n".join(
        line.strip()
        for line in (swiftly.stdout + swiftly.stderr).splitlines()
        if line.strip()
    )
    swiftly_lines = swiftly_output.splitlines()
    swiftly_selection = next(
        (line for line in reversed(swiftly_lines) if line.startswith("xcode")),
        swiftly_output,
    )

    if "xcode" not in swiftly_selection:
        print("Swiftly is not using the repo Xcode toolchain.", file=sys.stderr)
        print("Expected: xcode", file=sys.stderr)
        print(f"Actual: {swiftly_selection or 'unavailable'}", file=sys.stderr)
        print("Run: swiftly use xcode --global-default", file=sys.stderr)
        raise SystemExit(1)

    print(f"swiftly: {swiftly_selection}")


if __name__ == "__main__":
    main()
