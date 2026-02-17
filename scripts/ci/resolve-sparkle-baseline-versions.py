#!/usr/bin/env python3
import re
import sys


def main() -> int:
    if len(sys.argv) != 4:
        sys.stderr.write(
            "Usage: resolve-sparkle-baseline-versions.py <appcast_path> <current_version> <count>\n"
        )
        return 2

    appcast_path, current_version, count_value = sys.argv[1:]

    try:
        count = int(count_value)
    except ValueError:
        sys.stderr.write("Count must be an integer.\n")
        return 2

    with open(appcast_path, "r", encoding="utf-8") as handle:
        content = handle.read()

    pattern = re.compile(r"Voyager-([0-9A-Za-z][0-9A-Za-z.\-]*)\.zip")
    seen = set()
    versions = []
    for match in pattern.finditer(content):
        version = match.group(1)
        if version == current_version or version in seen:
            continue
        seen.add(version)
        versions.append(version)
        if len(versions) >= count:
            break

    sys.stdout.write("\n".join(versions))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
