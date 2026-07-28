"""Tests for scripts.validate_build_matrix."""

from __future__ import annotations

import tempfile
import unittest
from pathlib import Path
from unittest import mock

from scripts.validate_build_matrix import (
    DEV_DEBUG,
    DEV_RELEASE,
    PROD_DEBUG,
    PROD_RELEASE,
    PROD_RELEASE_SIZE_SETTINGS,
    check_ci_references,
    check_host_project,
    check_scheme_files,
    check_voyager_configs_exist,
    main,
    validate_voyager_pbxproj,
)

_cfg_counter = 0


def _make_cfg(
    name: str,
    build_settings: dict[str, str] | None = None,
) -> mock.MagicMock:
    """Create a mock XCBuildConfiguration with unique ID."""
    global _cfg_counter
    _cfg_counter += 1
    cfg = mock.MagicMock()
    cfg.get.side_effect = lambda key, default=None: {
        "name": name,
        "buildSettings": build_settings or {},
    }.get(key, default)
    cfg.get_id.return_value = f"id-{_cfg_counter}"
    return cfg


def _reset_cfg_counter() -> None:
    global _cfg_counter
    _cfg_counter = 0


def _make_cl(
    config_ids: list[str],
    config_names: list[str],
    default_name: str = PROD_RELEASE,
    cl_id: str = "mock-cl",
) -> mock.MagicMock:
    cl = mock.MagicMock()
    cl.get_id.return_value = cl_id
    cl.get.side_effect = lambda key, default=None: {
        "buildConfigurations": [
            f"{cid} /* {cname} */" for cid, cname in zip(config_ids, config_names)
        ],
        "defaultConfigurationName": default_name,
    }.get(key, default)
    return cl


def _make_target(name: str, cl_id: str = "mock-cl") -> mock.MagicMock:
    t = mock.MagicMock()
    t.get.side_effect = lambda key, default=None: {
        "name": name,
        "buildConfigurationList": cl_id,
    }.get(key, default)
    t.get_id.return_value = f"target-{name}"
    return t


def _make_project(cl_id: str = "mock-cl") -> mock.MagicMock:
    p = mock.MagicMock()
    p.get.side_effect = lambda key, default=None: {
        "buildConfigurationList": cl_id,
    }.get(key, default)
    return p


class CheckVoyagerConfigsExistTests(unittest.TestCase):
    """Tests for check_voyager_configs_exist."""

    def test_returns_true_when_all_voy580_configs_present(self) -> None:
        _reset_cfg_counter()
        configs = [
            _make_cfg(DEV_DEBUG),
            _make_cfg(DEV_RELEASE),
            _make_cfg(PROD_DEBUG),
            _make_cfg(PROD_RELEASE),
        ]
        errors: list[str] = []
        result = check_voyager_configs_exist(configs, errors)
        self.assertTrue(result)
        self.assertEqual(errors, [])

    def test_reports_error_on_legacy_debug_release(self) -> None:
        _reset_cfg_counter()
        configs = [_make_cfg("Debug"), _make_cfg("Release")]
        errors: list[str] = []
        result = check_voyager_configs_exist(configs, errors)
        self.assertFalse(result)
        self.assertGreater(len(errors), 0)
        self.assertIn("missing", errors[0].lower())

    def test_reports_error_when_missing_one_config(self) -> None:
        _reset_cfg_counter()
        configs = [
            _make_cfg(DEV_DEBUG),
            _make_cfg(DEV_RELEASE),
            _make_cfg(PROD_DEBUG),
        ]
        errors: list[str] = []
        result = check_voyager_configs_exist(configs, errors)
        self.assertFalse(result)
        self.assertGreater(len(errors), 0)
        self.assertIn("missing", errors[0].lower())


