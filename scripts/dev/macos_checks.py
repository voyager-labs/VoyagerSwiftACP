#!/usr/bin/env python3
from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path
from typing import TypedDict, cast

ROOT_DIR = Path(__file__).resolve().parents[2]
if str(ROOT_DIR) not in sys.path:
    sys.path.insert(0, str(ROOT_DIR))

from scripts.dev.voyager_contexts import (
    CONTEXTS,
    VOYAGER_PROJECT,
    changed_paths,
    command_to_record,
    context_to_json,
    find_package_dir,
    normalize_paths,
    path_is_under,
    primary_lsp_context,
    print_json,
    swift_package_command,
    xcode_scheme_command,
    xcode_target_build_command,
)


class CommandRecord(TypedDict):
    id: str
    title: str
    reason: str
    cwd: str
    argv: list[str]
    shell: str


class CommandResult(CommandRecord):
    returncode: int


def cli_args() -> list[str]:
    args = sys.argv[1:]
    if args and args[0] == "--":
        return args[1:]
    return args


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Plan or run affected Voyager macOS checks for selected paths."
    )
    parser.add_argument(
        "--path",
        action="append",
        default=[],
        help="Repo-relative or absolute changed path. Can be repeated.",
    )
    parser.add_argument(
        "--changed",
        action="store_true",
        help="Infer paths from git diff against HEAD plus untracked files.",
    )
    parser.add_argument(
        "--scope",
        choices=[
            "app",
            "app-tests",
            "helper",
            "helper-tests",
            "onboarding",
            "file-manager-host",
            "packages",
        ],
        help="Explicit check scope.",
    )
    parser.add_argument(
        "--json", action="store_true", help="Print the plan/results as JSON."
    )
    parser.add_argument(
        "--run", action="store_true", help="Run the planned checks sequentially."
    )
    return parser.parse_args(cli_args())


def add_unique(
    records: list[CommandRecord], seen: set[str], record: CommandRecord
) -> None:
    record_id = record["id"]
    if record_id not in seen:
        seen.add(record_id)
        records.append(record)


def package_reason(package_dir: Path) -> str:
    return f"Validate local SwiftPM package touched under {package_dir}."


def record(
    command_id: str, title: str, command: list[str], reason: str
) -> CommandRecord:
    return cast(
        CommandRecord,
        cast(object, command_to_record(command_id, title, command, reason)),
    )


def plan_for_scope(scope: str) -> list[CommandRecord]:
    if scope == "app":
        return [
            record(
                "xcode-build-app",
                "Build Voyager app",
                xcode_scheme_command(VOYAGER_PROJECT, "Voyager-Dev", "build"),
                "Validate the main app scheme.",
            )
        ]
    if scope == "app-tests":
        return [
            record(
                "xcode-test-app",
                "Test Voyager app",
                xcode_scheme_command(VOYAGER_PROJECT, "Voyager-Dev", "test"),
                "Validate VoyagerTests and scheme test wiring.",
            )
        ]
    if scope == "helper":
        return [
            record(
                "xcode-build-helper",
                "Build VoyagerHelper",
                xcode_scheme_command(VOYAGER_PROJECT, "VoyagerHelper-Dev", "build"),
                "Validate helper compilation.",
            )
        ]
    if scope == "helper-tests":
        return [
            record(
                "xcode-test-helper",
                "Test VoyagerHelper",
                xcode_scheme_command(VOYAGER_PROJECT, "VoyagerHelper-Dev", "test"),
                "Validate helper tests.",
            )
        ]
    if scope == "onboarding":
        ctx = CONTEXTS["onboarding"]
        return [
            record(
                "xcode-build-onboarding",
                "Build OnboardingHost",
                xcode_scheme_command(ctx.project_path, ctx.scheme, "build"),
                "Validate OnboardingHost integration.",
            )
        ]
    if scope == "file-manager-host":
        ctx = CONTEXTS["file-manager-host"]
        return [
            record(
                "xcode-build-file-manager-host",
                "Build FileManagerHost",
                xcode_scheme_command(ctx.project_path, ctx.scheme, "build"),
                "Validate FileManagerHost fixture integration.",
            )
        ]
    if scope == "packages":
        package_dirs = sorted(
            path.relative_to(ROOT_DIR)
            for path in (ROOT_DIR / "apps/macos/Packages").glob("*/*/Package.swift")
        )
        return [
            record(
                f"swift-package-{package.parent}",
                f"Check {package.parent}",
                swift_package_command(package.parent),
                package_reason(package.parent),
            )
            for package in package_dirs
        ]
    raise ValueError(f"Unsupported scope: {scope}")


