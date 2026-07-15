from __future__ import annotations

import ast
import json
import re
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
VALIDATE = "scripts.validate_harness"
VERIFY = "scripts.verify_plan"
RULE = """---
description: "fixture"
alwaysApply: true
schemaVersion: 2
---

# Fixture

## Outcome

- outcome

## Default Actions

1. action

## Decision Rules

- decision

## Stop Conditions

- stop

## Verification

- verify
"""
PLAN = """# Fixture Plan

## TL;DR

Summary.

## Context

Context.

## Work Objectives

Objective.

## TODOs

- [ ] 1. Fixture task
  - **What to do**: Do it.
  - **Must NOT do**: Do anything else.
  - **Acceptance**: It is done.
  - **QA**: Test it.
  - **Commit**: NO.
"""


class AgentValidationTests(unittest.TestCase):
    def run_cli(
        self, module: str, root: Path, *arguments: str
    ) -> tuple[subprocess.CompletedProcess[str], dict[str, Any]]:
        completed = subprocess.run(
            [sys.executable, "-m", module, "--root", str(root), *arguments],
            text=True,
            capture_output=True,
            check=False,
        )
        return completed, json.loads(completed.stdout)

    def make_repo(self) -> tempfile.TemporaryDirectory[str]:
        temp = tempfile.TemporaryDirectory()
        root = Path(temp.name)
        subprocess.run(["git", "init", "-q"], cwd=root, check=True)
        subprocess.run(
            ["git", "config", "user.email", "fixture@example.com"], cwd=root, check=True
        )
        subprocess.run(["git", "config", "user.name", "Fixture"], cwd=root, check=True)
        return temp

    def write(self, root: Path, relative: str, content: str) -> None:
        path = root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")

    def assert_exact_diagnostic(
        self,
        result: subprocess.CompletedProcess[str],
        payload: dict[str, Any],
        code: str,
    ) -> None:
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(len(payload["diagnostics"]), 1)
        diagnostic = payload["diagnostics"][0]
        self.assertEqual(set(diagnostic), {"file", "line", "code", "message"})
        self.assertEqual(diagnostic["code"], code)

    def emitted_diagnostic_codes(self) -> set[str]:
        tree = ast.parse(
            (ROOT / "scripts/agent_validation.py").read_text(encoding="utf-8")
        )
        return {
            value.value
            for value in ast.walk(tree)
            if isinstance(value, ast.Constant)
            and isinstance(value.value, str)
            and re.fullmatch(r"(?:HARNESS|PLAN)_[A-Z0-9_]+", value.value)
        }

    def test_valid_harness_fixture_is_clean(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            self.write(root, ".agents/rules/00-fixture.md", RULE)
            self.write(root, ".agents/skills/fixture/evals/evals.json", '{"evals": []}')
            result, payload = self.run_cli(VALIDATE, root, "--all")
            self.assertEqual(result.returncode, 0)
            self.assertEqual(payload["diagnostics"], [])

    def test_invalid_harness_fixtures_have_exact_diagnostics(self) -> None:
        cases = {
            "heading": (
                ".agents/rules/00-fixture.md",
                RULE.replace("## Outcome", "## Bad"),
                "HARNESS_V2_HEADING_ORDER",
            ),
            "applicability": (
                ".agents/rules/00-fixture.md",
                RULE.replace("alwaysApply: true\n", 'alwaysApply: true\nglobs: "**"\n'),
                "HARNESS_APPLICABILITY",
            ),
            "dead-link": (
                ".agents/rules/00-fixture.md",
                RULE + "\n[missing](missing.md)\n",
                "HARNESS_DEAD_REFERENCE",
            ),
            "placement": (
                ".agents/rules/voyager/00-fixture.md",
                RULE,
                "HARNESS_INVALID_PLACEMENT",
            ),
            "eval-json": (
                ".agents/skills/fixture/evals/evals.json",
                "{bad",
                "HARNESS_INVALID_EVAL_JSON",
            ),
        }
        for name, (relative, content, code) in cases.items():
            with self.subTest(name=name), tempfile.TemporaryDirectory() as temp:
                root = Path(temp)
                self.write(root, relative, content)
                result, payload = self.run_cli(VALIDATE, root, "--all")
                self.assert_exact_diagnostic(result, payload, code)

    def test_staged_artifact_fixture_fails(self) -> None:
        temp = self.make_repo()
        self.addCleanup(temp.cleanup)
        root = Path(temp.name)
        self.write(root, ".sisyphus/evidence/task.json", "{}")
        subprocess.run(["git", "add", "."], cwd=root, check=True)
        artifact_result, artifact_payload = self.run_cli(VALIDATE, root, "--staged")
        self.assert_exact_diagnostic(
            artifact_result, artifact_payload, "HARNESS_STAGED_ARTIFACT"
        )

    def test_artifacts_are_rejected_only_in_tracked_scopes(self) -> None:
        temp = self.make_repo()
        self.addCleanup(temp.cleanup)
        root = Path(temp.name)
        self.write(root, ".keep", "")
        subprocess.run(["git", "add", "."], cwd=root, check=True)
        subprocess.run(["git", "commit", "-qm", "fixture"], cwd=root, check=True)
        base_ref = subprocess.run(
            ["git", "rev-parse", "HEAD"],
            cwd=root,
            text=True,
            capture_output=True,
            check=True,
        ).stdout.strip()

        self.write(root, ".sisyphus/evidence/task.json", "{}")
        working_result, working_payload = self.run_cli(VALIDATE, root, "--working-tree")
        self.assertEqual(working_result.returncode, 0)
        self.assertEqual(working_payload["diagnostics"], [])

        subprocess.run(["git", "add", "."], cwd=root, check=True)
        staged_result, staged_payload = self.run_cli(VALIDATE, root, "--staged")
        self.assert_exact_diagnostic(
            staged_result, staged_payload, "HARNESS_STAGED_ARTIFACT"
        )
        subprocess.run(["git", "commit", "-qm", "artifact"], cwd=root, check=True)
        base_result, base_payload = self.run_cli(VALIDATE, root, "--base-ref", base_ref)
        self.assert_exact_diagnostic(
            base_result, base_payload, "HARNESS_STAGED_ARTIFACT"
        )

    def test_local_skill_links_and_path_literals_are_checked(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            self.write(
                root,
                ".agents/skills/fixture/SKILL.md",
                "[missing link](missing.md)\n`../missing-reference.md`\n[host](/etc/passwd)\n",
            )
            self.write(
                root,
                ".agents/skills/fixture/references/guide.md",
                "`../../missing-reference.md`\n",
            )
            result, payload = self.run_cli(VALIDATE, root, "--all")

        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(
            [item["code"] for item in payload["diagnostics"]],
            [
                "HARNESS_DEAD_REFERENCE",
                "HARNESS_DEAD_REFERENCE",
                "HARNESS_DEAD_REFERENCE",
                "HARNESS_DEAD_REFERENCE",
            ],
        )

    def test_rule_path_literals_are_checked(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            self.write(
                root,
                ".agents/rules/00-fixture.md",
                (
                    f"{RULE}\n`.agents/skills/missing/SKILL.md`\n"
                    "`.agents/skills/common/internal/fixture/SKILL.md`\n"
                ),
            )
            result, payload = self.run_cli(VALIDATE, root, "--all")

        self.assert_exact_diagnostic(result, payload, "HARNESS_DEAD_REFERENCE")

    def test_omx_artifacts_are_allowed_locally_and_rejected_when_staged(self) -> None:
        temp = self.make_repo()
        self.addCleanup(temp.cleanup)
        root = Path(temp.name)
        self.write(root, ".omx/session.json", "{}")

        working_result, working_payload = self.run_cli(VALIDATE, root, "--working-tree")
        self.assertEqual(working_result.returncode, 0)
        self.assertEqual(working_payload["diagnostics"], [])

        subprocess.run(["git", "add", "."], cwd=root, check=True)
        staged_result, staged_payload = self.run_cli(VALIDATE, root, "--staged")
        self.assert_exact_diagnostic(
            staged_result, staged_payload, "HARNESS_STAGED_ARTIFACT"
        )

    def test_scope_modes_select_working_tree_staged_and_base_ref(self) -> None:
        temp = self.make_repo()
        self.addCleanup(temp.cleanup)
        root = Path(temp.name)
        self.write(root, ".agents/rules/00-fixture.md", RULE)
        subprocess.run(["git", "add", "."], cwd=root, check=True)
        subprocess.run(["git", "commit", "-qm", "fixture"], cwd=root, check=True)
        base_ref = subprocess.run(
            ["git", "rev-parse", "HEAD"],
            cwd=root,
            text=True,
            capture_output=True,
            check=True,
        ).stdout.strip()
        self.write(
            root,
            ".agents/rules/00-fixture.md",
            RULE.replace("## Outcome", "## Bad"),
        )
        result, payload = self.run_cli(VALIDATE, root, "--working-tree")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(payload["mode"], "working-tree")
        subprocess.run(["git", "add", "."], cwd=root, check=True)
        result, payload = self.run_cli(VALIDATE, root, "--staged")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(payload["mode"], "staged")
        subprocess.run(["git", "commit", "-qm", "broken fixture"], cwd=root, check=True)
        result, payload = self.run_cli(VALIDATE, root, "--base-ref", base_ref)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(payload["mode"], "base-ref")

    def test_plan_fixtures_are_structural_only(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            self.write(root, ".sisyphus/plans/valid.md", PLAN)
            result, payload = self.run_cli(VERIFY, root, "--all")
            self.assertEqual(result.returncode, 0)
            self.assertEqual(payload["diagnostics"], [])
            self.write(
                root,
                ".sisyphus/plans/invalid.md",
                PLAN.replace("  - **QA**: Test it.\n", ""),
            )
            result, payload = self.run_cli(VERIFY, root, "--all")
            self.assert_exact_diagnostic(result, payload, "PLAN_TODO_CONTRACT")

    def test_every_emitted_diagnostic_has_an_exact_fixture(self) -> None:
        harness_cases = {
            "HARNESS_MISSING_FRONTMATTER": (
                ".agents/rules/00-fixture.md",
                "# Fixture\n",
            ),
            "HARNESS_MISSING_DESCRIPTION": (
                ".agents/rules/00-fixture.md",
                RULE.replace('description: "fixture"\n', ""),
            ),
            "HARNESS_APPLICABILITY": (
                ".agents/rules/00-fixture.md",
                RULE.replace("alwaysApply: true\n", 'alwaysApply: true\nglobs: "**"\n'),
            ),
            "HARNESS_V2_HEADING_ORDER": (
                ".agents/rules/00-fixture.md",
                RULE.replace("## Outcome", "## Bad"),
            ),
            "HARNESS_DEAD_REFERENCE": (
                ".agents/rules/00-fixture.md",
                RULE + "\n[missing](missing.md)\n",
            ),
            "HARNESS_INVALID_PLACEMENT": (
                ".agents/rules/voyager/00-fixture.md",
                RULE,
            ),
            "HARNESS_INVALID_EVAL_JSON": (
                ".agents/skills/fixture/evals/evals.json",
                "{bad",
            ),
        }
        seen_codes: set[str] = set()
        for code, (relative, content) in harness_cases.items():
            with self.subTest(code=code), tempfile.TemporaryDirectory() as temp:
                root = Path(temp)
                self.write(root, relative, content)
                result, payload = self.run_cli(VALIDATE, root, "--all")
                self.assert_exact_diagnostic(result, payload, code)
                seen_codes.add(code)

        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            self.write(root, ".agents/skills/Invalid_Name/SKILL.md", "# Fixture\n")
            result, payload = self.run_cli(VALIDATE, root, "--all")
            self.assert_exact_diagnostic(result, payload, "HARNESS_INVALID_PLACEMENT")
            seen_codes.add("HARNESS_INVALID_PLACEMENT")

        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            self.write(root, "scripts/evals/shadow-corpus.json", "{bad")
            result, payload = self.run_cli(VALIDATE, root, "--all")
            self.assert_exact_diagnostic(result, payload, "HARNESS_INVALID_EVAL_JSON")
            seen_codes.add("HARNESS_INVALID_EVAL_JSON")

        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            relative = ".agents/rules/00-fixture.md"
            self.write(root, relative, RULE.replace("schemaVersion: 2\n", ""))
            result, payload = self.run_cli(VALIDATE, root, relative)
            self.assert_exact_diagnostic(result, payload, "HARNESS_SCHEMA_VERSION")
            seen_codes.add("HARNESS_SCHEMA_VERSION")

        temp = self.make_repo()
        self.addCleanup(temp.cleanup)
        root = Path(temp.name)
        self.write(root, ".sisyphus/evidence/task.json", "{}")
        subprocess.run(["git", "add", "."], cwd=root, check=True)
        result, payload = self.run_cli(VALIDATE, root, "--staged")
        self.assert_exact_diagnostic(result, payload, "HARNESS_STAGED_ARTIFACT")
        seen_codes.add("HARNESS_STAGED_ARTIFACT")

        plan_cases = {
            "PLAN_MISSING_TITLE": PLAN.replace("# Fixture Plan", "Fixture Plan"),
            "PLAN_MISSING_SECTION": PLAN.replace("## Context", "## Background"),
            "PLAN_TODO_CONTRACT": PLAN.replace("  - **QA**: Test it.\n", ""),
        }
        for code, content in plan_cases.items():
            with self.subTest(code=code), tempfile.TemporaryDirectory() as temp:
                root = Path(temp)
                self.write(root, ".sisyphus/plans/fixture.md", content)
                result, payload = self.run_cli(VERIFY, root, "--all")
                self.assert_exact_diagnostic(result, payload, code)
                seen_codes.add(code)

        self.assertEqual(seen_codes, self.emitted_diagnostic_codes())

    def test_changed_rules_require_v2_schema_outside_all_mode(self) -> None:
        temp = self.make_repo()
        self.addCleanup(temp.cleanup)
        root = Path(temp.name)
        self.write(root, ".keep", "")
        subprocess.run(["git", "add", "."], cwd=root, check=True)
        subprocess.run(["git", "commit", "-qm", "fixture"], cwd=root, check=True)
        base_ref = subprocess.run(
            ["git", "rev-parse", "HEAD"],
            cwd=root,
            text=True,
            capture_output=True,
            check=True,
        ).stdout.strip()
        relative = ".agents/rules/00-legacy.md"
        legacy_rule = RULE.replace("schemaVersion: 2\n", "")
        self.write(root, relative, legacy_rule)

        all_result, all_payload = self.run_cli(VALIDATE, root, "--all")
        self.assertEqual(all_result.returncode, 0)
        self.assertEqual(all_payload["diagnostics"], [])

        working_result, working_payload = self.run_cli(VALIDATE, root, "--working-tree")
        self.assert_exact_diagnostic(
            working_result, working_payload, "HARNESS_SCHEMA_VERSION"
        )
        subprocess.run(["git", "add", relative], cwd=root, check=True)
        staged_result, staged_payload = self.run_cli(VALIDATE, root, "--staged")
        self.assert_exact_diagnostic(
            staged_result, staged_payload, "HARNESS_SCHEMA_VERSION"
        )
        subprocess.run(["git", "commit", "-qm", "legacy rule"], cwd=root, check=True)
        base_result, base_payload = self.run_cli(VALIDATE, root, "--base-ref", base_ref)
        self.assert_exact_diagnostic(
            base_result, base_payload, "HARNESS_SCHEMA_VERSION"
        )

    def test_plan_scope_modes_use_changed_files_only(self) -> None:
        temp = self.make_repo()
        self.addCleanup(temp.cleanup)
        root = Path(temp.name)
        relative = ".sisyphus/plans/fixture.md"
        self.write(root, relative, PLAN)
        subprocess.run(["git", "add", "."], cwd=root, check=True)
        subprocess.run(["git", "commit", "-qm", "valid plan"], cwd=root, check=True)
        base_ref = subprocess.run(
            ["git", "rev-parse", "HEAD"],
            cwd=root,
            text=True,
            capture_output=True,
            check=True,
        ).stdout.strip()
        self.write(root, relative, PLAN.replace("  - **QA**: Test it.\n", ""))
        result, payload = self.run_cli(VERIFY, root, "--working-tree")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(payload["mode"], "working-tree")
        subprocess.run(["git", "add", "."], cwd=root, check=True)
        result, payload = self.run_cli(VERIFY, root, "--staged")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(payload["mode"], "staged")
        subprocess.run(["git", "commit", "-qm", "broken plan"], cwd=root, check=True)
        result, payload = self.run_cli(VERIFY, root, "--base-ref", base_ref)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(payload["mode"], "base-ref")


if __name__ == "__main__":
    unittest.main()
