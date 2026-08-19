import os
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts/lint-and-format-macos.sh"


class LintAndFormatMacOSTests(unittest.TestCase):
    def test_discovery_uses_case_insensitive_build_component_pruning(self) -> None:
        script = SCRIPT.read_text()

        self.assertIn("-type d -iname build -prune", script)
        self.assertNotIn("-not -path '*/build/*'", script)

    def test_empty_build_root_runs_only_mise_version_probes(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            build_root = Path(directory) / "Build"
            build_root.mkdir()
            bin_dir = Path(directory) / "bin"
            bin_dir.mkdir()
            log_path = Path(directory) / "mise-calls.log"
            mise = bin_dir / "mise"
            mise.write_text(
                "#!/bin/bash\n"
                "set -euo pipefail\n"
                '[[ "$1 $2" == "exec --" ]]\n'
                "shift 2\n"
                'printf \'%s\\n\' "$*" >> "$MISE_CALLS_LOG"\n'
            )
            mise.chmod(0o755)

            environment = os.environ.copy()
            environment["PATH"] = f"{bin_dir}{os.pathsep}{environment['PATH']}"
            environment["MISE_CALLS_LOG"] = str(log_path)
            result = subprocess.run(
                ["bash", str(SCRIPT), str(build_root)],
                cwd=ROOT,
                env=environment,
                text=True,
                capture_output=True,
                check=False,
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(
                log_path.read_text().splitlines(),
                ["swiftformat --version", "swiftlint version"],
            )

    def test_emitted_build_paths_are_rejected_after_find_pruning(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            swift_root = Path(directory) / "swift root"
            swift_root.mkdir()
            expected_files = [
                swift_root / "Sources" / "Feature.swift",
                swift_root / "Tests" / "FeatureTests.swift",
                swift_root / "Buildable.swift",
                swift_root / "builder" / "Feature.swift",
            ]
            excluded_files = [
                swift_root / "Build" / "Generated.swift",
                swift_root / "bUiLd" / "SourcePackages" / "Generated.swift",
                swift_root / "build" / "DerivedSources" / "Generated.swift",
            ]
            for path in expected_files + excluded_files:
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text("struct Fixture {}\n")

            bin_dir = Path(directory) / "bin"
            bin_dir.mkdir()
            log_path = Path(directory) / "tool-args.log"
            fake_find = bin_dir / "find"
            fake_find.write_text(
                r"""#!/bin/bash
set -euo pipefail
root="$FAKE_FIND_ROOT"
printf '%s\0' \
  "$root/Sources/Feature.swift" \
  "$root/Tests/FeatureTests.swift" \
  "$root/Buildable.swift" \
  "$root/builder/Feature.swift" \
  "$root/Build/Generated.swift" \
  "$root/bUiLd/SourcePackages/Generated.swift" \
  "$root/build/DerivedSources/Generated.swift"
"""
            )
            fake_find.chmod(0o755)
            mise = bin_dir / "mise"
            mise.write_text(
                "#!/bin/bash\n"
                "set -euo pipefail\n"
                '[[ "$1 $2" == "exec --" ]]\n'
                "shift 2\n"
                'tool="$1"\n'
                "shift\n"
                'if [[ "$1" == "--version" || "$1" == "version" ]]; then exit 0; fi\n'
                'printf \'%s\\n\' "$tool" >> "$TOOL_ARGS_LOG"\n'
                'printf \'%s\\n\' "$@" >> "$TOOL_ARGS_LOG"\n'
            )
            mise.chmod(0o755)

            environment = os.environ.copy()
            environment["PATH"] = f"{bin_dir}{os.pathsep}{environment['PATH']}"
            environment["FAKE_FIND_ROOT"] = str(swift_root)
            environment["TOOL_ARGS_LOG"] = str(log_path)
            result = subprocess.run(
                ["bash", str(SCRIPT), str(swift_root)],
                cwd=ROOT,
                env=environment,
                text=True,
                capture_output=True,
                check=False,
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            invocations = log_path.read_text().splitlines()
            for path in expected_files:
                self.assertIn(str(path), invocations)
            for path in excluded_files:
                self.assertNotIn(str(path), invocations)

    def test_tools_receive_only_swift_files_outside_build_components(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            temporary_root = Path(directory) / "swift root with spaces"
            expected_source = temporary_root / "Sources" / "Feature.swift"
            expected_test = temporary_root / "Tests" / "FeatureTests.swift"
            expected_source.parent.mkdir(parents=True)
            expected_test.parent.mkdir(parents=True)
            expected_source.write_text("struct Feature {}\n")
            expected_test.write_text("final class FeatureTests {}\n")

            excluded_files = [
                temporary_root / "build" / "Generated.swift",
                temporary_root / "Build" / "Generated.swift",
                temporary_root / "bUiLd" / "Generated.swift",
                temporary_root / "Build" / "SourcePackages" / "Generated.swift",
                temporary_root / "build" / "DerivedSources" / "Generated.swift",
            ]
            for path in excluded_files:
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text("generated\n")

            bin_dir = Path(directory) / "bin"
            bin_dir.mkdir()
            log_path = Path(directory) / "tool-args.log"
            mise = bin_dir / "mise"
            mise.write_text(
                "#!/bin/bash\n"
                "set -euo pipefail\n"
                '[[ "$1 $2" == "exec --" ]]\n'
                "shift 2\n"
                'tool="$1"\n'
                "shift\n"
                'if [[ "$1" == "--version" || "$1" == "version" ]]; then exit 0; fi\n'
                'printf \'%s\\n\' "$tool" >> "$TOOL_ARGS_LOG"\n'
                'printf \'%s\\n\' "$@" >> "$TOOL_ARGS_LOG"\n'
            )
            mise.chmod(0o755)

            environment = os.environ.copy()
            environment["PATH"] = f"{bin_dir}{os.pathsep}{environment['PATH']}"
            environment["TOOL_ARGS_LOG"] = str(log_path)
            result = subprocess.run(
                ["bash", str(SCRIPT), str(temporary_root)],
                cwd=ROOT,
                env=environment,
                text=True,
                capture_output=True,
                check=False,
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            invocations = log_path.read_text().splitlines()
            self.assertIn("swiftformat", invocations)
            self.assertIn("swiftlint", invocations)
            for path in excluded_files:
                self.assertNotIn(str(path), invocations)
            self.assertIn(str(expected_source), invocations)
            self.assertIn(str(expected_test), invocations)

    def test_newline_in_swift_root_is_preserved(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            swift_root = Path(directory) / "swift\nroot"
            (swift_root / "Sources").mkdir(parents=True)
            (swift_root / "Sources" / "Feature.swift").write_text("struct Feature {}\n")
            bin_dir = Path(directory) / "bin"
            bin_dir.mkdir()
            mise = bin_dir / "mise"
            mise.write_text(
                "#!/bin/bash\n"
                "set -euo pipefail\n"
                '[[ "$1 $2" == "exec --" ]]\n'
                "shift 2\n"
                'if [[ "$2" == "--version" || "$2" == "version" ]]; then exit 0; fi\n'
                "exit 0\n"
            )
            mise.chmod(0o755)

            environment = os.environ.copy()
            environment["PATH"] = f"{bin_dir}{os.pathsep}{environment['PATH']}"
            result = subprocess.run(
                ["bash", str(SCRIPT), str(swift_root)],
                cwd=ROOT,
                env=environment,
                text=True,
                capture_output=True,
                check=False,
            )

            self.assertEqual(result.returncode, 0, result.stderr)

    def test_swiftlint_failure_is_propagated(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            swift_root = Path(directory) / "swift root"
            (swift_root / "Sources").mkdir(parents=True)
            (swift_root / "Sources" / "Feature.swift").write_text("struct Feature {}\n")
            bin_dir = Path(directory) / "bin"
            bin_dir.mkdir()
            mise = bin_dir / "mise"
            mise.write_text(
                "#!/bin/bash\n"
                "set -euo pipefail\n"
                '[[ "$1 $2" == "exec --" ]]\n'
                "shift 2\n"
                'tool="$1"\n'
                "shift\n"
                'if [[ "$1" == "--version" || "$1" == "version" ]]; then exit 0; fi\n'
                'if [[ "$tool" == "swiftlint" ]]; then exit 1; fi\n'
                "exit 0\n"
            )
            mise.chmod(0o755)

            environment = os.environ.copy()
            environment["PATH"] = f"{bin_dir}{os.pathsep}{environment['PATH']}"
            result = subprocess.run(
                ["bash", str(SCRIPT), str(swift_root)],
                cwd=ROOT,
                env=environment,
                text=True,
                capture_output=True,
                check=False,
            )

            self.assertEqual(result.returncode, 1)

    def test_swiftformat_failure_is_propagated(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            swift_root = Path(directory) / "swift root"
            (swift_root / "Sources").mkdir(parents=True)
            (swift_root / "Sources" / "Feature.swift").write_text("struct Feature {}\n")
            bin_dir = Path(directory) / "bin"
            bin_dir.mkdir()
            mise = bin_dir / "mise"
            mise.write_text(
                "#!/bin/bash\n"
                "set -euo pipefail\n"
                '[[ "$1 $2" == "exec --" ]]\n'
                "shift 2\n"
                'tool="$1"\n'
                "shift\n"
                'if [[ "$1" == "--version" || "$1" == "version" ]]; then exit 0; fi\n'
                'if [[ "$tool" == "swiftformat" ]]; then exit 1; fi\n'
                "exit 0\n"
            )
            mise.chmod(0o755)

            environment = os.environ.copy()
            environment["PATH"] = f"{bin_dir}{os.pathsep}{environment['PATH']}"
            result = subprocess.run(
                ["bash", str(SCRIPT), str(swift_root)],
                cwd=ROOT,
                env=environment,
                text=True,
                capture_output=True,
                check=False,
            )

            self.assertEqual(result.returncode, 1, result.stderr)


if __name__ == "__main__":
    unittest.main()