def plan_for_paths(
    paths: list[Path],
) -> tuple[dict[str, object], list[CommandRecord]]:
    context, reasons = primary_lsp_context(paths)
    commands: list[CommandRecord] = []
    seen: set[str] = set()

    for path in paths:
        package_dir = find_package_dir(path)
        if package_dir is not None:
            add_unique(
                commands,
                seen,
                record(
                    f"swift-package-{package_dir}",
                    f"Check {package_dir}",
                    swift_package_command(package_dir),
                    package_reason(package_dir),
                ),
            )
            add_unique(
                commands,
                seen,
                record(
                    "xcode-build-app",
                    "Build Voyager app",
                    xcode_scheme_command(VOYAGER_PROJECT, "Voyager-Dev", "build"),
                    "Package changes should compile in the broad app consumer.",
                ),
            )
            if path_is_under(
                package_dir, "apps/macos/Packages/02_Pages/Onboarding"
            ) or path_is_under(
                package_dir, "apps/macos/Packages/06_Shared/VoyagerShared"
            ):
                onboarding = CONTEXTS["onboarding"]
                add_unique(
                    commands,
                    seen,
                    record(
                        "xcode-build-onboarding",
                        "Build OnboardingHost",
                        xcode_scheme_command(
                            onboarding.project_path, onboarding.scheme, "build"
                        ),
                        "This package is consumed by OnboardingHost.",
                    ),
                )
            if path_is_under(package_dir, "apps/macos/Packages/02_Pages/FileManager"):
                add_unique(commands, seen, plan_for_scope("file-manager-host")[0])
            continue

        if path_is_under(path, "apps/macos/Voyager/VoyagerHelperTests"):
            add_unique(commands, seen, plan_for_scope("helper-tests")[0])
        elif path_is_under(path, "apps/macos/Voyager/VoyagerHelper"):
            add_unique(commands, seen, plan_for_scope("helper")[0])
        elif path_is_under(path, "apps/macos/Voyager/FilterSearchXPC"):
            add_unique(
                commands,
                seen,
                record(
                    "xcode-build-filter-search-xpc",
                    "Build FilterSearchXPC target",
                    xcode_target_build_command(VOYAGER_PROJECT, "FilterSearchXPC"),
                    "FilterSearchXPC has no dedicated shared scheme in the repo.",
                ),
            )
        elif path_is_under(path, "apps/macos/Hosts/OnboardingHost"):
            add_unique(commands, seen, plan_for_scope("onboarding")[0])
        elif path_is_under(path, "apps/macos/Hosts/FileManagerHost"):
            add_unique(commands, seen, plan_for_scope("file-manager-host")[0])
        elif path_is_under(path, "apps/macos/Voyager/VoyagerTests") or path_is_under(
            path, "apps/macos/Voyager/VoyagerUITests"
        ):
            add_unique(commands, seen, plan_for_scope("app-tests")[0])
        elif path_is_under(path, "apps/macos/Voyager"):
            add_unique(commands, seen, plan_for_scope("app")[0])

    return {"context": context_to_json(context), "reasons": reasons}, commands


def lsp_for_scope(scope: str) -> dict[str, object]:
    if scope in {"helper", "helper-tests"}:
        context = CONTEXTS["helper"]
    elif scope == "onboarding":
        context = CONTEXTS["onboarding"]
    elif scope == "file-manager-host":
        context = CONTEXTS["file-manager-host"]
    else:
        context = CONTEXTS["app"]
    return {
        "context": context_to_json(context),
        "reasons": [f"Explicit check scope: {scope}"],
    }


def run_commands(commands: list[CommandRecord]) -> list[CommandResult]:
    results: list[CommandResult] = []
    for command in commands:
        print(f"\n==> {command['title']}")
        print(command["shell"])
        completed = subprocess.run(command["argv"], cwd=ROOT_DIR, check=False)
        result = cast(
            CommandResult, cast(object, {**command, "returncode": completed.returncode})
        )
        results.append(result)
        if completed.returncode != 0:
            break
    return results


def main() -> None:
    args = parse_args()
    input_paths = cast(list[str], args.path)
    changed = cast(bool, args.changed)
    scope = cast("str | None", args.scope)
    run_checks = cast(bool, args.run)
    json_output = cast(bool, args.json)

    paths = normalize_paths(input_paths)
    if changed:
        paths.extend(changed_paths())
    paths = list(dict.fromkeys(paths))

    if scope:
        lsp = lsp_for_scope(scope)
        commands = plan_for_scope(scope)
    else:
        lsp, commands = plan_for_paths(paths)

    payload: dict[str, object] = {
        "input_paths": [str(path) for path in paths],
        "lsp": lsp,
        "checks": commands,
    }

    if run_checks:
        results = run_commands(commands)
        payload["results"] = results
        failed = next(
            (result for result in results if result.get("returncode") != 0), None
        )
        if json_output:
            print_json(payload)
        raise SystemExit(failed["returncode"] if failed else 0)

    if json_output:
        print_json(payload)
        return

    lsp_context = cast(dict[str, object], lsp["context"])
    print(f"LSP context: {lsp_context['name']} ({lsp_context['scheme']})")
    for reason in cast(list[str], lsp["reasons"]):
        print(f"- {reason}")
    if not commands:
        print("No macOS checks inferred for the selected input.")
        return
    print("\nPlanned checks:")
    for index, command in enumerate(commands, start=1):
        print(f"{index}. {command['title']}")
        print(f"   {command['shell']}")


if __name__ == "__main__":
    main()