class ValidateVoyagerPbxprojTests(unittest.TestCase):
    """Tests for validate_voyager_pbxproj."""

    def test_reports_error_on_legacy_configs(self) -> None:
        _reset_cfg_counter()
        errors: list[str] = []
        with mock.patch("scripts.validate_build_matrix._load_pbxproj") as mock_load:
            mock_proj = mock.MagicMock()
            mock_proj.objects.get_objects_in_section.side_effect = lambda section: {
                "XCBuildConfiguration": [
                    _make_cfg("Debug"),
                    _make_cfg("Release"),
                ],
                "XCConfigurationList": [],
                "PBXNativeTarget": [],
                "PBXProject": [],
            }.get(section, [])
            mock_load.return_value = mock_proj
            validate_voyager_pbxproj(Path("dummy.pbxproj"), errors)
            self.assertGreater(len(errors), 0)
            self.assertTrue(
                any("legacy" in e.lower() or "missing" in e.lower() for e in errors),
                f"Expected legacy/missing error, got: {errors}",
            )

    def test_well_formed_voyager_passes(self) -> None:
        _reset_cfg_counter()
        errors: list[str] = []

        v_cfgs = [
            _make_cfg(
                DEV_DEBUG,
                {
                    "APP_ENV": "dev",
                    "PRODUCT_BUNDLE_IDENTIFIER": "fm.voyager.Voyager.dev",
                    "CODE_SIGN_IDENTITY": "Apple Development",
                    "ENABLE_HARDENED_RUNTIME": "NO",
                    "VOYAGER_APP_SUFFIX": "",
                    "SUFeedURL": "",
                    "XPC_MACH_SERVICE_NAME": "fm.voyager.Voyager.FilterSearchXPC.dev",
                },
            ),
            _make_cfg(
                DEV_RELEASE,
                {
                    "APP_ENV": "dev",
                    "PRODUCT_BUNDLE_IDENTIFIER": "fm.voyager.Voyager.dev",
                    "CODE_SIGN_IDENTITY": "Apple Development",
                    "ENABLE_HARDENED_RUNTIME": "YES",
                    "VOYAGER_APP_SUFFIX": "-profile",
                    "SUFeedURL": "",
                    "XPC_MACH_SERVICE_NAME": "fm.voyager.Voyager.FilterSearchXPC.dev",
                },
            ),
            _make_cfg(
                PROD_DEBUG,
                {
                    "APP_ENV": "prod",
                    "PRODUCT_BUNDLE_IDENTIFIER": "fm.voyager.Voyager-proddebug",
                    "CODE_SIGN_IDENTITY": "Developer ID Application",
                    "ENABLE_HARDENED_RUNTIME": "YES",
                    "VOYAGER_APP_SUFFIX": "-proddebug",
                    "SUFeedURL": "",
                    "XPC_MACH_SERVICE_NAME": "fm.voyager.Voyager.FilterSearchXPC.proddebug",
                },
            ),
            _make_cfg(
                PROD_RELEASE,
                {
                    **PROD_RELEASE_SIZE_SETTINGS,
                    "APP_ENV": "prod",
                    "PRODUCT_BUNDLE_IDENTIFIER": "fm.voyager.Voyager",
                    "CODE_SIGN_IDENTITY": "Developer ID Application",
                    "ENABLE_HARDENED_RUNTIME": "YES",
                    "VOYAGER_APP_SUFFIX": "",
                    "SUFeedURL": "https://downloads.voyager.fm/releases/appcast.xml",
                    "XPC_MACH_SERVICE_NAME": "fm.voyager.Voyager.FilterSearchXPC",
                },
            ),
        ]
        v_ids = [c.get_id() for c in v_cfgs]
        v_names = [DEV_DEBUG, DEV_RELEASE, PROD_DEBUG, PROD_RELEASE]

        h_cfgs = [
            _make_cfg(
                DEV_DEBUG,
                {
                    "APP_ENV": "dev",
                    "PRODUCT_BUNDLE_IDENTIFIER": "fm.voyager.VoyagerHelper.dev",
                    "CODE_SIGN_IDENTITY": "Apple Development",
                    "ENABLE_HARDENED_RUNTIME": "NO",
                    "VOYAGER_APP_SUFFIX": "",
                },
            ),
            _make_cfg(
                DEV_RELEASE,
                {
                    "APP_ENV": "dev",
                    "PRODUCT_BUNDLE_IDENTIFIER": "fm.voyager.VoyagerHelper.dev",
                    "CODE_SIGN_IDENTITY": "Apple Development",
                    "ENABLE_HARDENED_RUNTIME": "YES",
                    "VOYAGER_APP_SUFFIX": "-profile",
                },
            ),
            _make_cfg(
                PROD_DEBUG,
                {
                    "APP_ENV": "prod",
                    "PRODUCT_BUNDLE_IDENTIFIER": "fm.voyager.VoyagerHelper-proddebug",
                    "CODE_SIGN_IDENTITY": "Developer ID Application",
                    "ENABLE_HARDENED_RUNTIME": "YES",
                    "VOYAGER_APP_SUFFIX": "-proddebug",
                },
            ),
            _make_cfg(
                PROD_RELEASE,
                {
                    **PROD_RELEASE_SIZE_SETTINGS,
                    "APP_ENV": "prod",
                    "PRODUCT_BUNDLE_IDENTIFIER": "fm.voyager.VoyagerHelper",
                    "CODE_SIGN_IDENTITY": "Developer ID Application",
                    "ENABLE_HARDENED_RUNTIME": "YES",
                    "VOYAGER_APP_SUFFIX": "",
                },
            ),
        ]
        h_ids = [c.get_id() for c in h_cfgs]

        t_cfgs = [
            _make_cfg(
                DEV_DEBUG,
                {
                    "APP_ENV": "dev",
                    "PRODUCT_BUNDLE_IDENTIFIER": "fm.voyager.VoyagerTests.dev",
                    "CODE_SIGN_IDENTITY": "Apple Development",
                    "ENABLE_HARDENED_RUNTIME": "NO",
                },
            ),
        ]
        t_ids = [c.get_id() for c in t_cfgs]

        x_cfgs = [
            _make_cfg(
                DEV_DEBUG,
                {
                    "APP_ENV": "dev",
                    "PRODUCT_BUNDLE_IDENTIFIER": "fm.voyager.Voyager.FilterSearchXPC.dev",
                    "XPC_MACH_SERVICE_NAME": "fm.voyager.Voyager.FilterSearchXPC.dev",
                    "CODE_SIGN_IDENTITY": "Apple Development",
                    "ENABLE_HARDENED_RUNTIME": "NO",
                },
            ),
            _make_cfg(
                DEV_RELEASE,
                {
                    "APP_ENV": "dev",
                    "PRODUCT_BUNDLE_IDENTIFIER": "fm.voyager.Voyager.FilterSearchXPC.dev",
                    "XPC_MACH_SERVICE_NAME": "fm.voyager.Voyager.FilterSearchXPC.dev",
                    "CODE_SIGN_IDENTITY": "Apple Development",
                    "ENABLE_HARDENED_RUNTIME": "YES",
                },
            ),
            _make_cfg(
                PROD_DEBUG,
                {
                    "APP_ENV": "prod",
                    "PRODUCT_BUNDLE_IDENTIFIER": "fm.voyager.Voyager.FilterSearchXPC.proddebug",
                    "XPC_MACH_SERVICE_NAME": "fm.voyager.Voyager.FilterSearchXPC.proddebug",
                    "CODE_SIGN_IDENTITY": "Developer ID Application",
                    "ENABLE_HARDENED_RUNTIME": "YES",
                },
            ),
            _make_cfg(
                PROD_RELEASE,
                {
                    **PROD_RELEASE_SIZE_SETTINGS,
                    "APP_ENV": "prod",
                    "PRODUCT_BUNDLE_IDENTIFIER": "fm.voyager.Voyager.FilterSearchXPC",
                    "XPC_MACH_SERVICE_NAME": "fm.voyager.Voyager.FilterSearchXPC",
                    "CODE_SIGN_IDENTITY": "Developer ID Application",
                    "ENABLE_HARDENED_RUNTIME": "YES",
                },
            ),
        ]
        x_ids = [c.get_id() for c in x_cfgs]

        v_cl = _make_cl(v_ids, v_names, cl_id="v-cl")
        h_cl = _make_cl(h_ids, v_names, cl_id="h-cl")
        t_cl = _make_cl(t_ids, [DEV_DEBUG], default_name=DEV_DEBUG, cl_id="t-cl")
        x_cl = _make_cl(x_ids, v_names, cl_id="x-cl")

        all_configs = v_cfgs + h_cfgs + t_cfgs + x_cfgs
        all_cls = [v_cl, h_cl, t_cl, x_cl]
        all_targets = [
            _make_target("Voyager", "v-cl"),
            _make_target("VoyagerHelper", "h-cl"),
            _make_target("VoyagerTests", "t-cl"),
            _make_target("VoyagerUITests", "t-cl"),
            _make_target("VoyagerHelperTests", "t-cl"),
            _make_target("FilterSearchXPC", "x-cl"),
        ]

        with mock.patch("scripts.validate_build_matrix._load_pbxproj") as mock_load:
            mock_proj = mock.MagicMock()
            mock_proj.objects.get_objects_in_section.side_effect = lambda section: {
                "XCBuildConfiguration": all_configs,
                "XCConfigurationList": all_cls,
                "PBXNativeTarget": all_targets,
                "PBXProject": [_make_project("v-cl")],
            }.get(section, [])
            mock_load.return_value = mock_proj
            validate_voyager_pbxproj(Path("dummy.pbxproj"), errors)
            self.assertEqual(errors, [])

    def test_missing_config_reported(self) -> None:
        _reset_cfg_counter()
        errors: list[str] = []
        # All 4 configs exist in the project but target's config list
        # only references 3 of them (missing PROD_RELEASE)
        p_cfg = _make_cfg(PROD_RELEASE)
        cfgs = [
            _make_cfg(DEV_DEBUG),
            _make_cfg(DEV_RELEASE),
            _make_cfg(PROD_DEBUG),
            p_cfg,
        ]
        all_ids = [c.get_id() for c in cfgs]
        # Project config list has all 4
        proj_cl = _make_cl(
            all_ids, [DEV_DEBUG, DEV_RELEASE, PROD_DEBUG, PROD_RELEASE], cl_id="proj-cl"
        )
        # Target config list only has 3 (missing PROD_RELEASE)
        target_ids = [cfgs[0].get_id(), cfgs[1].get_id(), cfgs[2].get_id()]
        target_cl = _make_cl(
            target_ids, [DEV_DEBUG, DEV_RELEASE, PROD_DEBUG], cl_id="target-cl"
        )

        with mock.patch("scripts.validate_build_matrix._load_pbxproj") as mock_load:
            mock_proj = mock.MagicMock()
            mock_proj.objects.get_objects_in_section.side_effect = lambda section: {
                "XCBuildConfiguration": cfgs,
                "XCConfigurationList": [proj_cl, target_cl],
                "PBXNativeTarget": [_make_target("Voyager", "target-cl")],
                "PBXProject": [_make_project("proj-cl")],
            }.get(section, [])
            mock_load.return_value = mock_proj
            validate_voyager_pbxproj(Path("dummy.pbxproj"), errors)
            self.assertGreater(len(errors), 0)


