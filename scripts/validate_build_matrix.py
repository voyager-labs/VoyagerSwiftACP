#!/usr/bin/env python3
"""Validate Xcode build configuration matrix invariants for VOY-580.

Checks that each target in Voyager.xcodeproj and the Host projects
has the correct set of build configurations with the expected build
settings for each config (APP_ENV, PRODUCT_BUNDLE_IDENTIFIER, etc.).

VOY-580 has landed. Legacy Debug/Release configs and references are
treated as errors, not gracefully skipped.
"""

from __future__ import annotations

import os
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path
from typing import Any

# Expected VOY-580 configuration names
DEV_DEBUG = "Dev-Debug"
DEV_RELEASE = "Dev-Release"
PROD_DEBUG = "Prod-Debug"
PROD_RELEASE = "Prod-Release"
ALL_VOYAGER_CONFIGS = {DEV_DEBUG, DEV_RELEASE, PROD_DEBUG, PROD_RELEASE}
HOST_CONFIGS = {DEV_DEBUG, DEV_RELEASE}

# Mapping from config name to expected APP_ENV value
APP_ENV_MAP = {
    DEV_DEBUG: "dev",
    DEV_RELEASE: "dev",
    PROD_DEBUG: "prod",
    PROD_RELEASE: "prod",
}

# CODE_SIGN_IDENTITY per config pattern
CODE_SIGN_MAP = {
    DEV_DEBUG: "Apple Development",
    DEV_RELEASE: "Apple Development",
    PROD_DEBUG: "Developer ID Application",
    PROD_RELEASE: "Developer ID Application",
}

# ENABLE_HARDENED_RUNTIME per config
HARDENED_RUNTIME_MAP = {
    DEV_DEBUG: "NO",
    DEV_RELEASE: "YES",
    PROD_DEBUG: "YES",
    PROD_RELEASE: "YES",
}

# VOYAGER_APP_SUFFIX per config
VOYAGER_APP_SUFFIX_MAP: dict[str, str | None] = {
    DEV_DEBUG: None,  # empty/branch-injected
    DEV_RELEASE: "-profile",
    PROD_DEBUG: "-proddebug",
    PROD_RELEASE: None,  # empty
}

# PRODUCT_BUNDLE_IDENTIFIER per target per config
BUNDLE_ID_MAP: dict[str, dict[str, str]] = {
    "Voyager": {
        DEV_DEBUG: "fm.voyager.Voyager.dev",
        DEV_RELEASE: "fm.voyager.Voyager.dev",
        PROD_DEBUG: "fm.voyager.Voyager-proddebug",
        PROD_RELEASE: "fm.voyager.Voyager",
    },
    "VoyagerHelper": {
        DEV_DEBUG: "fm.voyager.VoyagerHelper.dev",
        DEV_RELEASE: "fm.voyager.VoyagerHelper.dev",
        PROD_DEBUG: "fm.voyager.VoyagerHelper-proddebug",
        PROD_RELEASE: "fm.voyager.VoyagerHelper",
    },
    "FilterSearchXPC": {
        DEV_DEBUG: "fm.voyager.Voyager.FilterSearchXPC.dev",
        DEV_RELEASE: "fm.voyager.Voyager.FilterSearchXPC.dev",
        PROD_DEBUG: "fm.voyager.Voyager.FilterSearchXPC.proddebug",
        PROD_RELEASE: "fm.voyager.Voyager.FilterSearchXPC",
    },
}

# SUFeedURL per config
SUFEED_URL_MAP: dict[str, str | None] = {
    DEV_DEBUG: None,
    DEV_RELEASE: None,
    PROD_DEBUG: None,
    PROD_RELEASE: "https://downloads.voyager.fm/releases/appcast.xml",
}

