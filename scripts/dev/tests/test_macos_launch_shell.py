import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path
from typing import final, override


ROOT = Path(__file__).resolve().parents[3]
SCRIPT = ROOT / "scripts/dev/macos-launch.sh"


@final
class MacOSLaunchShellTests(unittest.TestCase):
    temp_dir: tempfile.TemporaryDirectory[str] | None = None
    tmpdir: Path = Path()
    bin_dir: Path = Path()
    calls: Path = Path()
    derived_data: Path = Path()

    @override
    def setUp(self) -> None:
        self.temp_dir = tempfile.TemporaryDirectory()
        self.tmpdir = Path(self.temp_dir.name)
        self.bin_dir = self.tmpdir / "bin"
        self.bin_dir.mkdir()
        self.calls = self.tmpdir / "calls"
        self.derived_data = self.tmpdir / "derived"
        app_dir = self.tmpdir / "products/Fake.app/Contents/MacOS"
        app_dir.mkdir(parents=True)
        executable = app_dir / "Fake"
        executable.write_text("#!/usr/bin/env bash\nexit 0\n")
        executable.chmod(0o755)
        self.write_executable("mise", "#!/usr/bin/env bash\nexit 1\n")
        self.write_executable(
            "xcrun", "#!/usr/bin/env bash\nprintf 'Swift version 6.2.1\\n'\n"
        )
        payload = json.dumps(
            [
                {
                    "buildSettings": {
                        "TARGET_BUILD_DIR": str(app_dir.parent.parent.parent),
                        "WRAPPER_NAME": "Fake.app",
                        "EXECUTABLE_NAME": "Fake",
                    }
                }
            ]
        )
        self.write_executable(
            "fake-xcodebuild",
            "\n".join(
                [
                    "#!/usr/bin/env bash",
                    'if [[ "$1" == "-version" ]]; then printf "Xcode 26.1\\nBuild version 17B55\\n"; exit 0; fi',
                    f'printf "%s " "$@" >> "{self.calls}"',
                    f'printf "\\n" >> "{self.calls}"',
                    'if [[ " $* " == *" -showBuildSettings "* ]]; then',
                    f"  printf '%s\\n' '{payload}'",
                    "fi",
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

    def test_explicit_derived_data_reaches_build_and_settings_lookup(self) -> None:
        environment = os.environ.copy()
        environment["PATH"] = f"{self.bin_dir}{os.pathsep}{environment['PATH']}"
        result = subprocess.run(
            [
                str(SCRIPT),
                "--scheme",
                "Voyager-Dev",
                "--configuration",
                "Dev-Debug",
                "--derived-data",
                str(self.derived_data),
            ],
            cwd=ROOT,
            env={
                **environment,
                "XCODEBUILD_CMD": str(self.bin_dir / "fake-xcodebuild"),
            },
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        calls = self.calls.read_text().splitlines()
        self.assertEqual(len(calls), 2)
        for call in calls:
            self.assertIn(f"-derivedDataPath {self.derived_data}", call)
        self.assertIn("build", calls[0])
        self.assertIn("-showBuildSettings", calls[1])

    def test_default_path_works_in_stock_bash_through_cache_wrapper(self) -> None:
        environment = os.environ.copy()
        environment["PATH"] = f"{self.bin_dir}{os.pathsep}{environment['PATH']}"
        cache_root = self.tmpdir / "cache"
        result = subprocess.run(
            [
                "/bin/bash",
                str(SCRIPT),
                "--scheme",
                "Voyager-Dev",
                "--configuration",
                "Dev-Debug",
            ],
            cwd=ROOT,
            env={
                **environment,
                "XCODEBUILD_CMD": str(
                    ROOT / "scripts/dev/xcodebuild-branch-product.sh"
                ),
                "XCODEBUILD_REAL": str(self.bin_dir / "fake-xcodebuild"),
                "VOYAGER_XCODE_CACHE_ROOT": str(cache_root),
            },
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        calls = self.calls.read_text().splitlines()
        self.assertEqual(len(calls), 2)
        for call in calls:
            self.assertIn("-derivedDataPath", call)
            self.assertIn("-clonedSourcePackagesDirPath", call)
            self.assertIn("-packageCachePath", call)
            self.assertIn(str(cache_root / "package-cache"), call)
            self.assertIn(str(ROOT / "build/dev/DerivedData"), call)
            self.assertIn(str(ROOT / "build/dev/SourcePackages"), call)


if __name__ == "__main__":
    _ = unittest.main()
