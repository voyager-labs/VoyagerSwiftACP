"""Regression contract for FilterSearchXPC Mach-service registration plists."""

from __future__ import annotations

import plistlib
import unittest
from pathlib import Path

from scripts.validate_build_matrix import (
    DEV_DEBUG,
    DEV_RELEASE,
    PROD_DEBUG,
    PROD_RELEASE,
    _load_pbxproj,
    _resolve_configs_for_target,
)


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
PROJECT_PATH = REPOSITORY_ROOT / "apps/macos/Voyager/Voyager.xcodeproj/project.pbxproj"
XPC_PLIST_DIRECTORY = REPOSITORY_ROOT / "apps/macos/Voyager/FilterSearchXPC"

EXPECTED_MACH_SERVICES = {
    DEV_DEBUG: "fm.voyager.Voyager.FilterSearchXPC.dev",
    DEV_RELEASE: "fm.voyager.Voyager.FilterSearchXPC.dev",
    PROD_DEBUG: "fm.voyager.Voyager.FilterSearchXPC.proddebug",
    PROD_RELEASE: "fm.voyager.Voyager.FilterSearchXPC",
}


class FilterSearchXPCMachServicePlistTests(unittest.TestCase):
    def test_each_configuration_selects_a_literal_mach_service_plist(self) -> None:
        self.assertFalse(
            (XPC_PLIST_DIRECTORY / "Info.plist").exists(),
            "obsolete shared XPC Info.plist must not remain selectable",
        )
        project = _load_pbxproj(PROJECT_PATH)
        objects = project.objects
        configs = objects.get_objects_in_section("XCBuildConfiguration")
        config_lists = objects.get_objects_in_section("XCConfigurationList")
        xpc_target = next(
            target
            for target in objects.get_objects_in_section("PBXNativeTarget")
            if target.get("name") == "FilterSearchXPC"
        )
        target_configs = _resolve_configs_for_target(configs, config_lists, xpc_target)

        for configuration, mach_service_name in EXPECTED_MACH_SERVICES.items():
            expected_plist = f"FilterSearchXPC/Info-{configuration}.plist"
            self.assertEqual(
                target_configs[configuration]
                .get("buildSettings", {})
                .get("INFOPLIST_FILE"),
                expected_plist,
            )

            plist_path = XPC_PLIST_DIRECTORY / f"Info-{configuration}.plist"
            self.assertTrue(plist_path.is_file(), f"missing {plist_path.name}")
            with plist_path.open("rb") as source:
                info = plistlib.load(source)
            self.assertEqual(info["MachServices"], {mach_service_name: True})


if __name__ == "__main__":
    unittest.main()
