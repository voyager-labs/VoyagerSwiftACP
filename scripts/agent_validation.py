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
PLAN_QUALITY_SECTIONS = ["TDD Evidence", "Test Ownership", "Commit Strategy"]
PLAN_TODO_FIELDS = ["What to do", "Must NOT do", "Acceptance", "QA", "Commit"]
MARKDOWN_LINK = re.compile(r"(?<!!)\[[^]]*]\(([^)#]+)(?:#[^)]+)?\)")
SKILL_PATH_LITERAL = re.compile(r"`((?:\.agents/|\.\.?/)[^`\s*]+(?:\.md|SKILL\.md))`")
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
            if path.is_file()
            and ".git" not in path.parts
            and not path.is_relative_to(root / ".agents/skills/common")
        }
    if mode == "staged":
        command = ["git", "diff", "--cached", "--name-only", "--diff-filter=ACMRD"]
        deleted_command = ["git", "diff", "--cached", "--name-only", "--diff-filter=D"]
    elif mode == "base-ref":
        command = [
            "git",
            "diff",
            "--name-only",
            "--diff-filter=ACMRD",
            f"{base_ref}...HEAD",
        ]
        deleted_command = [
            "git",
            "diff",
            "--name-only",
            "--diff-filter=D",
            f"{base_ref}...HEAD",
        ]
    else:
        command = ["git", "status", "--porcelain"]
        deleted_command = None

    completed = subprocess.run(
        command, cwd=root, text=True, capture_output=True, check=False
    )
    if completed.returncode != 0:
        raise RuntimeError(
            completed.stderr.strip() or "could not determine validation scope"
        )
    if mode != "working-tree":
        paths = {line for line in completed.stdout.splitlines() if line}
        if deleted_command is not None:
            deleted = subprocess.run(
                deleted_command,
                cwd=root,
                text=True,
                capture_output=True,
                check=False,
            )
            if deleted.returncode != 0:
                raise RuntimeError(
                    deleted.stderr.strip() or "could not determine deleted paths"
                )
            deleted_paths = {
                (root / line).resolve()
                for line in deleted.stdout.splitlines()
                if line.startswith(".agents/") and line.endswith(".md")
            }
            if deleted_paths:
                paths.update(markdown_referrers(root, deleted_paths))
        return paths

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
        if mode in {"staged", "base-ref"} and path_string.startswith(
            (".sisyphus/", ".omx/")
        ):
            diagnostics.append(
                Diagnostic(
                    path_string,
                    1,
                    "HARNESS_STAGED_ARTIFACT",
                    "local harness artifacts must not be tracked",
                )
            )
            continue
        if path_string.startswith((".sisyphus/", ".omx/")):
            continue
        if not path.is_file():
            continue
        if (
            path_string.startswith(".agents/rules/")
            and len(Path(path_string).relative_to(".agents/rules").parts) > 1
        ):
            diagnostics.append(
                diagnostic(
                    path,
                    root,
                    1,
                    "HARNESS_INVALID_PLACEMENT",
                    "rules must live directly under .agents/rules",
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
            diagnostics.extend(validate_markdown_references(root, path, text))
        elif (
            path_string.startswith(".agents/skills/")
            and not path_string.startswith(".agents/skills/common/")
            and path.suffix == ".md"
        ):
            diagnostics.extend(
                validate_markdown_references(
                    root, path, path.read_text(encoding="utf-8")
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

    return diagnostics


def validate_markdown_references(root: Path, path: Path, text: str) -> list[Diagnostic]:
    diagnostics: list[Diagnostic] = []
    for line_number, line in enumerate(text.splitlines(), 1):
        targets = [str(target) for target in MARKDOWN_LINK.findall(line)]
        targets += [str(target) for target in SKILL_PATH_LITERAL.findall(line)]
        for target in targets:
            if "<" in target or ">" in target:
                continue
            resolved = (
                root / target if target.startswith(".agents/") else path.parent / target
            ).resolve()
            if resolved.is_relative_to((root / ".agents/skills/common").resolve()):
                continue
            if not resolved.is_relative_to(root.resolve()) or not resolved.exists():
                diagnostics.append(
                    diagnostic(
                        path,
                        root,
                        line_number,
                        "HARNESS_DEAD_REFERENCE",
                        f"Markdown reference does not exist: {target}",
                    )
                )
    return diagnostics


def markdown_referrers(root: Path, deleted_paths: set[Path]) -> set[str]:
    referrers: set[str] = set()
    for directory in (root / ".agents/rules", root / ".agents/skills"):
        if not directory.is_dir():
            continue
        for path in directory.rglob("*.md"):
            if path.is_relative_to(root / ".agents/skills/common"):
                continue
            for line in path.read_text(encoding="utf-8").splitlines():
                targets = [str(target) for target in MARKDOWN_LINK.findall(line)]
                targets += [str(target) for target in SKILL_PATH_LITERAL.findall(line)]
                resolved_targets = {
                    (
                        root / target
                        if target.startswith(".agents/")
                        else path.parent / target
                    ).resolve()
                    for target in targets
                    if "<" not in target and ">" not in target
                }
                if resolved_targets & deleted_paths:
                    referrers.add(path.relative_to(root).as_posix())
                    break
    return referrers


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
        for section in PLAN_QUALITY_SECTIONS:
            if section not in headings:
                diagnostics.append(
                    diagnostic(
                        path,
                        root,
                        1,
                        "PLAN_MISSING_QUALITY_SECTION",
                        f"plan requires ## {section}",
                    )
                )
        tdd_evidence = plan_section_text(lines, headings, "TDD Evidence")
        no_source_changes = bool(
            tdd_evidence
            and re.search(
                r"source changes:\s*no|no executable behavior changes",
                tdd_evidence,
                re.IGNORECASE,
            )
        )
        if (
            tdd_evidence is not None
            and not no_source_changes
            and not (
                re.search(r"\bRED\b", tdd_evidence, re.IGNORECASE)
                and re.search(r"\bGREEN\b", tdd_evidence, re.IGNORECASE)
            )
        ):
            diagnostics.append(
                diagnostic(
                    path,
                    root,
                    headings["TDD Evidence"],
                    "PLAN_TDD_EVIDENCE",
                    "TDD Evidence requires RED and GREEN evidence or an explicit no-source-change rationale",
                )
            )
        test_ownership = plan_section_text(lines, headings, "Test Ownership")
        if test_ownership is not None and not re.search(
            r"\bowner(?:ship)?\b|no product behavior assertions",
            test_ownership,
            re.IGNORECASE,
        ):
            diagnostics.append(
                diagnostic(
                    path,
                    root,
                    headings["Test Ownership"],
                    "PLAN_TEST_OWNERSHIP",
                    "Test Ownership must name the canonical test owner",
                )
            )
        commit_strategy = plan_section_text(lines, headings, "Commit Strategy")
        if commit_strategy is not None and not (
            "commit-message" in commit_strategy
            or (
                "alternative:" in commit_strategy.lower()
                and "justification:" in commit_strategy.lower()
            )
        ):
            diagnostics.append(
                diagnostic(
                    path,
                    root,
                    headings["Commit Strategy"],
                    "PLAN_COMMIT_STRATEGY",
                    "Commit Strategy must reference commit-message or justify an alternative",
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
            acceptance = plan_field_text(block, "Acceptance")
            if acceptance is not None and "evidence" not in acceptance.lower():
                diagnostics.append(
                    diagnostic(
                        path,
                        root,
                        index + 1,
                        "PLAN_ACCEPTANCE_EVIDENCE",
                        "TODO Acceptance must name required evidence",
                    )
                )
            qa = plan_field_text(block, "QA")
            todo_has_no_source_changes = bool(
                qa
                and re.search(
                    r"source changes:\s*no|no executable behavior changes",
                    qa,
                    re.IGNORECASE,
                )
            )
            if (
                qa is not None
                and not todo_has_no_source_changes
                and not (
                    re.search(r"\bRED\b", qa, re.IGNORECASE)
                    and re.search(r"\bGREEN\b", qa, re.IGNORECASE)
                )
            ):
                diagnostics.append(
                    diagnostic(
                        path,
                        root,
                        index + 1,
                        "PLAN_TODO_TDD_EVIDENCE",
                        "TODO QA must name RED and GREEN evidence",
                    )
                )
    return diagnostics


def plan_section_text(
    lines: list[str], headings: dict[str, int], section: str
) -> str | None:
    start = headings.get(section)
    if start is None:
        return None
    end = min(
        (line for line in headings.values() if line > start), default=len(lines) + 1
    )
    return "\n".join(lines[start : end - 1]).strip()


def plan_field_text(block: str, field: str) -> str | None:
    match = re.search(
        rf"^\s*- \*\*{re.escape(field)}\*\*:\s*(.*?)(?=^\s*- \*\*|\Z)",
        block,
        re.MULTILINE | re.DOTALL,
    )
    return match.group(1).strip() if match else None


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
