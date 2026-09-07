"""Boundary tests for argv batching, receipts and the optional matrix CLI."""
from __future__ import annotations

from contextlib import redirect_stdout
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

from scripts.run_swift_checks import (
    CheckResult, check_exit, check_sources, main, path_batches,
)


class SwiftCheckContractTests(unittest.TestCase):
    def test_batches_preserve_order_and_unicode_byte_budget(self):
        paths = ["a b.swift", "한글.swift", "a\nb.swift", "d.swift"]
        batches = list(path_batches(paths, budget=22))
        self.assertEqual([path for batch in batches for path in batch], paths)
        self.assertTrue(all(sum(len(os.fsencode(path)) + 1 for path in batch) <= 22 for batch in batches))
        self.assertGreater(len(batches), 1)

    def test_empty_batches_do_not_invoke_whole_repository_implicitly(self):
        self.assertEqual(list(path_batches([])), [])

    def test_single_path_larger_than_budget_is_blocked(self):
        with self.assertRaises(RuntimeError):
            list(path_batches(["too-long.swift"], budget=3))

    def test_unknown_and_unrun_status_cannot_pass(self):
        for status in ["notRun", "unknown", "blocked"]:
            with self.subTest(status=status):
                self.assertEqual(check_exit([CheckResult("test", status)]), 2)

    def test_broken_source_symlink_is_not_silently_ignored(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "apps/macos/Sources/A.swift"
            source.parent.mkdir(parents=True)
            source.symlink_to("missing.swift")
            with self.assertRaises(RuntimeError):
                check_sources(root, [source.relative_to(root).as_posix()], ["ast"])

    def test_later_scope_error_keeps_earlier_failure_in_receipt(self):
        output = io.StringIO()
        with tempfile.TemporaryDirectory() as directory, patch.object(
            sys, "argv", ["swift-checks", "--root", directory, "--all", "--checks", "format", "lint"],
        ), patch(
            "scripts.run_swift_checks.changed_paths", return_value=[],
        ), patch(
            "scripts.run_swift_checks.git", return_value=b"",
        ), patch(
            "scripts.run_swift_checks.check_sources",
            side_effect=[[CheckResult("format", "failed", 1)], RuntimeError("missing lint config")],
        ), redirect_stdout(output):
            code = main()
        receipt = json.loads(output.getvalue())
        self.assertEqual(code, 2)
        self.assertEqual([result["status"] for result in receipt["checks"]], ["failed", "blocked"])
        self.assertEqual(receipt["selectedChecks"], ["format", "lint"])

    def test_matrix_is_explicit_and_its_actual_exit_is_reported(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            scripts = root / "scripts"
            scripts.mkdir()
            (scripts / "__init__.py").write_text("")
            matrix = scripts / "validate_build_matrix.py"
            matrix.write_text("raise SystemExit(1)\n")
            command = [sys.executable, "-m", "scripts.validate_harness", "--root", str(root), "--all"]
            plain = subprocess.run(command, capture_output=True, text=True, check=False)
            self.assertEqual(plain.returncode, 0, plain.stderr)
            self.assertEqual(json.loads(plain.stdout)["buildMatrix"]["status"], "notRun")
            required = subprocess.run([*command, "--with-build-matrix"], capture_output=True, text=True, check=False)
            self.assertEqual(required.returncode, 1, required.stderr)
            self.assertEqual(json.loads(required.stdout)["buildMatrix"]["status"], "failed")
            # Change source size as well as content: timestamp-based .pyc caches
            # can otherwise reuse the failure fixture within the same second.
            matrix.write_text("raise SystemExit(0)  # corrected fixture\n")
            corrected = subprocess.run([*command, "--with-build-matrix"], capture_output=True, text=True, check=False)
            self.assertEqual(corrected.returncode, 0, corrected.stderr)
            self.assertEqual(json.loads(corrected.stdout)["buildMatrix"]["status"], "passed")

    def test_missing_requested_matrix_does_not_auto_skip(self):
        with tempfile.TemporaryDirectory() as directory:
            result = subprocess.run(
                [sys.executable, "-m", "scripts.validate_harness", "--root", directory, "--all", "--with-build-matrix"],
                capture_output=True, text=True, check=False,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertNotIn(json.loads(result.stdout)["buildMatrix"]["status"], ["passed", "notRun", "notApplicable"])


if __name__ == "__main__":
    unittest.main()
