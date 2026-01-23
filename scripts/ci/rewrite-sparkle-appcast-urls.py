#!/usr/bin/env python3
import re
import sys


def main() -> int:
    if len(sys.argv) != 3:
        sys.stderr.write(
            "Usage: rewrite-sparkle-appcast-urls.py <appcast_path> <download_prefix>\n"
        )
        return 2

    appcast_path, download_prefix = sys.argv[1:]
    download_prefix = download_prefix.rstrip("/")

    with open(appcast_path, "r", encoding="utf-8") as handle:
        content = handle.read()

    pattern = re.compile(r'url="[^"]*?Voyager-([^/"]+)\.zip"')
    content = pattern.sub(
        lambda match: f'url="{download_prefix}/{match.group(1)}/Voyager-{match.group(1)}.zip"',
        content,
    )

    with open(appcast_path, "w", encoding="utf-8") as handle:
        handle.write(content)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
