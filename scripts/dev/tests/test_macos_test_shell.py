import os
import subprocess
import tempfile
import unittest
from pathlib import Path
from typing import final, override


ROOT = Path(__file__).resolve().parents[3]
SCRIPT = ROOT / "scripts/dev/macos-test.sh"


@final
class MacOSTestShellTests(unittest.TestCase):
    temp_dir: tempfile.TemporaryDirectory[str] | None = None
    tmpdir: Path = Path()
    bin_dir: Path = Path()
    xcodebuild_args: Path = Path()
    xcbeautify_input: Path = Path()
    xcodebuild_count: Path = Path()

    @override
    def setUp(self) -> None:
        self.temp_dir = tempfile.TemporaryDirectory()
        self.tmpdir = Path(self.temp_dir.name)
        self.bin_dir = self.tmpdir / "bin"
        self.bin_dir.mkdir()
        self.xcodebuild_args = self.tmpdir / "xcodebuild_args.txt"
        self.xcbeautify_input = self.tmpdir / "xcbeautify_input.txt"
        self.xcodebuild_count = self.tmpdir / "xcodebuild_count.txt"
        self._write_fake_tools()

    @override
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
                    f'printf "%s\\n" "$@" > "{self.xcodebuild_args}"',
                    f'printf "xcodebuild\\n" >> "{self.xcodebuild_count}"',
                    'printf "xcodebuild output"',
                    'exit "${FAKE_XCODEBUILD_EXIT:-0}"',
                    "",
                ]
            ),
        )
        self._write_executable(
            "xcbeautify",
            "\n".join(
                [
                    "#!/usr/bin/env bash",
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
        self._write_executable("tee", "#!/usr/bin/env bash\ncat\n")

    def run_script(
        self, *args: str, cwd: Path | None = None, **env: str
    ) -> subprocess.CompletedProcess[str]:
        environment = os.environ.copy()
        environment["PATH"] = f"{self.bin_dir}{os.pathsep}{environment['PATH']}"
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

    def captured_args(self) -> list[str]:
        return self.xcodebuild_args.read_text().splitlines()

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
            "Debug",
            "-derivedDataPath",
            str(ROOT / "build/dev/DerivedData"),
            "-clonedSourcePackagesDirPath",
            str(ROOT / "build/dev/SourcePackages"),
            "-skipPackagePluginValidation",
            "-skipMacroValidation",
            "COMPILER_INDEX_STORE_ENABLE=NO",
            "CODE_SIGNING_ALLOWED=NO",
        ]
        for flag in expected:
            self.assertIn(flag, args)

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
        self.assertIn("NSUnbufferedIO=YES xcodebuild test", result.stdout)
        self.assertIn("tee build/dev/xcodebuild-test.log", result.stdout)

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
