"""Regression tests use real temporary Git indexes and controlled tool processes."""
from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

from scripts.run_swift_checks import (
    CheckResult, changed_paths, check_exit, check_sources, git, is_test,
    paths_from_nul, policy_changed, run_check, safe_file, snapshot,
)
from scripts.validate_harness import _run_build_matrix_validator

ROOT = Path(__file__).resolve().parents[2]


class HarnessExecutionTests(unittest.TestCase):
    def test_failure_is_not_overwritten_by_later_success(self):
        self.assertEqual(check_exit([CheckResult("first", "failed", 1), CheckResult("last", "passed", 0)]), 1)

    def test_blocked_is_not_success(self):
        self.assertEqual(check_exit([CheckResult("tool", "blocked")]), 2)

    def test_configuration_change_expands_only_affected_engine(self):
        self.assertTrue(policy_changed(["apps/macos/.swiftformat"], "format"))
        self.assertFalse(policy_changed(["apps/macos/.swiftformat"], "lint"))
        self.assertTrue(policy_changed([".ast-grep/rules/ui/new.yaml"], "ast"))
        self.assertTrue(policy_changed(["mise.toml"], "lint"))

    def test_nul_paths_keep_spaces_tabs_and_newlines(self):
        self.assertEqual(paths_from_nul(b"a b.swift\0a\tb.swift\0a\nb.swift\0"), ["a b.swift", "a\tb.swift", "a\nb.swift"])

    def test_tests_are_path_components_not_substrings(self):
        self.assertTrue(is_test("apps/macos/Voyager/VoyagerTests/A.swift"))
        self.assertTrue(is_test("apps/macos/Packages/A/Tests/A.swift"))
        self.assertFalse(is_test("apps/macos/TestsHelpers/Sources/A.swift"))

    def test_missing_executable_is_blocked(self):
        result = run_check("missing", ["/not-an-installed-voyager-tool"], ROOT)
        self.assertEqual(result.status, "blocked")

    def test_timeout_is_blocked(self):
        with patch("scripts.run_swift_checks.subprocess.run", side_effect=subprocess.TimeoutExpired("tool", 300)):
            self.assertEqual(run_check("timeout", ["tool"], ROOT).status, "blocked")

    def test_empty_source_scope_does_not_claim_tools_ran(self):
        with patch("scripts.run_swift_checks.run_check") as run:
            results = check_sources(ROOT, [], ["ast", "lint", "format"])
        run.assert_not_called()
        self.assertEqual([result.status for result in results], ["notApplicable"] * 3)

    def test_snapshot_keeps_index_bytes_and_leaves_worktree_untouched(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            git(root, "init", "-q")
            git(root, "config", "user.email", "fixture@example.invalid")
            git(root, "config", "user.name", "Fixture")
            relative = "apps/macos/Sources/with space\nand newline.swift"
            file = root / relative
            file.parent.mkdir(parents=True)
            file.write_text("let value = 1\n")
            git(root, "add", ".")
            git(root, "commit", "-qm", "fixture")
            file.write_text("let value = 2\n")
            git(root, "add", "--", relative)
            file.write_text("let value = 3\n")
            index_before = git(root, "write-tree")
            self.assertEqual(changed_paths(root, "staged", None), [relative])
            with snapshot(root, "staged") as (content, tree):
                self.assertEqual((content / relative).read_text(), "let value = 2\n")
                self.assertEqual(tree, index_before.decode().strip())
            self.assertEqual(file.read_text(), "let value = 3\n")
            self.assertEqual(git(root, "write-tree"), index_before)

    def test_base_snapshot_ignores_uncommitted_fixes(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            git(root, "init", "-q")
            git(root, "config", "user.email", "fixture@example.invalid")
            git(root, "config", "user.name", "Fixture")
            file = root / "a.swift"
            file.write_text("committed")
            git(root, "add", ".")
            git(root, "commit", "-qm", "fixture")
            file.write_text("uncommitted")
            with snapshot(root, "base-ref") as (content, _):
                self.assertEqual((content / "a.swift").read_text(), "committed")

    def test_input_cannot_escape_snapshot(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "escape").symlink_to("/etc/passwd")
            with self.assertRaises(RuntimeError):
                safe_file(root, "escape")
            with self.assertRaises(RuntimeError):
                safe_file(root, "../missing")

    def test_build_matrix_runs_the_explicit_snapshot_module(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            scripts = root / "scripts"
            scripts.mkdir()
            (scripts / "__init__.py").write_text("")
            (scripts / "validate_build_matrix.py").write_text(
                "from pathlib import Path\nraise SystemExit(0 if Path('index-marker').is_file() else 1)\n"
            )
            (root / "index-marker").write_text("snapshot")
            self.assertEqual(_run_build_matrix_validator(root), 0)
            (root / "index-marker").unlink()
            self.assertEqual(_run_build_matrix_validator(root), 1)

    def test_build_matrix_timeout_is_blocked(self):
        with patch("scripts.validate_harness.subprocess.run", side_effect=subprocess.TimeoutExpired("matrix", 120)):
            self.assertEqual(_run_build_matrix_validator(ROOT), 2)

    def test_missing_lint_tool_blocks_before_formatting(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            bin_dir = root / "bin"
            bin_dir.mkdir()
            log = root / "calls"
            tool = bin_dir / "mise"
            tool.write_text("#!/bin/bash\nprintf '%s\\n' \"$*\" >> \"$CALLS\"\nif [[ \"$*\" == *'swiftlint version'* ]]; then exit 1; fi\n")
            tool.chmod(0o755)
            (root / "A.swift").write_text("struct A {}")
            env = dict(os.environ, PATH=f"{bin_dir}:{os.environ['PATH']}", CALLS=str(log))
            result = subprocess.run(["bash", str(ROOT / "scripts/lint-and-format-macos.sh"), str(root)], env=env, capture_output=True)
            self.assertEqual(result.returncode, 2)
            self.assertNotIn("--config", log.read_text())

    def test_all_ast_failures_are_aggregated(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = "apps/macos/Sources/A.swift"
            (root / source).parent.mkdir(parents=True)
            (root / source).write_text("struct A {}")
            for name in ["a", "b"]:
                rule = root / f".ast-grep/rules/common/{name}.yaml"
                rule.parent.mkdir(parents=True, exist_ok=True)
                rule.write_text("id: fixture")
            with patch("scripts.run_swift_checks.run_check", side_effect=[CheckResult("probe", "passed", 0), CheckResult("first", "failed", 1), CheckResult("last", "passed", 0)]):
                self.assertEqual(check_exit(check_sources(root, [source], ["ast"])), 1)


if __name__ == "__main__":
    unittest.main()
