import os
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts/dev/macos-launch.sh"


class MacOSLaunchTests(unittest.TestCase):
    def run_launch(
        self, configuration: str
    ) -> tuple[subprocess.CompletedProcess[str], list[str]]:
        with tempfile.TemporaryDirectory() as directory:
            temporary_root = Path(directory)
            workspace = temporary_root / "Voyager.xcworkspace"
            workspace.mkdir()
            bin_directory = temporary_root / "bin"
            bin_directory.mkdir()
            downstream_log = temporary_root / "xcodebuild-calls.log"

            fake_xcodebuild = bin_directory / "xcodebuild"
            fake_xcodebuild.write_text(
                "#!/usr/bin/env bash\n"
                "set -euo pipefail\n"
                'printf \'%s\\n\' "$*" >> "$FAKE_XCODEBUILD_LOG"\n'
                "printf 'fake downstream success\\n'\n",
                encoding="utf-8",
            )
            fake_xcodebuild.chmod(0o755)

            fake_xcbeautify = bin_directory / "xcbeautify"
            fake_xcbeautify.write_text(
                "#!/usr/bin/env bash\nset -euo pipefail\ncat\n",
                encoding="utf-8",
            )
            fake_xcbeautify.chmod(0o755)

            environment = os.environ.copy()
            environment["PATH"] = f"{bin_directory}{os.pathsep}{environment['PATH']}"
            environment["FAKE_XCODEBUILD_LOG"] = str(downstream_log)
            environment["XCODEBUILD_CMD"] = str(fake_xcodebuild)

            result = subprocess.run(
                [
                    "bash",
                    str(SCRIPT),
                    "--scheme",
                    "Voyager-Dev",
                    "--configuration",
                    configuration,
                    "--workspace",
                    str(workspace),
                    "--no-launch",
                ],
                cwd=temporary_root,
                env=environment,
                text=True,
                capture_output=True,
                check=False,
            )
            calls = (
                downstream_log.read_text(encoding="utf-8").splitlines()
                if downstream_log.exists()
                else []
            )
            return result, calls

    def test_invalid_configuration_is_rejected_before_downstream_commands(self) -> None:
        for attempt in range(2):
            with self.subTest(attempt=attempt):
                result, downstream_calls = self.run_launch("Debug")

                self.assertEqual(
                    result.returncode,
                    2,
                    f"stderr={result.stderr!r}; downstream_calls={downstream_calls!r}",
                )
                self.assertIn("Debug", result.stderr)
                self.assertIn("Dev-Debug", result.stderr)
                self.assertIn("Prod-Release", result.stderr)
                self.assertEqual(downstream_calls, [])
                self.assertNotIn("빌드 완료", result.stdout)

    def test_supported_configurations_reach_downstream_build(self) -> None:
        for configuration in ("Dev-Debug", "Dev-Release", "Prod-Debug", "Prod-Release"):
            with self.subTest(configuration=configuration):
                result, downstream_calls = self.run_launch(configuration)

                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(len(downstream_calls), 1)
                self.assertIn(f"-configuration {configuration}", downstream_calls[0])


if __name__ == "__main__":
    unittest.main()
