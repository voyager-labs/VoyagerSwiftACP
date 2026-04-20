#!/usr/bin/env python3
"""Normalize TSV whitespace deterministically.

Goal: reduce noisy diffs caused by accidental spaces while avoiding meaning changes.

Conservative rules:
- Preserve tabs as delimiters; do not re-align.
- Normalize CRLF/LF handling by reading/writing in text mode without changing newlines
  unless --eol is provided.
- Per-cell normalization:
  - Replace NBSP (\u00a0) with a normal space.
  - Strip trailing whitespace from every cell.
  - For "key-like" columns, also strip leading whitespace and collapse internal runs of
    whitespace to a single space.
  - For other columns (free text), do NOT collapse internal multiple spaces.
- Normalize '-' sentinel:
  - If a cell becomes exactly '-' after trimming, keep '-'.

Default mode is check-only (no file writes). Use --write to apply.
"""

from __future__ import annotations

import argparse
import csv
import sys
from dataclasses import dataclass
from pathlib import Path


KEY_LIKE_COLUMNS = {
    # inventory keys/ids
    "feature_id",
    "category_key",
    "interaction_id",
    "structure_key",
    # inventory enums-ish
    "status",
    "release_phase",
    "interaction_type",
    # refs
    "related_ui",
    "related_region",
    # UI-ish but usually short tokens
    "menu",
    "shortcut",
    # common IA keys
    "window_id",
    "region_id",
    "parent_region_id",
}


@dataclass(frozen=True)
class TextFile:
    text: str
    newline: str
    has_trailing_newline: bool


def read_text_preserve_newline(path: Path) -> TextFile:
    data = path.read_bytes()
    newline = "\r\n" if b"\r\n" in data else "\n"
    text = data.decode("utf-8")
    has_trailing_newline = text.endswith(newline)
    return TextFile(
        text=text, newline=newline, has_trailing_newline=has_trailing_newline
    )


def write_text_preserve_newline(path: Path, file: TextFile) -> None:
    out = file.text
    if file.has_trailing_newline and not out.endswith(file.newline):
        out += file.newline
    if not file.has_trailing_newline and out.endswith(file.newline):
        out = out[: -len(file.newline)]
    path.write_bytes(out.encode("utf-8"))


def split_lines(file: TextFile) -> list[str]:
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


def collapse_ws(value: str) -> str:
    parts = value.split()
    return " ".join(parts)


def normalize_cell(value: str, *, key_like: bool) -> str:
    # Normalize non-breaking spaces that often sneak in from copy/paste.
    v = value.replace("\u00a0", " ")

    # Always remove trailing whitespace (safe; doesn't change meaning in TSV cells).
    v = v.rstrip()

    if key_like:
        # Keys should be strict and not contain accidental padding.
        v = v.strip()
        v = collapse_ws(v)

    # Normalize '-' sentinel if user typed '- ' etc.
    if v.strip() == "-":
        return "-"

    return v


def normalize_tsv_lines(lines: list[str], *, eol: str | None) -> tuple[list[str], int]:
    if not lines:
        return lines, 0

    # Parse using csv with tab delimiter, but keep per-line control via join.
    reader = csv.reader(lines, delimiter="\t")
    rows = list(reader)
    if not rows:
        return lines, 0

    header = rows[0]
    key_like_by_index = {i: (col in KEY_LIKE_COLUMNS) for i, col in enumerate(header)}

    changed = 0
    out_rows: list[list[str]] = []

    for r_idx, row in enumerate(rows):
        # Keep column count stable.
        if r_idx == 0:
            out_rows.append(row)
            continue
        if len(row) < len(header):
            row = row + ([""] * (len(header) - len(row)))
        elif len(row) > len(header):
            row = row[: len(header)]

        new_row = []
        row_changed = False
        for i, cell in enumerate(row):
            key_like = key_like_by_index.get(i, False)
            new_cell = normalize_cell(cell, key_like=key_like)
            if new_cell != cell:
                row_changed = True
            new_row.append(new_cell)

        if row_changed:
            changed += 1
        out_rows.append(new_row)

    # Re-serialize with tabs.
    out_lines = ["\t".join(r) for r in out_rows]
    return out_lines, changed


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description="Normalize TSV whitespace (conservative)")
    ap.add_argument("paths", nargs="+", help="TSV file(s) to check/format")
    ap.add_argument(
        "--write",
        action="store_true",
        help="Apply changes in-place (default: check-only)",
    )
    ap.add_argument(
        "--eol",
        choices=["lf", "crlf"],
        default=None,
        help="Force output line endings (optional)",
    )
    args = ap.parse_args(argv)

    total_changed_files = 0
    total_changed_rows = 0

    for p_str in args.paths:
        path = Path(p_str)
        tf = read_text_preserve_newline(path)
        lines = split_lines(tf)

        out_lines, changed_rows = normalize_tsv_lines(lines, eol=args.eol)
        out_tf = join_lines(out_lines, tf)
        if args.eol == "lf":
            out_tf = TextFile(text=out_tf.text, newline="\n", has_trailing_newline=True)
        elif args.eol == "crlf":
            out_tf = TextFile(
                text=out_tf.text, newline="\r\n", has_trailing_newline=True
            )

        changed = (out_tf.text != tf.text) or (out_tf.newline != tf.newline)
        if changed:
            total_changed_files += 1
            total_changed_rows += changed_rows

        if args.write and changed:
            write_text_preserve_newline(path, out_tf)

        status = "CHANGED" if changed else "OK"
        print(f"{status}: {path} (rows_touched={changed_rows})")

    if total_changed_files and not args.write:
        print(
            f"\nWould change {total_changed_files} file(s), touching {total_changed_rows} row(s)."
        )
        print("Re-run with --write to apply.")
        return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