# XPC_MACH_SERVICE_NAME per config
XPC_MACH_SERVICE_NAME_MAP: dict[str, str] = {
    DEV_DEBUG: "fm.voyager.Voyager.FilterSearchXPC.dev",
    DEV_RELEASE: "fm.voyager.Voyager.FilterSearchXPC.dev",
    PROD_DEBUG: "fm.voyager.Voyager.FilterSearchXPC.proddebug",
    PROD_RELEASE: "fm.voyager.Voyager.FilterSearchXPC",
}

# Test targets (non-Prod, Dev-Debug only)
TEST_TARGETS = {"VoyagerTests", "VoyagerUITests", "VoyagerHelperTests"}

# Host project names
HOST_PROJECTS = {"OnboardingHost", "SettingsHost", "FileManagerHost"}

# Host project test targets
HOST_TEST_TARGETS = {"SettingsHostTests"}

# Scheme files directory
SCHEMES_DIR = Path("apps/macos/Voyager/Voyager.xcodeproj/xcshareddata/xcschemes")
WORKSPACE_SCHEMES_DIR = Path(
    "apps/macos/Voyager/Voyager.xcworkspace/xcshareddata/xcschemes"
)

# CI files to check for Prod-Release references
CI_SCRIPT = Path("scripts/ci/release-macos-prod.sh")
CI_WORKFLOW = Path(".github/workflows/release-macos-prod.yml")

# Valid scheme buildConfiguration values
VALID_SCHEME_CONFIGS = {DEV_DEBUG, DEV_RELEASE, PROD_DEBUG, PROD_RELEASE}


class _PbxObjectWrapper:
    """Wrapper around a plutil-parsed pbxproj JSON object dict.

    Provides get() and get_id() matching the pbxproj library's API so that
    existing validation code works without modification.
    """

    __slots__ = ("_uuid", "_data")

    def __init__(self, uuid: str, data: dict[str, Any]) -> None:
        self._uuid = uuid
        self._data = data

    def get(self, key: str, default: Any = None) -> Any:
        return self._data.get(key, default)

    def get_id(self) -> str:
        return self._uuid


class _PbxProjectWrapper:
    """Wrapper around parsed pbxproj data, providing .objects API.

    Uses a pure-Python OpenStep plist parser (no external dependencies)
    that works on macOS, Linux, and CI runners alike.
    """

    __slots__ = ("_objects",)

    def __init__(self, data: dict[str, Any]) -> None:
        self._objects = data.get("objects", {})

    @property
    def objects(self) -> _PbxProjectWrapper:
        return self

    def get_objects_in_section(self, isa: str) -> list[_PbxObjectWrapper]:
        return [
            _PbxObjectWrapper(uuid, obj)
            for uuid, obj in self._objects.items()
            if isinstance(obj, dict) and obj.get("isa") == isa
        ]


class BuildMatrixError(Exception):
    """Raised when a build matrix invariant is violated."""

    def __init__(self, message: str) -> None:
        self.message = message
        super().__init__(message)


