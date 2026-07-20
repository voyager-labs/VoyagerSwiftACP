import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path
from typing import final, override


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

    def run_script(
        self, *args: str, **overrides: str
    ) -> subprocess.CompletedProcess[str]:
        environment = os.environ.copy()
        environment["PATH"] = f"{self.bin_dir}{os.pathsep}{environment['PATH']}"
        environment["XCODEBUILD_REAL"] = str(self.bin_dir / "xcodebuild")
        environment["VOYAGER_XCODE_CACHE_ROOT"] = str(self.tmpdir / "cache")
        environment.update(overrides)
        return subprocess.run(
            [str(SCRIPT), *args],
            cwd=ROOT,
            env=environment,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )

    def args(self) -> list[str]:
        return self.captured.read_text().splitlines()

    def test_injects_missing_cache_flags_and_preserves_branch_suffix(self) -> None:
        result = self.run_script(
            "-project",
            "apps/macos/Voyager/Voyager.xcodeproj",
            "-scheme",
            "Voyager-Dev",
            "-configuration",
            "Debug",
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