class CheckHostProjectTests(unittest.TestCase):
    """Tests for check_host_project."""

    def test_reports_error_on_legacy_configs(self) -> None:
        _reset_cfg_counter()
        errors: list[str] = []
        with mock.patch("scripts.validate_build_matrix._load_pbxproj") as mock_load:
            mock_proj = mock.MagicMock()
            mock_proj.objects.get_objects_in_section.side_effect = lambda section: {
                "XCBuildConfiguration": [
                    _make_cfg("Debug"),
                    _make_cfg("Release"),
                ],
                "XCConfigurationList": [],
                "PBXNativeTarget": [],
            }.get(section, [])
            mock_load.return_value = mock_proj
            check_host_project(Path("dummy.pbxproj"), "OnboardingHost", errors)
            self.assertGreater(len(errors), 0)
            self.assertTrue(
                any("legacy" in e.lower() or "missing" in e.lower() for e in errors),
                f"Expected legacy/missing error, got: {errors}",
            )


class CheckSchemeFilesTests(unittest.TestCase):
    """Tests for check_scheme_files."""

    def test_reports_error_when_directory_missing(self) -> None:
        errors: list[str] = []
        check_scheme_files(Path("/nonexistent/directory"), errors)
        self.assertGreater(len(errors), 0)
        self.assertIn("missing", errors[0].lower())

    def test_reports_error_on_legacy_schemes(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            schemes_dir = Path(temp)
            scheme_file = schemes_dir / "Voyager-Dev.xcscheme"
            scheme_file.write_text(
                '<?xml version="1.0" encoding="UTF-8"?>\n'
                '<Scheme version="1.7">\n'
                '  <TestAction buildConfiguration="Debug">\n'
                "  </TestAction>\n"
                '  <LaunchAction buildConfiguration="Debug">\n'
                "  </LaunchAction>\n"
                '  <ArchiveAction buildConfiguration="Release">\n'
                "  </ArchiveAction>\n"
                "</Scheme>\n"
            )
            errors: list[str] = []
            check_scheme_files(schemes_dir, errors)
            self.assertGreater(len(errors), 0)
            self.assertTrue(
                any("Debug" in e or "Release" in e for e in errors),
                f"Expected Debug/Release errors, got: {errors}",
            )

    def test_valid_voy580_schemes_pass(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            schemes_dir = Path(temp)
            scheme_file = schemes_dir / "Voyager-Dev.xcscheme"
            scheme_file.write_text(
                '<?xml version="1.0" encoding="UTF-8"?>\n'
                '<Scheme version="1.7">\n'
                f'  <TestAction buildConfiguration="{DEV_DEBUG}">\n'
                "  </TestAction>\n"
                f'  <LaunchAction buildConfiguration="{DEV_DEBUG}">\n'
                "  </LaunchAction>\n"
                f'  <ArchiveAction buildConfiguration="{DEV_RELEASE}">\n'
                "  </ArchiveAction>\n"
                "</Scheme>\n"
            )
            errors: list[str] = []
            check_scheme_files(schemes_dir, errors)
            self.assertEqual(errors, [])

    def test_invalid_config_reported(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            schemes_dir = Path(temp)
            # First scheme with valid VOY-580 configs
            scheme_file = schemes_dir / "Voyager-Dev.xcscheme"
            scheme_file.write_text(
                '<?xml version="1.0" encoding="UTF-8"?>\n'
                '<Scheme version="1.7">\n'
                f'  <TestAction buildConfiguration="{DEV_DEBUG}">\n'
                "  </TestAction>\n"
                f'  <LaunchAction buildConfiguration="{DEV_DEBUG}">\n'
                "  </LaunchAction>\n"
                f'  <ArchiveAction buildConfiguration="{DEV_RELEASE}">\n'
                "  </ArchiveAction>\n"
                "</Scheme>\n"
            )
            # Second scheme with invalid config
            scheme_file2 = schemes_dir / "Voyager-Prod.xcscheme"
            scheme_file2.write_text(
                '<?xml version="1.0" encoding="UTF-8"?>\n'
                '<Scheme version="1.7">\n'
                f'  <TestAction buildConfiguration="{PROD_DEBUG}">\n'
                "  </TestAction>\n"
                '  <LaunchAction buildConfiguration="InvalidConfig">\n'
                "  </LaunchAction>\n"
                "</Scheme>\n"
            )
            errors: list[str] = []
            check_scheme_files(schemes_dir, errors)
            self.assertGreater(len(errors), 0)


class CheckCiReferencesTests(unittest.TestCase):
    """Tests for check_ci_references."""

    def test_reports_error_when_files_missing(self) -> None:
        with (
            mock.patch(
                "scripts.validate_build_matrix.CI_SCRIPT",
                Path("/nonexistent/script.sh"),
            ),
            mock.patch(
                "scripts.validate_build_matrix.CI_WORKFLOW",
                Path("/nonexistent/workflow.yml"),
            ),
        ):
            errors: list[str] = []
            check_ci_references(errors)
            self.assertGreater(len(errors), 0)

    def test_reports_wrong_config_in_shell_script(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            script_path = Path(temp) / "release-macos-prod.sh"
            workflow_path = Path(temp) / "release-macos-prod.yml"
            script_path.write_text('CONFIGURATION="${CONFIGURATION:-Release}"\n')
            workflow_path.write_text("on: push\n")
            with (
                mock.patch("scripts.validate_build_matrix.CI_SCRIPT", script_path),
                mock.patch(
                    "scripts.validate_build_matrix.CI_WORKFLOW",
                    workflow_path,
                ),
            ):
                errors: list[str] = []
                check_ci_references(errors)
                self.assertGreater(len(errors), 0)

    def test_passes_with_correct_config(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            script_path = Path(temp) / "release-macos-prod.sh"
            workflow_path = Path(temp) / "release-macos-prod.yml"
            script_path.write_text(
                f'CONFIGURATION="${{CONFIGURATION:-{PROD_RELEASE}}}"\n'
            )
            workflow_path.write_text("on: push\n")
            with (
                mock.patch("scripts.validate_build_matrix.CI_SCRIPT", script_path),
                mock.patch(
                    "scripts.validate_build_matrix.CI_WORKFLOW",
                    workflow_path,
                ),
            ):
                errors: list[str] = []
                check_ci_references(errors)
                self.assertEqual(errors, [])


class MainFunctionTests(unittest.TestCase):
    """Tests for main()."""

    def test_passes_on_current_repo_state(self) -> None:
        exit_code = main()
        self.assertEqual(exit_code, 0)

    def test_invalid_settings_reported(self) -> None:
        _reset_cfg_counter()
        cfgs = [
            _make_cfg(DEV_DEBUG, {"APP_ENV": "wrong_value"}),
            _make_cfg(DEV_RELEASE, {"APP_ENV": "dev"}),
            _make_cfg(PROD_DEBUG, {"APP_ENV": "prod"}),
            _make_cfg(PROD_RELEASE, {"APP_ENV": "prod"}),
        ]
        ids = [c.get_id() for c in cfgs]
        names = [DEV_DEBUG, DEV_RELEASE, PROD_DEBUG, PROD_RELEASE]
        cl = _make_cl(ids, names, cl_id="mock-cl")

        with mock.patch("scripts.validate_build_matrix._load_pbxproj") as mock_load:
            mock_proj = mock.MagicMock()
            mock_proj.objects.get_objects_in_section.side_effect = lambda section: {
                "XCBuildConfiguration": cfgs,
                "XCConfigurationList": [cl],
                "PBXNativeTarget": [_make_target("Voyager", "mock-cl")],
                "PBXProject": [_make_project("mock-cl")],
            }.get(section, [])
            mock_load.return_value = mock_proj
            exit_code = main()
            self.assertNotEqual(exit_code, 0)


# ── Env key parity, duplicate, launch-surface, deprecated, and allowed-control tests ──

TRACKED_KEY_A = "PUBLIC_APP_NAME"
TRACKED_KEY_B = "PUBLIC_GATEWAY_URL"
DEPRECATED_KEY = "VOYAGER_ONBOARDING_MOCK_BETA"


class ParseEnvKeysTests(unittest.TestCase):
    """Tests for _parse_env_keys."""

    def test_parses_simple_keys(self) -> None:
        from scripts.validate_build_matrix import _parse_env_keys

        with tempfile.NamedTemporaryFile(mode="w", suffix=".env", delete=False) as f:
            f.write("KEY_A=value1\nKEY_B=value2\n")
            path = f.name
        try:
            keys = _parse_env_keys(Path(path))
            self.assertEqual(keys, ["KEY_A", "KEY_B"])
        finally:
            Path(path).unlink()

    def test_ignores_comments_and_blanks(self) -> None:
        from scripts.validate_build_matrix import _parse_env_keys

        with tempfile.NamedTemporaryFile(mode="w", suffix=".env", delete=False) as f:
            f.write("# comment\n\nKEY_A=value1\n  \n# another\nKEY_B=value2\n")
            path = f.name
        try:
            keys = _parse_env_keys(Path(path))
            self.assertEqual(keys, ["KEY_A", "KEY_B"])
        finally:
            Path(path).unlink()

    def test_rejects_duplicate_keys(self) -> None:
        from scripts.validate_build_matrix import _parse_env_keys

        with tempfile.NamedTemporaryFile(mode="w", suffix=".env", delete=False) as f:
            f.write("KEY_A=value1\nKEY_A=value2\n")
            path = f.name
        try:
            with self.assertRaises(ValueError):
                _parse_env_keys(Path(path))
        finally:
            Path(path).unlink()

    def test_handles_empty_file(self) -> None:
        from scripts.validate_build_matrix import _parse_env_keys

        with tempfile.NamedTemporaryFile(mode="w", suffix=".env", delete=False) as f:
            f.write("# only comments\n\n")
            path = f.name
        try:
            keys = _parse_env_keys(Path(path))
            self.assertEqual(keys, [])
        finally:
            Path(path).unlink()


class CheckEnvKeyParityTests(unittest.TestCase):
    """Tests for check_env_key_parity."""

    def test_passes_when_keys_equal(self) -> None:
        from scripts.validate_build_matrix import check_env_key_parity

        errors: list[str] = []
        check_env_key_parity(errors)
        self.assertEqual(errors, [])

    def test_fails_when_key_missing_from_example(self) -> None:
        from scripts.validate_build_matrix import check_env_key_parity

        with (
            mock.patch("scripts.validate_build_matrix.ENV_EXAMPLE_PATH") as mock_ex,
            mock.patch("scripts.validate_build_matrix.ENV_PROD_PATH") as mock_pr,
        ):
            mock_ex.read_text.return_value = "KEY_A=val1\n"
            mock_pr.read_text.return_value = "KEY_A=val1\nKEY_B=val2\n"
            errors: list[str] = []
            check_env_key_parity(errors)
            self.assertGreater(len(errors), 0)
            self.assertIn("KEY_B", errors[0])


class CheckExpectedTrackedEnvKeysTests(unittest.TestCase):
    def test_fails_when_matching_templates_add_an_unapproved_key(self) -> None:
        from scripts.validate_build_matrix import (
            EXPECTED_TRACKED_ENV_KEYS,
            check_expected_tracked_env_keys,
        )

        with tempfile.TemporaryDirectory() as temp:
            env_path = Path(temp) / ".env.example"
            env_path.write_text(
                "".join(f"{key}=value\n" for key in sorted(EXPECTED_TRACKED_ENV_KEYS))
                + "UNAPPROVED_SECRET_KEY=value\n"
            )
            errors: list[str] = []
            check_expected_tracked_env_keys(errors, paths=[env_path])
            self.assertEqual(len(errors), 1)
            self.assertIn("UNAPPROVED_SECRET_KEY", errors[0])

    def test_passes_for_exact_contract(self) -> None:
        from scripts.validate_build_matrix import (
            EXPECTED_TRACKED_ENV_KEYS,
            check_expected_tracked_env_keys,
        )

        with tempfile.TemporaryDirectory() as temp:
            env_path = Path(temp) / ".env.example"
            env_path.write_text(
                "".join(f"{key}=value\n" for key in sorted(EXPECTED_TRACKED_ENV_KEYS))
            )
            errors: list[str] = []
            check_expected_tracked_env_keys(errors, paths=[env_path])
            self.assertEqual(errors, [])

    def test_reports_missing_env_file(self) -> None:
        from scripts.validate_build_matrix import check_expected_tracked_env_keys

        with tempfile.TemporaryDirectory() as temp:
            missing_path = Path(temp) / ".env.prod"
            errors: list[str] = []
            check_expected_tracked_env_keys(errors, paths=[missing_path])
            self.assertEqual(len(errors), 1)
            self.assertIn("missing", errors[0])

    def test_fails_when_key_missing_from_prod(self) -> None:
        from scripts.validate_build_matrix import check_env_key_parity

        with (
            mock.patch("scripts.validate_build_matrix.ENV_EXAMPLE_PATH") as mock_ex,
            mock.patch("scripts.validate_build_matrix.ENV_PROD_PATH") as mock_pr,
        ):
            mock_ex.read_text.return_value = "KEY_A=val1\nKEY_B=val2\n"
            mock_pr.read_text.return_value = "KEY_A=val1\n"
            errors: list[str] = []
            check_env_key_parity(errors)
            self.assertGreater(len(errors), 0)
            self.assertIn("KEY_B", errors[0])


class CheckNoDuplicateEnvKeysTests(unittest.TestCase):
    """Tests for check_no_duplicate_env_keys."""

    def test_passes_without_duplicates(self) -> None:
        from scripts.validate_build_matrix import check_no_duplicate_env_keys

        errors: list[str] = []
        check_no_duplicate_env_keys(errors)
        self.assertEqual(errors, [])

    def test_fails_on_duplicate_in_example(self) -> None:
        from scripts.validate_build_matrix import check_no_duplicate_env_keys

        with mock.patch("scripts.validate_build_matrix.ENV_EXAMPLE_PATH") as mock_ex:
            mock_ex.read_text.return_value = "KEY_A=val1\nKEY_A=val2\n"
            errors: list[str] = []
            check_no_duplicate_env_keys(errors)
            self.assertGreater(len(errors), 0)
            self.assertIn("Duplicate key", errors[0])
            self.assertIn("KEY_A", errors[0])

    def test_fails_on_duplicate_in_prod(self) -> None:
        from scripts.validate_build_matrix import check_no_duplicate_env_keys

        with mock.patch("scripts.validate_build_matrix.ENV_PROD_PATH") as mock_pr:
            mock_pr.read_text.return_value = "KEY_B=val1\nKEY_B=val2\n"
            errors: list[str] = []
            check_no_duplicate_env_keys(errors)
            self.assertGreater(len(errors), 0)
            self.assertIn("Duplicate key", errors[0])
            self.assertIn("KEY_B", errors[0])


class CheckNoTrackedKeysInXcschemesTests(unittest.TestCase):
    """Tests for check_no_tracked_keys_in_xcschemes."""

    def test_passes_with_no_tracked_keys(self) -> None:
        from scripts.validate_build_matrix import check_no_tracked_keys_in_xcschemes

        tracked = {TRACKED_KEY_A, TRACKED_KEY_B}
        with tempfile.TemporaryDirectory() as temp:
            sd = Path(temp)
            (sd / "Voyager-Dev.xcscheme").write_text(
                '<?xml version="1.0" encoding="UTF-8"?>\n<Scheme version="1.7">\n'
                '  <LaunchAction buildConfiguration="Dev-Debug">\n'
                "    <EnvironmentVariables>\n"
                '      <EnvironmentVariable key="VOYAGER_PROJECT_ROOT" value="x" isEnabled="YES"/>\n'
                "    </EnvironmentVariables>\n"
                "  </LaunchAction>\n"
                "</Scheme>\n"
            )
            errors: list[str] = []
            check_no_tracked_keys_in_xcschemes(tracked, errors, scheme_dirs=[sd])
            self.assertEqual(errors, [])

    def test_fails_on_tracked_key_in_scheme(self) -> None:
        from scripts.validate_build_matrix import check_no_tracked_keys_in_xcschemes

        tracked = {TRACKED_KEY_A, TRACKED_KEY_B}
        with tempfile.TemporaryDirectory() as temp:
            sd = Path(temp)
            (sd / "Bad.xcscheme").write_text(
                '<?xml version="1.0" encoding="UTF-8"?>\n<Scheme version="1.7">\n'
                '  <LaunchAction buildConfiguration="Dev-Debug">\n'
                "    <EnvironmentVariables>\n"
                '      <EnvironmentVariable key="PUBLIC_APP_NAME" value="Voyager" isEnabled="YES"/>\n'
                "    </EnvironmentVariables>\n"
                "  </LaunchAction>\n"
                "</Scheme>\n"
            )
            errors: list[str] = []
            check_no_tracked_keys_in_xcschemes(tracked, errors, scheme_dirs=[sd])
            self.assertGreater(len(errors), 0)
            self.assertIn(TRACKED_KEY_A, errors[0])

    def test_allows_untracked_launch_control(self) -> None:
        from scripts.validate_build_matrix import check_no_tracked_keys_in_xcschemes

        with tempfile.TemporaryDirectory() as temp:
            schemes_dir = Path(temp)
            (schemes_dir / "Bad.xcscheme").write_text(
                "<Scheme><LaunchAction><EnvironmentVariables>"
                '<EnvironmentVariable key="ARBITRARY_PROCESS_OVERRIDE" value="1" isEnabled="YES"/>'
                "</EnvironmentVariables></LaunchAction></Scheme>"
            )
            errors: list[str] = []
            check_no_tracked_keys_in_xcschemes(set(), errors, scheme_dirs=[schemes_dir])
            self.assertEqual(errors, [])


class CheckNoTrackedKeysInVscodeTests(unittest.TestCase):
    """Tests for check_no_tracked_keys_in_vscode."""

    def test_passes_with_allowed_controls_only(self) -> None:
        from scripts.validate_build_matrix import check_no_tracked_keys_in_vscode

        tracked = {TRACKED_KEY_A, TRACKED_KEY_B}
        with tempfile.NamedTemporaryFile(mode="w", suffix=".json", delete=False) as f:
            f.write(
                '{"version": "2.0.0", "tasks": ['
                '{"label": "test", "launchEnv": {"VOYAGER_PROJECT_ROOT": "${workspaceFolder}"}}'
                "]}"
            )
            path = f.name
        try:
            errors: list[str] = []
            check_no_tracked_keys_in_vscode(tracked, errors, path_override=Path(path))
            self.assertEqual(errors, [])
        finally:
            Path(path).unlink()

    def test_allows_untracked_launch_control(self) -> None:
        from scripts.validate_build_matrix import check_no_tracked_keys_in_vscode

        with tempfile.NamedTemporaryFile(mode="w", suffix=".json", delete=False) as f:
            f.write(
                '{"tasks": [{"label": "test", "launchEnv": '
                '{"ARBITRARY_PROCESS_OVERRIDE": "1"}}]}'
            )
            path = Path(f.name)
        try:
            errors: list[str] = []
            check_no_tracked_keys_in_vscode(set(), errors, path_override=path)
            self.assertEqual(errors, [])
        finally:
            path.unlink()

    def test_allows_untracked_options_environment(self) -> None:
        from scripts.validate_build_matrix import check_no_tracked_keys_in_vscode

        with tempfile.NamedTemporaryFile(mode="w", suffix=".json", delete=False) as f:
            f.write(
                '{"tasks": [{"label": "test", "options": {"env": '
                '{"ARBITRARY_PROCESS_OVERRIDE": "1"}}}]}'
            )
            path = Path(f.name)
        try:
            errors: list[str] = []
            check_no_tracked_keys_in_vscode(set(), errors, path_override=path)
            self.assertEqual(errors, [])
        finally:
            path.unlink()

    def test_fails_on_tracked_key_in_launch_env(self) -> None:
        from scripts.validate_build_matrix import check_no_tracked_keys_in_vscode

        tracked = {TRACKED_KEY_A, TRACKED_KEY_B}
        with tempfile.NamedTemporaryFile(mode="w", suffix=".json", delete=False) as f:
            f.write(
                '{"version": "2.0.0", "tasks": ['
                '{"label": "test", "launchEnv": {"PUBLIC_APP_NAME": "Voyager"}}'
                "]}"
            )
            path = f.name
        try:
            errors: list[str] = []
            check_no_tracked_keys_in_vscode(tracked, errors, path_override=Path(path))
            self.assertGreater(len(errors), 0)
            self.assertIn(TRACKED_KEY_A, errors[0])
        finally:
            Path(path).unlink()


class CheckNoTrackedKeysInZedTests(unittest.TestCase):
    """Tests for check_no_tracked_keys_in_zed."""

    def test_passes_with_allowed_controls_only(self) -> None:
        from scripts.validate_build_matrix import check_no_tracked_keys_in_zed

        tracked = {TRACKED_KEY_A, TRACKED_KEY_B}
        tasks = [
            {
                "label": "test",
                "command": "./script.sh",
                "args": [
                    "--env",
                    "VOYAGER_PROJECT_ROOT=$ZED_WORKTREE_ROOT",
                ],
            }
        ]
        with tempfile.NamedTemporaryFile(mode="w", suffix=".json", delete=False) as f:
            f.write(str(tasks).replace("'", '"'))
            path = f.name
        try:
            errors: list[str] = []
            check_no_tracked_keys_in_zed(tracked, errors, path_override=Path(path))
            self.assertEqual(errors, [])
        finally:
            Path(path).unlink()

    def test_allows_untracked_launch_control(self) -> None:
        from scripts.validate_build_matrix import check_no_tracked_keys_in_zed

        tasks = [{"label": "test", "args": ["--env", "ARBITRARY_PROCESS_OVERRIDE=1"]}]
        with tempfile.NamedTemporaryFile(mode="w", suffix=".json", delete=False) as f:
            f.write(str(tasks).replace("'", '"'))
            path = Path(f.name)
        try:
            errors: list[str] = []
            check_no_tracked_keys_in_zed(set(), errors, path_override=path)
            self.assertEqual(errors, [])
        finally:
            path.unlink()

    def test_allows_untracked_environment_dictionary(self) -> None:
        from scripts.validate_build_matrix import check_no_tracked_keys_in_zed

        tasks = [{"label": "test", "env": {"ARBITRARY_PROCESS_OVERRIDE": "1"}}]
        with tempfile.NamedTemporaryFile(mode="w", suffix=".json", delete=False) as f:
            f.write(str(tasks).replace("'", '"'))
            path = Path(f.name)
        try:
            errors: list[str] = []
            check_no_tracked_keys_in_zed(set(), errors, path_override=path)
            self.assertEqual(errors, [])
        finally:
            path.unlink()

    def test_fails_on_tracked_key_in_zed_env(self) -> None:
        from scripts.validate_build_matrix import check_no_tracked_keys_in_zed

        tracked = {TRACKED_KEY_A, TRACKED_KEY_B}
        tasks = [
            {
                "label": "test",
                "command": "./script.sh",
                "args": [
                    "--env",
                    "PUBLIC_GATEWAY_URL=https://example.com",
                ],
            }
        ]
        with tempfile.NamedTemporaryFile(mode="w", suffix=".json", delete=False) as f:
            f.write(str(tasks).replace("'", '"'))
            path = f.name
        try:
            errors: list[str] = []
            check_no_tracked_keys_in_zed(tracked, errors, path_override=Path(path))
            self.assertGreater(len(errors), 0)
            self.assertIn(TRACKED_KEY_B, errors[0])
        finally:
            Path(path).unlink()


class CheckNoDeprecatedKeysTests(unittest.TestCase):
    """Tests for check_no_deprecated_keys."""

    def test_passes_when_deprecated_absent(self) -> None:
        from scripts.validate_build_matrix import (
            check_no_deprecated_keys,
            DEPRECATED_KEYS,
        )

        with (
            mock.patch(
                "scripts.validate_build_matrix.VSCodeTasksPath",
                Path("/nonexistent/vscode.json"),
            ),
            mock.patch(
                "scripts.validate_build_matrix.ZedTasksPath",
                Path("/nonexistent/zed.json"),
            ),
        ):
            errors: list[str] = []
            check_no_deprecated_keys(errors)
            self.assertEqual(errors, [])

    def test_fails_when_deprecated_in_scheme(self) -> None:
        from scripts.validate_build_matrix import check_no_deprecated_keys

        with tempfile.TemporaryDirectory() as temp:
            sd = Path(temp)
            (sd / "Bad.xcscheme").write_text(
                '<?xml version="1.0" encoding="UTF-8"?>\n<Scheme version="1.7">\n'
                '  <LaunchAction buildConfiguration="Dev-Debug">\n'
                "    <EnvironmentVariables>\n"
                '      <EnvironmentVariable key="VOYAGER_ONBOARDING_MOCK_BETA" value="1" isEnabled="YES"/>\n'
                "    </EnvironmentVariables>\n"
                "  </LaunchAction>\n"
                "</Scheme>\n"
            )
            errors: list[str] = []
            check_no_deprecated_keys(errors, scheme_dirs=[sd])
            self.assertGreater(len(errors), 0)
            self.assertIn(DEPRECATED_KEY, errors[0])

    def test_fails_when_deprecated_in_vscode_options_environment(self) -> None:
        from scripts.validate_build_matrix import check_no_deprecated_keys

        with tempfile.NamedTemporaryFile(mode="w", suffix=".json", delete=False) as f:
            f.write(
                '{"tasks": [{"label": "test", "options": {"env": '
                '{"VOYAGER_ONBOARDING_MOCK_BETA": "1"}}}]}'
            )
            path = Path(f.name)
        try:
            with (
                mock.patch("scripts.validate_build_matrix.VSCodeTasksPath", path),
                mock.patch(
                    "scripts.validate_build_matrix.ZedTasksPath",
                    Path("/nonexistent/zed.json"),
                ),
            ):
                errors: list[str] = []
                check_no_deprecated_keys(errors, scheme_dirs=[])
            self.assertEqual(len(errors), 1)
            self.assertIn(DEPRECATED_KEY, errors[0])
        finally:
            path.unlink()

    def test_fails_when_deprecated_in_zed_environment_dictionary(self) -> None:
        from scripts.validate_build_matrix import check_no_deprecated_keys

        tasks = [{"label": "test", "env": {"VOYAGER_ONBOARDING_MOCK_BETA": "1"}}]
        with tempfile.NamedTemporaryFile(mode="w", suffix=".json", delete=False) as f:
            f.write(str(tasks).replace("'", '"'))
            path = Path(f.name)
        try:
            with (
                mock.patch(
                    "scripts.validate_build_matrix.VSCodeTasksPath",
                    Path("/nonexistent/vscode.json"),
                ),
                mock.patch("scripts.validate_build_matrix.ZedTasksPath", path),
            ):
                errors: list[str] = []
                check_no_deprecated_keys(errors, scheme_dirs=[])
            self.assertEqual(len(errors), 1)
            self.assertIn(DEPRECATED_KEY, errors[0])
        finally:
            path.unlink()

    def test_fails_when_removed_codex_key_is_in_env_template(self) -> None:
        from scripts.validate_build_matrix import check_no_deprecated_keys

        with tempfile.TemporaryDirectory() as temp:
            env_path = Path(temp) / ".env.example"
            env_path.write_text("OPENAI_CODEX_OAUTH_CLIENT_ID=value\n")
            errors: list[str] = []
            check_no_deprecated_keys(
                errors,
                scheme_dirs=[],
                env_paths=[env_path],
                source_roots=[],
            )
            self.assertEqual(len(errors), 1)
            self.assertIn("OPENAI_CODEX_OAUTH_CLIENT_ID", errors[0])

    def test_fails_when_removed_codex_key_is_in_swift_source(self) -> None:
        from scripts.validate_build_matrix import check_no_deprecated_keys

        with tempfile.TemporaryDirectory() as temp:
            source_root = Path(temp)
            (source_root / "Config.swift").write_text(
                'let key = "VOYAGER_CODEX_WORKING_DIRECTORY"\n'
            )
            errors: list[str] = []
            check_no_deprecated_keys(
                errors,
                scheme_dirs=[],
                env_paths=[],
                source_roots=[source_root],
            )
            self.assertEqual(len(errors), 1)
            self.assertIn("VOYAGER_CODEX_WORKING_DIRECTORY", errors[0])


class CheckProcessInfoEnvironmentOwnershipTests(unittest.TestCase):
    def test_fails_on_unapproved_literal_key(self) -> None:
        from scripts.validate_build_matrix import (
            check_process_info_environment_ownership,
        )

        with tempfile.TemporaryDirectory() as temp:
            source_root = Path(temp)
            source_path = source_root / "Config.swift"
            source_path.write_text(
                'let value = ProcessInfo.processInfo.environment["NEW_PROCESS_CONTROL"]\n'
            )
            with mock.patch(
                "scripts.validate_build_matrix.ALLOWED_PROCESS_INFO_LITERAL_KEYS",
                {},
            ):
                errors: list[str] = []
                check_process_info_environment_ownership(errors, [source_root])
            self.assertEqual(len(errors), 1)
            self.assertIn("NEW_PROCESS_CONTROL", errors[0])

    def test_fails_on_dynamic_key_access(self) -> None:
        from scripts.validate_build_matrix import (
            check_process_info_environment_ownership,
        )

        with tempfile.TemporaryDirectory() as temp:
            source_root = Path(temp)
            (source_root / "Config.swift").write_text(
                "let value = ProcessInfo.processInfo.environment[key]\n"
            )
            errors: list[str] = []
            check_process_info_environment_ownership(errors, [source_root])
            self.assertEqual(len(errors), 1)
            self.assertIn("dynamic", errors[0])

    def test_fails_on_unapproved_full_snapshot(self) -> None:
        from scripts.validate_build_matrix import (
            check_process_info_environment_ownership,
        )

        with tempfile.TemporaryDirectory() as temp:
            source_root = Path(temp)
            (source_root / "Config.swift").write_text(
                "let environment = ProcessInfo.processInfo.environment\n"
            )
            with mock.patch(
                "scripts.validate_build_matrix.ALLOWED_PROCESS_INFO_SNAPSHOT_FILES",
                set(),
            ):
                errors: list[str] = []
                check_process_info_environment_ownership(errors, [source_root])
            self.assertEqual(len(errors), 1)
            self.assertIn("snapshot", errors[0])

    def test_passes_for_manifested_literal_and_snapshot_access(self) -> None:
        from scripts.validate_build_matrix import (
            check_process_info_environment_ownership,
        )

        with tempfile.TemporaryDirectory() as temp:
            source_root = Path(temp)
            literal_path = source_root / "Literal.swift"
            snapshot_path = source_root / "Snapshot.swift"
            literal_path.write_text(
                'let value = ProcessInfo.processInfo.environment["HOST_SMOKE"]\n'
            )
            snapshot_path.write_text(
                "let environment = ProcessInfo.processInfo.environment\n"
            )
            with (
                mock.patch(
                    "scripts.validate_build_matrix.ALLOWED_PROCESS_INFO_LITERAL_KEYS",
                    {literal_path.as_posix(): {"HOST_SMOKE"}},
                ),
                mock.patch(
                    "scripts.validate_build_matrix.ALLOWED_PROCESS_INFO_SNAPSHOT_FILES",
                    {snapshot_path.as_posix()},
                ),
            ):
                errors: list[str] = []
                check_process_info_environment_ownership(errors, [source_root])
            self.assertEqual(errors, [])


class AllowedControlsNotFlaggedTests(unittest.TestCase):
    """Test that allowed controls in launch surfaces are not flagged."""

    def test_allowed_control_in_scheme_not_flagged(self) -> None:
        from scripts.validate_build_matrix import check_no_tracked_keys_in_xcschemes

        tracked = {TRACKED_KEY_A, TRACKED_KEY_B}
        with tempfile.TemporaryDirectory() as temp:
            sd = Path(temp)
            (sd / "Ok.xcscheme").write_text(
                '<?xml version="1.0" encoding="UTF-8"?>\n<Scheme version="1.7">\n'
                '  <LaunchAction buildConfiguration="Dev-Debug">\n'
                "    <EnvironmentVariables>\n"
                '      <EnvironmentVariable key="VOYAGER_PROJECT_ROOT" value="x" isEnabled="YES"/>\n'
                '      <EnvironmentVariable key="ONBOARDING_HOST_SMOKE" value="1" isEnabled="YES"/>\n'
                "    </EnvironmentVariables>\n"
                "  </LaunchAction>\n"
                "</Scheme>\n"
            )
            errors: list[str] = []
            check_no_tracked_keys_in_xcschemes(tracked, errors, scheme_dirs=[sd])
            self.assertEqual(errors, [])

    def test_allowed_control_in_vscode_not_flagged(self) -> None:
        from scripts.validate_build_matrix import check_no_tracked_keys_in_vscode

        tracked = {TRACKED_KEY_A, TRACKED_KEY_B}
        with tempfile.NamedTemporaryFile(mode="w", suffix=".json", delete=False) as f:
            f.write(
                '{"version": "2.0.0", "tasks": ['
                '{"label": "t", "launchEnv": {"ONBOARDING_HOST_RESET_PROGRESS": "1"}}'
                "]}"
            )
            path = f.name
        try:
            errors: list[str] = []
            check_no_tracked_keys_in_vscode(tracked, errors, path_override=Path(path))
            self.assertEqual(errors, [])
        finally:
            Path(path).unlink()

    def test_allowed_control_in_zed_not_flagged(self) -> None:
        from scripts.validate_build_matrix import check_no_tracked_keys_in_zed

        tracked = {TRACKED_KEY_A, TRACKED_KEY_B}
        tasks = [
            {
                "label": "t",
                "command": "./script.sh",
                "args": ["--env", "SETTINGS_HOST_SMOKE=1"],
            }
        ]
        with tempfile.NamedTemporaryFile(mode="w", suffix=".json", delete=False) as f:
            f.write(str(tasks).replace("'", '"'))
            path = f.name
        try:
            errors: list[str] = []
            check_no_tracked_keys_in_zed(tracked, errors, path_override=Path(path))
            self.assertEqual(errors, [])
        finally:
            Path(path).unlink()


if __name__ == "__main__":
    unittest.main()
