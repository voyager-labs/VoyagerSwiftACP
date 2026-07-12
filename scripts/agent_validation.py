"""Shared deterministic validation helpers for agent-harness contracts."""

from __future__ import annotations

import json
import re
import subprocess
from dataclasses import asdict, dataclass
from pathlib import Path


@dataclass(frozen=True)
class Diagnostic:
    file: str
    line: int
    code: str
    message: str


V2_HEADINGS = [
    "Outcome",
    "Default Actions",
    "Decision Rules",
    "Stop Conditions",
    "Verification",
]
PLAN_SECTIONS = ["TL;DR", "Context", "Work Objectives", "TODOs"]
PLAN_TODO_FIELDS = ["What to do", "Must NOT do", "Acceptance", "QA", "Commit"]
MARKDOWN_LINK = re.compile(r"(?<!!)\[[^]]*]\(([^)#]+)(?:#[^)]+)?\)")
ROUTING_REFERENCE = re.compile(r"(?<![\w/])((?:\d{2}-[\w-]+/)+[\w-]+\.md)")
TODO = re.compile(r"^- \[[ xX]] \d+\. .+")


def diagnostic(
    path: Path, root: Path, line: int, code: str, message: str
) -> Diagnostic:
    return Diagnostic(path.relative_to(root).as_posix(), line, code, message)


def git_paths(root: Path, mode: str, base_ref: str | None) -> set[str]:
    if mode == "all":
        return {
            path.relative_to(root).as_posix()
            for path in root.rglob("*")
            if path.is_file() and ".git" not in path.parts
        }
    if mode == "staged":
        command = ["git", "diff", "--cached", "--name-only", "--diff-filter=ACMR"]
    elif mode == "base-ref":
        command = [
            "git",
            "diff",
            "--name-only",
            "--diff-filter=ACMR",
            f"{base_ref}...HEAD",
        ]
    else:
        command = ["git", "status", "--porcelain"]

    completed = subprocess.run(
        command, cwd=root, text=True, capture_output=True, check=False
    )
    if completed.returncode != 0:
        raise RuntimeError(
            completed.stderr.strip() or "could not determine validation scope"
        )
    if mode != "working-tree":
        return {line for line in completed.stdout.splitlines() if line}

    paths: set[str] = set()
    for line in completed.stdout.splitlines():
        if len(line) >= 4:
            paths.add(line[3:].split(" -> ")[-1])
    untracked = subprocess.run(
        ["git", "ls-files", "--others", "--exclude-standard"],
        cwd=root,
        text=True,
        capture_output=True,
        check=False,
    )
    if untracked.returncode != 0:
        raise RuntimeError(
            untracked.stderr.strip() or "could not determine untracked validation scope"
        )
    paths.update(line for line in untracked.stdout.splitlines() if line)
    return paths


def parse_frontmatter(text: str) -> tuple[dict[str, str], int]:
    lines = text.splitlines()
    if not lines or lines[0] != "---":
        return {}, 0
    for index, line in enumerate(lines[1:], start=2):
        if line == "---":
            values: dict[str, str] = {}
            for value in lines[1 : index - 1]:
                if ":" in value:
                    key, raw = value.split(":", 1)
                    values[key.strip()] = raw.strip().strip('"')
            return values, index
    return {}, 0


