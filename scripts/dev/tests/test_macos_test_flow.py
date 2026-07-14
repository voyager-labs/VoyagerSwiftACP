import contextlib
import io
import json
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock


ROOT = Path(__file__).resolve().parents[3]

from scripts.dev import macos_test_flow


class MacOSTestFlowTests(unittest.TestCase):
    temp_dir = ""
    root = Path()
    docs_root = Path()
    tests_root = Path()
    shell = Path()
    old_root = Path()
    old_shell = Path()
    old_gaps = Path()

    def setUp(self) -> None:
        self.temp_dir = tempfile.mkdtemp()
        self.root = Path(self.temp_dir)
        self.docs_root = self.root / "docs"
        self.tests_root = self.root / "apps/macos/Voyager/VoyagerTests"
        self.shell = self.root / "macos-test.sh"
        self.old_root = macos_test_flow.ROOT_DIR
        self.old_shell = macos_test_flow.DEFAULT_SHELL
        self.old_gaps = macos_test_flow.GAPS_PATH
        macos_test_flow.ROOT_DIR = self.root
        macos_test_flow.DEFAULT_SHELL = self.shell
        macos_test_flow.GAPS_PATH = self.root / "macos_test_flow_gaps.json"
        self.shell.write_text("#!/bin/sh\nexit 0\n")
        os.chmod(self.shell, 0o755)
        macos_test_flow.GAPS_PATH.write_text('{"version": 1, "product_gaps": {}}')

    def tearDown(self) -> None:
        macos_test_flow.ROOT_DIR = self.old_root
        macos_test_flow.DEFAULT_SHELL = self.old_shell
        macos_test_flow.GAPS_PATH = self.old_gaps
        for path in sorted(self.root.rglob("*"), reverse=True):
            if path.is_file():
                path.unlink()
            else:
                path.rmdir()
        self.root.rmdir()

    def add_doc(self, category: str, slug: str) -> Path:
        path = (
            self.docs_root
            / "PRODUCT/05_FEATURE_SPECS"
            / category
            / "flows"
            / f"{slug}_flow.md"
        )
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("# Flow\n")
        return path

    def add_suite(
        self,
        category: str,
        slug: str,
        class_name: str | None = None,
        marker: bool = True,
    ) -> Path:
        pascal = macos_test_flow.slug_to_pascal(slug)
        path = self.tests_root / "Flows" / category.upper() / f"{pascal}FlowTests.swift"
        path.parent.mkdir(parents=True, exist_ok=True)
        class_name = class_name or f"{pascal}FlowTests"
        marker_line = f"// FLOW-ID: {category}.{slug}\n" if marker else ""
        path.write_text(f"{marker_line}final class {class_name}: XCTestCase {{}}\n")
        return path

    def add_gap_config(self, product_gaps: dict[str, object]) -> Path:
        macos_test_flow.GAPS_PATH.write_text(
            json.dumps({"version": 1, "product_gaps": product_gaps})
        )
        return macos_test_flow.GAPS_PATH

    def run_main(self, args: list[str]) -> tuple[int, str, str]:
        stdout = io.StringIO()
        stderr = io.StringIO()
        with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
            result = macos_test_flow.main(args)
        return result, stdout.getvalue(), stderr.getvalue()

    def test_valid_mapping(self) -> None:
        mapping = macos_test_flow.resolve_mapping(
            *macos_test_flow.parse_flow_id("onb.access_unlock")
        )
        self.assertEqual(mapping.document_path, "onb/flows/access_unlock_flow.md")
        self.assertEqual(
            mapping.swift_path,
            "apps/macos/Voyager/VoyagerTests/Flows/ONB/AccessUnlockFlowTests.swift",
        )
        self.assertEqual(mapping.class_name, "AccessUnlockFlowTests")
        self.assertEqual(mapping.selector, "VoyagerTests/AccessUnlockFlowTests")

    def test_invalid_flow_ids(self) -> None:
        for flow_id in (
            "ONB.access_unlock",
            "onb-.access_unlock",
            "onb.access-unlock",
            "onb.AccessUnlock",
        ):
            with self.subTest(flow_id=flow_id):
                self.assertEqual(macos_test_flow.main(["--flow", flow_id]), 2)

    def test_missing_flow_argument(self) -> None:
        self.assertEqual(macos_test_flow.main([]), 2)

    def test_docs_root_precedence(self) -> None:
        old_env = os.environ.get("VOYAGER_PRODUCT_DOCS_ROOT")
        os.environ["VOYAGER_PRODUCT_DOCS_ROOT"] = str(self.root / "env-docs")
        try:
            self.assertEqual(
                macos_test_flow.resolve_docs_root(None, self.root),
                self.root / "env-docs",
            )
            self.assertEqual(
                macos_test_flow.resolve_docs_root(
                    str(self.root / "cli-docs"), self.root
                ),
                self.root / "cli-docs",
            )
        finally:
            if old_env is None:
                del os.environ["VOYAGER_PRODUCT_DOCS_ROOT"]
            else:
                os.environ["VOYAGER_PRODUCT_DOCS_ROOT"] = old_env
        self.assertEqual(
            macos_test_flow.resolve_docs_root(None, self.root),
            self.root / "docs/canonical",
        )

    def test_slug_to_pascal(self) -> None:
        self.assertEqual(
            macos_test_flow.slug_to_pascal("access_unlock"), "AccessUnlock"
        )
        self.assertEqual(
            macos_test_flow.slug_to_pascal("chat_session_management"),
            "ChatSessionManagement",
        )

    def test_list_is_stably_sorted(self) -> None:
        self.add_suite("onb", "zebra")
        self.add_suite("onb", "access_unlock")
        self.add_suite("acc", "auth_session")
        self.assertEqual(
            macos_test_flow.list_mappings(self.tests_root),
            ["acc.auth_session", "onb.access_unlock", "onb.zebra"],
        )

    def test_category_discovers_existing_suites(self) -> None:
        self.add_suite("onb", "access_unlock")
        self.add_suite("onb", "permission_readiness")
        self.add_suite("acc", "auth_session")
        self.assertEqual(
            macos_test_flow.category_mappings("onb", self.tests_root),
            ["onb.access_unlock", "onb.permission_readiness"],
        )

    def test_category_rejects_unknown_regex_valid_category(self) -> None:
        result, stdout, stderr = self.run_main(["--category", "onbb", "--dry-run"])

        self.assertEqual(result, 2)
        self.assertEqual(stdout, "")
        self.assertIn("Invalid flow category: onbb", stderr)

    def test_category_rejects_allowed_category_without_suites(self) -> None:
        result, stdout, stderr = self.run_main(["--category", "acc", "--dry-run"])

        self.assertEqual(result, 2)
        self.assertEqual(stdout, "")
        self.assertIn("No flow suites found for category: acc", stderr)

    def test_checker_duplicate_slug(self) -> None:
        self.add_doc("onb", "access_unlock")
        self.add_doc("acc", "access_unlock")
        self.assertEqual(
            macos_test_flow.main(
                [
                    "--check",
                    "--docs-root",
                    str(self.docs_root),
                ]
            ),
            1,
        )

    def test_discover_flow_docs_limits_checker_to_managed_categories(self) -> None:
        self.add_doc("onb", "access_unlock")
        self.add_doc("cbw", "chat_session_management")

        self.assertEqual(
            [
                (category, slug)
                for category, slug, _ in macos_test_flow.discover_flow_docs(
                    self.docs_root
                )
            ],
            [("onb", "access_unlock")],
        )

    def test_flow_missing_document_or_suite(self) -> None:
        self.assertEqual(
            macos_test_flow.main(
                [
                    "--flow",
                    "onb.access_unlock",
                    "--docs-root",
                    str(self.docs_root),
                ]
            ),
            2,
        )
        self.add_doc("onb", "access_unlock")
        self.assertEqual(
            macos_test_flow.main(
                [
                    "--flow",
                    "onb.access_unlock",
                    "--docs-root",
                    str(self.docs_root),
                ]
            ),
            2,
        )

    def test_checker_orphan_mismatch_and_missing_marker(self) -> None:
        self.add_suite("onb", "access_unlock")
        self.assertEqual(
            macos_test_flow.main(
                [
                    "--check",
                    "--docs-root",
                    str(self.docs_root),
                ]
            ),
            1,
        )
        self.add_doc("onb", "access_unlock")
        self.add_suite("onb", "permission_readiness", class_name="WrongName")
        self.add_doc("onb", "permission_readiness")
        self.add_suite("onb", "ai_provider_setup", marker=False)
        self.add_doc("onb", "ai_provider_setup")
        errors = macos_test_flow.check_structure(self.docs_root, self.tests_root)
        self.assertTrue(any("WrongName" in error for error in errors))
        self.assertTrue(any("missing FLOW-ID" in error for error in errors))

    def test_checker_reports_unmigrated_without_failure(self) -> None:
        self.add_doc("onb", "access_unlock")
        self.assertEqual(
            macos_test_flow.main(
                [
                    "--check",
                    "--docs-root",
                    str(self.docs_root),
                ]
            ),
            0,
        )

    def test_checker_classifies_registered_product_gap(self) -> None:
        self.add_doc("set", "settings_shortcuts")
        self.add_gap_config(
            {
                "set.settings_shortcuts": {
                    "reason": "Missing production support",
                    "missing_symbols": ["KeyboardShortcutsFeature"],
                }
            }
        )
        result, stdout, stderr = self.run_main(
            ["--check", "--docs-root", str(self.docs_root)]
        )
        self.assertEqual(result, 0)
        self.assertEqual(stderr, "")
        self.assertIn("product-gap: set.settings_shortcuts", stdout)
        self.assertNotIn("unmigrated:", stdout)

    def test_checker_rejects_unknown_product_gap_document(self) -> None:
        self.add_gap_config(
            {
                "set.settings_shortcuts": {
                    "reason": "Missing production support",
                    "missing_symbols": ["KeyboardShortcutsFeature"],
                }
            }
        )
        result, _, stderr = self.run_main(
            ["--check", "--docs-root", str(self.docs_root)]
        )
        self.assertEqual(result, 1)
        self.assertIn("unknown product gap document: set.settings_shortcuts", stderr)

    def test_checker_rejects_product_gap_without_reason(self) -> None:
        self.add_doc("set", "settings_shortcuts")
        self.add_gap_config(
            {
                "set.settings_shortcuts": {
                    "missing_symbols": ["KeyboardShortcutsFeature"],
                }
            }
        )
        result, _, stderr = self.run_main(
            ["--check", "--docs-root", str(self.docs_root)]
        )
        self.assertEqual(result, 1)
        self.assertIn("product gap missing reason: set.settings_shortcuts", stderr)

    def test_checker_rejects_product_gap_without_missing_symbols(self) -> None:
        self.add_doc("set", "settings_shortcuts")
        self.add_gap_config(
            {"set.settings_shortcuts": {"reason": "Missing production support"}}
        )
        result, _, stderr = self.run_main(
            ["--check", "--docs-root", str(self.docs_root)]
        )
        self.assertEqual(result, 1)
        self.assertIn("product gap missing symbols: set.settings_shortcuts", stderr)

    def test_checker_rejects_product_gap_suite_collision(self) -> None:
        self.add_doc("set", "settings_shortcuts")
        self.add_suite("set", "settings_shortcuts")
        self.add_gap_config(
            {
                "set.settings_shortcuts": {
                    "reason": "Missing production support",
                    "missing_symbols": ["KeyboardShortcutsFeature"],
                }
            }
        )
        result, _, stderr = self.run_main(
            ["--check", "--docs-root", str(self.docs_root)]
        )
        self.assertEqual(result, 1)
        self.assertIn(
            "product gap has executable suite: set.settings_shortcuts", stderr
        )

    def test_checker_omits_unmigrated_when_docs_are_suites_or_gaps(self) -> None:
        self.add_doc("onb", "access_unlock")
        self.add_suite("onb", "access_unlock")
        self.add_doc("set", "settings_shortcuts")
        self.add_gap_config(
            {
                "set.settings_shortcuts": {
                    "reason": "Missing production support",
                    "missing_symbols": ["KeyboardShortcutsFeature"],
                }
            }
        )
        result, stdout, stderr = self.run_main(
            ["--check", "--docs-root", str(self.docs_root)]
        )
        self.assertEqual(result, 0)
        self.assertEqual(stderr, "")
        self.assertEqual(stdout, "product-gap: set.settings_shortcuts\n")

    def test_product_gap_flow_still_requires_suite(self) -> None:
        self.add_doc("set", "settings_shortcuts")
        self.add_gap_config(
            {
                "set.settings_shortcuts": {
                    "reason": "Missing production support",
                    "missing_symbols": ["KeyboardShortcutsFeature"],
                }
            }
        )
        result, _, stderr = self.run_main(
            ["--flow", "set.settings_shortcuts", "--docs-root", str(self.docs_root)]
        )
        self.assertEqual(result, 2)
        self.assertIn("Missing flow suite", stderr)

    def test_flow_dry_run_uses_xctest_passthrough_selector(self) -> None:
        self.add_doc("onb", "access_unlock")
        self.add_suite("onb", "access_unlock")
        result, stdout, stderr = self.run_main(
            [
                "--flow",
                "onb.access_unlock",
                "--docs-root",
                str(self.docs_root),
                "--dry-run",
            ]
        )
        self.assertEqual(result, 0)
        self.assertEqual(stderr, "")
        self.assertEqual(
            stdout,
            f"{self.shell} -only-testing:VoyagerTests/AccessUnlockFlowTests\n",
        )
        self.assertNotIn("--selector", stdout)
        self.assertNotIn("/Flows/", stdout)

    def test_flow_dry_run_is_independent_of_current_directory(self) -> None:
        self.add_doc("onb", "access_unlock")
        nested_dir = self.root / "nested" / "directory"
        nested_dir.mkdir(parents=True)
        original_cwd = Path.cwd()
        try:
            os.chdir(nested_dir)
            result, stdout, stderr = self.run_main(
                [
                    "--flow",
                    "onb.access_unlock",
                    "--docs-root",
                    str(self.docs_root),
                    "--dry-run",
                ]
            )
        finally:
            os.chdir(original_cwd)
        self.assertEqual(result, 0)
        self.assertEqual(stderr, "")
        self.assertEqual(
            stdout,
            f"{self.shell} -only-testing:VoyagerTests/AccessUnlockFlowTests\n",
        )

    def test_category_dry_run_runs_each_sorted_suite_once(self) -> None:
        for slug in ("zebra", "access_unlock", "permission_readiness"):
            self.add_doc("onb", slug)
            self.add_suite("onb", slug)
        result, stdout, stderr = self.run_main(
            ["--category", "onb", "--docs-root", str(self.docs_root), "--dry-run"]
        )
        self.assertEqual(result, 0)
        self.assertEqual(stderr, "")
        self.assertEqual(
            stdout.splitlines(),
            [
                f"{self.shell} -only-testing:VoyagerTests/AccessUnlockFlowTests",
                f"{self.shell} -only-testing:VoyagerTests/PermissionReadinessFlowTests",
                f"{self.shell} -only-testing:VoyagerTests/ZebraFlowTests",
            ],
        )

    def test_child_exit_is_preserved(self) -> None:
        self.add_doc("onb", "access_unlock")
        self.add_suite("onb", "access_unlock")
        self.shell.write_text(f"#!{sys.executable}\nimport sys\nsys.exit(23)\n")
        self.assertEqual(
            macos_test_flow.main(
                [
                    "--flow",
                    "onb.access_unlock",
                    "--docs-root",
                    str(self.docs_root),
                ]
            ),
            23,
        )

    def test_list_does_not_invoke_shell(self) -> None:
        self.add_doc("onb", "access_unlock")
        self.add_suite("onb", "access_unlock")
        with mock.patch("scripts.dev.macos_test_flow.subprocess.run") as run:
            self.assertEqual(macos_test_flow.main(["--list"]), 0)
        run.assert_not_called()

    def test_check_does_not_invoke_shell(self) -> None:
        self.add_doc("onb", "access_unlock")
        with mock.patch("scripts.dev.macos_test_flow.subprocess.run") as run:
            self.assertEqual(
                macos_test_flow.main(["--check", "--docs-root", str(self.docs_root)]),
                0,
            )
        run.assert_not_called()

    def test_explicit_unmigrated_flow_reports_expected_suite_without_running(
        self,
    ) -> None:
        self.add_doc("onb", "access_unlock")
        with mock.patch("scripts.dev.macos_test_flow.subprocess.run") as run:
            result, _, stderr = self.run_main(
                [
                    "--flow",
                    "onb.access_unlock",
                    "--docs-root",
                    str(self.docs_root),
                ]
            )
        self.assertEqual(result, 2)
        self.assertIn(
            f"Missing flow suite: {self.root / 'apps/macos/Voyager/VoyagerTests/Flows/ONB/AccessUnlockFlowTests.swift'}",
            stderr,
        )
        run.assert_not_called()


if __name__ == "__main__":
    unittest.main()
