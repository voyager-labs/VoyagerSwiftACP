from __future__ import annotations

import os
import subprocess
import tempfile
import unittest
from pathlib import Path

from scripts.validate_build_matrix import validate_voyager_pbxproj

REPO_ROOT = Path(__file__).resolve().parents[2]
PBXPROJ_PATH = REPO_ROOT / "apps/macos/Voyager/Voyager.xcodeproj/project.pbxproj"
ZIP_SCRIPT_PATH = REPO_ROOT / "scripts/ci/create-sparkle-zip.sh"
BUILD_ARCHIVE_SCRIPT_PATH = REPO_ROOT / "scripts/ci/build-archive.sh"
REGRESSION_REPLACEMENTS = {
    "COPY_PHASE_STRIP = YES;": "COPY_PHASE_STRIP = NO;",
    "DEAD_CODE_STRIPPING = YES;": "DEAD_CODE_STRIPPING = NO;",
    "DEPLOYMENT_POSTPROCESSING = YES;": "DEPLOYMENT_POSTPROCESSING = NO;",
    "ENABLE_PREVIEWS = NO;": "ENABLE_PREVIEWS = YES;",
    "STRIP_INSTALLED_PRODUCT = YES;": "STRIP_INSTALLED_PRODUCT = NO;",
    "STRIP_STYLE = all;": "STRIP_STYLE = non-global;",
    "SWIFT_COMPILATION_MODE = wholemodule;": "SWIFT_COMPILATION_MODE = singlefile;",
    'SWIFT_OPTIMIZATION_LEVEL = "-Osize";': 'SWIFT_OPTIMIZATION_LEVEL = "-O";',
}


class ReleaseSizeBuildContractTests(unittest.TestCase):
    def test_validator_rejects_prod_release_size_setting_regressions(self) -> None:
        optimized_project = PBXPROJ_PATH.read_text(encoding="utf-8")
        regressed_project = optimized_project
        for optimized, regressed in REGRESSION_REPLACEMENTS.items():
            regressed_project = regressed_project.replace(optimized, regressed)

        with tempfile.TemporaryDirectory() as temporary_directory:
            project_path = Path(temporary_directory) / "project.pbxproj"
            _ = project_path.write_text(regressed_project, encoding="utf-8")
            errors: list[str] = []

            validate_voyager_pbxproj(project_path, errors)

        for setting in REGRESSION_REPLACEMENTS:
            setting_name = setting.partition(" = ")[0]
            with self.subTest(setting=setting_name):
                self.assertTrue(any(setting_name in error for error in errors), errors)

    def test_xcode_project_has_no_debug_only_or_redundant_sentry_links(self) -> None:
        project_text = PBXPROJ_PATH.read_text(encoding="utf-8")

        self.assertNotIn("Inject in Frameworks", project_text)
        self.assertNotIn("Sentry in Frameworks", project_text)


class SparkleZipContractTests(unittest.TestCase):
    def test_zip_command_passes_zlib_level_nine_to_ditto(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            fake_bin = root / "bin"
            fake_bin.mkdir()
            capture_path = root / "ditto-arguments.txt"
            fake_ditto = fake_bin / "ditto"
            _ = fake_ditto.write_text(
                '#!/bin/sh\nprintf "%s\\n" "$@" > "$CAPTURE_PATH"\n',
                encoding="utf-8",
            )
            _ = fake_ditto.chmod(0o755)
            app_path = root / "Voyager.app"
            app_path.mkdir()
            build_dir = root / "build"
            environment = os.environ | {
                "APP_PATH": str(app_path),
                "BUILD_DIR": str(build_dir),
                "CAPTURE_PATH": str(capture_path),
                "PATH": f"{fake_bin}:{os.environ['PATH']}",
                "VERSION": "1.0.0",
            }

            _ = subprocess.run([ZIP_SCRIPT_PATH], env=environment, check=True)

            arguments = capture_path.read_text(encoding="utf-8").splitlines()
            self.assertIn("--zlibCompressionLevel", arguments)
            level_index = arguments.index("--zlibCompressionLevel")
            self.assertEqual(arguments[level_index + 1], "9")


class BuildArchiveContractTests(unittest.TestCase):
    def test_prod_release_passes_size_optimization_to_package_graph(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            fake_bin = root / "bin"
            fake_bin.mkdir()
            capture_path = root / "xcodebuild-arguments.txt"
            fake_xcodebuild = fake_bin / "xcodebuild"
            _ = fake_xcodebuild.write_text(
                '#!/bin/sh\nprintf "%s\\n" "$@" > "$CAPTURE_PATH"\n',
                encoding="utf-8",
            )
            _ = fake_xcodebuild.chmod(0o755)
            environment = os.environ | {
                "BUILD_DIR": str(root / "build"),
                "CAPTURE_PATH": str(capture_path),
                "CONFIGURATION": "Prod-Release",
                "PATH": f"{fake_bin}:{os.environ['PATH']}",
                "PROJECT_PATH": "Voyager.xcodeproj",
                "SCHEME": "Voyager-Prod",
            }

            _ = subprocess.run(
                [BUILD_ARCHIVE_SCRIPT_PATH],
                env=environment,
                check=True,
            )

            arguments = capture_path.read_text(encoding="utf-8").splitlines()
            self.assertIn("SWIFT_OPTIMIZATION_LEVEL=-Osize", arguments)


if __name__ == "__main__":
    _ = unittest.main()