def _parse_openstep_plist(text: str) -> Any:
    """Parse an OpenStep-format plist string into Python objects.

    This is a minimal parser for the subset of OpenStep format used by
    Xcode .pbxproj files. No external dependencies required — works on
    any platform (macOS, Linux, CI).
    """
    # Strip // and /* */ comments
    # // comments are only at line-start (section markers, UTF8 magic header)
    text = re.sub(r"(?m)^\s*//.*", "", text)
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.DOTALL)
    text = text.strip()

    def _parse_dict(pos: int) -> tuple[dict[str, Any], int]:
        pos += 1  # skip {
        result: dict[str, Any] = {}
        while pos < len(text):
            while pos < len(text) and text[pos] in " \t\n\r":
                pos += 1
            if pos >= len(text) or text[pos] == "}":
                return result, pos + 1 if pos < len(text) else pos
            if text[pos] == ";":
                pos += 1
                continue
            key, pos = _parse_value(pos)
            while pos < len(text) and text[pos] in " \t\n\r":
                pos += 1
            if pos < len(text) and text[pos] == "=":
                pos += 1
            val, pos = _parse_value(pos)
            while pos < len(text) and text[pos] in " \t\n\r":
                pos += 1
            if pos < len(text) and text[pos] == ";":
                pos += 1
            if isinstance(key, str):
                result[key] = val
        return result, pos

    def _parse_array(pos: int) -> tuple[list[Any], int]:
        pos += 1  # skip (
        result: list[Any] = []
        while pos < len(text):
            while pos < len(text) and text[pos] in " \t\n\r":
                pos += 1
            if pos >= len(text) or text[pos] == ")":
                return result, pos + 1 if pos < len(text) else pos
            if text[pos] in ",;":
                pos += 1
                continue
            val, pos = _parse_value(pos)
            if val is not None:
                result.append(val)
        return result, pos

    def _parse_value(pos: int) -> tuple[Any, int]:
        while pos < len(text) and text[pos] in " \t\n\r":
            pos += 1
        if pos >= len(text):
            return None, pos
        c = text[pos]
        if c == "{":
            return _parse_dict(pos)
        elif c == "(":
            return _parse_array(pos)
        elif c == '"':
            pos += 1
            buf: list[str] = []
            while pos < len(text):
                if text[pos] == '"':
                    return "".join(buf), pos + 1
                if text[pos] == "\\" and pos + 1 < len(text):
                    pos += 1
                    buf.append(text[pos])
                else:
                    buf.append(text[pos])
                pos += 1
            return "".join(buf), pos
        else:
            buf: list[str] = []
            while pos < len(text) and text[pos] not in " \t\n\r;)}],":
                buf.append(text[pos])
                pos += 1
            val = "".join(buf)
            if val in ("nil", "null"):
                return None, pos
            return val, pos

    result, _ = _parse_value(0)
    return result if isinstance(result, dict) else {}


def _load_pbxproj(path: Path) -> _PbxProjectWrapper:
    """Load a pbxproj file using a portable pure-Python OpenStep parser."""
    return _PbxProjectWrapper(_parse_openstep_plist(path.read_text(encoding="utf-8")))


def _get_config_by_name(configs: list[Any], name: str) -> Any | None:
    """Find a build configuration by name."""
    for cfg in configs:
        if cfg.get("name", "") == name:
            return cfg
    return None


def _get_build_setting(cfg: Any, key: str) -> str | None:
    """Get a build setting value from a configuration."""
    bs = cfg.get("buildSettings", {})
    if bs is None:
        return None
    return bs.get(key)


def _target_config_names(config_lists: list[Any], cl_id: str) -> list[str]:
    """Get configuration names for a configuration list ID."""
    for cl in config_lists:
        if cl.get_id() == cl_id:
            bcs = cl.get("buildConfigurations", [])
            names = []
            for bc in bcs:
                if isinstance(bc, str):
                    # Just the ID, need to look up the name
                    names.append(bc)  # Will be resolved later
                else:
                    names.append(str(bc))
            return names
    return []


def _resolve_config_names(configs: list[Any], config_list: Any) -> list[str]:
    """Resolve build configuration names from a configuration list."""
    bcs = config_list.get("buildConfigurations", [])
    names: list[str] = []
    for bc_ref in bcs:
        # bc_ref is a string like "7E14EDF0 /* Debug */"
        cfg_id = (
            bc_ref.split(" /* ")[0].strip() if " /* " in bc_ref else str(bc_ref).strip()
        )
        for cfg in configs:
            if cfg.get_id() == cfg_id:
                names.append(cfg.get("name", "?"))
                break
        else:
            names.append("?")
    return names


def _find_config_by_name(configs: list[Any], name: str) -> Any | None:
    """Find a build configuration by name."""
    return _get_config_by_name(configs, name)


def _get_config_id_from_ref(ref: str) -> str:
    """Extract the configuration ID from a reference string like 'GUID /* Name */'."""
    return ref.split(" /* ")[0].strip()