def validate_harness(root: Path, paths: set[str], mode: str) -> list[Diagnostic]:
    diagnostics: list[Diagnostic] = []
    for path_string in sorted(paths):
        path = root / path_string
        if mode == "staged" and path_string.startswith((".sisyphus/", ".omx/")):
            diagnostics.append(
                Diagnostic(
                    path_string,
                    1,
                    "HARNESS_STAGED_ARTIFACT",
                    "local harness artifacts must not be staged",
                )
            )
            continue
        if path_string.startswith((".sisyphus/", ".omx/")):
            continue
        if not path.is_file():
            continue
        if path_string.startswith(".agents/rules/voyager/"):
            diagnostics.append(
                diagnostic(
                    path,
                    root,
                    1,
                    "HARNESS_INVALID_PLACEMENT",
                    "rules must use an established domain directory",
                )
            )
        if path.name == "SKILL.md" and not re.fullmatch(
            r"[a-z0-9]+(?:-[a-z0-9]+)*", path.parent.name
        ):
            diagnostics.append(
                diagnostic(
                    path,
                    root,
                    1,
                    "HARNESS_INVALID_PLACEMENT",
                    "skill directories must use kebab-case",
                )
            )
        if (
            path.suffix == ".md"
            and path.name != "README.md"
            and path_string.startswith(".agents/rules/")
        ):
            text = path.read_text(encoding="utf-8")
            frontmatter, end_line = parse_frontmatter(text)
            if not end_line:
                diagnostics.append(
                    diagnostic(
                        path,
                        root,
                        1,
                        "HARNESS_MISSING_FRONTMATTER",
                        "rule must start with YAML frontmatter",
                    )
                )
            elif "description" not in frontmatter:
                diagnostics.append(
                    diagnostic(
                        path,
                        root,
                        2,
                        "HARNESS_MISSING_DESCRIPTION",
                        "rule frontmatter requires description",
                    )
                )
            elif mode != "all" and frontmatter.get("schemaVersion") != "2":
                diagnostics.append(
                    diagnostic(
                        path,
                        root,
                        1,
                        "HARNESS_SCHEMA_VERSION",
                        "changed rules require schemaVersion: 2",
                    )
                )
            elif frontmatter.get("schemaVersion") == "2":
                applicability = [
                    key for key in ("alwaysApply", "globs") if key in frontmatter
                ]
                if len(applicability) != 1:
                    diagnostics.append(
                        diagnostic(
                            path,
                            root,
                            1,
                            "HARNESS_APPLICABILITY",
                            "v2 rules require exactly one of alwaysApply or globs",
                        )
                    )
                headings = [
                    line[3:] for line in text.splitlines() if line.startswith("## ")
                ]
                if headings != V2_HEADINGS:
                    line = next(
                        (
                            index
                            for index, value in enumerate(text.splitlines(), 1)
                            if value.startswith("## ")
                        ),
                        end_line + 1,
                    )
                    diagnostics.append(
                        diagnostic(
                            path,
                            root,
                            line,
                            "HARNESS_V2_HEADING_ORDER",
                            "v2 rules require the five headings in canonical order",
                        )
                    )
            for line_number, line in enumerate(text.splitlines(), 1):
                for target in (str(value) for value in MARKDOWN_LINK.findall(line)):
                    resolved = (path.parent / target).resolve()
                    if not resolved.exists():
                        diagnostics.append(
                            diagnostic(
                                path,
                                root,
                                line_number,
                                "HARNESS_DEAD_REFERENCE",
                                f"Markdown reference does not exist: {target}",
                            )
                        )
        is_skill_eval = path.name == "evals.json" and "evals" in path.parts
        is_shadow_corpus = (
            path.parent == root / "scripts/evals" and path.suffix == ".json"
        )
        if is_skill_eval or is_shadow_corpus:
            try:
                json.loads(path.read_text(encoding="utf-8"))
            except json.JSONDecodeError as error:
                diagnostics.append(
                    diagnostic(
                        path, root, error.lineno, "HARNESS_INVALID_EVAL_JSON", error.msg
                    )
                )

    routing = root / ".agents/rules/00-core/02-routing.md"
    if routing.is_file() and routing.relative_to(root).as_posix() in paths:
        for line_number, line in enumerate(
            routing.read_text(encoding="utf-8").splitlines(), 1
        ):
            for reference in (str(value) for value in ROUTING_REFERENCE.findall(line)):
                if not (root / ".agents/rules" / reference).is_file():
                    diagnostics.append(
                        diagnostic(
                            routing,
                            root,
                            line_number,
                            "HARNESS_DEAD_ROUTING",
                            f"routing target does not exist: {reference}",
                        )
                    )
    return diagnostics


def verify_plans(root: Path, paths: set[str]) -> list[Diagnostic]:
    diagnostics: list[Diagnostic] = []
    for path_string in sorted(paths):
        if not path_string.startswith(".sisyphus/plans/") or not path_string.endswith(
            ".md"
        ):
            continue
        path = root / path_string
        if not path.is_file():
            continue
        lines = path.read_text(encoding="utf-8").splitlines()
        if not lines or not lines[0].startswith("# "):
            diagnostics.append(
                diagnostic(
                    path,
                    root,
                    1,
                    "PLAN_MISSING_TITLE",
                    "plan must start with a level-one title",
                )
            )
        headings = {
            line[3:]: index
            for index, line in enumerate(lines, 1)
            if line.startswith("## ")
        }
        for section in PLAN_SECTIONS:
            if section not in headings:
                diagnostics.append(
                    diagnostic(
                        path,
                        root,
                        1,
                        "PLAN_MISSING_SECTION",
                        f"plan requires ## {section}",
                    )
                )
        for index, line in enumerate(lines):
            if not TODO.match(line):
                continue
            next_todo = next(
                (
                    offset
                    for offset in range(index + 1, len(lines))
                    if TODO.match(lines[offset])
                ),
                len(lines),
            )
            block = "\n".join(lines[index + 1 : next_todo])
            for field in PLAN_TODO_FIELDS:
                if f"**{field}**" not in block:
                    diagnostics.append(
                        diagnostic(
                            path,
                            root,
                            index + 1,
                            "PLAN_TODO_CONTRACT",
                            f"TODO is missing **{field}**",
                        )
                    )
    return diagnostics


def json_result(name: str, diagnostics: list[Diagnostic], mode: str) -> str:
    return json.dumps(
        {
            "validator": name,
            "mode": mode,
            "diagnostics": [asdict(item) for item in diagnostics],
        },
        ensure_ascii=False,
        indent=2,
    )
