import json
import os
import select
import subprocess
import tempfile
import unittest
from pathlib import Path
from typing import Optional, final, override


ROOT = Path(__file__).resolve().parents[3]
SCRIPT = ROOT / "scripts/dev/xcodebuild-branch-product.sh"


@final
class XcodebuildBranchProductShellTests(unittest.TestCase):
    temp_dir: tempfile.TemporaryDirectory[str] | None = None
    tmpdir: Path = Path()
    bin_dir: Path = Path()
    captured: Path = Path()

    @override
    def setUp(self) -> None:
        self.temp_dir = tempfile.TemporaryDirectory()
        self.tmpdir = Path(self.temp_dir.name)
        self.bin_dir = self.tmpdir / "bin"
        self.bin_dir.mkdir()
        self.captured = self.tmpdir / "args"
        self.write_executable(
            "xcrun", "#!/usr/bin/env bash\nprintf 'Swift version 6.2.1\\n'\n"
        )
        self.write_executable(
            "xcodebuild",
            "\n".join(
                [
                    "#!/usr/bin/env bash",
                    'if [[ "$1" == "-version" ]]; then printf "Xcode 26.1\\nBuild version 17B55\\n"; exit 0; fi',
                    f'printf "%s\\n" "$@" > "{self.captured}"',
                    "",
                ]
            ),
        )

    @override
    def tearDown(self) -> None:
        if self.temp_dir is not None:
            self.temp_dir.cleanup()

    def write_executable(self, name: str, content: str) -> None:
        path = self.bin_dir / name
        path.write_text(content)
        path.chmod(0o755)

    def environment(self, **overrides: str) -> dict[str, str]:
        environment = os.environ.copy()
        environment["PATH"] = f"{self.bin_dir}{os.pathsep}{environment['PATH']}"
        environment["XCODEBUILD_REAL"] = str(self.bin_dir / "xcodebuild")
        environment["VOYAGER_XCODE_CACHE_ROOT"] = str(self.tmpdir / "cache")
        environment.update(overrides)
        return environment

    def run_script(
        self, *args: str, **overrides: str
    ) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [str(SCRIPT), *args],
            cwd=ROOT,
            env=self.environment(**overrides),
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )

    def await_entry(self, process: subprocess.Popen[str]) -> str:
        assert process.stdout is not None
        readable, _, _ = select.select([process.stdout], [], [], 5)
        if not readable:
            process.terminate()
            _, stderr = process.communicate(timeout=5)
            self.fail(f"fake xcodebuild did not enter: {stderr}")
        return process.stdout.readline()

    def args(self) -> list[str]:
        return self.captured.read_text().splitlines()

    def test_injects_missing_cache_flags_and_preserves_branch_suffix(self) -> None:
        result = self.run_script(
            "-project",
            "apps/macos/Voyager/Voyager.xcodeproj",
            "-scheme",
            "Voyager-Dev",
            "-configuration",
            "Dev-Debug",
            "build",
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        arguments = self.args()
        self.assertEqual(arguments.count("-derivedDataPath"), 1)
        self.assertEqual(arguments.count("-clonedSourcePackagesDirPath"), 1)
        self.assertEqual(arguments.count("-packageCachePath"), 1)
        self.assertEqual(
            arguments[arguments.index("-derivedDataPath") + 1],
            str((ROOT / "build/dev/DerivedData").resolve()),
        )
        self.assertEqual(
            arguments[arguments.index("-clonedSourcePackagesDirPath") + 1],
            str((ROOT / "build/dev/SourcePackages").resolve()),
        )
        suffixes = [
            argument
            for argument in arguments
            if argument.startswith("VOYAGER_APP_SUFFIX=-")
        ]
        self.assertEqual(len(suffixes), 1)
        self.assertNotEqual(suffixes[0], "VOYAGER_APP_SUFFIX=-")

    def test_dev_release_does_not_trigger_suffix_injection(self) -> None:
        result = self.run_script(
            "-project",
            "apps/macos/Voyager/Voyager.xcodeproj",
            "-scheme",
            "Voyager-Dev",
            "-configuration",
            "Dev-Release",
            "build",
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        arguments = self.args()
        self.assertEqual(arguments.count("-derivedDataPath"), 1)
        self.assertEqual(arguments.count("-clonedSourcePackagesDirPath"), 1)
        self.assertEqual(arguments.count("-packageCachePath"), 1)
        suffixes = [
            argument
            for argument in arguments
            if argument.startswith("VOYAGER_APP_SUFFIX=")
        ]
        self.assertEqual(len(suffixes), 0)

    def test_explicit_cache_flags_are_preserved_without_duplication(self) -> None:
        result = self.run_script(
            "-project",
            "apps/macos/Voyager/Voyager.xcodeproj",
            "-derivedDataPath",
            "/tmp/derived",
            "-clonedSourcePackagesDirPath",
            "/tmp/source",
            "-packageCachePath",
            "/tmp/packages",
            "build",
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        arguments = self.args()
        self.assertEqual(arguments.count("-derivedDataPath"), 1)
        self.assertEqual(
            arguments[arguments.index("-derivedDataPath") + 1], "/tmp/derived"
        )
        self.assertEqual(arguments.count("-clonedSourcePackagesDirPath"), 1)
        self.assertEqual(arguments.count("-packageCachePath"), 1)
        self.assertFalse((self.tmpdir / "cache/worktrees").exists())

    def test_metadata_records_selected_scheme_as_entrypoint(self) -> None:
        result = self.run_script(
            "-project",
            "apps/macos/Voyager/Voyager.xcodeproj",
            "-scheme",
            "FileManagerHost-Dev",
            "build",
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        metadata_paths = list((self.tmpdir / "cache/worktrees").glob("*/metadata.json"))
        self.assertEqual(len(metadata_paths), 1)
        self.assertEqual(
            json.loads(metadata_paths[0].read_text())["entrypoint"],
            "FileManagerHost-Dev",
        )

    def test_same_worktree_schemes_enter_xcodebuild_serially(self) -> None:
        release_fifo = self.tmpdir / "release"
        helper_probe_fifo = self.tmpdir / "helper-probe"
        os.mkfifo(release_fifo)
        os.mkfifo(helper_probe_fifo)
        self.write_executable(
            "xcrun",
            "\n".join(
                [
                    "#!/usr/bin/env bash",
                    'if [[ -n "${FAKE_PROBE_FIFO:-}" ]]; then printf "ready\n" > "$FAKE_PROBE_FIFO"; fi',
                    "printf 'Swift version 6.2.1\n'",
                    "",
                ]
            ),
        )
        self.write_executable(
            "xcodebuild",
            "\n".join(
                [
                    "#!/usr/bin/env bash",
                    'if [[ "$1" == "-version" ]]; then printf "Xcode 26.1\nBuild version 17B55\n"; exit 0; fi',
                    'scheme=""',
                    'previous=""',
                    'for argument in "$@"; do',
                    '  if [[ "$previous" == "-scheme" ]]; then scheme="$argument"; fi',
                    '  previous="$argument"',
                    'done',
                    'printf "entered:%s\n" "$scheme"',
                    f'if [[ "$scheme" == "Voyager-Dev" ]]; then read -r _ < "{release_fifo}"; fi',
                    "",
                ]
            ),
        )
        arguments = [
            "-project",
            "apps/macos/Voyager/Voyager.xcodeproj",
            "-configuration",
            "Dev-Debug",
            "test",
        ]
        first = subprocess.Popen(
            [str(SCRIPT), *arguments[:2], "-scheme", "Voyager-Dev", *arguments[2:]],
            cwd=ROOT,
            env=self.environment(),
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        second: Optional[subprocess.Popen[str]] = None
        probe_descriptor = os.open(helper_probe_fifo, os.O_RDONLY | os.O_NONBLOCK)
        try:
            self.assertEqual(self.await_entry(first), "entered:Voyager-Dev\n")
            second = subprocess.Popen(
                [
                    str(SCRIPT),
                    *arguments[:2],
                    "-scheme",
                    "VoyagerHelper-Dev",
                    *arguments[2:],
                ],
                cwd=ROOT,
                env=self.environment(FAKE_PROBE_FIFO=str(helper_probe_fifo)),
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )
            probe_signals = b""
            while probe_signals.count(b"\n") < 2:
                probe_ready, _, _ = select.select([probe_descriptor], [], [], 5)
                self.assertTrue(
                    probe_ready, "helper resolver did not complete its toolchain probes"
                )
                probe_signals += os.read(probe_descriptor, 64)
            self.assertEqual(probe_signals, b"ready\nready\n")
            assert second.stdout is not None
            entered_early, _, _ = select.select([second.stdout], [], [], 0.5)
            self.assertEqual(entered_early, [])
            self.assertIsNone(second.poll())

            with release_fifo.open("w") as release:
                _ = release.write("release\n")
            _, first_stderr = first.communicate(timeout=5)
            self.assertEqual(first.returncode, 0, first_stderr)
            self.assertEqual(self.await_entry(second), "entered:VoyagerHelper-Dev\n")
            _, second_stderr = second.communicate(timeout=5)
            self.assertEqual(second.returncode, 0, second_stderr)
        finally:
            os.close(probe_descriptor)
            for process in (first, second):
                if process is not None and process.poll() is None:
                    process.terminate()
                    _ = process.communicate(timeout=5)

    def test_resolver_failure_prevents_real_xcodebuild_execution(self) -> None:
        self.write_executable(
            "xcodebuild",
            "\n".join(
                [
                    "#!/usr/bin/env bash",
                    'if [[ "$1" == "-version" ]]; then exit 71; fi',
                    f'printf "%s\\n" "$@" > "{self.captured}"',
                    "",
                ]
            ),
        )

        result = self.run_script(
            "-project", "apps/macos/Voyager/Voyager.xcodeproj", "build"
        )

        self.assertEqual(result.returncode, 2)
        self.assertIn("cache flag resolver failed", result.stderr)
        self.assertFalse(self.captured.exists())


if __name__ == "__main__":
    _ = unittest.main()