def _get_config_name_from_ref(ref: str) -> str:
    """Extract the name from a reference string like 'GUID /* Name */'."""
    if " /* " in ref and ref.endswith(" */"):
        return ref.split(" /* ")[1].removesuffix(" */").strip()
    return ref


def check_voyager_configs_exist(
    configs: list[Any],
    errors: list[str],
    prefix: str = "",
) -> bool:
    """Verify all VOY-580 config names exist; report missing as errors."""
    names = {cfg.get("name", "") for cfg in configs}
    required = {DEV_DEBUG, DEV_RELEASE, PROD_DEBUG, PROD_RELEASE}
    missing = required - names
    if missing:
        errors.append(
            f"{prefix}Voyager.xcodeproj missing required configs: {sorted(missing)}"
        )
        return False
    legacy = names & {"Debug", "Release"}
    if legacy:
        errors.append(
            f"{prefix}Voyager.xcodeproj still references legacy configs: "
            f"{sorted(legacy)} (must be removed)"
        )
        return False
    return True


def check_target_config_counts(
    configs: list[Any],
    config_lists: list[Any],
    native_targets: list[Any],
    errors: list[str],
    prefix: str = "",
) -> None:
    """Check that each target has the expected number of configs."""
    for target in native_targets:
        target_name = target.get("name", "?")
        cl_id = target.get("buildConfigurationList", "")
        for cl in config_lists:
            if cl.get_id() == cl_id:
                names = _resolve_config_names(configs, cl)
                break
        else:
            errors.append(f"{prefix}{target_name}: no configuration list found")
            continue

        is_test = target_name in TEST_TARGETS
        if is_test:
            # Test targets: Dev-Debug only
            expected = {DEV_DEBUG}
        else:
            # Non-test targets: all 4 configs
            expected = ALL_VOYAGER_CONFIGS

        actual = set(names)
        missing = expected - actual
        extra = actual - expected

        if missing:
            errors.append(
                f"{prefix}{target_name}: missing configs: {', '.join(sorted(missing))}"
            )
        if extra:
            errors.append(
                f"{prefix}{target_name}: unexpected configs: {', '.join(sorted(extra))}"
            )


def check_project_config_list(
    configs: list[Any],
    config_lists: list[Any],
    pbx_projects: list[Any],
    errors: list[str],
) -> None:
    """Check project-level XCConfigurationList."""
    for proj in pbx_projects:
        cl_id = proj.get("buildConfigurationList", "")
        for cl in config_lists:
            if cl.get_id() == cl_id:
                names = _resolve_config_names(configs, cl)
                default = cl.get("defaultConfigurationName", "?")

                for expected in ALL_VOYAGER_CONFIGS:
                    if expected not in names:
                        errors.append(
                            f"Project: missing {expected} in project config list"
                        )
                if default != PROD_RELEASE:
                    errors.append(
                        f"Project: defaultConfigurationName is '{default}', expected '{PROD_RELEASE}'"
                    )
                break


def _resolve_configs_for_target(
    configs: list[Any],
    config_lists: list[Any],
    target: Any,
) -> dict[str, Any]:
    """Resolve a target's build configs into a name->config dict."""
    cl_id = target.get("buildConfigurationList", "")
    for cl in config_lists:
        if cl.get_id() == cl_id:
            result: dict[str, Any] = {}
            bcs = cl.get("buildConfigurations", [])
            for bc_ref in bcs:
                cfg_id = (
                    bc_ref.split(" /* ")[0].strip()
                    if " /* " in bc_ref
                    else str(bc_ref).strip()
                )
                for cfg in configs:
                    if cfg.get_id() == cfg_id:
                        result[cfg.get("name", "?")] = cfg
                        break
            return result
    return {}


