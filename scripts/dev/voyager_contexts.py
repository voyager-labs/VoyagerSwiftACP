#!/usr/bin/env python3
from __future__ import annotations

import json
import shlex
import subprocess
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable


ROOT_DIR = Path(__file__).resolve().parents[2]
BUILD_DIR = ROOT_DIR / "build/dev"
DERIVED_DATA_PATH = BUILD_DIR / "DerivedData"
SOURCE_PACKAGES_PATH = BUILD_DIR / "SourcePackages"

VOYAGER_PROJECT = "apps/macos/Voyager/Voyager.xcodeproj"
ONBOARDING_PROJECT = "apps/macos/Hosts/OnboardingHost/OnboardingHost.xcodeproj"
PACKAGES_ROOT = Path("apps/macos/Packages")


@dataclass(frozen=True)
class LSPContext:
    name: str
    description: str
    project_path: str
    scheme: str
    reason: str


CONTEXTS: dict[str, LSPContext] = {
    "app": LSPContext(
        name="app",
        description="Voyager app and most local SwiftPM package source files",
        project_path=VOYAGER_PROJECT,
        scheme="Voyager-Dev",
        reason="Voyager-Dev is the broadest default scheme and consumes most local packages.",
    ),
    "helper": LSPContext(
        name="helper",
        description="VoyagerHelper and helper tests",
        project_path=VOYAGER_PROJECT,
        scheme="VoyagerHelper-Dev",
        reason="Helper files compile under the VoyagerHelper-Dev scheme, not the app launch context.",
    ),
    "onboarding": LSPContext(
        name="onboarding",
        description="OnboardingHost and onboarding package integration",
        project_path=ONBOARDING_PROJECT,
        scheme="OnboardingHost-Dev",
        reason="OnboardingHost is a separate Xcode project with its own development scheme.",
    ),
}


def to_repo_relative(path: str | Path) -> Path:
    candidate = Path(path).expanduser()
    if candidate.is_absolute():
        try:
            return candidate.resolve().relative_to(ROOT_DIR)
        except ValueError:
            return candidate
    return candidate


def normalize_paths(paths: Iterable[str | Path]) -> list[Path]:
    normalized: list[Path] = []
    for path in paths:
        if str(path).strip():
            normalized.append(to_repo_relative(path))
    return normalized


def path_is_under(path: Path, parent: str | Path) -> bool:
    parent_path = Path(parent)
    try:
        path.relative_to(parent_path)
        return True
    except ValueError:
        return False


def find_package_dir(path: Path) -> Path | None:
    if not path_is_under(path, PACKAGES_ROOT):
        return None

    current = path
    if current.name == "Package.swift":
        current = current.parent
    elif (ROOT_DIR / current).is_file():
        current = current.parent

    while current != current.parent:
        if (
            path_is_under(current, PACKAGES_ROOT)
            and (ROOT_DIR / current / "Package.swift").exists()
        ):
            return current
        if current == PACKAGES_ROOT:
            break
        current = current.parent
    return None


def package_has_tests(package_dir: Path) -> bool:
    manifest = ROOT_DIR / package_dir / "Package.swift"
    if not manifest.exists():
        return False
    return ".testTarget(" in manifest.read_text()


def changed_paths() -> list[Path]:
    diff = subprocess.run(
        ["git", "diff", "--name-only", "HEAD", "--"],
        cwd=ROOT_DIR,
        check=False,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    others = subprocess.run(
        ["git", "ls-files", "--others", "--exclude-standard"],
        cwd=ROOT_DIR,
        check=False,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    names = [
        line.strip()
        for line in (diff.stdout + "\n" + others.stdout).splitlines()
        if line.strip()
    ]
    return normalize_paths(dict.fromkeys(names).keys())


def primary_lsp_context(paths: Iterable[Path]) -> tuple[LSPContext, list[str]]:
    reasons: list[str] = []
    paths = list(paths)

    if not paths:
        return CONTEXTS["app"], [
            "No path was provided; using the broad Voyager app context."
        ]

    if any(path_is_under(path, "apps/macos/Voyager/VoyagerHelper") for path in paths):
        return CONTEXTS["helper"], ["A VoyagerHelper path was selected."]

    if any(path_is_under(path, "apps/macos/Hosts/OnboardingHost") for path in paths):
        return CONTEXTS["onboarding"], ["An OnboardingHost path was selected."]

    if any(
        path_is_under(path, "apps/macos/Packages/02_Pages/Onboarding") for path in paths
    ):
        return CONTEXTS["onboarding"], [
            "The onboarding package is primarily exercised by OnboardingHost."
        ]

    if any(path_is_under(path, "apps/macos/Packages") for path in paths):
        reasons.append(
            "A local package path was selected; Voyager-Dev is the broadest package-consuming Xcode context."
        )
        return CONTEXTS["app"], reasons

    if any(path_is_under(path, "apps/macos/Voyager/FilterSearchXPC") for path in paths):
        return CONTEXTS["app"], [
            "FilterSearchXPC has no dedicated shared scheme; start from the broad Voyager app context."
        ]

    return CONTEXTS["app"], ["Defaulting to the Voyager app context."]


def common_xcode_args() -> list[str]:
    return [
        "-configuration",
        "Debug",
        "-derivedDataPath",
        str(DERIVED_DATA_PATH),
        "-clonedSourcePackagesDirPath",
        str(SOURCE_PACKAGES_PATH),
        "-skipPackagePluginValidation",
        "-skipMacroValidation",
    ]


def xcode_scheme_command(project_path: str, scheme: str, action: str) -> list[str]:
    return [
        "xcodebuild",
        action,
        "-project",
        project_path,
        "-scheme",
        scheme,
        *common_xcode_args(),
    ]


def xcode_target_build_command(project_path: str, target: str) -> list[str]:
    return [
        "xcodebuild",
        "build",
        "-project",
        project_path,
        "-target",
        target,
        *common_xcode_args(),
    ]


def swift_package_command(package_dir: Path) -> list[str]:
    action = "test" if package_has_tests(package_dir) else "build"
    return ["xcrun", "swift", action, "--package-path", str(package_dir)]


def command_to_record(
    command_id: str, title: str, command: list[str], reason: str
) -> dict[str, object]:
    return {
        "id": command_id,
        "title": title,
        "reason": reason,
        "cwd": str(ROOT_DIR),
        "argv": command,
        "shell": shlex.join(command),
    }


def context_to_json(context: LSPContext) -> dict[str, str]:
    return {
        "name": context.name,
        "description": context.description,
        "project_path": context.project_path,
        "scheme": context.scheme,
        "derived_data_path": str(DERIVED_DATA_PATH),
        "source_packages_path": str(SOURCE_PACKAGES_PATH),
        "reason": context.reason,
    }


def print_json(payload: object) -> None:
    print(json.dumps(payload, indent=2, sort_keys=True))
