import os
import subprocess
import tempfile
import unittest
from pathlib import Path
from typing import Optional, final


ROOT = Path(__file__).resolve().parents[3]
SCRIPT = ROOT / "scripts/dev/macos-test.sh"
XCODEBUILD_WRAPPER = ROOT / "scripts/dev/xcodebuild-branch-product.sh"
LINT_SCRIPT = ROOT / "scripts/lint-and-format-macos.sh"
MISE_CONFIG = ROOT / "mise.toml"


@final
class MacOSTestShellTests(unittest.TestCase):
    temp_dir: Optional[tempfile.TemporaryDirectory[str]] = None
    tmpdir: Path = Path()
    bin_dir: Path = Path()
    xcodebuild_args: Path = Path()
    xcbeautify_input: Path = Path()
    xcbeautify_args: Path = Path()
    tee_args: Path = Path()
    xcodebuild_count: Path = Path()

    def setUp(self) -> None:
        self.temp_dir = tempfile.TemporaryDirectory()
        self.tmpdir = Path(self.temp_dir.name)
        self.bin_dir = self.tmpdir / "bin"
        self.bin_dir.mkdir()
        self.xcodebuild_args = self.tmpdir / "xcodebuild_args.txt"
        self.xcbeautify_input = self.tmpdir / "xcbeautify_input.txt"
        self.xcbeautify_args = self.tmpdir / "xcbeautify_args.txt"
        self.tee_args = self.tmpdir / "tee_args.txt"
        self.xcodebuild_count = self.tmpdir / "xcodebuild_count.txt"
        self._write_fake_tools()

    def tearDown(self) -> None:
        if self.temp_dir is not None:
            self.temp_dir.cleanup()

    def _write_executable(self, name: str, content: str) -> None:
        path = self.bin_dir / name
        _ = path.write_text(content)
        path.chmod(0o755)

    def _write_fake_tools(self) -> None:
        self._write_executable(
            "xcodebuild",
            "\n".join(
                [
                    "#!/usr/bin/env bash",
                    'if [[ "$1" == "-version" ]]; then printf "Xcode 26.1\\nBuild version 17B55\\n"; exit 0; fi',
                    f'printf "%s\\n" "$@" > "{self.xcodebuild_args}"',
                    f'printf "xcodebuild\\n" >> "{self.xcodebuild_count}"',
                    'printf "xcodebuild output"',
                    'exit "${FAKE_XCODEBUILD_EXIT:-0}"',
                    "",
                ]
            ),
        )
        self._write_executable(
            "xcrun",
            "#!/usr/bin/env bash\nprintf 'Swift version 6.2.1\\n'\n",
        )
        self._write_executable(
            "xcbeautify",
            "\n".join(
                [
                    "#!/usr/bin/env bash",
                    f'printf "%s\\n" "$@" > "{self.xcbeautify_args}"',
                    f'cat > "{self.xcbeautify_input}"',
                    'exit "${FAKE_XCBEAUTIFY_EXIT:-0}"',
                    "",
                ]
            ),
        )
        self._write_executable(
            "mise",
            "\n".join(
                [
                    "#!/usr/bin/env bash",
                    'if [[ "$1" == "exec" && "$2" == "--" ]]; then',
                    "  shift 2",
                    '  exec "$@"',
                    "fi",
                    "exit 64",
                    "",
                ]
            ),
        )
        self._write_executable(
            "tee",
            "#!/usr/bin/env bash\n"
            f'printf "%s\\n" "$@" > "{self.tee_args}"\n'
            "cat\n",
        )

    def run_script(
        self, *args: str, cwd: Optional[Path] = None, **env: str
    ) -> subprocess.CompletedProcess[str]:
        environment = os.environ.copy()
        environment["PATH"] = f"{self.bin_dir}{os.pathsep}{environment['PATH']}"
        environment["XCODEBUILD_REAL"] = str(self.bin_dir / "xcodebuild")
        environment["VOYAGER_XCODE_CACHE_ROOT"] = str(self.tmpdir / "cache")
        environment.update(env)
        return subprocess.run(
            [str(SCRIPT), *args],
            cwd=cwd or ROOT,
            env=environment,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )

    def run_xcodebuild_wrapper(
        self, *args: str, **env: str
    ) -> subprocess.CompletedProcess[str]:
        environment = os.environ.copy()
        environment["PATH"] = f"{self.bin_dir}{os.pathsep}{environment['PATH']}"
        environment["XCODEBUILD_REAL"] = str(self.bin_dir / "xcodebuild")
        environment["VOYAGER_XCODE_CACHE_ROOT"] = str(self.tmpdir / "cache")
        environment.update(env)
        return subprocess.run(
            [str(XCODEBUILD_WRAPPER), *args],
            cwd=ROOT,
            env=environment,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )

    def captured_args(self) -> list[str]:
        return self.xcodebuild_args.read_text().splitlines()

    def captured_xcbeautify_args(self) -> list[str]:
        return self.xcbeautify_args.read_text().splitlines()

    def captured_tee_args(self) -> list[str]:
        return self.tee_args.read_text().splitlines()

    def test_fixed_flags_are_present(self) -> None:
        result = self.run_script()

        self.assertEqual(result.returncode, 0, result.stderr)
        args = self.captured_args()
        expected = [
            "test",
            "-project",
            str(ROOT / "apps/macos/Voyager/Voyager.xcodeproj"),
            "-scheme",
            "Voyager-Dev",
            "-configuration",
            "Dev-Debug",
            "-derivedDataPath",
            "-clonedSourcePackagesDirPath",
            "-packageCachePath",
            "-skipPackagePluginValidation",
            "-skipMacroValidation",
            "COMPILER_INDEX_STORE_ENABLE=NO",
            "CODE_SIGNING_ALLOWED=NO",
        ]
        for flag in expected:
            self.assertIn(flag, args)

    def test_default_scheme_and_artifacts_are_isolated(self) -> None:
        result = self.run_script()

        self.assertEqual(result.returncode, 0, result.stderr)
        args = self.captured_args()
        self.assertEqual(args.count("-scheme"), 1)
        self.assertEqual(args.count("Voyager-Dev"), 1)
        self.assertEqual(
            self.captured_tee_args(),
            [str(ROOT / "build/dev/xcodebuild-test-voyager-dev.log")],
        )
        beautify_args = self.captured_xcbeautify_args()
        report_path_index = beautify_args.index("--report-path")
        self.assertEqual(
            beautify_args[report_path_index + 1],
            str(ROOT / "build/dev/reports/voyager-dev"),
        )
        self.assertTrue((ROOT / "build/dev/reports/voyager-dev").is_dir())

    def test_helper_scheme_is_consumed_and_passthrough_boundaries_are_preserved(
        self,
    ) -> None:
        passthrough = [
            "-only-testing:VoyagerHelperTests/XPC Search Tests",
            "CUSTOM_SETTING=two words",
            "-retry-tests-on-failure",
        ]
        result = self.run_script(
            passthrough[0],
            "--scheme",
            "VoyagerHelper-Dev",
            *passthrough[1:],
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        args = self.captured_args()
        self.assertEqual(args.count("-scheme"), 1)
        self.assertEqual(args.count("VoyagerHelper-Dev"), 1)
        passthrough_start = args.index("CODE_SIGNING_ALLOWED=NO") + 1
        self.assertEqual(
            args[passthrough_start : passthrough_start + len(passthrough)],
            passthrough,
        )
        for argument in passthrough:
            self.assertEqual(args.count(argument), 1)
        self.assertEqual(
            self.captured_tee_args(),
            [str(ROOT / "build/dev/xcodebuild-test-voyager-helper-dev.log")],
        )
        beautify_args = self.captured_xcbeautify_args()
        report_path_index = beautify_args.index("--report-path")
        self.assertEqual(
            beautify_args[report_path_index + 1],
            str(ROOT / "build/dev/reports/voyager-helper-dev"),
        )
        self.assertTrue((ROOT / "build/dev/reports/voyager-helper-dev").is_dir())

    def test_unsupported_scheme_exits_two_without_invoking_xcodebuild(self) -> None:
        result = self.run_script("--scheme", "Voyager-Prod")

        self.assertEqual(result.returncode, 2)
        self.assertFalse(self.xcodebuild_args.exists())
        self.assertFalse(self.xcodebuild_count.exists())
        self.assertIn("unsupported scheme: Voyager-Prod", result.stderr)

    def test_missing_scheme_value_exits_two_without_invoking_xcodebuild(self) -> None:
        result = self.run_script("--scheme")

        self.assertEqual(result.returncode, 2)
        self.assertFalse(self.xcodebuild_args.exists())
        self.assertFalse(self.xcodebuild_count.exists())
        self.assertIn("--scheme requires a value", result.stderr)

    def test_passthrough_arguments_follow_fixed_build_settings(self) -> None:
        selector = "-only-testing:VoyagerTests/AccessUnlockFlowTests"
        result = self.run_script(selector)

        self.assertEqual(result.returncode, 0, result.stderr)
        args = self.captured_args()
        self.assertGreater(args.index(selector), args.index("CODE_SIGNING_ALLOWED=NO"))

    def test_selector_is_forwarded_once(self) -> None:
        selector = "-only-testing:VoyagerTests/AccessUnlockFlowTests"
        result = self.run_script(selector)

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.captured_args().count(selector), 1)

    def test_works_from_repo_root_and_nested_directory(self) -> None:
        root_result = self.run_script(cwd=ROOT)
        nested_dir = self.tmpdir / "nested/working/directory"
        nested_dir.mkdir(parents=True)
        nested_result = self.run_script(cwd=nested_dir)

        self.assertEqual(root_result.returncode, 0, root_result.stderr)
        self.assertEqual(nested_result.returncode, 0, nested_result.stderr)
        self.assertIn(
            str(ROOT / "apps/macos/Voyager/Voyager.xcodeproj"), self.captured_args()
        )

    def test_nonzero_xcodebuild_exit_is_preserved(self) -> None:
        result = self.run_script(FAKE_XCODEBUILD_EXIT="37", FAKE_XCBEAUTIFY_EXIT="0")

        self.assertEqual(result.returncode, 37)

    def test_dry_run_prints_command_without_executing_xcodebuild(self) -> None:
        selector = "-only-testing:VoyagerTests/AccessUnlockFlowTests"
        result = self.run_script("--dry-run", selector)

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(self.xcodebuild_args.exists())
        self.assertIn(selector, result.stdout)
        self.assertIn(
            "NSUnbufferedIO=YES scripts/dev/xcodebuild-branch-product.sh test",
            result.stdout,
        )
        self.assertIn(
            "tee build/dev/xcodebuild-test-voyager-dev.log", result.stdout
        )
        self.assertIn(
            "--report-path build/dev/reports/voyager-dev", result.stdout
        )
        self.assertIn(
            f"CODE_SIGNING_ALLOWED=NO \\\n  {selector} \\\n  2>&1 | tee",
            result.stdout,
        )
        self.assertNotIn("\\n+", result.stdout)
        self.assertNotIn("\n+", result.stdout)

    def test_dry_run_continues_from_signing_setting_to_pipeline_without_arguments(
        self,
    ) -> None:
        result = self.run_script("--dry-run")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(
            "CODE_SIGNING_ALLOWED=NO \\\n  2>&1 | tee build/dev/xcodebuild-test-voyager-dev.log",
            result.stdout,
        )

    def test_helper_dry_run_prints_selected_scheme_and_artifacts(self) -> None:
        selector = "-only-testing:VoyagerHelperTests/XPCSearchServiceRecentTagDispatchTests"
        result = self.run_script(
            "--dry-run", "--scheme", "VoyagerHelper-Dev", selector
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(self.xcodebuild_args.exists())
        self.assertEqual(result.stdout.count("-scheme VoyagerHelper-Dev"), 1)
        self.assertEqual(result.stdout.count(selector), 1)
        self.assertIn(
            "tee build/dev/xcodebuild-test-voyager-helper-dev.log", result.stdout
        )
        self.assertIn(
            "--report-path build/dev/reports/voyager-helper-dev", result.stdout
        )

    def test_xcbeautify_nonzero_exit_is_preserved(self) -> None:
        result = self.run_script(FAKE_XCODEBUILD_EXIT="0", FAKE_XCBEAUTIFY_EXIT="41")

        self.assertEqual(result.returncode, 41)

    def test_target_mode_omits_only_automatic_derived_data_path(self) -> None:
        requested = [
            "-project",
            "apps/macos/Voyager/Voyager.xcodeproj",
            "-target",
            "FilterSearchXPC",
            "-configuration",
            "Dev-Debug",
            "CODE_SIGNING_ALLOWED=NO",
            "build",
        ]
        result = self.run_xcodebuild_wrapper(*requested)

        self.assertEqual(result.returncode, 0, result.stderr)
        args = self.captured_args()
        self.assertEqual(args[: len(requested)], requested)
        self.assertNotIn("-derivedDataPath", args)
        self.assertEqual(args.count("-clonedSourcePackagesDirPath"), 1)
        self.assertEqual(args.count("-packageCachePath"), 1)
        self.assertEqual(
            args.count(f"SYMROOT={ROOT / 'build/dev/TargetBuild'}"), 1
        )
        self.assertEqual(
            args.count(
                f"OBJROOT={ROOT / 'build/dev/TargetBuild/Intermediates.noindex'}"
            ),
            1,
        )

    def test_target_mode_preserves_explicit_cache_overrides(self) -> None:
        result = self.run_xcodebuild_wrapper(
            "-project",
            "apps/macos/Voyager/Voyager.xcodeproj",
            "-target",
            "FilterSearchXPC",
            "-derivedDataPath",
            "/tmp/caller-derived-data",
            "-clonedSourcePackagesDirPath",
            "/tmp/caller-source-packages",
            "-packageCachePath",
            "/tmp/caller-package-cache",
            "SYMROOT=/tmp/caller-products",
            "OBJROOT=/tmp/caller-intermediates",
            "build",
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        args = self.captured_args()
        expected = {
            "-derivedDataPath": "/tmp/caller-derived-data",
            "-clonedSourcePackagesDirPath": "/tmp/caller-source-packages",
            "-packageCachePath": "/tmp/caller-package-cache",
        }
        for flag, value in expected.items():
            self.assertEqual(args.count(flag), 1)
            self.assertEqual(args[args.index(flag) + 1], value)
        self.assertEqual(args.count("SYMROOT=/tmp/caller-products"), 1)
        self.assertEqual(args.count("OBJROOT=/tmp/caller-intermediates"), 1)

    def test_lint_script_excludes_lowercase_and_uppercase_build_paths(self) -> None:
        swift_root = self.tmpdir / "SwiftRoot"
        source_file = swift_root / "Sources/Feature.swift"
        lowercase_generated = swift_root / "build/Generated.swift"
        uppercase_generated = swift_root / "Build/GeneratedAssetSymbols.swift"
        for file in (source_file, lowercase_generated, uppercase_generated):
            file.parent.mkdir(parents=True, exist_ok=True)
            file.write_text("struct Fixture {}\n")

        swiftformat_args = self.tmpdir / "swiftformat_args.txt"
        swiftlint_args = self.tmpdir / "swiftlint_args.txt"
        self._write_executable(
            "swiftformat",
            "#!/usr/bin/env bash\n"
            'if [[ "$1" == "--version" ]]; then exit 0; fi\n'
            f'printf "%s\n" "$@" > "{swiftformat_args}"\n',
        )
        self._write_executable(
            "swiftlint",
            "#!/usr/bin/env bash\n"
            'if [[ "$1" == "version" ]]; then exit 0; fi\n'
            f'printf "%s\n" "$@" > "{swiftlint_args}"\n',
        )
        environment = os.environ.copy()
        environment["PATH"] = f"{self.bin_dir}{os.pathsep}{environment['PATH']}"
        result = subprocess.run(
            ["/bin/bash", str(LINT_SCRIPT), str(swift_root)],
            cwd=ROOT,
            env=environment,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        format_args = swiftformat_args.read_text().splitlines()
        exclude_index = format_args.index("--exclude")
        self.assertEqual(
            format_args[exclude_index + 1],
            f"{swift_root / 'build'},{swift_root / 'Build'}",
        )
        lint_args = swiftlint_args.read_text().splitlines()
        self.assertIn(str(source_file), lint_args)
        self.assertNotIn(str(lowercase_generated), lint_args)
        self.assertNotIn(str(uppercase_generated), lint_args)

    def test_mise_tasks_delegate_to_canonical_wrappers(self) -> None:
        config = MISE_CONFIG.read_text()

        self.assertIn("[tasks.macos-helper-test]", config)
        self.assertIn(
            'run = "scripts/dev/macos-test.sh --scheme VoyagerHelper-Dev \\"$@\\""',
            config,
        )
        self.assertIn("[tasks.macos-filter-search-xpc-build]", config)
        xpc_task = config.split(
            "[tasks.macos-filter-search-xpc-build]", maxsplit=1
        )[1].split("\n[", maxsplit=1)[0]
        self.assertIn(
            "scripts/dev/xcodebuild-branch-product.sh "
            "-project apps/macos/Voyager/Voyager.xcodeproj "
            "-target FilterSearchXPC -configuration Dev-Debug",
            xpc_task,
        )
        self.assertIn("CODE_SIGNING_ALLOWED=NO", xpc_task)
        self.assertIn("COMPILER_INDEX_STORE_ENABLE=NO", xpc_task)
        self.assertIn("-skipPackagePluginValidation", xpc_task)
        self.assertIn("-skipMacroValidation", xpc_task)
        self.assertNotIn("-scheme", xpc_task)

    def test_xcbeautify_receives_piped_xcodebuild_output(self) -> None:
        result = self.run_script()

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.xcbeautify_input.read_text(), "xcodebuild output")

    def test_xcodebuild_is_invoked_once(self) -> None:
        result = self.run_script()

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.xcodebuild_count.read_text().splitlines(), ["xcodebuild"])

    def test_ns_unbuffered_io_is_set(self) -> None:
        self._write_executable(
            "xcodebuild",
            "\n".join(
                [
                    "#!/usr/bin/env bash",
                    'if [[ "$1" == "-version" ]]; then printf "Xcode 26.1\\nBuild version 17B55\\n"; exit 0; fi',
                    f'printf "%s" "$NSUnbufferedIO" > "{self.xcodebuild_args}"',
                    "",
                ]
            ),
        )

        result = self.run_script()

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.xcodebuild_args.read_text(), "YES")


if __name__ == "__main__":
    _ = unittest.main()