def check_build_setting(
    target_name: str,
    config_name: str,
    target_configs: dict[str, Any],
    setting_key: str,
    expected_value: str | None,
    errors: list[str],
    prefix: str = "",
) -> None:
    """Check a build setting value for a specific target and config."""
    cfg = target_configs.get(config_name)
    if cfg is None:
        errors.append(
            f"{prefix}{target_name}: config '{config_name}' not found "
            f"for {setting_key} check"
        )
        return

    actual = _get_build_setting(cfg, setting_key)
    if expected_value is None:
        if actual and actual.strip():
            errors.append(
                f"{prefix}{target_name}/{config_name}: "
                f"{setting_key} should be empty, got '{actual}'"
            )
    else:
        if actual != expected_value:
            errors.append(
                f"{prefix}{target_name}/{config_name}: "
                f"{setting_key} is '{actual}', expected '{expected_value}'"
            )


def check_app_env(
    target_configs: dict[str, Any],
    target_name: str,
    config_name: str,
    errors: list[str],
    prefix: str = "",
) -> None:
    expected = APP_ENV_MAP.get(config_name)
    if expected is not None:
        check_build_setting(
            target_name,
            config_name,
            target_configs,
            "APP_ENV",
            expected,
            errors,
            prefix,
        )


def check_bundle_id(
    target_configs: dict[str, Any],
    target_name: str,
    config_name: str,
    errors: list[str],
    prefix: str = "",
) -> None:
    target_map = BUNDLE_ID_MAP.get(target_name)
    if target_map is not None:
        expected = target_map.get(config_name)
        if expected is not None:
            check_build_setting(
                target_name,
                config_name,
                target_configs,
                "PRODUCT_BUNDLE_IDENTIFIER",
                expected,
                errors,
                prefix,
            )


def check_code_sign(
    target_configs: dict[str, Any],
    target_name: str,
    config_name: str,
    errors: list[str],
    prefix: str = "",
) -> None:
    expected = CODE_SIGN_MAP.get(config_name)
    if expected is not None:
        check_build_setting(
            target_name,
            config_name,
            target_configs,
            "CODE_SIGN_IDENTITY",
            expected,
            errors,
            prefix,
        )


def check_hardened_runtime(
    target_configs: dict[str, Any],
    target_name: str,
    config_name: str,
    errors: list[str],
    prefix: str = "",
) -> None:
    expected = HARDENED_RUNTIME_MAP.get(config_name)
    if expected is not None:
        check_build_setting(
            target_name,
            config_name,
            target_configs,
            "ENABLE_HARDENED_RUNTIME",
            expected,
            errors,
            prefix,
        )


def check_voyager_app_suffix(
    target_configs: dict[str, Any],
    target_name: str,
    config_name: str,
    errors: list[str],
    prefix: str = "",
) -> None:
    expected = VOYAGER_APP_SUFFIX_MAP.get(config_name)
    if target_name == "Voyager":
        check_build_setting(
            target_name,
            config_name,
            target_configs,
            "VOYAGER_APP_SUFFIX",
            expected,
            errors,
            prefix,
        )


def check_su_feed_url(
    target_configs: dict[str, Any],
    target_name: str,
    config_name: str,
    errors: list[str],
    prefix: str = "",
) -> None:
    expected = SUFEED_URL_MAP.get(config_name)
    if target_name == "Voyager":
        check_build_setting(
            target_name,
            config_name,
            target_configs,
            "SUFeedURL",
            expected,
            errors,
            prefix,
        )


def check_xpc_mach_service_name(
    target_configs: dict[str, Any],
    target_name: str,
    config_name: str,
    errors: list[str],
    prefix: str = "",
) -> None:
    expected = XPC_MACH_SERVICE_NAME_MAP.get(config_name)
    if target_name in ("FilterSearchXPC", "Voyager"):
        check_build_setting(
            target_name,
            config_name,
            target_configs,
            "XPC_MACH_SERVICE_NAME",
            expected,
            errors,
            prefix,
        )


