#!/usr/bin/env python3
"""Migrate Voyager FEATURE_INVENTORY tables to schema v2.

This script is designed to be deterministic and minimally invasive:
- It inserts new key columns without reformatting other cells.
- It preserves CRLF line endings if the input file uses CRLF.

Migrations:
- FEATURES/data.tsv: add `category_key` (derived from feature_id prefix)
- INTERACTIONS/data.tsv: add `interaction_id` (generated as <FEATURE_ID>-<snake_slug>)

Notes:
- `interaction_id` generation is one-time. After migration, treat the ID as stable.
- If `feature_id` is missing/blank on an interaction row, prefix defaults to "UNK-000".
"""

from __future__ import annotations

import re
import sys
from dataclasses import dataclass
from pathlib import Path


FEATURES_TSV = Path("PRODUCT/04_FEATURE_INVENTORY/FEATURES/data.tsv")
INTERACTIONS_TSV = Path("PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv")


def find_repo_root(start: Path) -> Path:
    start = start.resolve()
    for p in [start] + list(start.parents):
        if (p / ".git").is_dir():
            return p
    return start


@dataclass(frozen=True)
class TextFile:
    text: str
    newline: str
    has_trailing_newline: bool


def read_text_preserve_newline(path: Path) -> TextFile:
    data = path.read_bytes()

    # Newline detection: prefer CRLF if present.
    newline = "\r\n" if b"\r\n" in data else "\n"
    text = data.decode("utf-8")
    has_trailing_newline = text.endswith(newline)
    return TextFile(
        text=text, newline=newline, has_trailing_newline=has_trailing_newline
    )


def write_text_preserve_newline(path: Path, file: TextFile) -> None:
    # Ensure consistent trailing newline behavior.
    out = file.text
    if file.has_trailing_newline and not out.endswith(file.newline):
        out += file.newline
    if not file.has_trailing_newline and out.endswith(file.newline):
        out = out[: -len(file.newline)]
    path.write_bytes(out.encode("utf-8"))


def split_lines(file: TextFile) -> list[str]:
    # Keep behavior stable even if the last line has no newline.
    lines = file.text.split(file.newline)
    if file.has_trailing_newline:
        lines = lines[:-1]
    return lines


def join_lines(lines: list[str], template: TextFile) -> TextFile:
    return TextFile(
        text=template.newline.join(lines),
        newline=template.newline,
        has_trailing_newline=template.has_trailing_newline,
    )


def feature_prefix(feature_id: str) -> str:
    fid = feature_id.strip()
    if "-" in fid:
        return fid.split("-", 1)[0]
    return fid


def slug_pascal_case(text: str) -> str:
    # Convert a title into a stable-ish identifier.
    # Keep only alnum tokens, then PascalCase.
    cleaned = re.sub(r"[^A-Za-z0-9]+", " ", text).strip()
    if not cleaned:
        return "Untitled"
    parts = [p for p in cleaned.split(" ") if p]

    def cap(p: str) -> str:
        if p.isupper() and len(p) > 1:
            return p
        return p[:1].upper() + p[1:]

    return "".join(cap(p) for p in parts)


def slug_snake_case(text: str) -> str:
    cleaned = re.sub(r"[^A-Za-z0-9]+", " ", text).strip()
    if not cleaned:
        return "untitled"
    parts = [p for p in cleaned.split(" ") if p]
    return "_".join(p.lower() for p in parts)


def insert_column(
    header: list[str], row: list[str], *, index: int, value: str
) -> list[str]:
    out = list(row)
    out.insert(index, value)
    # Keep row length aligned with header length.
    if len(out) < len(header):
        out.extend([""] * (len(header) - len(out)))
    elif len(out) > len(header):
        out = out[: len(header)]
    return out


def migrate_features(repo_root: Path) -> bool:
    path = repo_root / FEATURES_TSV
    tf = read_text_preserve_newline(path)
    lines = split_lines(tf)
    if not lines:
        raise ValueError(f"Empty TSV: {FEATURES_TSV}")

    header = lines[0].split("\t")
    if "category_key" in header:
        return False

    if "feature_category" not in header or "feature_id" not in header:
        raise ValueError(
            "FEATURES TSV missing required columns (feature_category/feature_id)"
        )

    insert_at = header.index("feature_category") + 1
    new_header = list(header)
    new_header.insert(insert_at, "category_key")

    idx_feature_id = header.index("feature_id")
    new_lines: list[str] = ["\t".join(new_header)]

    for line in lines[1:]:
        row = line.split("\t")
        # Pad rows that are short.
        if len(row) < len(header):
            row = row + ([""] * (len(header) - len(row)))

        fid = row[idx_feature_id]
        ck = feature_prefix(fid)
        row2 = insert_column(new_header, row, index=insert_at, value=ck)
        new_lines.append("\t".join(row2))

    write_text_preserve_newline(path, join_lines(new_lines, tf))
    return True


def migrate_interactions(repo_root: Path) -> bool:
    path = repo_root / INTERACTIONS_TSV
    tf = read_text_preserve_newline(path)
    lines = split_lines(tf)
    if not lines:
        raise ValueError(f"Empty TSV: {INTERACTIONS_TSV}")

    header = lines[0].split("\t")
    if "interaction_id" in header:
        return False

    if "interaction_title" not in header:
        raise ValueError("INTERACTIONS TSV missing interaction_title")

    insert_at = header.index("interaction_title") + 1
    new_header = list(header)
    new_header.insert(insert_at, "interaction_id")

    idx_title = header.index("interaction_title")
    idx_feature_id = header.index("feature_id") if "feature_id" in header else None

    used: dict[str, int] = {}
    new_lines: list[str] = ["\t".join(new_header)]

    for line in lines[1:]:
        row = line.split("\t")
        if len(row) < len(header):
            row = row + ([""] * (len(header) - len(row)))

        title = row[idx_title]
        fid = row[idx_feature_id].strip() if idx_feature_id is not None else ""
        fid = fid if fid not in ("", "-") else "UNK-000"
        base = f"{fid}-{slug_snake_case(title)}"
        n = used.get(base, 0) + 1
        used[base] = n
        interaction_id = base if n == 1 else f"{base}__{n}"

        row2 = insert_column(new_header, row, index=insert_at, value=interaction_id)
        new_lines.append("\t".join(row2))

    # Normalize to include a trailing newline for this file after migration.
    out_tf = join_lines(new_lines, tf)
    out_tf = TextFile(
        text=out_tf.text, newline=out_tf.newline, has_trailing_newline=True
    )
    write_text_preserve_newline(path, out_tf)
    return True


def main(argv: list[str]) -> int:
    repo_root = find_repo_root(Path(__file__))
    if not (repo_root / ".git").is_dir():
        repo_root = find_repo_root(Path.cwd())

    changed_any = False
    changed_any = migrate_features(repo_root) or changed_any
    changed_any = migrate_interactions(repo_root) or changed_any

    if changed_any:
        print("OK: migration applied")
    else:
        print("OK: nothing to do")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