def check_target_config_settings(
    configs: list[Any],
    config_lists: list[Any],
    native_targets: list[Any],
    errors: list[str],
    prefix: str = "",
) -> None:
    for target in native_targets:
        target_name = target.get("name", "?")
        target_configs = _resolve_configs_for_target(configs, config_lists, target)
        if not target_configs:
            continue

        names = set(target_configs.keys())
        is_test = target_name in TEST_TARGETS
        if is_test:
            # Test targets inherit APP_ENV, codesign, etc. from project-level
            # configs; only check that Dev-Debug exists (already verified above)
            continue
        check_configs = sorted(ALL_VOYAGER_CONFIGS)

        for config_name in check_configs:
            if config_name not in names:
                continue
            check_app_env(target_configs, target_name, config_name, errors, prefix)
            check_bundle_id(target_configs, target_name, config_name, errors, prefix)
            check_code_sign(target_configs, target_name, config_name, errors, prefix)
            check_hardened_runtime(
                target_configs, target_name, config_name, errors, prefix
            )
            check_voyager_app_suffix(
                target_configs, target_name, config_name, errors, prefix
            )
            check_su_feed_url(target_configs, target_name, config_name, errors, prefix)
            check_xpc_mach_service_name(
                target_configs, target_name, config_name, errors, prefix
            )


def check_host_project(
    pbxproj_path: Path,
    project_name: str,
    errors: list[str],
) -> None:
    """Check a Host project's build configuration matrix."""
    try:
        proj = _load_pbxproj(pbxproj_path)
    except Exception:
        errors.append(f"{project_name}: failed to load pbxproj")
        return

    objects = proj.objects
    configs = objects.get_objects_in_section("XCBuildConfiguration")
    config_lists = objects.get_objects_in_section("XCConfigurationList")
    native_targets = objects.get_objects_in_section("PBXNativeTarget")

    prefix = f"{project_name}/"
    names = {cfg.get("name", "") for cfg in configs}

    missing = HOST_CONFIGS - names
    if missing:
        errors.append(f"{prefix}missing required configs: {sorted(missing)}")
        return

    legacy = names & {"Debug", "Release"}
    if legacy:
        errors.append(
            f"{prefix}still references legacy configs: {sorted(legacy)} "
            f"(must be removed)"
        )
        return

    for target in native_targets:
        target_name = target.get("name", "?")
        target_configs = _resolve_configs_for_target(configs, config_lists, target)
        if not target_configs:
            errors.append(f"{prefix}{target_name}: no configuration list found")
            continue

        names = set(target_configs.keys())
        is_test = target_name in HOST_TEST_TARGETS
        if is_test:
            expected = {DEV_DEBUG}
        else:
            expected = HOST_CONFIGS

        missing = expected - names
        extra = names - HOST_CONFIGS

        if missing:
            errors.append(
                f"{prefix}{target_name}: missing configs: {', '.join(sorted(missing))}"
            )
        if extra:
            errors.append(
                f"{prefix}{target_name}: unexpected configs: {', '.join(sorted(extra))}"
            )

        for config_name in expected:
            if config_name in names:
                check_app_env(target_configs, target_name, config_name, errors, prefix)


def check_scheme_files(
    schemes_dir: Path,
    errors: list[str],
) -> None:
    """Check scheme files for valid buildConfiguration values."""
    if not schemes_dir.is_dir():
        errors.append(f"Scheme directory missing: {schemes_dir}")
        return

    for scheme_path in sorted(schemes_dir.glob("*.xcscheme")):
        try:
            tree = ET.parse(str(scheme_path))
            root = tree.getroot()
        except ET.ParseError as e:
            errors.append(f"Scheme {scheme_path.name}: XML parse error: {e}")
            continue

        for action_elem in root.iter():
            config = action_elem.get("buildConfiguration")
            if config is not None and config not in VALID_SCHEME_CONFIGS:
                errors.append(
                    f"Scheme {scheme_path.name}: "
                    f"<{action_elem.tag}> buildConfiguration='{config}'"
                    f" is not a valid VOY-580 config "
                    f"(expected one of {sorted(VALID_SCHEME_CONFIGS)})"
                )


def check_ci_references(errors: list[str]) -> None:
    if not CI_SCRIPT.is_file():
        errors.append(f"CI script missing: {CI_SCRIPT}")
        return
    content = CI_SCRIPT.read_text(encoding="utf-8")
    lines = content.splitlines()
    for i, line in enumerate(lines, 1):
        m = re.match(
            r'^\s*CONFIGURATION="?\$\{CONFIGURATION:-([^}]+)\}"?\s*$',
            line,
        )
        if m:
            value = m.group(1)
            if value != PROD_RELEASE:
                errors.append(
                    f"{CI_SCRIPT}:{i}: default CONFIGURATION is '{value}', "
                    f"expected '{PROD_RELEASE}'"
                )

    if not CI_WORKFLOW.is_file():
        errors.append(f"CI workflow missing: {CI_WORKFLOW}")
        return
    content = CI_WORKFLOW.read_text(encoding="utf-8")
    lines = content.splitlines()
    for i, line in enumerate(lines, 1):
        m = re.search(r"CONFIGURATION:\s*(\S+)", line)
        if m:
            value = m.group(1).strip('"')
            if value == "Release":
                errors.append(
                    f"{CI_WORKFLOW}:{i}: CONFIGURATION is '{value}', "
                    f"expected '{PROD_RELEASE}'"
                )


def validate_voyager_pbxproj(pbxproj_path: Path, errors: list[str]) -> None:
    """Validate the main Voyager.xcodeproj build matrix."""
    try:
        proj = _load_pbxproj(pbxproj_path)
    except Exception as e:
        errors.append(f"Voyager: failed to load pbxproj: {e}")
        return

    objects = proj.objects
    configs = objects.get_objects_in_section("XCBuildConfiguration")
    config_lists = objects.get_objects_in_section("XCConfigurationList")
    native_targets = objects.get_objects_in_section("PBXNativeTarget")
    pbx_projects = objects.get_objects_in_section("PBXProject")

    if not check_voyager_configs_exist(configs, errors, "Voyager/"):
        return

    check_target_config_counts(
        configs, config_lists, native_targets, errors, "Voyager/"
    )
    check_project_config_list(configs, config_lists, pbx_projects, errors)
    check_target_config_settings(
        configs, config_lists, native_targets, errors, "Voyager/"
    )


def validate_host_projects(errors: list[str]) -> None:
    """Validate Host project build matrices."""
    for host_name in HOST_PROJECTS:
        pbxproj_path = (
            Path("apps/macos/Hosts")
            / host_name
            / f"{host_name}.xcodeproj"
            / "project.pbxproj"
        )
        if pbxproj_path.is_file():
            check_host_project(pbxproj_path, host_name, errors)


def validate_schemes(errors: list[str]) -> None:
    """Validate scheme files (project + workspace mirrors)."""
    check_scheme_files(SCHEMES_DIR, errors)
    check_scheme_files(WORKSPACE_SCHEMES_DIR, errors)


def validate_ci(errors: list[str]) -> None:
    """Validate CI references."""
    check_ci_references(errors)


def main() -> int:
    """Run the build matrix validator. Returns 0 on success, non-zero on failure."""
    errors: list[str] = []

    voyager_pbxproj = Path("apps/macos/Voyager/Voyager.xcodeproj/project.pbxproj")
    validate_voyager_pbxproj(voyager_pbxproj, errors)
    validate_host_projects(errors)
    validate_schemes(errors)
    validate_ci(errors)

    if errors:
        for error in errors:
            print(f"✗ {error}")
        return 1
    print("✓ All build matrix invariants satisfied")
    return 0


if __name__ == "__main__":
    # Allow running from repo root via `python3 -m scripts.validate_build_matrix`
    os.chdir(Path(__file__).resolve().parents[1])
    raise SystemExit(main())
